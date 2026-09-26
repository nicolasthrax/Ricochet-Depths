--!strict
-- Global constants for the lane game, shared by server and client.
--
-- Coordinate system: all gameplay runs on one flat 2D plane (the "lane"). The 3D view is
-- presentation only. In lane space, x runs across the lane (0 is the centre line) and y runs up
-- the lane, away from the players: y = 0 is the rail the avatars stand on, y = Lane.length is
-- the back wall. Distances are studs. Each pit instance maps lane space to the world through its
-- own origin CFrame, so these numbers never depend on where a pit is built.
--
-- Values marked "tuning" are first-pass numbers for the vertical slice and are expected to move
-- in playtests. Values quoted from the design proposal are marked "(design)".

local Source = script.Parent
local Types = require(Source.Types)
local deepFreeze = require(Source.DeepFreeze)

local LANE_HALF_WIDTH = 13.5
local LANE_LENGTH = 42
local GRID_COLUMNS = 9
local CELL_SIZE = (LANE_HALF_WIDTH * 2) / GRID_COLUMNS -- 3 studs: blocks tile the lane exactly
local DANGER_LINE_Y = 6
local AVATAR_RADIUS = 1

local GameConfig = {
	Version = 1,

	-----------------------------------------------------------------------------------------
	-- Lane boundaries (the playfield)
	-----------------------------------------------------------------------------------------
	Lane = {
		halfWidth = LANE_HALF_WIDTH,
		length = LANE_LENGTH,
		-- Side and back walls are bumpers. The rail edge is open: a shot that comes back past
		-- y = 0 leaves the lane and is spent.
		openBottom = true,
		-- Targets that cross this line cost HP (design: the magenta danger line).
		dangerLineY = DANGER_LINE_Y,
		-- The target grid. Row 1 is against the back wall; rows count towards the rail.
		grid = {
			columns = GRID_COLUMNS,
			cellSize = CELL_SIZE,
			rows = math.floor((LANE_LENGTH - DANGER_LINE_Y) / CELL_SIZE), -- 12
			-- Blocks are drawn slightly smaller than their cell so rows read as separate pieces.
			blockInset = 0.2,
		},
	},

	-----------------------------------------------------------------------------------------
	-- The rail (left thumb, 1D movement)
	-----------------------------------------------------------------------------------------
	Rail = {
		y = 0,
		minX = -LANE_HALF_WIDTH + AVATAR_RADIUS,
		maxX = LANE_HALF_WIDTH - AVATAR_RADIUS,
		avatarRadius = AVATAR_RADIUS,
		maxSpeed = 30, -- tuning: studs/s
		-- How often the client sends its rail position (unreliable). The server moves its own
		-- copy towards each update by at most maxSpeed * speedTolerance * elapsed (elapsed capped
		-- at maxGapSeconds), so a teleport is never accepted.
		sendRateHz = 20,
		speedTolerance = 1.25,
		maxGapSeconds = 0.5,
		-- A shot's origin comes from the client (it fires from where it sees itself), but only
		-- when within this distance of the server's rail position; otherwise the server's is used.
		fireOriginTolerance = 3,
		-- Co-op: all four players share one rail; this is the smallest gap kept between avatars.
		minSeparation = 2,
	},

	-----------------------------------------------------------------------------------------
	-- Shots (server-simulated, no Roblox physics)
	-----------------------------------------------------------------------------------------
	Shot = {
		baseSpeed = 70, -- tuning: studs/s
		radius = 0.45,
		baseDamage = 3, -- tuning
		-- Bounces off walls and targets before a shot is spent (Echo adds to this).
		baseBounces = 3,
		lifetimeSeconds = 4,
		cooldownSeconds = 0.35, -- tuning; Quickdraw/Gatling scale this
		-- No combination of modifiers fires faster than this (also sizes the remote rate limit).
		minCooldownSeconds = 0.15,
		maxActivePerPlayer = 12,
		-- Aim must point up the lane: the direction's y must be at least this (a unit vector),
		-- about 8.6 degrees above the rail. Stops shots skimming along the rail forever.
		minAimY = 0.15,
		-- Where a shot starts, measured up the lane from the avatar.
		muzzleOffset = 1.2,
	},

	-----------------------------------------------------------------------------------------
	-- Ricochet response
	-----------------------------------------------------------------------------------------
	-- Friction is applied as speed loss only. Tangential friction stays 0 so the reflected angle
	-- always equals the incoming angle: "the skill is the angle" (design), and the aim preview
	-- must match what the server simulates.
	Ricochet = {
		wallSpeedRetention = 0.97, -- speed kept after a wall bounce
		targetSpeedRetention = 0.92, -- speed kept after bouncing off a target
		tangentialFriction = 0,
		-- A shot slower than this is spent, however many bounces it has left.
		minSpeed = 30,
		-- Gap left between a shot and the surface it just left, to stop it re-hitting it.
		surfaceSkin = 0.02,
		-- Safety cap on reflections resolved inside one simulation step (corners chain).
		maxBouncesPerStep = 4,
	},

	-----------------------------------------------------------------------------------------
	-- Server simulation
	-----------------------------------------------------------------------------------------
	Simulation = {
		fixedStep = 1 / 60,
		-- Steps run at most this many times per Heartbeat; a longer stall drops time instead of
		-- spiralling.
		maxStepsPerFrame = 4,
		maxShotsPerPit = 120,
		-- Hits are batched per step into one DamageReport per party.
		batchDamageReports = true,
	},

	-----------------------------------------------------------------------------------------
	-- Players
	-----------------------------------------------------------------------------------------
	Player = {
		hpPips = 5, -- (design) 5 pips, never a number
		hitInvulnerabilitySeconds = 0.75,
		reviveSeconds = 1.5,
		reviveRange = 6,
	},

	-----------------------------------------------------------------------------------------
	-- Targets
	-----------------------------------------------------------------------------------------
	Targets = {
		-- Every pulse, targets step one row closer to the rail (design: threat shows as distance).
		pulseIntervalSeconds = 3, -- tuning
		-- HP pips lost when a target crosses the danger line.
		breachDamage = {
			Block = 1,
			Elite = 2,
		},
		elite = {
			hp = 80, -- (design) tuned to die in about 3 Inferno shots
			telegraphSeconds = 1.5, -- (design) magenta telegraph lane before each attack
			attackIntervalSeconds = 4,
			attackDamage = 1,
			widthColumns = 2,
		},
	},

	-----------------------------------------------------------------------------------------
	-- Run structure
	-----------------------------------------------------------------------------------------
	Run = {
		roomsPerDepth = 6, -- (design) ROOM 3/6
		-- The last room of a depth holds the mini-elite and leads to the extract choice.
		eliteRoom = 6,
		-- A defeated run keeps this share of its haul; banking keeps all of it.
		defeatedHaulKept = 0.5,
		-- Bank loot pays this bonus per depth cleared (0.1 = +10% per depth).
		bankBonusPerDepth = 0.1,
		-- Seconds between a defeat and the next run starting.
		restartDelaySeconds = 4,
	},

	-----------------------------------------------------------------------------------------
	-- Rooms (target waves)
	-----------------------------------------------------------------------------------------
	Rooms = {
		-- Rows on the grid when a room opens; the rest stream in at the back, one per pulse.
		startRows = 3,
		streamRowsBase = 1,
		streamRowsPerRoom = 0.5, -- streamed rows = base + perRoom * room + (depth - 1), floored
		rowFill = 0.55, -- chance each free cell starts a block
		wideBlockChance = 0.15, -- chance a block is 2 cells wide
		blockHp = {
			base = 4,
			perRoom = 1.5,
			perDepth = 8,
			jitter = 0.25, -- +-25%
		},
		eliteHpPerDepth = 0.5, -- elite HP grows by this fraction of its base per depth
		clearDelaySeconds = 1.5, -- ROOM CLEAR beat before the next room opens
	},

	-----------------------------------------------------------------------------------------
	-- World layout (server)
	-----------------------------------------------------------------------------------------
	-- Each player's lane is built in its own slot. A lane origin's Position is the rail centre on
	-- the lane floor; its LookVector points up the lane.
	World = {
		firstLaneOrigin = CFrame.new(0, 100, 0),
		laneSpacing = 60, -- studs between neighbouring lane slots, along +X
		floorThickness = 2,
		wallHeight = 1.5,
		wallThickness = 1,
		apronDepth = 6, -- floor behind the rail, where the avatar stands
		blockHeight = 1.6, -- how tall target blocks are drawn
	},

	-----------------------------------------------------------------------------------------
	-- XP and gems
	-----------------------------------------------------------------------------------------
	Xp = {
		-- XP needed for the first level-up; each level after needs growth times the last.
		firstLevel = 10,
		growth = 1.35,
		perBlockHp = 0.5, -- tuning
	},
	Gems = {
		perBlockHp = 0.5, -- tuning
		-- An elite pays this many times a block's gems per HP: the gem fountain (design: about 4x).
		eliteMultiplier = 4,
	},

	-----------------------------------------------------------------------------------------
	-- Upgrade picks
	-----------------------------------------------------------------------------------------
	Upgrades = {
		choices = 3,
		maxRecommendedPerDraw = 1, -- (design) at most one star per draw
		-- A held aim-release can't pick a card by accident (design: 0.4s input lock on open).
		inputLockSeconds = 0.4,
		-- Solo: no timer and the world freezes. Co-op: each player picks privately, the world
		-- keeps running slowly, and the recommended card is auto-picked when the ring runs out.
		soloTimeoutSeconds = nil :: number?,
		coopTimeoutSeconds = 10,
		coopWorldTimeScale = 0.2,
		-- Rerolls are earned in play; none at the start of a run. Hidden during the FTUE.
		startingRerolls = 0,
	},

	-----------------------------------------------------------------------------------------
	-- Fusion
	-----------------------------------------------------------------------------------------
	Fusion = {
		-- Picking a card that has a recipe with a card already held fuses the two on the spot.
		fuseOnPick = true,
	},

	-----------------------------------------------------------------------------------------
	-- Party (co-op)
	-----------------------------------------------------------------------------------------
	Party = {
		maxPlayers = 4,
		liftWaitSeconds = 5, -- (design) the lift waits up to 5s for everyone
		dropInMaxWaitSeconds = 10, -- (design) a friend joins at the next room boundary
	},

	-----------------------------------------------------------------------------------------
	-- First 60 seconds (FTUE), all (design)
	-----------------------------------------------------------------------------------------
	Ftue = {
		firstOffer = { "Splitshot", "Ember", "Bigshot" } :: { Types.BaseModifierId },
		recommended = "Ember" :: Types.BaseModifierId,
		-- The second pick always includes a duplicate of the first pick.
		guaranteeDuplicateOnSecondPick = true,
		room1XpMultiplier = 3,
		noInputHintSeconds = 8, -- the ghost thumb grows and the aim line snaps to the cluster
		missRespawnRowsCloser = 1,
		fusionRowWidth = 5,
		-- Pacing targets, measured from spawn. Used by telemetry alerts, not gameplay.
		targets = {
			firstHitSeconds = 15,
			firstUpgradeSeconds = 30,
			firstFusionSeconds = 45,
			firstEliteKillSeconds = 55,
			firstGoalSeconds = 60,
		},
	},

	-----------------------------------------------------------------------------------------
	-- Camera (client), all (design)
	-----------------------------------------------------------------------------------------
	Camera = {
		pitchDegrees = 62,
		fovDegrees = 32,
		introPitchDegrees = 70, -- eased to pitchDegrees on spawn so the pit "opens up"
		introEaseSeconds = 1,
		-- The camera distance is solved so the lane fills this share of the screen width,
		-- from 4:3 to 20:9.
		laneScreenWidthFraction = 0.56,
		maxShakeStuds = 0.15, -- fusion and elite only; off with Reduce Motion
		followCamBlendSeconds = 0.8, -- lift arrival hand-off to the default follow cam
	},

	-----------------------------------------------------------------------------------------
	-- Presentation (client)
	-----------------------------------------------------------------------------------------
	Presentation = {
		hitStopSeconds = 0.06, -- (design) 60ms
		maxVisibleShots = 80, -- (design) past this, trails merge into brighter streaks
		aimPreview = {
			solidBounces = 1, -- (design) solid to the 1st bounce
			dashedBounces = 1, -- (design) dashed to the 2nd, nothing after
		},
		fusionFlashSeconds = 0.8,
		goalCardSeconds = 3,
		tallyMaxSeconds = 3,
	},

	-----------------------------------------------------------------------------------------
	-- HUD budget (client), all (design)
	-----------------------------------------------------------------------------------------
	Hud = {
		maxVisibleElements = 8,
		modifierSlots = 6, -- then the column scrolls
		minTouchTargetPoints = 44,
	},

	-----------------------------------------------------------------------------------------
	-- Colour = meaning, in the world and the UI (design)
	-----------------------------------------------------------------------------------------
	Palette = {
		Harm = Color3.fromRGB(236, 72, 153), -- magenta always means harm
		Gem = Color3.fromRGB(74, 222, 128),
		Wall = Color3.fromRGB(34, 211, 238), -- walls and XP share cyan
		Xp = Color3.fromRGB(34, 211, 238),
		Fusion = Color3.fromRGB(251, 191, 36),
		Target = Color3.fromRGB(99, 132, 212),
		Floor = Color3.fromRGB(16, 36, 46), -- under 30% lightness
		ShotCore = Color3.fromRGB(255, 255, 255),
		Rarity = {
			Common = Color3.fromRGB(205, 210, 218),
			Rare = Color3.fromRGB(77, 176, 245),
			Epic = Color3.fromRGB(192, 122, 239),
			Fused = Color3.fromRGB(251, 191, 36),
		},
	},
}

deepFreeze(GameConfig)
return GameConfig
