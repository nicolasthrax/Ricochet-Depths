-- Run shape and pacing. A descent is deliberately short enough for a Roblox session.
local RunConfig = {}

RunConfig.Version = "0.7.0-dev"

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
-- Brief grace after spawning or respawning so a player cannot be chain-hit.
RunConfig.SpawnInvulnerability = 2.5
RunConfig.StartCountdown = 3
RunConfig.TransitionDuration = 2.5
RunConfig.ResultsDuration = 15

-- Target descent length. Room count and spawn budgets are tuned against this.
RunConfig.TargetRunSeconds = 420
-- A room that somehow cannot be cleared is force-cleared rather than soft-locking the run.
RunConfig.RoomTimeLimit = 150
-- Safety net: a run can never outlive this, whatever state it is stuck in.
RunConfig.HardRunTimeLimit = 1200

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
}

-- Lobby: two multiplayer gates of GateMinPlayers..GateCapacity. Once a gate holds the minimum,
-- a countdown runs (shorter when it fills) and its members descend together into their own
-- arena. A solo portal starts a one-player run at once.
RunConfig.Lobby = {
	GateCapacity = 8,
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
RunConfig.Rooms = {
	-- Upper Ruins: teaching rooms. Drifters to learn the ricochet on, then the first Chasers.
	{
		Id = "Atrium",
		DisplayName = "Collapsed Atrium",
		Layout = "Atrium",
		Zone = "Ruins",
		Tier = 1,
		Kind = "Normal",
		Spawns = { { Archetype = "Drifter", Count = 6 } },
	},
	{
		Id = "Cistern",
		DisplayName = "Drowned Cistern",
		Layout = "Cistern",
		Zone = "Ruins",
		Tier = 1,
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Drifter", Count = 5 },
			{ Archetype = "Chaser", Count = 1, Markers = { 5 } },
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
			{ Archetype = "Drifter", Count = 4 },
			{ Archetype = "Chaser", Count = 3 },
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
	},

	-- The Foundry: tighter lanes and more Chasers; Bulwarks start guarding the back rooms.
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
	},

	-- The Abyss: the hardest mixes, then the Warden itself.
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

-- The shape of every run: one room per slot, drawn at random from the rooms matching the
-- slot's Zone and Tier (never the same room twice), or the fixed Room named.
RunConfig.RunShape = {
	{ Zone = "Ruins", Tier = 1 },
	{ Zone = "Ruins", Tier = 2 },
	{ Zone = "Foundry", Tier = 1 },
	{ Zone = "Foundry", Tier = 2 },
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
