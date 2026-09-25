-- Constructs and wires every server system. Main.server.luau does nothing but call this.
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ArenaDirector = require(script.Parent.ArenaDirector)
local BaseBuilder = require(script.Parent.BaseBuilder)
local BaseConfig = require(ReplicatedStorage:WaitForChild("BaseConfig"))
local BaseService = require(script.Parent.BaseService)
local DailyModifierConfig = require(ReplicatedStorage:WaitForChild("DailyModifierConfig"))
local DataStoreProvider = require(script.Parent.DataStoreProvider)
local DebugConfig = require(ReplicatedStorage:WaitForChild("DebugConfig"))
local FeatureFlags = require(ReplicatedStorage:WaitForChild("FeatureFlags"))
local FriendCache = require(script.Parent.FriendCache)
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
local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local RemoteRouter = require(script.Parent.RemoteRouter)
local Remotes = require(ReplicatedStorage:WaitForChild("Remotes"))
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local RunConfig = require(ReplicatedStorage:WaitForChild("RunConfig"))
local ShopService = require(script.Parent.ShopService)
local Signage = require(script.Parent.Signage)
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
	"SurgeOffer",
	"SurgeResolved",
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

	-- Roblox friendships between players on this server, looked up as they join (the party bonus).
	local friends = FriendCache.new(function(a, b)
		return a:IsFriendsWith(b.UserId)
	end)

	-- Today's biome modifier, as the hub sign, the HUD and the lobby panel show it.
	local function todaysModifier()
		if not FeatureFlags.DailyModifiers then
			return nil
		end
		local now = os.time()
		return DailyModifierConfig.Describe(DailyModifierConfig.Today(now), MetaConfig.SecondsUntilReset(now))
	end

	local metaSync, notify = Remotes.Get("MetaSync"), Remotes.Get("Notify")
	local function pushMeta(player)
		if not FeatureFlags.DailyRewards then
			return
		end
		local state = metaService:GetState(player)
		if state then
			state.Modifier = todaysModifier()
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

	-- The home base: the service that builds, claims and cheers, and the Outpost's plots that
	-- show it. Managed in the lobby only, like the shop.
	local baseSync = Remotes.Get("BaseSync")
	local builder
	local pushBase
	local base = BaseService.new(persistence, {
		canManage = function(player)
			return director ~= nil and director:MatchFor(player) == nil
		end,
		extraCapHours = function(player)
			return monetization:GetExtraCapHours(player)
		end,
		onChanged = function(player)
			pushProfile(player)
			pushBase(player)
		end,
		onFirstBuild = function()
			telemetry:Log("FirstBaseUpgrade", {}, os.clock())
		end,
	})
	-- Sends the player their base and rebuilds their plot to match. open asks the client to show
	-- the panel (the Hearth's "Manage base" prompt).
	pushBase = function(player, open)
		if not FeatureFlags.BaseBuilding then
			return
		end
		local state = base:GetState(player)
		if state then
			state.Open = open == true
			state.PlotIndex = player:GetAttribute("PlotIndex")
			baseSync:FireClient(player, state)
			if builder then
				builder:Refresh(player, state)
			end
		end
	end

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
			-- Building, pass and rig bonuses, and the equipped trail, are read as each run starts.
			metaProvider = function(player)
				local meta = { stats = {}, trail = FeatureFlags.SalvageShop and shop:GetTrail(player) or nil }
				if FeatureFlags.BaseBuilding then
					for stat, delta in base:GetRunBonuses(player) do
						meta.stats[stat] = (meta.stats[stat] or 0) + delta
					end
				end
				for stat, delta in monetization:GetRunBonuses(player) do
					meta.stats[stat] = (meta.stats[stat] or 0) + delta
				end
				-- Roblox Premium members earn a little more from every run.
				if GameBootstrap._isPremium(player) then
					meta.stats.CoinMultiplier = (meta.stats.CoinMultiplier or 0) + MetaConfig.PremiumCoinBonus
				end
				-- The account level gates which cards can be offered (gradual unlocks).
				meta.level = ProgressionConfig.LevelFor(persistence:GetXp(player))
				-- The chosen rig bends the starting stats the same way the buildings do.
				if FeatureFlags.Loadouts then
					local rig = loadout:GetRig(player)
					for stat, delta in rig.Stats do
						meta.stats[stat] = (meta.stats[stat] or 0) + delta
					end
					meta.rig = rig.Id
				end
				return meta
			end,
			wallClock = os.time,
			areFriends = function(a, b)
				return friends:AreFriends(a, b)
			end,
			-- Each member's saved Pact; the match runs the group at the lowest shared ranks.
			pactProvider = function(player)
				return FeatureFlags.Loadouts and loadout:GetPact(player) or {}
			end,
		},
	})

	local lobbyStatus = Remotes.Get("LobbyReadyState")
	local function startSolo(player, now, options)
		local slot, reason = director:StartGroup({ player }, now, options)
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

	local BASE_REASONS = {
		["profile not loaded"] = "Your data is offline right now. Rejoin to try again.",
		["in a run"] = "You can build between runs.",
		["base disabled"] = "The Outpost is closed right now.",
		["hearth too low"] = "Raise your Camp Hearth first.",
		["insufficient salvage"] = "Not enough coins yet. Descend for more!",
		["max level"] = "That building is fully upgraded.",
		["tile taken"] = "Something already stands there.",
		["invalid tile"] = "Pick a tile on your grid.",
		["no free tile"] = "Your grid is full.",
		["nothing to claim"] = "Your Salvage Yard is empty. Come back later!",
		["not built"] = "Build it first.",
		["unknown building"] = "That building has changed. Reopen the base.",
		["already cheered"] = "You already cheered this base today.",
		["own base"] = "That is your own base!",
	}
	local function onBaseResult(player, kind, ok, result)
		if kind == "Sync" then
			pushBase(player)
		elseif not ok then
			notify:FireClient(player, { Kind = "Error", Text = BASE_REASONS[result] or "That did not go through." })
			pushBase(player)
		elseif kind == "Upgrade" then
			local building = BaseConfig.Get(result.Id)
			local verb = result.Level == 1 and building.StartLevel == 0 and "built" or "upgraded to Lv" .. result.Level
			notify:FireClient(player, { Kind = "Reward", Text = string.format("%s %s!", building.Title, verb) })
		elseif kind == "Claim" then
			notify:FireClient(player, { Kind = "Reward", Text = string.format("+%d coins from the Salvage Yard", result.Coins) })
		end
	end

	-- Visiting: your own plot (userId nil) or another player's on this server. Lobby only.
	local function visitBase(player, userId)
		if not FeatureFlags.BaseBuilding then
			return
		end
		if director:MatchFor(player) then
			notify:FireClient(player, { Kind = "Error", Text = "You can visit the Outpost between runs." })
			return
		end
		local target = userId and Players:GetPlayerByUserId(userId) or player
		local _, index = builder:PlotFor(target or player)
		if not target or not index then
			notify:FireClient(player, { Kind = "Error", Text = "That base has no plot on this server." })
			return
		end
		WorldAdapter.Teleport(player, builder:EntryPosition(index))
		if target ~= player then
			notify:FireClient(player, { Kind = "Info", Text = string.format("%s's outpost. Cheer at their Hearth!", target.Name) })
		end
	end

	local function cheerBase(player, owner)
		local ok, result = base:Cheer(player, owner)
		if not ok then
			notify:FireClient(player, { Kind = "Error", Text = BASE_REASONS[result] or "That did not go through." })
			return
		end
		local mine = result.VisitorCoins > 0 and string.format("  +%d coins", result.VisitorCoins) or ""
		notify:FireClient(player, { Kind = "Reward", Text = string.format("You cheered %s's base!%s", owner.Name, mine) })
		local theirs = result.OwnerCoins > 0 and string.format("  +%d coins", result.OwnerCoins) or ""
		notify:FireClient(owner, { Kind = "Reward", Text = string.format("%s cheered your base!%s", player.Name, theirs) })
	end

	builder = BaseBuilder.new(workspace, RunConfig.LobbyPosition, {
		onManage = function(player, owner)
			if owner == player then
				pushBase(player, true)
			elseif owner then
				notify:FireClient(player, { Kind = "Info", Text = string.format("This is %s's outpost. Cheer them on!", owner.Name) })
			end
		end,
		onCheer = cheerBase,
		onReturn = function(player)
			WorldAdapter.Teleport(player, RunConfig.LobbyReturnPosition)
		end,
	})

	local router = RemoteRouter.new(function(player)
		return director:MatchFor(player)
	end, persistence, pushProfile, FeatureFlags.SalvageShop and shop or nil, {
		onStartRequest = startSolo,
		meta = FeatureFlags.DailyRewards and metaService or nil,
		onMetaResult = onMetaResult,
		loadout = FeatureFlags.Loadouts and loadout or nil,
		onLoadoutResult = onLoadoutResult,
		base = FeatureFlags.BaseBuilding and base or nil,
		onBaseResult = onBaseResult,
		onVisitBase = visitBase,
		onCheerBase = function(player, userId)
			local owner = Players:GetPlayerByUserId(userId)
			if owner then
				cheerBase(player, owner)
			end
		end,
	})
	router:Bind()

	soloPrompt.Triggered:Connect(function(player)
		startSolo(player, os.clock())
	end)

	-- The Cosmetics kiosk only opens the view; every purchase still goes through ShopService.
	-- With the shop off there is no entry point at all.
	local shopOpen, shopResult = Remotes.Get("ShopOpen"), Remotes.Get("ShopResult")
	if FeatureFlags.SalvageShop then
		lobbyParts.cosmeticsPrompt.Triggered:Connect(function(player)
			pushProfile(player)
			shopOpen:FireClient(player, "Cosmetics")
		end)
	else
		lobbyParts.cosmeticsPrompt.Enabled = false
	end
	-- The Outpost kiosk takes you to your own plot.
	if FeatureFlags.BaseBuilding then
		lobbyParts.outpostPrompt.Triggered:Connect(function(player)
			visitBase(player, nil)
		end)
	else
		lobbyParts.outpostPrompt.Enabled = false
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

	-- The hub sign shows today's modifier, reprinted when the UTC day turns.
	local modifierShown = nil
	local function refreshModifierSign()
		local modifier = todaysModifier()
		local text = modifier and string.format("TODAY: %s\n%s", string.upper(modifier.Title), modifier.Text)
			or "TODAY IN THE DEPTHS"
		if text ~= modifierShown and lobbyParts.modifierBoard then
			modifierShown = text
			Signage.SetText(lobbyParts.modifierBoard, text)
		end
	end
	refreshModifierSign()

	local function onPlayerAdded(player)
		friends:Learn(player, Players:GetPlayers())
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
			if FeatureFlags.BaseBuilding then
				builder:Assign(player)
			end
			pushProfile(player)
			pushMeta(player)
			pushBase(player)
			metaService:AwardBadge(player, "Welcome")
			-- No title card and no lobby wall: a player who has never descended goes straight
			-- into the scripted first descent once their character is standing in the hall.
			local public = persistence:GetPublicProfile(player)
			if GameBootstrap._wantsFirstDescent(public) then
				if not player.Character then
					player.CharacterAdded:Wait()
				end
				if director:MatchFor(player) == nil and player.Parent ~= nil then
					startSolo(player, os.clock(), { firstDescent = true })
				end
			end
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
		builder:Release(player)
		friends:Forget(player)
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
			refreshModifierSign()
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
		base = base,
		builder = builder,
	}
end

-- Whether a freshly loaded profile should be dropped into the first descent. A read-only session
-- never is: it could never record having done it, and would repeat it on every join.
function GameBootstrap._wantsFirstDescent(public)
	return FeatureFlags.FirstDescent == true
		and type(public) == "table"
		and not public.ReadOnly
		and type(public.Flags) == "table"
		and public.Flags.FirstDescentDone == false
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
