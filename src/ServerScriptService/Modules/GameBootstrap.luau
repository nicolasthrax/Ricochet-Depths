-- Constructs and wires every server system. Main.server.luau does nothing but call this.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArenaDirector = require(script.Parent.ArenaDirector)
local DataStoreProvider = require(script.Parent.DataStoreProvider)
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local LobbyBuilder = require(script.Parent.LobbyBuilder)
local PartyRooms = require(script.Parent.PartyRooms)
local ProjectileConfig = require(ReplicatedStorage:WaitForChild("ProjectileConfig"))
local PlayerDataConfig = require(ReplicatedStorage:WaitForChild("PlayerDataConfig"))
local PlayerDataService = require(script.Parent.PlayerDataService)
local RemoteRouter = require(script.Parent.RemoteRouter)
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local ShopService = require(script.Parent.ShopService)
local TelemetryService = require(script.Parent.TelemetryService)
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

	local _, soloPrompt, lobbyParts = LobbyBuilder.Build(workspace)

	-- Arena slots live under one folder, far from the lobby.
	local arenas = Instance.new("Folder")
	arenas.Name = "Arenas"
	arenas.Parent = workspace

	local planeY = RoomConfig.FloorY + ProjectileConfig.PlaneHeight

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

	-- The shop is open to anyone in the lobby; `director` is assigned just below, before any
	-- request can arrive.
	local director
	local shop = ShopService.new(persistence, {
		canShop = function(player)
			return director ~= nil and director:MatchFor(player) == nil
		end,
		onChanged = pushProfile,
	})

	director = ArenaDirector.new({
		parent = arenas,
		planeY = planeY,
		seed = seed,
		effectsRemote = Remotes.Get("ProjectileImpact"),
		shared = {
			telemetry = telemetry,
			net = net,
			world = WorldAdapter,
			persistence = persistence,
			runKeyPrefix = game.JobId ~= "" and game.JobId or "studio",
			-- Shop bonuses are read as each run starts; with the shop off, nobody has any.
			metaProvider = FeatureFlags.SalvageShop and function(player)
				return shop:GetRunBonuses(player)
			end or nil,
		},
	})

	local lobbyStatus = Remotes.Get("LobbyReadyState")
	local function startSolo(player, now)
		local slot, reason = director:StartGroup({ player }, now)
		if not slot and reason == "all arenas busy" then
			lobbyStatus:FireClient(player, { Active = true, Notice = "Every arena is busy. Try again in a moment." })
		end
	end

	local router = RemoteRouter.new(function(player)
		return director:MatchFor(player)
	end, persistence, pushProfile, FeatureFlags.SalvageShop and shop or nil, { onStartRequest = startSolo })
	router:Bind()

	soloPrompt.Triggered:Connect(function(player)
		startSolo(player, os.clock())
	end)

	-- The kiosks only open the view on their tab; every purchase still goes through ShopService.
	-- With the shop off there is no entry point at all.
	local shopOpen, shopResult = Remotes.Get("ShopOpen"), Remotes.Get("ShopResult")
	for prompt, tab in { [lobbyParts.armoryPrompt] = "Armory", [lobbyParts.cosmeticsPrompt] = "Cosmetics" } do
		if FeatureFlags.SalvageShop then
			prompt.Triggered:Connect(function(player)
				pushProfile(player)
				shopOpen:FireClient(player, tab)
			end)
		else
			prompt.Enabled = false
		end
	end

	-- Multiplayer gates: a gate's party descends together when its countdown ends.
	local gates = PartyRooms.new(PartyRooms.FromGates(lobbyParts.gates))
	local gateById = {}
	for _, gate in lobbyParts.gates do
		gateById[gate.Id] = gate
	end
	local lastStatus, nextStatusPush = {}, 0
	local function stepLobby(now)
		local result = gates:Step(now, Players:GetPlayers(), WorldAdapter.GetPosition, function(player)
			return director:MatchFor(player) ~= nil
		end)

		local statusOf = {}
		for id, entry in result do
			local gate = gateById[id]
			LobbyBuilder.SetGateStatus(gate, #entry.Members, entry.Countdown)
			for _, player in entry.Overflow do
				WorldAdapter.Teleport(player, gate.mouth)
			end
			for _, player in entry.Members do
				statusOf[player] = {
					Active = true,
					Gate = gate.name,
					Count = #entry.Members,
					Capacity = gate.capacity,
					MinPlayers = gate.minPlayers,
					Countdown = entry.Countdown and math.ceil(entry.Countdown) or nil,
				}
			end
			if entry.Start then
				local slot = director:StartGroup(entry.Members, now)
				if not slot then
					for _, player in entry.Members do
						statusOf[player].Notice = "Every arena is busy. Starting as soon as one frees up."
					end
				end
			end
		end

		-- Each lobby player hears about their own gate, on change and at a steady beat.
		local beat = now >= nextStatusPush
		if beat then
			nextStatusPush = now + RunConfig.Lobby.GateBroadcastInterval
		end
		for _, player in Players:GetPlayers() do
			if not director:MatchFor(player) then
				local status = statusOf[player] or { Active = true }
				local key = string.format("%s:%s:%s:%s", tostring(status.Gate), tostring(status.Count),
					tostring(status.Countdown), tostring(status.Notice))
				if key ~= lastStatus[player] or (beat and status.Countdown) then
					lastStatus[player] = key
					lobbyStatus:FireClient(player, status)
				end
			end
		end
	end

	-- A purchase another server beat to the coins is undone on the next save; tell the player.
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
		-- A mid-run respawn lands in the lobby; send the character back to its room once its
		-- root part exists.
		player.CharacterAdded:Connect(function(character)
			if character:WaitForChild("HumanoidRootPart", 5) then
				local match = director:MatchFor(player)
				if match then
					match:HandleCharacterAdded(player)
				end
			end
		end)
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
		director:RemovePlayer(player, os.clock())
		router:ClearPlayer(player)
		lastStatus[player] = nil
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

	RunService.Heartbeat:Connect(function(deltaTime)
		local now = os.clock()
		director:Step(deltaTime, now)
		persistence:StepAutosave(now)
		stepLobby(now)

		-- Developer overlay feed. Nothing here reaches a normal player in a published build.
		if now >= nextDebugPush then
			nextDebugPush = now + DebugConfig.OverlayUpdateInterval
			reportRefusedPurchases()
			for _, player in Players:GetPlayers() do
				if DebugConfig.IsDebugUser(player) then
					debugStats:FireClient(player, GameBootstrap._debugSnapshot(director, player, telemetry, persistence))
				end
			end
		end
	end)

	return {
		director = director,
		router = router,
		telemetry = telemetry,
		persistence = persistence,
		shop = shop,
		gates = gates,
	}
end

function GameBootstrap._debugSnapshot(director, player, telemetry, persistence)
	local match = director:MatchFor(player)
	local run = match and match:GetRunSnapshot() or { State = RunConfig.States.Lobby, RoomIndex = 0, RoomCount = 0, EnemiesRemaining = 0, Players = 0 }
	local arenas = director:GetStats()
	local telemetryStats = telemetry:GetStats()
	local dataStats = persistence:GetStats()
	return {
		State = run.State,
		RoomIndex = run.RoomIndex,
		RoomCount = run.RoomCount,
		EnemiesRemaining = run.EnemiesRemaining,
		Participants = run.Players,
		ArenasBusy = arenas.Busy,
		ArenaSlots = arenas.Slots,
		ProjectilesActive = arenas.ProjectilesActive,
		EnemiesActive = arenas.EnemiesActive,
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
