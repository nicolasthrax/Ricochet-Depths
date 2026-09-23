-- Constructs and wires every server system. Main.server.luau does nothing but call this.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local DataStoreProvider = require(script.Parent.DataStoreProvider)
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local EffectBroadcaster = require(script.Parent.EffectBroadcaster)
local EnemyService = require(script.Parent.EnemyService)
local LobbyBuilder = require(script.Parent.LobbyBuilder)
local LobbyReady = require(script.Parent.LobbyReady)
local MatchService = require(script.Parent.MatchService)
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local PlayerDataConfig = require(ReplicatedStorage:WaitForChild("PlayerDataConfig"))
local PlayerDataService = require(script.Parent.PlayerDataService)
local ProjectileService = require(script.Parent.ProjectileService)
local RemoteRouter = require(script.Parent.RemoteRouter)
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RewardService = require(script.Parent.RewardService)
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RoomService = require(script.Parent.RoomService)
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local ShopService = require(script.Parent.ShopService)
local TelemetryService = require(script.Parent.TelemetryService)
local UpgradeService = require(script.Parent.UpgradeService)
local WorldAdapter = require(script.Parent.WorldAdapter)

local GameBootstrap = {}

local NET_EVENTS = {
	"RunStateChanged",
	"PlayerStateChanged",
	"UpgradeOffer",
	"UpgradeResolved",
	"RunResults",
	"EnemyDefeated",
}

function GameBootstrap.Start()
	local seed = os.time() % 2147483647

	-- Everything a projectile may collide with lives under Arena, so one filter covers it all.
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena.Parent = workspace

	local _, startPrompt, lobbyParts = LobbyBuilder.Build(workspace)

	local planeY = RoomConfig.FloorY + ProjectileConfig.PlaneHeight
	local enemies = EnemyService.new(arena, planeY, seed)
	local projectiles = ProjectileService.new(workspace, arena, planeY)
	local rooms = RoomService.new(arena, enemies, planeY, Random.new(seed))

	local telemetry
	telemetry = TelemetryService.new(function(eventName, payload, now)
		if DebugConfig.LogTelemetry and DebugConfig.IsEnabled() then
			print(string.format("[telemetry %7.1f] %s %s", now, eventName, GameBootstrap._format(payload)))
		end
	end)

	-- Development builds are pinned to a separate datastore scope, so test runs can never
	-- write into live player data.
	telemetry:SetEnabled(FeatureFlags.Telemetry)

	-- Persistence can be switched off wholesale; nothing is read or written when it is.
	local store, scope = DataStoreProvider.Get(DebugConfig.IsEnabled())
	if not FeatureFlags.Persistence then
		store = DataStoreProvider.UnavailableStore.new("persistence feature flag is off")
	end
	local persistence = PlayerDataService.new(store)
	if DebugConfig.IsEnabled() then
		print(("[data] scope=%s schema=v%d"):format(scope, PlayerDataConfig.SchemaVersion))
	end

	local net = {}
	for _, name in NET_EVENTS do
		net[name] = Remotes.Get(name)
	end

	local profileSync = Remotes.Get("ProfileSync")
	local function pushProfile(player)
		local public = persistence:GetPublicProfile(player)
		if public then
			profileSync:FireClient(player, public)
		end
	end

	-- The shop is open in the lobby only; `match` is assigned just below, before any request
	-- can arrive.
	local match
	local shop = ShopService.new(persistence, {
		canShop = function()
			return match ~= nil and match:GetState() == RunConfig.States.Lobby
		end,
		onChanged = pushProfile,
	})

	match = MatchService.new({
		rooms = rooms,
		enemies = enemies,
		upgrades = UpgradeService.new(seed),
		projectiles = projectiles,
		rewards = RewardService.new(),
		effects = EffectBroadcaster.new(Remotes.Get("ProjectileImpact")),
		telemetry = telemetry,
		net = net,
		world = WorldAdapter,
		persistence = persistence,
		runKeyPrefix = game.JobId ~= "" and game.JobId or "studio",
		-- Salvage-shop bonuses are read as each run starts; with the shop off, nobody has any.
		metaProvider = FeatureFlags.SalvageShop and function(player)
			return shop:GetRunBonuses(player)
		end or nil,
	})

	projectiles.OnImpact = function(result, entry)
		return match:HandleImpact(result, entry, os.clock())
	end

	local router = RemoteRouter.new(match, persistence, pushProfile, FeatureFlags.SalvageShop and shop or nil)
	router:Bind()

	startPrompt.Triggered:Connect(function(player)
		match:RequestStart(player, os.clock())
	end)

	-- The kiosk only opens the view; every purchase still goes through ShopService. With the
	-- shop off there is no entry point at all.
	local shopOpen, shopResult = Remotes.Get("ShopOpen"), Remotes.Get("ShopResult")
	if FeatureFlags.SalvageShop then
		lobbyParts.shopPrompt.Triggered:Connect(function(player)
			pushProfile(player)
			shopOpen:FireClient(player)
		end)
	else
		lobbyParts.shopPrompt.Enabled = false
	end

	-- Ready pads: when everyone in the lobby stands on one, the descent starts by itself.
	local lobbyReady = LobbyReady.new(LobbyReady.PadsFromParts(lobbyParts.readyPads))
	local lobbyReadyState = Remotes.Get("LobbyReadyState")
	local padLit = {}
	local lastReadyKey, nextReadyPush = nil, 0
	local function stepLobby(now)
		local inLobby = match:GetState() == RunConfig.States.Lobby
		local snapshot = inLobby and lobbyReady:Step(now, Players:GetPlayers(), WorldAdapter.GetPosition)
			or { Ready = 0, Total = 0, Occupied = {} }
		for index, pad in lobbyParts.readyPads do
			local lit = snapshot.Occupied[index] == true
			if padLit[index] ~= lit then
				padLit[index] = lit
				LobbyBuilder.SetPadReady(pad, lit)
			end
		end

		-- Pushed on every change, and at a steady beat while a countdown runs.
		local countdown = snapshot.Countdown and math.ceil(snapshot.Countdown) or nil
		local key = string.format("%s:%d:%d:%s", tostring(inLobby), snapshot.Ready, snapshot.Total, tostring(countdown))
		if key ~= lastReadyKey or (countdown and now >= nextReadyPush) then
			lastReadyKey = key
			nextReadyPush = now + RunConfig.Lobby.ReadyBroadcastInterval
			lobbyReadyState:FireAllClients({
				Active = inLobby,
				Ready = snapshot.Ready,
				Total = snapshot.Total,
				Countdown = countdown,
			})
		end

		if snapshot.Start then
			match:RequestStart(snapshot.Starter, now)
		end
	end

	-- A purchase another server beat to the salvage is undone on the next save; tell the player.
	local function reportRefusedPurchases()
		for _, player in Players:GetPlayers() do
			local refused = shop:DrainRejections(player)
			for _, rejection in refused do
				shopResult:FireClient(player, { Ok = false, Action = "Refunded", ItemId = rejection.ItemId })
			end
			if #refused > 0 then
				pushProfile(player)
			end
		end
	end

	local function onPlayerAdded(player)
		match:RegisterPlayer(player)
		-- Loading yields, so it runs off the join thread.
		task.spawn(function()
			local profile, err = persistence:Load(player)
			if not profile then
				-- Superseded: the player left, or rejoined and a newer load took over, while this
				-- one was in flight. That newer load pushes its own profile.
				return
			end
			if err then
				warn(("[data] profile load failed for %s, session is read-only: %s"):format(player.Name, err))
				telemetry:LogError("ProfileLoadFailed", err, os.clock())
			end
			pushProfile(player)
		end)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		match:UnregisterPlayer(player, os.clock())
		router:ClearPlayer(player)
		task.spawn(function()
			local ok, err = persistence:Release(player, os.clock())
			if not ok and err and err ~= "profile not loaded" then
				telemetry:LogError("ProfileSaveFailed", err, os.clock())
			end
		end)
	end)

	-- Last chance to flush before the server closes.
	-- Saves run in parallel under a shared budget inside Roblox's 30-second limit; a write
	-- still hanging at the deadline is reported rather than waited on.
	game:BindToClose(function()
		local report = persistence:SaveAllOnShutdown(os.clock())
		for _, failure in report.failures do
			telemetry:LogError(
				failure.timedOut and "ShutdownSaveTimedOut" or "ShutdownSaveFailed",
				failure.error,
				os.clock()
			)
		end
	end)

	local debugStats = Remotes.Get("DebugStats")
	local nextDebugPush = 0

	local effects = match._effects
	RunService.Heartbeat:Connect(function(deltaTime)
		local now = os.clock()
		enemies:Step(deltaTime, now)
		projectiles:Step(deltaTime)
		match:Step(deltaTime, now)
		effects:Step(now)
		persistence:StepAutosave(now)
		stepLobby(now)

		-- Developer overlay feed. Nothing here reaches a normal player in a published build.
		if now >= nextDebugPush then
			nextDebugPush = now + DebugConfig.OverlayUpdateInterval
			reportRefusedPurchases()
			local snapshot = GameBootstrap._debugSnapshot(match, projectiles, enemies, effects, telemetry, persistence)
			for _, player in Players:GetPlayers() do
				if DebugConfig.IsDebugUser(player) then
					debugStats:FireClient(player, snapshot)
				end
			end
		end
	end)

	return {
		match = match,
		rooms = rooms,
		enemies = enemies,
		projectiles = projectiles,
		router = router,
		telemetry = telemetry,
		persistence = persistence,
		shop = shop,
	}
end

function GameBootstrap._debugSnapshot(match, projectiles, enemies, effects, telemetry, persistence)
	local run = match:GetRunSnapshot()
	local telemetryStats = telemetry:GetStats()
	local dataStats = persistence:GetStats()
	return {
		State = run.State,
		RoomIndex = run.RoomIndex,
		RoomCount = run.RoomCount,
		EnemiesRemaining = run.EnemiesRemaining,
		Participants = run.Players,
		ProjectilesActive = projectiles:GetActiveCount(),
		ProjectilesFree = projectiles:GetFreeCount(),
		EnemiesActive = enemies:GetActiveCount(),
		EffectsDropped = effects:GetDroppedCount(),
		TelemetryEmitted = telemetryStats.emitted,
		TelemetryDropped = telemetryStats.dropped,
		DataSaves = dataStats.saves,
		DataSaveFailures = dataStats.saveFailures,
		DataRetries = dataStats.retries,
	}
end

function GameBootstrap._format(payload)
	local parts = {}
	for key, value in payload do
		table.insert(parts, tostring(key) .. "=" .. tostring(value))
	end
	table.sort(parts)
	return "{" .. table.concat(parts, " ") .. "}"
end

return GameBootstrap
