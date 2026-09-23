-- Coins: dropped by kills as spinning pickups. Walk near one and it flies to you; anything still
-- on the floor when a room clears goes to the nearest player. Coins are the only currency, and
-- the profile keeps them under its original "Salvage" field so older balances carry over.
return {
	PoolSize = 60, -- pickups per arena; past this, value is held and paid at the room-clear sweep
	MaxPickupsPerDrop = 5,
	ScatterRadius = 2.5, -- studs from the kill, on the floor plane
	MagnetRadius = 8, -- a player within this (plus Coin Magnet) pulls coins in
	CollectRadius = 2.6, -- and collects them at this distance
	MagnetSpeed = 36, -- studs per second while pulled
	HeightBelowPlane = 1.4, -- coins float this far below the shot plane, about waist height
	Size = Vector3.new(0.35, 1.6, 1.6), -- a cylinder standing on edge
	Color = Color3.fromRGB(255, 206, 72),
	StoragePosition = Vector3.new(0, -520, 0),
}
