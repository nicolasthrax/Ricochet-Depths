-- Run shape and pacing. A descent is deliberately short enough for a Roblox session.
local RunConfig = {}

RunConfig.Version = "0.4.0-dev"

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
RunConfig.HardRunTimeLimit = 900

RunConfig.Rooms = {
	{
		Id = "Atrium",
		DisplayName = "Collapsed Atrium",
		Layout = "Atrium",
		Kind = "Normal",
		Spawns = { { Archetype = "Drifter", Count = 6 } },
	},
	{
		Id = "Gallery",
		DisplayName = "Shattered Gallery",
		Layout = "Gallery",
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
		Kind = "Normal",
		Spawns = {
			{ Archetype = "Chaser", Count = 4 },
			{ Archetype = "Bulwark", Count = 2 },
		},
	},
	{
		Id = "WardenVault",
		DisplayName = "Warden Vault",
		Layout = "WardenVault",
		Kind = "Elite",
		Spawns = {
			{ Archetype = "WardenCore", Count = 1 },
			{ Archetype = "Chaser", Count = 2 },
		},
		-- While the core lives, escorts return on this delay to keep pressure on.
		EscortRespawn = { Archetype = "Chaser", Delay = 7, MaxAlive = 3 },
	},
}

-- An upgrade choice is offered after every room except the last.
RunConfig.OfferUpgradeAfterRoom = function(roomIndex)
	return roomIndex < #RunConfig.Rooms
end

function RunConfig.GetRoom(index)
	return RunConfig.Rooms[index]
end

function RunConfig.RoomCount()
	return #RunConfig.Rooms
end

return RunConfig
