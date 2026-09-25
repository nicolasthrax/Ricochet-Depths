-- Run shape and pacing. A descent is deliberately short enough for a Roblox session.
local RunConfig = {}

RunConfig.Version = "3.0.0"

-- Explicit state machine. MatchService only ever moves between these.
RunConfig.States = {
	Lobby = "Lobby",
	Starting = "Starting",
	Combat = "Combat",
	UpgradeChoice = "UpgradeChoice",
	Transition = "Transition",
	Results = "Results",
	Cleanup = "Cleanup",
}

RunConfig.BaseHealth = 100
-- Roblox's default Humanoid walk speed; the salvage shop's Stride adds to it for a run.
RunConfig.BaseWalkSpeed = 16
-- A downed player crawls at this speed until revived or the room ends.
RunConfig.DownedWalkSpeed = 6
-- Out-of-combat healing during a run: once Delay seconds pass without taking damage, a live
-- player heals PerSecond (plus the Armory's Mending) until full.
RunConfig.Regen = {
	Delay = 4,
	PerSecond = 1.5,
	-- How often a healing player's HUD is updated.
	PushInterval = 0.5,
}
-- Brief grace after spawning or respawning so a player cannot be chain-hit.
RunConfig.SpawnInvulnerability = 2.5
RunConfig.StartCountdown = 3
RunConfig.TransitionDuration = 2.5
-- How long the group has to vote on the next door (it closes early once everyone has voted).
-- The concept's co-op rule: a 10-second vote cap, then the default.
RunConfig.DoorVoteSeconds = 10
RunConfig.ResultsDuration = 15

-- Target descent length. Room count and spawn budgets are tuned against this.
RunConfig.TargetRunSeconds = 420
-- A room that somehow cannot be cleared is force-cleared rather than soft-locking the run.
RunConfig.RoomTimeLimit = 150
-- Depth pressure (FeatureFlags.Pressure): a normal room that drags on past After seconds starts
-- sending hunters, one every Delay seconds up to MaxAlive at once. Hunters are Swift champions
-- that drop nothing and never hold the room open; they go when it clears. A normal room that
-- reaches RoomTimeLimit anyway is still cleared, but its door reward and any Trial are lost.
RunConfig.Pressure = {
	After = 60,
	Delay = 8,
	MaxAlive = 3,
	Archetype = "Chaser",
	Champion = "Swift",
	-- The HUD starts counting down this many seconds before the first hunter.
	WarnSeconds = 15,
}
-- The boss is the exception: outlasting it is not beating it. Its room gets longer, and when
-- the time runs out the run ends out of time, without the extraction bonus.
RunConfig.BossRoomTimeLimit = 300
-- Safety net: a run can never outlive this, whatever state it is stuck in.
RunConfig.HardRunTimeLimit = 1800
-- A player this far below the room's floor has fallen out of the world; they are put back on
-- the spawn pad instead of dying in the void and respawning in the lobby.
RunConfig.FallRescueDepth = 30

-- Lobby sits far from the arenas so room geometry never overlaps it.
RunConfig.LobbyPosition = Vector3.new(0, 0, 600)
-- Where players land when a run ends: beside the lobby spawn.
RunConfig.LobbyReturnPosition = RunConfig.LobbyPosition + Vector3.new(0, 3, 28)

-- Concurrent runs: each group plays in its own arena slot, centred at X = index * Spacing.
RunConfig.Arenas = {
	MaxSlots = 6,
	Spacing = 500,
}
-- Run state is pushed to clients on every transition, and at most this often in between.
RunConfig.RunStateBroadcastInterval = 0.25

-- Token-bucket limits for every client-callable remote.
RunConfig.RemoteRules = {
	Fire = { Cooldown = 0.08, Burst = 4 },
	ChooseUpgrade = { Cooldown = 0.25, Burst = 3 },
	RequestStartRun = { Cooldown = 1, Burst = 2 },
	RequestReturnToLobby = { Cooldown = 1, Burst = 2 },
	UpdateSettings = { Cooldown = 0.5, Burst = 4 },
	PurchaseShopItem = { Cooldown = 0.4, Burst = 3 },
	EquipShopItem = { Cooldown = 0.3, Burst = 3 },
	ClaimDaily = { Cooldown = 1, Burst = 2 },
	ClaimQuest = { Cooldown = 0.4, Burst = 3 },
	RedeemCode = { Cooldown = 2, Burst = 3 },
	RequestMeta = { Cooldown = 0.5, Burst = 4 },
	SelectRig = { Cooldown = 0.4, Burst = 3 },
	SetPact = { Cooldown = 0.3, Burst = 4 },
	ClaimAchievement = { Cooldown = 0.4, Burst = 3 },
	Dash = { Cooldown = 0.25, Burst = 2 },
	ChooseSurge = { Cooldown = 0.2, Burst = 3 },
	ChooseDoor = { Cooldown = 0.2, Burst = 4 },
	UpgradeBuilding = { Cooldown = 0.4, Burst = 3 },
	MoveBuilding = { Cooldown = 0.2, Burst = 4 },
	ClaimBase = { Cooldown = 1, Burst = 2 },
	VisitBase = { Cooldown = 1, Burst = 2 },
	CheerBase = { Cooldown = 0.5, Burst = 3 },
	RequestBase = { Cooldown = 0.5, Burst = 4 },
	RerollOffer = { Cooldown = 0.5, Burst = 2 },
	RespecCard = { Cooldown = 0.5, Burst = 2 },
	UseRevive = { Cooldown = 1, Burst = 2 },
	SavePreset = { Cooldown = 0.5, Burst = 3 },
	ApplyPreset = { Cooldown = 0.5, Burst = 3 },
	PlayEmote = { Cooldown = 3, Burst = 1 },
	FeatureBase = { Cooldown = 2, Burst = 2 },
	WatchAd = { Cooldown = 5, Burst = 1 },
}

-- Lobby: two multiplayer gates of GateMinPlayers..GateCapacity. Once a gate holds the minimum,
-- a countdown runs (shorter when it fills) and its members descend together into their own
-- arena. A solo portal starts a one-player run at once, so every party size from 1 to 4 has a
-- way down (the concept's 1-4 player runs).
RunConfig.Lobby = {
	GateCapacity = 4,
	GateMinPlayers = 2,
	GateCountdown = 15,
	FullCountdown = 5,
	-- How often gate state is pushed to clients while it is not changing.
	GateBroadcastInterval = 0.5,
}

-- The descent passes through three zones, each with its own look and its own pool of rooms.
-- Order sets the sequence; difficulty climbs zone by zone.
RunConfig.Zones = {
	Ruins = { Id = "Ruins", DisplayName = "Upper Ruins", Order = 1 },
	Foundry = { Id = "Foundry", DisplayName = "The Foundry", Order = 2 },
	Abyss = { Id = "Abyss", DisplayName = "The Abyss", Order = 3 },
}

-- Every room a run can draw. Zone and Tier place a room in the run shape below; Markers pin a
-- spawn group to the layout's EnemySpawns, otherwise groups take markers in order.
--
-- 2.0: rooms fight in waves. Spawns is the first wave; each entry of Waves arrives later,
-- announced by circles on the floor, once WhenRemaining or fewer enemies are left (or After
-- seconds pass). An Objective room keeps its waves coming, looping, until the job is done.
local function wave(spawns, whenRemaining, after)
	return { Spawns = spawns, WhenRemaining = whenRemaining or 1, After = after or 18 }
end

RunConfig.Rooms = {
	-- Upper Ruins: teaching rooms. Drifters to learn the ricochet on, then Mites to chain.
	{
		Id = "Atrium",
		DisplayName = "Collapsed Atrium",
		Layout = "Atrium",
		Zone = "Ruins",
		Tier = 1,
		Kind = "Normal",
		Spawns = { { Archetype = "Drifter", Count = 5 } },
		Waves = {
			wave({ { Archetype = "Mite", Count = 6, Markers = { 1, 2, 3, 4, 5, 6 } } }),
		},
	},
	{
		Id = "Cistern",
		DisplayName = "Drowned Cistern",
		Layout = "Cistern",
		Zone = "Ruins",
		Tier = 1,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Drifter", Count = 4 },
			{ Archetype = "Chaser", Count = 1, Markers = { 5 } },
		},
		Waves = {
			wave({
				{ Archetype = "Mite", Count = 5, Markers = { 1, 2, 3, 4, 6 } },
				{ Archetype = "Chaser", Count = 1, Markers = { 8 } },
			}),
		},
	},
	{
		Id = "Gallery",
		DisplayName = "Shattered Gallery",
		Layout = "Gallery",
		Zone = "Ruins",
		Tier = 2,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Drifter", Count = 3 },
			{ Archetype = "Chaser", Count = 2, Markers = { 5, 6 } },
		},
		Waves = {
			wave({
				{ Archetype = "Mirror", Count = 1, Markers = { 1 } },
				{ Archetype = "Mite", Count = 6, Markers = { 2, 3, 4, 7, 8, 5 } },
			}),
			wave({ { Archetype = "Chaser", Count = 2, Markers = { 5, 6 } } }),
		},
	},
	{
		Id = "Crossing",
		DisplayName = "Fractured Crossing",
		Layout = "Crossing",
		Zone = "Ruins",
		Tier = 2,
		Kind = "Normal",
		-- Difficulty pass. About 85% of simulated runs ended here, and the dry run's damage
		-- breakdown put ~100% of the damage on Bulwark lunges (Chasers ~1%). Two Bulwarks
		-- lunging together was the wall, so the room keeps its four Chasers and fields one
		-- Bulwark, posted away from the spawn with open ground around it to flank through.
		Spawns = {
			{ Archetype = "Chaser", Count = 4, Markers = { 1, 2, 3, 4 } },
			{ Archetype = "Bulwark", Count = 1, Markers = { 9 } },
		},
		Waves = {
			wave({
				{ Archetype = "Mirror", Count = 1, Markers = { 5 } },
				{ Archetype = "Mite", Count = 5, Markers = { 1, 2, 3, 4, 7 } },
			}),
		},
	},
	-- Crystal Hunt: four crystals only a bank shot can crack, while the Ruins keep sending
	-- more. Breaking the last one wins the room.
	{
		Id = "Reliquary",
		DisplayName = "Sunken Reliquary",
		Layout = "Atrium",
		Zone = "Ruins",
		Tier = 2,
		Kind = "Normal",
		Objective = {
			Kind = "Crystals",
			Spots = { Vector2.new(-42, 42), Vector2.new(42, 42), Vector2.new(-24, -44), Vector2.new(24, -44) },
		},
		Spawns = { { Archetype = "Drifter", Count = 3, Markers = { 4, 5, 6 } } },
		Waves = {
			wave({ { Archetype = "Mite", Count = 5, Markers = { 2, 4, 5, 6, 1 } } }, 3, 12),
			wave({ { Archetype = "Chaser", Count = 2, Markers = { 4, 5 } }, { Archetype = "Mirror", Count = 1, Markers = { 6 } } }, 3, 14),
		},
	},
	-- Ruins mini-boss.
	{
		Id = "ColossusHall",
		DisplayName = "Hall of the Colossus",
		Layout = "Colosseum",
		Zone = "Ruins",
		Tier = 3,
		Kind = "MiniBoss",
		Spawns = {
			{ Archetype = "Colossus", Count = 1, Markers = { 1 } },
			{ Archetype = "Mite", Count = 4, Markers = { 2, 3, 5, 6 } },
		},
		HealOnClear = 0.35,
		-- 3.0: an extract point. The doors after it include "Bank loot".
		ExtractPoint = true,
	},

	-- The Foundry: tighter lanes, barrels, and enemies that punish straight shooting.
	{
		Id = "Smelter",
		DisplayName = "Cold Smelter",
		Layout = "Smelter",
		Zone = "Foundry",
		Tier = 1,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Drifter", Count = 2 },
			{ Archetype = "Chaser", Count = 3, Markers = { 1, 2, 4 } },
			{ Archetype = "Sentinel", Count = 1, Markers = { 3 } },
		},
		Waves = {
			wave({
				{ Archetype = "Sponge", Count = 1, Markers = { 5 } },
				{ Archetype = "Mite", Count = 6, Markers = { 1, 2, 4, 6, 7, 8 } },
			}),
		},
	},
	{
		Id = "Conveyor",
		DisplayName = "Stalled Conveyor",
		Layout = "Conveyor",
		Zone = "Foundry",
		Tier = 1,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Splitter", Count = 2, Markers = { 1, 2 } },
			{ Archetype = "Chaser", Count = 2, Markers = { 3, 4 } },
			{ Archetype = "Drifter", Count = 2, Markers = { 6, 7 } },
		},
		Waves = {
			wave({
				{ Archetype = "Mirror", Count = 2, Markers = { 1, 2 } },
				{ Archetype = "Mite", Count = 5, Markers = { 3, 4, 5, 6, 7 } },
			}),
		},
	},
	{
		Id = "Crucible",
		DisplayName = "The Crucible",
		Layout = "Crucible",
		Zone = "Foundry",
		Tier = 2,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Bulwark", Count = 1, Markers = { 9 } },
			{ Archetype = "Chaser", Count = 2, Markers = { 1, 2 } },
			{ Archetype = "Splitter", Count = 1, Markers = { 8 } },
			{ Archetype = "Drifter", Count = 2, Markers = { 3, 4 } },
		},
		Waves = {
			wave({
				{ Archetype = "SplitterKing", Count = 1, Markers = { 2 } },
				{ Archetype = "Mite", Count = 4, Markers = { 1, 3, 4, 5 } },
			}),
		},
	},
	{
		Id = "Forgeworks",
		DisplayName = "Forgeworks",
		Layout = "Forgeworks",
		Zone = "Foundry",
		Tier = 2,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Bulwark", Count = 1, Markers = { 1 } },
			{ Archetype = "Sentinel", Count = 1, Markers = { 2 } },
			{ Archetype = "Chaser", Count = 2, Markers = { 3, 4 } },
			{ Archetype = "Splitter", Count = 1, Markers = { 6 } },
		},
		Waves = {
			wave({
				{ Archetype = "Sponge", Count = 2, Markers = { 5, 6 } },
				{ Archetype = "Mite", Count = 6, Markers = { 1, 2, 3, 4, 7, 8 } },
			}),
		},
	},
	-- Hold the Beacon: stand in the ring while the Foundry throws everything at you.
	{
		Id = "SignalTower",
		DisplayName = "Signal Tower",
		Layout = "Smelter",
		Zone = "Foundry",
		Tier = 2,
		Kind = "Normal",
		Objective = { Kind = "Beacon", Spot = Vector2.new(0, -6) },
		Spawns = { { Archetype = "Chaser", Count = 2, Markers = { 1, 2 } } },
		Waves = {
			wave({ { Archetype = "Mite", Count = 6, Markers = { 1, 2, 4, 5, 6, 7 } } }, 3, 7),
			wave({ { Archetype = "Splitter", Count = 2, Markers = { 1, 2 } }, { Archetype = "Drifter", Count = 2, Markers = { 4, 5 } } }, 3, 8),
			wave({ { Archetype = "Sentinel", Count = 1, Markers = { 3 } }, { Archetype = "Mite", Count = 5, Markers = { 1, 2, 6, 7, 8 } } }, 3, 8),
		},
	},
	-- Foundry mini-boss.
	{
		Id = "ForgeHall",
		DisplayName = "The Forge Hall",
		Layout = "ForgeHall",
		Zone = "Foundry",
		Tier = 3,
		Kind = "MiniBoss",
		Spawns = {
			{ Archetype = "ForgePress", Count = 1, Markers = { 1 } },
			{ Archetype = "Mite", Count = 4, Markers = { 2, 3, 5, 6 } },
		},
		HealOnClear = 0.35,
		-- 3.0: an extract point. The doors after it include "Bank loot".
		ExtractPoint = true,
	},

	-- The Abyss: the hardest mixes, magnets that bend your shots, then the Warden itself.
	{
		Id = "Rift",
		DisplayName = "The Rift",
		Layout = "Rift",
		Zone = "Abyss",
		Tier = 1,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Bulwark", Count = 1, Markers = { 1 } },
			{ Archetype = "Phaser", Count = 2, Markers = { 5, 6 } },
			{ Archetype = "Chaser", Count = 2, Markers = { 7, 8 } },
			{ Archetype = "Drifter", Count = 2, Markers = { 3, 4 } },
		},
		Waves = {
			wave({
				{ Archetype = "Magnet", Count = 1, Markers = { 2 } },
				{ Archetype = "Mite", Count = 6, Markers = { 1, 3, 4, 5, 6, 7 } },
			}),
		},
	},
	{
		Id = "Spire",
		DisplayName = "Hanging Spire",
		Layout = "Spire",
		Zone = "Abyss",
		Tier = 1,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Sentinel", Count = 1, Markers = { 3 } },
			{ Archetype = "Phaser", Count = 2, Markers = { 1, 2 } },
			{ Archetype = "Chaser", Count = 3, Markers = { 5, 6, 7 } },
		},
		Waves = {
			wave({
				{ Archetype = "Mirror", Count = 2, Markers = { 1, 2 } },
				{ Archetype = "Mite", Count = 5, Markers = { 4, 5, 6, 7, 8 } },
			}),
		},
	},
	{
		Id = "Hollow",
		DisplayName = "Starless Hollow",
		Layout = "Hollow",
		Zone = "Abyss",
		Tier = 1,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Bulwark", Count = 1, Markers = { 1 } },
			{ Archetype = "Sentinel", Count = 1, Markers = { 6 } },
			{ Archetype = "Phaser", Count = 2, Markers = { 2, 3 } },
			{ Archetype = "Chaser", Count = 2, Markers = { 7, 8 } },
		},
		Waves = {
			wave({
				{ Archetype = "Magnet", Count = 1, Markers = { 4 } },
				{ Archetype = "Sponge", Count = 1, Markers = { 5 } },
				{ Archetype = "Mite", Count = 5, Markers = { 1, 2, 3, 7, 8 } },
			}),
		},
	},
	{
		Id = "WardenVault",
		DisplayName = "Warden Vault",
		Layout = "WardenVault",
		Zone = "Abyss",
		Tier = 2,
		Kind = "Elite",
		Spawns = {
			{ Archetype = "WardenCore", Count = 1 },
			{ Archetype = "Chaser", Count = 2 },
		},
		-- While the core lives, escorts return on this delay to keep pressure on.
		EscortRespawn = { Archetype = "Chaser", Delay = 7, MaxAlive = 3 },
		-- Everyone walks into the Throne at full health.
		HealOnClear = 1,
	},
	{
		Id = "Throne",
		DisplayName = "The Throne",
		Layout = "Throne",
		Zone = "Abyss",
		Tier = 3,
		Kind = "Boss",
		-- The Warden Prime alone; it summons its own Shards from its second phase.
		Spawns = { { Archetype = "WardenPrime", Count = 1, Markers = { 1 } } },
	},
}

-- 3.0: the first descent, a new player's first 60 seconds (RunConfig.FirstDescent). Tier 0, so
-- no run shape slot or door ever draws them; the plan puts them in front of a normal run.
local TUTORIAL_ROOMS = {
	-- A tight pack of harmless Drifters straight ahead of the spawn: the first hit lands within
	-- seconds, and the first bank shot clears half the pack.
	{
		Id = "FirstPit",
		DisplayName = "The First Pit",
		Layout = "Atrium",
		Zone = "Ruins",
		Tier = 0,
		Kind = "Tutorial",
		Spawns = { { Archetype = "Drifter", Count = 6, Markers = { 6 } } },
	},
	-- A pair round: sentries to bank shots off, and a few Mites that close in.
	{
		Id = "FirstPair",
		DisplayName = "Echoing Stair",
		Layout = "Atrium",
		Zone = "Ruins",
		Tier = 0,
		Kind = "Tutorial",
		Spawns = {
			{ Archetype = "Drifter", Count = 4, Markers = { 1, 3 } },
			{ Archetype = "Mite", Count = 4, Markers = { 2, 6 } },
		},
	},
	-- A mini-elite that bursts into coins, at an extract point: the first "Bank loot" choice.
	{
		Id = "FirstElite",
		DisplayName = "The Hoard Keeper",
		Layout = "Colosseum",
		Zone = "Ruins",
		Tier = 0,
		Kind = "Elite",
		Spawns = {
			{ Archetype = "Bulwark", Count = 1, Markers = { 1 } },
			{ Archetype = "Drifter", Count = 3, Markers = { 2, 3, 5 } },
		},
		CoinBurst = 40,
		HealOnClear = 0.5,
		ExtractPoint = true,
	},
}
for _, room in TUTORIAL_ROOMS do
	table.insert(RunConfig.Rooms, room)
end

-- The scripted opening for a player who has never descended. Rooms run first, then the normal
-- run shape; ForceCards[n] puts those cards into the offer after room n. Split Shot twice: the
-- duplicate completes a fusion, and the first descent offers it at once ("try it now"), before
-- the Hoard Keeper, as the concept's first 60 seconds lay out. Banner is the first thing read.
RunConfig.FirstDescent = {
	Rooms = { "FirstPit", "FirstPair", "FirstElite" },
	ForceCards = { [1] = { "SplitShot" }, [2] = { "SplitShot" } },
	Banner = "BOUNCE SHOTS. BREAK EVERYTHING.",
}

-- Card rounds: one free reroll per run (more cost a Reroll token each), and one free respec per
-- run during the first RespecRounds upgrade rounds (undo the card just taken and pick again).
RunConfig.Cards = {
	FreeRerolls = 1,
	RespecRounds = 2,
	-- The use counter a spent Reroll token is recorded against (PlayerDataService purchase path).
	RerollUseId = "RerollUse",
}

-- Revive tokens (earned in daily rewards, or the paid Revive product): spent while down, once a
-- run, to get straight back up. When everyone is down and someone could still revive, the run
-- waits GraceSeconds before it is lost.
RunConfig.Revive = {
	GraceSeconds = 8,
	HealthFraction = 0.5,
	UseId = "ReviveUse",
}

-- More players, tougher enemies: every member past the first adds this much enemy health. A
-- solo run is never scaled down or penalised.
RunConfig.PartyScaling = {
	EnemyHealthPerExtra = 0.35,
}

-- The shape of every run: one room per slot, drawn at random from the rooms matching the
-- slot's Zone and Tier (never the same room twice), or the fixed Room named. 2.0: each zone
-- ends in a mini-boss, and after every room the group chooses the next door.
RunConfig.RunShape = {
	{ Zone = "Ruins", Tier = 1 },
	{ Zone = "Ruins", Tier = 2 },
	{ Room = "ColossusHall" },
	{ Zone = "Foundry", Tier = 1 },
	{ Zone = "Foundry", Tier = 2 },
	{ Room = "ForgeHall" },
	{ Zone = "Abyss", Tier = 1 },
	{ Room = "WardenVault" },
	{ Room = "Throne" },
}

-- Rooms in a run: one per slot of the run shape.
function RunConfig.RoomCount()
	return #RunConfig.RunShape
end

-- An upgrade choice is offered after every room except the last.
RunConfig.OfferUpgradeAfterRoom = function(roomIndex)
	return roomIndex < RunConfig.RoomCount()
end

function RunConfig.GetRoomById(roomId)
	for _, room in RunConfig.Rooms do
		if room.Id == roomId then
			return room
		end
	end
	return nil
end

return RunConfig
