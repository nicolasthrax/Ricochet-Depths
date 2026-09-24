-- How each enemy looks: a model of simple parts drawn on the client over the server's hitbox.
-- Cosmetic only; the hitbox (EnemyConfig Size) still decides every hit.
--
-- Offsets are in the enemy's own frame, from the hitbox centre: X right, Y up, -Z forward (the
-- way it faces). Roles colour a part:
--   Body  the live hitbox colour, so telegraph flashes show on the whole model
--   Glow  neon, the live colour washed towards white
--   Eye   neon, EyeColor
--   Dark  metal, DarkColor
-- Rings are Count copies of one part orbiting the body at Radius, Height, Speed (deg/s) and
-- Tilt (degrees about the enemy's X axis).
local EnemyVisualConfig = {}

EnemyVisualConfig.EyeColor = Color3.fromRGB(255, 250, 236)
EnemyVisualConfig.DarkColor = Color3.fromRGB(36, 38, 50)
-- How far Glow parts are washed towards white.
EnemyVisualConfig.GlowWash = 0.35

local function part(name, shape, size, offset, role)
	return { Name = name, Shape = shape, Size = size, Offset = offset, Role = role }
end

EnemyVisualConfig.Archetypes = {
	-- A drifting eye with a little orbit of motes: harmless, and reads that way.
	Drifter = {
		Bob = 0.4,
		BobRate = 0.7,
		Parts = {
			part("Core", "Ball", Vector3.new(2.6, 2.6, 2.6), Vector3.new(0, 0.4, 0), "Body"),
			part("Eye", "Ball", Vector3.new(1, 1, 1), Vector3.new(0, 0.6, -1.0), "Eye"),
			part("Pupil", "Ball", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, 0.6, -1.4), "Dark"),
			part("Tail", "Ball", Vector3.new(1.2, 1.2, 1.2), Vector3.new(0, -1.3, 0.3), "Glow"),
		},
		Rings = {
			{ Name = "Mote", Shape = "Ball", Size = Vector3.new(0.5, 0.5, 0.5), Count = 6, Radius = 2.1, Height = 0.4, Speed = 120, Tilt = 20, Role = "Glow" },
		},
	},

	-- Low, fast and pointed: a scuttling hull with a finned back and two bright eyes.
	Chaser = {
		Bob = 0.12,
		BobRate = 4,
		Parts = {
			part("Hull", "Block", Vector3.new(2.4, 1.4, 2.8), Vector3.new(0, -1.6, 0.2), "Body"),
			part("Nose", "Wedge", Vector3.new(2.2, 1.1, 1.3), Vector3.new(0, -1.75, -1.85), "Body"),
			part("EyeLeft", "Ball", Vector3.new(0.45, 0.45, 0.45), Vector3.new(-0.55, -1.0, -1.3), "Eye"),
			part("EyeRight", "Ball", Vector3.new(0.45, 0.45, 0.45), Vector3.new(0.55, -1.0, -1.3), "Eye"),
			part("FinFront", "Wedge", Vector3.new(0.3, 0.8, 1.0), Vector3.new(0, -0.5, -0.5), "Dark"),
			part("FinBack", "Wedge", Vector3.new(0.3, 0.8, 1.0), Vector3.new(0, -0.5, 0.7), "Dark"),
			part("Tailfin", "Block", Vector3.new(1.8, 0.2, 0.6), Vector3.new(0, -1.1, 1.5), "Glow"),
			part("LegFrontLeft", "Block", Vector3.new(0.35, 0.8, 0.35), Vector3.new(-1.0, -2.6, -0.7), "Dark"),
			part("LegFrontRight", "Block", Vector3.new(0.35, 0.8, 0.35), Vector3.new(1.0, -2.6, -0.7), "Dark"),
			part("LegBackLeft", "Block", Vector3.new(0.35, 0.8, 0.35), Vector3.new(-1.0, -2.6, 1.0), "Dark"),
			part("LegBackRight", "Block", Vector3.new(0.35, 0.8, 0.35), Vector3.new(1.0, -2.6, 1.0), "Dark"),
		},
	},

	-- Heavy and square-shouldered, a visor slit on a domed head. Its shield slab is drawn by the
	-- server, where the shield arc actually is.
	Bulwark = {
		Bob = 0,
		Parts = {
			part("Torso", "Block", Vector3.new(3.0, 3.2, 3.2), Vector3.new(0, -1.1, 0.2), "Body"),
			part("Head", "Ball", Vector3.new(2.2, 2.2, 2.2), Vector3.new(0, 0.9, 0.3), "Dark"),
			part("Visor", "Block", Vector3.new(1.6, 0.35, 0.3), Vector3.new(0, 1.0, -0.75), "Eye"),
			part("ShoulderLeft", "Block", Vector3.new(0.9, 1.3, 2.6), Vector3.new(-1.75, -0.1, 0.2), "Dark"),
			part("ShoulderRight", "Block", Vector3.new(0.9, 1.3, 2.6), Vector3.new(1.75, -0.1, 0.2), "Dark"),
			part("Core", "Block", Vector3.new(1.0, 1.0, 0.3), Vector3.new(0, -0.9, -1.45), "Glow"),
			part("FootLeft", "Block", Vector3.new(1.1, 0.6, 1.8), Vector3.new(-0.9, -2.7, 0.1), "Dark"),
			part("FootRight", "Block", Vector3.new(1.1, 0.6, 1.8), Vector3.new(0.9, -2.7, 0.1), "Dark"),
		},
	},

	-- The vault's heart: a glowing core and eye inside two counter-spinning rings.
	WardenCore = {
		Bob = 0.35,
		BobRate = 0.45,
		Parts = {
			part("Core", "Ball", Vector3.new(3.2, 3.2, 3.2), Vector3.new(0, 0.4, 0), "Glow"),
			part("Eye", "Ball", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 0.5, -1.35), "Eye"),
			part("Plinth", "Block", Vector3.new(3.6, 0.6, 3.6), Vector3.new(0, -2.5, 0), "Dark"),
			part("PylonLeft", "Block", Vector3.new(0.6, 2.6, 0.6), Vector3.new(-3.0, -0.8, 0), "Body"),
			part("PylonRight", "Block", Vector3.new(0.6, 2.6, 0.6), Vector3.new(3.0, -0.8, 0), "Body"),
		},
		Rings = {
			{ Name = "Plate", Shape = "Block", Size = Vector3.new(0.6, 0.7, 1.3), Count = 8, Radius = 3.1, Height = 0.4, Speed = 70, Tilt = 0, Role = "Dark" },
			{ Name = "Spark", Shape = "Ball", Size = Vector3.new(0.6, 0.6, 0.6), Count = 6, Radius = 2.5, Height = 0.4, Speed = -130, Tilt = 35, Role = "Glow" },
		},
	},

	-- A crystalline cluster: three facets around a glowing seam, which is where it splits.
	Splitter = {
		Bob = 0.15,
		BobRate = 1.5,
		Parts = {
			part("Core", "Block", Vector3.new(1.8, 3.0, 1.8), Vector3.new(0, -0.6, 0), "Body"),
			part("FacetLeft", "Wedge", Vector3.new(1.2, 2.4, 1.6), Vector3.new(-1.1, -0.9, 0), "Body"),
			part("FacetRight", "Wedge", Vector3.new(1.2, 2.4, 1.6), Vector3.new(1.1, -0.9, 0), "Body"),
			part("Seam", "Block", Vector3.new(0.3, 3.2, 1.9), Vector3.new(0, -0.6, 0), "Glow"),
			part("EyeLeft", "Ball", Vector3.new(0.4, 0.4, 0.4), Vector3.new(-0.4, 0.4, -0.95), "Eye"),
			part("EyeRight", "Ball", Vector3.new(0.4, 0.4, 0.4), Vector3.new(0.4, 0.4, -0.95), "Eye"),
			part("Base", "Block", Vector3.new(2.6, 0.5, 2.6), Vector3.new(0, -2.6, 0), "Dark"),
		},
	},

	-- A splinter of the Splitter: small, bright and quick.
	Shard = {
		Bob = 0.1,
		BobRate = 5,
		Parts = {
			part("Body", "Wedge", Vector3.new(1.4, 1.2, 1.8), Vector3.new(0, -1.9, 0), "Body"),
			part("Spine", "Block", Vector3.new(0.3, 0.8, 1.2), Vector3.new(0, -1.1, 0.2), "Glow"),
			part("Eye", "Ball", Vector3.new(0.4, 0.4, 0.4), Vector3.new(0, -1.5, -0.8), "Eye"),
			part("Foot", "Block", Vector3.new(1.2, 0.3, 1.2), Vector3.new(0, -2.8, 0), "Dark"),
		},
	},

	-- A squat turret: an armoured base, a turning head and a long barrel that glows as it
	-- charges.
	Sentinel = {
		Bob = 0,
		Parts = {
			part("Base", "Block", Vector3.new(3.2, 1.2, 3.2), Vector3.new(0, -2.4, 0), "Dark"),
			part("Column", "Block", Vector3.new(1.6, 2.2, 1.6), Vector3.new(0, -0.8, 0), "Body"),
			part("Head", "Ball", Vector3.new(2.4, 2.4, 2.4), Vector3.new(0, 0.9, 0), "Body"),
			part("Barrel", "Block", Vector3.new(0.6, 0.6, 2.0), Vector3.new(0, 0.9, -1.6), "Dark"),
			part("Muzzle", "Ball", Vector3.new(0.7, 0.7, 0.7), Vector3.new(0, 0.9, -2.6), "Glow"),
			part("Eye", "Block", Vector3.new(1.2, 0.3, 0.2), Vector3.new(0, 1.4, -1.1), "Eye"),
		},
	},

	-- A flickering wraith: a tall glowing core in a hooded shell, trailing motes.
	Phaser = {
		Bob = 0.3,
		BobRate = 1.1,
		Parts = {
			part("Shell", "Wedge", Vector3.new(2.2, 3.4, 2.2), Vector3.new(0, -0.4, 0.2), "Body"),
			part("Core", "Ball", Vector3.new(1.3, 1.3, 1.3), Vector3.new(0, 0.2, -0.5), "Glow"),
			part("Eye", "Block", Vector3.new(1.0, 0.25, 0.2), Vector3.new(0, 0.9, -0.9), "Eye"),
			part("Tail", "Ball", Vector3.new(0.9, 0.9, 0.9), Vector3.new(0, -2.3, 0.6), "Glow"),
		},
		Rings = {
			{ Name = "Mote", Shape = "Ball", Size = Vector3.new(0.35, 0.35, 0.35), Count = 4, Radius = 1.7, Height = -0.5, Speed = 200, Tilt = 50, Role = "Glow" },
		},
	},

	-- The final boss: a crowned core on a dais, orbited by a ring of armour plates and a wider
	-- ring of sparks.
	WardenPrime = {
		Bob = 0.3,
		BobRate = 0.35,
		Parts = {
			part("Core", "Ball", Vector3.new(4.4, 4.4, 4.4), Vector3.new(0, 0.4, 0), "Glow"),
			part("Eye", "Ball", Vector3.new(1.6, 1.6, 1.6), Vector3.new(0, 0.6, -1.9), "Eye"),
			part("Pupil", "Ball", Vector3.new(0.7, 0.7, 0.7), Vector3.new(0, 0.6, -2.55), "Dark"),
			part("Dais", "Block", Vector3.new(6, 0.8, 6), Vector3.new(0, -2.6, 0), "Dark"),
			part("CrownLeft", "Wedge", Vector3.new(0.6, 1.4, 1.6), Vector3.new(-1.4, 2.2, 0), "Body"),
			part("CrownRight", "Wedge", Vector3.new(0.6, 1.4, 1.6), Vector3.new(1.4, 2.2, 0), "Body"),
			part("CrownCentre", "Wedge", Vector3.new(0.6, 1.6, 1.6), Vector3.new(0, 2.3, -0.4), "Body"),
		},
		Rings = {
			{ Name = "Plate", Shape = "Block", Size = Vector3.new(0.8, 1.2, 1.8), Count = 10, Radius = 4.0, Height = 0.4, Speed = 50, Tilt = 0, Role = "Dark" },
			{ Name = "Spark", Shape = "Ball", Size = Vector3.new(0.7, 0.7, 0.7), Count = 8, Radius = 3.2, Height = 0.6, Speed = -110, Tilt = 30, Role = "Glow" },
		},
	},

	--// 2.0 ---------------------------------------------------------------------

	-- Swarm fodder: a skittering tick with a bright back, small enough to read as "one of many".
	Mite = {
		Bob = 0.08,
		BobRate = 7,
		Parts = {
			part("Body", "Ball", Vector3.new(1.6, 1.1, 1.8), Vector3.new(0, -2.2, 0), "Body"),
			part("Back", "Ball", Vector3.new(1.0, 0.6, 1.1), Vector3.new(0, -1.7, 0.1), "Glow"),
			part("Eye", "Ball", Vector3.new(0.35, 0.35, 0.35), Vector3.new(0, -2.0, -0.85), "Eye"),
			part("LegLeft", "Block", Vector3.new(1.8, 0.15, 0.2), Vector3.new(0, -2.6, -0.3), "Dark"),
			part("LegRight", "Block", Vector3.new(1.8, 0.15, 0.2), Vector3.new(0, -2.6, 0.4), "Dark"),
		},
	},

	-- A walking mirror: a tall polished slab with a single eye, flanked by glass fins.
	Mirror = {
		Bob = 0.15,
		BobRate = 1.3,
		Parts = {
			part("Slab", "Block", Vector3.new(2.4, 4.0, 0.6), Vector3.new(0, -0.6, 0), "Body"),
			part("Frame", "Block", Vector3.new(2.7, 4.3, 0.3), Vector3.new(0, -0.6, 0.35), "Dark"),
			part("Eye", "Ball", Vector3.new(0.6, 0.6, 0.6), Vector3.new(0, 0.6, -0.4), "Eye"),
			part("FinLeft", "Wedge", Vector3.new(0.3, 2.2, 1.2), Vector3.new(-1.5, -1.2, 0), "Glow"),
			part("FinRight", "Wedge", Vector3.new(0.3, 2.2, 1.2), Vector3.new(1.5, -1.2, 0), "Glow"),
		},
		Rings = {
			{ Name = "Glint", Shape = "Ball", Size = Vector3.new(0.3, 0.3, 0.3), Count = 3, Radius = 1.9, Height = 0.8, Speed = 160, Tilt = 0, Role = "Glow" },
		},
	},

	-- A bloated sac on stubby legs, pocked with pores that drink shots.
	Sponge = {
		Bob = 0.2,
		BobRate = 0.9,
		Parts = {
			part("Sac", "Ball", Vector3.new(3.4, 3.0, 3.4), Vector3.new(0, -0.9, 0), "Body"),
			part("PoreA", "Ball", Vector3.new(0.7, 0.7, 0.7), Vector3.new(-0.9, -0.3, -1.4), "Dark"),
			part("PoreB", "Ball", Vector3.new(0.6, 0.6, 0.6), Vector3.new(0.8, -1.2, -1.45), "Dark"),
			part("PoreC", "Ball", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0.2, 0.3, -1.5), "Dark"),
			part("Eye", "Ball", Vector3.new(0.5, 0.5, 0.5), Vector3.new(0, -0.8, -1.6), "Eye"),
			part("Foot", "Block", Vector3.new(2.6, 0.5, 2.6), Vector3.new(0, -2.7, 0), "Dark"),
		},
	},

	-- A horseshoe magnet on a plinth, with sparks circling between its poles.
	Magnet = {
		Bob = 0.1,
		BobRate = 1.8,
		Parts = {
			part("Plinth", "Block", Vector3.new(2.8, 0.8, 2.8), Vector3.new(0, -2.5, 0), "Dark"),
			part("ArmLeft", "Block", Vector3.new(0.8, 3.2, 0.8), Vector3.new(-0.9, -0.5, 0), "Body"),
			part("ArmRight", "Block", Vector3.new(0.8, 3.2, 0.8), Vector3.new(0.9, -0.5, 0), "Body"),
			part("Bridge", "Block", Vector3.new(2.6, 0.8, 0.8), Vector3.new(0, -1.9, 0), "Body"),
			part("PoleLeft", "Block", Vector3.new(0.85, 0.6, 0.85), Vector3.new(-0.9, 1.3, 0), "Glow"),
			part("PoleRight", "Block", Vector3.new(0.85, 0.6, 0.85), Vector3.new(0.9, 1.3, 0), "Glow"),
		},
		Rings = {
			{ Name = "Spark", Shape = "Ball", Size = Vector3.new(0.35, 0.35, 0.35), Count = 5, Radius = 2.4, Height = 0.6, Speed = -240, Tilt = 70, Role = "Glow" },
		},
	},

	-- The Splitter's elder: a great crystal crown that cracks into three.
	SplitterKing = {
		Bob = 0.12,
		BobRate = 0.9,
		Parts = {
			part("Core", "Block", Vector3.new(2.8, 4.0, 2.8), Vector3.new(0, -0.6, 0), "Body"),
			part("FacetLeft", "Wedge", Vector3.new(1.6, 3.4, 2.4), Vector3.new(-1.9, -1.0, 0), "Body"),
			part("FacetRight", "Wedge", Vector3.new(1.6, 3.4, 2.4), Vector3.new(1.9, -1.0, 0), "Body"),
			part("Seam", "Block", Vector3.new(0.4, 4.2, 2.9), Vector3.new(0, -0.6, 0), "Glow"),
			part("CrownLeft", "Wedge", Vector3.new(0.5, 1.2, 1.0), Vector3.new(-0.9, 2.0, 0), "Glow"),
			part("CrownRight", "Wedge", Vector3.new(0.5, 1.2, 1.0), Vector3.new(0.9, 2.0, 0), "Glow"),
			part("Eye", "Ball", Vector3.new(0.7, 0.7, 0.7), Vector3.new(0, 0.6, -1.45), "Eye"),
			part("Base", "Block", Vector3.new(4.2, 0.5, 4.2), Vector3.new(0, -2.7, 0), "Dark"),
		},
	},

	-- A hooded thief hunched under a glowing sack of coins.
	TreasureRunner = {
		Bob = 0.25,
		BobRate = 5,
		Parts = {
			part("Body", "Ball", Vector3.new(1.8, 2.0, 1.8), Vector3.new(0, -1.6, 0), "Dark"),
			part("Hood", "Wedge", Vector3.new(1.6, 1.2, 1.6), Vector3.new(0, -0.2, -0.1), "Dark"),
			part("Eye", "Block", Vector3.new(0.9, 0.2, 0.2), Vector3.new(0, -0.3, -0.8), "Eye"),
			part("Sack", "Ball", Vector3.new(1.8, 1.8, 1.8), Vector3.new(0, -0.9, 1.1), "Body"),
			part("Knot", "Ball", Vector3.new(0.6, 0.6, 0.6), Vector3.new(0, 0.1, 1.1), "Glow"),
		},
		Rings = {
			{ Name = "Coin", Shape = "Block", Size = Vector3.new(0.6, 0.6, 0.15), Count = 4, Radius = 1.6, Height = -0.4, Speed = 200, Tilt = 20, Role = "Glow" },
		},
	},

	-- The Ruins mini-boss: a squat stone statue with glowing runes and a heavy brow.
	Colossus = {
		Bob = 0,
		Parts = {
			part("Torso", "Block", Vector3.new(5.6, 3.6, 4.6), Vector3.new(0, -0.9, 0), "Body"),
			part("Head", "Block", Vector3.new(3.0, 1.6, 2.6), Vector3.new(0, 1.8, -0.2), "Body"),
			part("Brow", "Block", Vector3.new(3.2, 0.5, 0.6), Vector3.new(0, 2.2, -1.5), "Dark"),
			part("Eyes", "Block", Vector3.new(2.0, 0.3, 0.3), Vector3.new(0, 1.7, -1.55), "Eye"),
			part("RuneChest", "Block", Vector3.new(1.4, 1.4, 0.3), Vector3.new(0, -0.6, -2.35), "Glow"),
			part("ArmLeft", "Block", Vector3.new(1.4, 3.8, 1.6), Vector3.new(-3.4, -1.0, 0), "Dark"),
			part("ArmRight", "Block", Vector3.new(1.4, 3.8, 1.6), Vector3.new(3.4, -1.0, 0), "Dark"),
			part("FootLeft", "Block", Vector3.new(1.8, 0.8, 2.6), Vector3.new(-1.5, -2.6, 0), "Dark"),
			part("FootRight", "Block", Vector3.new(1.8, 0.8, 2.6), Vector3.new(1.5, -2.6, 0), "Dark"),
		},
		Rings = {
			{ Name = "Rune", Shape = "Block", Size = Vector3.new(0.5, 0.8, 0.2), Count = 6, Radius = 4.4, Height = 1.2, Speed = 40, Tilt = 0, Role = "Glow" },
		},
	},

	-- The Foundry mini-boss: a hovering press head with a glowing underside and piston rods.
	ForgePress = {
		Bob = 0.3,
		BobRate = 0.8,
		Parts = {
			part("Head", "Block", Vector3.new(6.2, 1.8, 6.2), Vector3.new(0, 1.3, 0), "Body"),
			part("Plate", "Block", Vector3.new(5.6, 0.4, 5.6), Vector3.new(0, 0.1, 0), "Glow"),
			part("RodA", "Block", Vector3.new(0.6, 1.4, 0.6), Vector3.new(-2.2, 2.5, -2.2), "Dark"),
			part("RodB", "Block", Vector3.new(0.6, 1.4, 0.6), Vector3.new(2.2, 2.5, -2.2), "Dark"),
			part("RodC", "Block", Vector3.new(0.6, 1.4, 0.6), Vector3.new(-2.2, 2.5, 2.2), "Dark"),
			part("RodD", "Block", Vector3.new(0.6, 1.4, 0.6), Vector3.new(2.2, 2.5, 2.2), "Dark"),
			part("Eye", "Block", Vector3.new(2.4, 0.4, 0.3), Vector3.new(0, 1.4, -3.15), "Eye"),
			part("Shadow", "Block", Vector3.new(5, 0.1, 5), Vector3.new(0, -2.9, 0), "Dark"),
		},
	},
}

return EnemyVisualConfig
