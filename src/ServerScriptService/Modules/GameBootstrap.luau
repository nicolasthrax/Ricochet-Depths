-- Constructs and wires every server system. Main.server.luau does nothing but call this.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArenaDirector = require(script.Parent.ArenaDirector)
local DataStoreProvider = require(script.Parent.DataStoreProvider)
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local LeaderboardService = require(script.Parent.LeaderboardService)
local Leaderstats = require(script.Parent.Leaderstats)
local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))
local MetaService = require(script.Parent.MetaService)
local MonetizationService = require(script.Parent.MonetizationService)
local Nameplates = require(script.Parent.Nameplates)
local LoadoutService = require(script.Parent.LoadoutService)
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
	"Notify",
}

function GameBootstrap.Start()
	local seed = os.time() % 2147483647

	local lobby, soloPrompt, lobbyParts = LobbyBuilder.Build(workspace)
	-- Only reported, never changed: the place file is the owner's to edit.
	for _, message in GameBootstrap._placeWarnings(workspace, lobby) do
		warn("[place] " .. message)
	end

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

	-- Daily rewards, quests, codes and badges.
	local badgeService = game:GetService("BadgeService")
	local metaService = MetaService.new(persistence, {
		awardBadge = function(player, badgeId)
			task.spawn(function()
				local ok, err = pcall(function()
					badgeService:AwardBadge(player.UserId, badgeId)
				end)
				if not ok then
					telemetry:LogError("BadgeAwardFailed", tostring(err), os.clock())
				end
			end)
		end,
	})

	-- Global boards on the lobby wall. They share the profile store's availability and scope.
	local leaderboards = LeaderboardService.new({
		boards = lobbyParts.leaderboards,
		getStore = function(storeName)
			-- A real DataStore is userdata and has no Available member; only the stand-in table does.
			if type(store) == "table" and store.Available == false then
				error("datastore unavailable")
			end
			return game:GetService("DataStoreService"):GetOrderedDataStore(storeName, scope)
		end,
		getName = function(userId)
			return Players:GetNameFromUserIdAsync(userId)
		end,
	})

	local net = {}
	for _, name in NET_EVENTS do
		net[name] = Remotes.Get(name)
	end

	local profileSync = Remotes.Get("ProfileSync")
	local function refreshLeaderstats(player)
		local public = persistence:GetPublicProfile(player)
		if public then
			local level = public.Progression and public.Progression.Level or 1
			Leaderstats.Update(player, public.Salvage or 0, public.Stats and public.Stats.BestRoomsCleared or 0, level)
			Nameplates.Update(player, level)
		end
		return public
	end

	-- Assigned just below; pushProfile only runs once players are about.
	local monetization

	local metaSync, notify = Remotes.Get("MetaSync"), Remotes.Get("Notify")
	local function pushMeta(player)
		if not FeatureFlags.DailyRewards then
			return
		end
		local state = metaService:GetState(player)
		if state then
			metaSync:FireClient(player, state)
		end
	end

	local function pushProfile(player)
		local public = refreshLeaderstats(player)
		if public then
			public.Passes = monetization and monetization:OwnedList(player) or {}
			-- Chat shows a VIP tag for pass holders (ChatTags).
			player:SetAttribute("VIP", table.find(public.Passes, "VIP") ~= nil)
			profileSync:FireClient(player, public)
			leaderboards:Submit(player, {
				Level = public.Progression and public.Progression.Xp or 0,
				Kills = public.Stats and public.Stats.EnemiesDefeated or 0,
				Extractions = public.Stats and public.Stats.RunsExtracted or 0,
			})
		end
	end

	-- Player-facing text for why a claim or code did not go through.
	local META_REASONS = {
		["profile not loaded"] = "Your data is offline right now. Rejoin to try again.",
		["already claimed"] = "Already claimed. Come back tomorrow!",
		["not complete"] = "Finish the quest first.",
		["unknown quest"] = "That quest has changed. Reopen Quests.",
		["invalid code"] = "That code does not exist.",
		["expired"] = "That code has expired.",
		["already redeemed"] = "You already redeemed that code.",
	}
	local function rewardText(result)
		local parts = {}
		if result.Coins and result.Coins > 0 then
			table.insert(parts, string.format("+%d coins", result.Coins))
		end
		if result.Xp and result.Xp > 0 then
			table.insert(parts, string.format("+%d XP", result.Xp))
		end
		if result.LevelCoins and result.LevelCoins > 0 then
			table.insert(parts, string.format("+%d level-up coins", result.LevelCoins))
		end
		return table.concat(parts, "  ")
	end
	local function onMetaResult(player, kind, result, reason)
		if kind ~= "Sync" then
			if result then
				local headline = kind == "Daily" and string.format("Day %d reward!", result.Streak)
					or kind == "Quest" and "Quest complete!"
					or "Code redeemed!"
				notify:FireClient(player, { Kind = "Reward", Text = headline .. "  " .. rewardText(result) })
				pushProfile(player)
				persistence:SaveInBackground(player, os.clock())
			else
				notify:FireClient(player, { Kind = "Error", Text = META_REASONS[reason] or "That did not go through." })
			end
		end
		pushMeta(player)
	end

	monetization = MonetizationService.new({
		marketplace = game:GetService("MarketplaceService"),
		persistence = persistence,
		getPlayer = function(userId)
			return Players:GetPlayerByUserId(userId)
		end,
		onChanged = pushProfile,
	})
	if FeatureFlags.Monetization then
		monetization:Bind()
	end

	-- The shop is open to anyone in the lobby; `director` is assigned just below, before any
	-- request can arrive.
	local director
	-- Rigs, the Depth Pact and achievements; changed in the lobby only, like the shop.
	local loadout = LoadoutService.new(persistence, {
		canChange = function(player)
			return director ~= nil and director:MatchFor(player) == nil
		end,
	})
	local shop = ShopService.new(persistence, {
		canShop = function(player)
			return director ~= nil and director:MatchFor(player) == nil
		end,
		ownsPass = function(player, passKey)
			return monetization:OwnsPass(player, passKey)
		end,
		onChanged = pushProfile,
	})

	director = ArenaDirector.new({
		parent = arenas,
		-- A finished run paid out: show the new balance straight away.
		onReleased = function(players)
			for _, player in players do
				pushProfile(player)
				pushMeta(player)
			end
		end,
		planeY = planeY,
		seed = seed,
		effectsRemote = Remotes.Get("ProjectileImpact"),
		shared = {
			telemetry = telemetry,
			net = net,
			world = WorldAdapter,
			persistence = persistence,
			runKeyPrefix = GameBootstrap._runKeyPrefix(game.JobId, HttpService:GenerateGUID(false)),
			-- Every finished run advances quests, may earn badges, and feeds the leaderboards.
			onRunEnd = function(player, summary)
				if not FeatureFlags.DailyRewards then
					return
				end
				for _, title in metaService:OnRunEnd(player, summary) do
					notify:FireClient(player, { Kind = "Quest", Text = "Quest complete: " .. title .. ". Claim it in Quests!" })
				end
			end,
			-- Shop and pass bonuses are read as each run starts.
			metaProvider = function(player)
				local meta = FeatureFlags.SalvageShop and shop:GetRunBonuses(player) or { stats = {} }
				for stat, delta in monetization:GetRunBonuses(player) do
					meta.stats[stat] = (meta.stats[stat] or 0) + delta
				end
				-- Roblox Premium members earn a little more from every run.
				if GameBootstrap._isPremium(player) then
					meta.stats.CoinMultiplier = (meta.stats.CoinMultiplier or 0) + MetaConfig.PremiumCoinBonus
				end
				-- The chosen rig bends the starting stats the same way the Armory does.
				if FeatureFlags.Loadouts then
					local rig = loadout:GetRig(player)
					for stat, delta in rig.Stats do
						meta.stats[stat] = (meta.stats[stat] or 0) + delta
					end
					meta.rig = rig.Id
				end
				return meta
			end,
			-- Each member's saved Pact; the match runs the group at the lowest shared ranks.
			pactProvider = function(player)
				return FeatureFlags.Loadouts and loadout:GetPact(player) or {}
			end,
		},
	})

	local lobbyStatus = Remotes.Get("LobbyReadyState")
	local function startSolo(player, now)
		local slot, reason = director:StartGroup({ player }, now)
		if not slot and reason == "all arenas busy" then
			lobbyStatus:FireClient(player, { Active = true, Notice = "Every arena is busy. Try again in a moment." })
		end
	end

	local LOADOUT_REASONS = {
		["profile not loaded"] = "Your data is offline right now. Rejoin to try again.",
		["in a run"] = "You can change that in the lobby.",
		["unknown rig"] = "That rig does not exist.",
		["locked"] = "That is still locked.",
		["unknown achievement"] = "That achievement has changed. Reopen the Journal.",
		["already claimed"] = "Already claimed.",
		["not complete"] = "Not complete yet.",
	}
	local function onLoadoutResult(player, kind, result, reason)
		if not result then
			notify:FireClient(player, { Kind = "Error", Text = LOADOUT_REASONS[reason] or "That did not go through." })
		elseif kind == "Achievement" then
			notify:FireClient(player, { Kind = "Reward", Text = "Achievement: " .. result.Title .. "!  " .. rewardText(result) })
			persistence:SaveInBackground(player, os.clock())
		elseif kind == "Rig" then
			notify:FireClient(player, { Kind = "Info", Text = "Rig selected: " .. result.Title })
		end
		pushProfile(player)
	end

	local router = RemoteRouter.new(function(player)
		return director:MatchFor(player)
	end, persistence, pushProfile, FeatureFlags.SalvageShop and shop or nil, {
		onStartRequest = startSolo,
		meta = FeatureFlags.DailyRewards and metaService or nil,
		onMetaResult = onMetaResult,
		loadout = FeatureFlags.Loadouts and loadout or nil,
		onLoadoutResult = onLoadoutResult,
	})
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
			if FeatureFlags.Monetization then
				monetization:RefreshOwnership(player)
			end
			pushProfile(player)
			pushMeta(player)
			metaService:AwardBadge(player, "Welcome")
			local dailyReady, questReady = false, false
			if FeatureFlags.DailyRewards then
				dailyReady, questReady = metaService:HasClaimable(player)
			end
			if dailyReady then
				notify:FireClient(player, { Kind = "Info", Text = "Your daily reward is ready! Open Daily to claim it." })
			elseif questReady then
				notify:FireClient(player, { Kind = "Info", Text = "A quest reward is waiting in Quests." })
			end
		end)
	end

	for _, player in Players:GetPlayers() do
		onPlayerAdded(player)
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	Players.PlayerRemoving:Connect(function(player)
		director:RemovePlayer(player, os.clock())
		router:ClearPlayer(player)
		monetization:ClearPlayer(player)
		metaService:ClearPlayer(player)
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
		if FeatureFlags.Leaderboards then
			leaderboards:Step(now)
		end

		-- Developer overlay feed. Nothing here reaches a normal player in a published build.
		if now >= nextDebugPush then
			nextDebugPush = now + DebugConfig.OverlayUpdateInterval
			reportRefusedPurchases()
			for _, player in Players:GetPlayers() do
				refreshLeaderstats(player)
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
		monetization = monetization,
		meta = metaService,
		leaderboards = leaderboards,
		loadout = loadout,
	}
end

function GameBootstrap._isPremium(player)
	local ok, premium = pcall(function()
		return player.MembershipType == Enum.MembershipType.Premium
	end)
	return ok and premium == true
end

-- Payout keys are stored in each profile's run ledger, so their prefix must never repeat across
-- server sessions. Studio has no JobId, and a fixed "studio" prefix made every Studio session's
-- first run reuse a key an earlier session had already paid: the ledger refused it and the
-- coins were never saved. A live server's JobId is already unique; Studio gets a fresh GUID.
function GameBootstrap._runKeyPrefix(jobId, guid)
	if type(jobId) == "string" and jobId ~= "" then
		return jobId
	end
	return "studio-" .. tostring(guid)
end

-- Settings and leftovers in the place file that break the game in ways the code cannot fix by
-- itself. Returns player-facing sentences; nothing is modified.
function GameBootstrap._placeWarnings(root, lobby)
	local warnings = {}
	local ok, streaming = pcall(function()
		return root.StreamingEnabled
	end)
	if ok and streaming == true then
		table.insert(warnings, "Workspace.StreamingEnabled is on. Arenas sit hundreds of studs from the lobby and "
			.. "players are teleported between them, so a room may not have streamed in when they land. "
			.. "Turn it off: Workspace > Properties > StreamingEnabled.")
	end
	local baseplate = root:FindFirstChild("Baseplate")
	if baseplate and baseplate:IsA("BasePart") then
		table.insert(warnings, "Workspace.Baseplate (from the Studio template) is still here. Its top is level "
			.. "with the lobby and arena floors, so they will flicker. Delete it before publishing.")
	end
	local lobbySpawn = lobby and lobby:FindFirstChild("LobbySpawn")
	for _, descendant in root:GetDescendants() do
		if descendant:IsA("SpawnLocation") and descendant ~= lobbySpawn then
			local parent = descendant.Parent
			table.insert(warnings, string.format("SpawnLocation '%s.%s' is outside the lobby, so players may spawn "
				.. "there instead of the hall. Delete it.", parent and parent.Name or "?", descendant.Name))
		end
	end
	return warnings
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
