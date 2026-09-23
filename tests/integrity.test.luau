-- Cross-references between config modules. These catch config drift — a room pointing at a
-- layout that no longer exists, a spawn naming a deleted archetype, a behaviour with no
-- implementation — none of which any single-module test would notice.
local EnemyBehaviour = __require("EnemyBehaviour")
local EnemyConfig = __require("EnemyConfig")
local PlayerDataConfig = __require("PlayerDataConfig")
local ProjectileConfig = __require("ProjectileConfig")
local RewardConfig = __require("RewardConfig")
local RoomConfig = __require("RoomConfig")
local RunConfig = __require("RunConfig")
local UpgradeConfig = __require("UpgradeConfig")

describe("run and room configuration agree", function()
	it("points every room at a layout that exists", function()
		for _, room in RunConfig.Rooms do
			local layout = RoomConfig.GetLayout(room.Layout)
			expect(layout).toBeTruthy()
			expect(layout.InteriorSize.X).toBeGreaterThan(0)
			expect(layout.InteriorSize.Y).toBeGreaterThan(0)
		end
		expect(RoomConfig.GetLayout(RoomConfig.DefaultLayout)).toBeTruthy()
	end)

	it("ships the room mix the vertical slice promises", function()
		local normal, elite = 0, 0
		for _, room in RunConfig.Rooms do
			if room.Kind == "Normal" then
				normal += 1
			elseif room.Kind == "Elite" then
				elite += 1
			end
		end
		expect(normal).toBeGreaterThanOrEqual(3)
		expect(elite).toBe(1)
		-- The elite encounter, then the boss, close every run, so the run builds to them.
		local shape = RunConfig.RunShape
		expect(RunConfig.GetRoomById(shape[#shape - 1].Room).Kind).toBe("Elite")
		expect(RunConfig.GetRoomById(shape[#shape].Room).Kind).toBe("Boss")
	end)

	it("gives every room unique ids and a display name", function()
		local seen = {}
		for _, room in RunConfig.Rooms do
			expect(seen[room.Id]).toBeNil()
			seen[room.Id] = true
			expect(#room.DisplayName).toBeGreaterThan(0)
		end
	end)

	it("names only archetypes that exist, within the active cap", function()
		for _, room in RunConfig.Rooms do
			local total = 0
			for _, group in room.Spawns do
				expect(EnemyConfig.Get(group.Archetype)).toBeTruthy()
				expect(group.Count).toBeGreaterThan(0)
				total += group.Count
			end
			expect(total).toBeGreaterThan(0)
			expect(total).toBeLessThanOrEqual(EnemyConfig.MaxActive)

			if room.EscortRespawn then
				expect(EnemyConfig.Get(room.EscortRespawn.Archetype)).toBeTruthy()
				expect(room.EscortRespawn.Delay).toBeGreaterThan(0)
				expect(total + room.EscortRespawn.MaxAlive).toBeLessThanOrEqual(EnemyConfig.MaxActive)
			end
		end
	end)

	it("gives every layout enough spawn markers inside its own walls", function()
		for layoutId, layout in RoomConfig.Layouts do
			expect(#layout.EnemySpawns).toBeGreaterThanOrEqual(1)
			local halfX = layout.InteriorSize.X / 2
			local halfZ = layout.InteriorSize.Y / 2
			for _, marker in layout.EnemySpawns do
				-- Markers are jittered by up to 3 studs, so leave clearance from the wall.
				expect(math.abs(marker.X)).toBeLessThan(halfX - 3)
				expect(math.abs(marker.Y)).toBeLessThan(halfZ - 3)
			end
			expect(#layoutId).toBeGreaterThan(0)
		end
	end)

	it("keeps obstacles inside the room and clear of the spawn pad", function()
		for _, layout in RoomConfig.Layouts do
			local halfX = layout.InteriorSize.X / 2
			local halfZ = layout.InteriorSize.Y / 2
			local padClearance = RoomConfig.SpawnPadSize.X / 2 + 1
			for _, obstacle in layout.Obstacles do
				expect(math.abs(obstacle.Offset.X) + obstacle.Size.X / 2).toBeLessThanOrEqual(halfX)
				expect(math.abs(obstacle.Offset.Y) + obstacle.Size.Y / 2).toBeLessThanOrEqual(halfZ)

				-- Players are teleported to the room centre; an obstacle there would trap them.
				local overlapsX = math.abs(obstacle.Offset.X) < obstacle.Size.X / 2 + padClearance
				local overlapsZ = math.abs(obstacle.Offset.Y) < obstacle.Size.Y / 2 + padClearance
				expect(overlapsX and overlapsZ).toBe(false)
			end
		end
	end)

	it("declares every state as its own name and offers upgrades between rooms only", function()
		for key, value in RunConfig.States do
			expect(value).toBe(key)
		end
		expect(RunConfig.OfferUpgradeAfterRoom(RunConfig.RoomCount())).toBe(false)
		expect(RunConfig.OfferUpgradeAfterRoom(1)).toBe(true)
	end)

	it("sets pacing limits in a sane order", function()
		expect(RunConfig.RoomTimeLimit).toBeGreaterThan(RunConfig.TransitionDuration)
		-- The hard limit must outlast every room hitting its own limit, or a legitimate slow run
		-- would be cut short before it could finish.
		expect(RunConfig.HardRunTimeLimit).toBeGreaterThan(RunConfig.RoomTimeLimit)
		expect(RunConfig.TargetRunSeconds).toBeLessThan(RunConfig.HardRunTimeLimit)
		expect(RunConfig.StartCountdown).toBeGreaterThan(0)
		expect(RunConfig.SpawnInvulnerability).toBeGreaterThan(0)
	end)
end)

describe("enemy configuration is self-consistent", function()
	it("implements every declared behaviour", function()
		for id, archetype in EnemyConfig.Archetypes do
			expect(archetype.Id).toBe(id)
			expect(EnemyBehaviour.Get(archetype.Behaviour)).toBeTruthy()
			expect(archetype.Health).toBeGreaterThan(0)
			expect(archetype.Size.Y).toBe(EnemyConfig.BodyHeight)
			expect(#archetype.DisplayName).toBeGreaterThan(0)
		end
	end)

	it("gives every lunging archetype the data its behaviour reads", function()
		for _, archetype in EnemyConfig.Archetypes do
			if archetype.Behaviour == "Lunger" then
				expect(archetype.Lunge).toBeTruthy()
				expect(archetype.Lunge.Interval).toBeGreaterThan(0)
				expect(archetype.Lunge.TelegraphTime).toBeGreaterThan(0)
				expect(archetype.Lunge.Duration).toBeGreaterThan(0)
				expect(archetype.Lunge.SpeedMultiplier).toBeGreaterThan(1)
				expect(archetype.StandoffDistance).toBeGreaterThan(0)
				-- The telegraph has to be long enough to read before the lunge lands.
				expect(archetype.Lunge.TelegraphTime).toBeGreaterThanOrEqual(0.5)
			elseif archetype.Behaviour == "Sentry" then
				expect(archetype.WanderRadius).toBeGreaterThan(0)
				expect(archetype.WanderInterval).toBeGreaterThan(0)
			elseif archetype.Behaviour == "Chaser" then
				expect(archetype.StandoffDistance).toBeGreaterThan(0)
			end
		end
	end)

	it("keeps every shield arc partial, so a flank always exists", function()
		for _, archetype in EnemyConfig.Archetypes do
			if archetype.Shield then
				expect(archetype.Shield.HalfAngleDegrees).toBeGreaterThan(0)
				expect(archetype.Shield.HalfAngleDegrees).toBeLessThan(180)
				expect(archetype.Shield.DamageMultiplier).toBeGreaterThanOrEqual(0)
				expect(archetype.Shield.Offset).toBeGreaterThan(archetype.Size.X / 2 - 1)
			end
		end
	end)

	it("pools at least as many bodies as it will ever have alive", function()
		expect(EnemyConfig.PoolSize).toBeGreaterThanOrEqual(EnemyConfig.MaxActive)
		expect(EnemyConfig.MaxActive).toBeGreaterThan(0)
	end)

	it("gives any enemy that can damage a player a range and a cooldown", function()
		for _, archetype in EnemyConfig.Archetypes do
			if (archetype.ContactDamage or 0) > 0 then
				expect(archetype.ContactRange).toBeGreaterThan(0)
				expect(archetype.ContactCooldown or EnemyConfig.DefaultContactCooldown).toBeGreaterThan(0)
				-- Reach has to exceed the standoff, or it could never actually connect.
				expect(archetype.ContactRange).toBeGreaterThanOrEqual(archetype.StandoffDistance)
			end
		end
	end)
end)

describe("projectile and reward configuration", function()
	it("keeps the pool within its ceiling and the geometry coherent", function()
		expect(ProjectileConfig.PoolSize).toBeGreaterThan(0)
		expect(ProjectileConfig.PoolSize).toBeLessThanOrEqual(150)
		expect(ProjectileConfig.Radius).toBeGreaterThan(0)
		expect(ProjectileConfig.SurfaceSkin).toBeGreaterThan(0)
		expect(ProjectileConfig.CastBackStep).toBeGreaterThan(0)
		-- The back-step must stay inside the clearance a bounce leaves, or a cast could start
		-- back inside the surface it just left.
		expect(ProjectileConfig.CastBackStep).toBeLessThan(ProjectileConfig.Radius + ProjectileConfig.SurfaceSkin)
		expect(ProjectileConfig.MaxBouncesPerStep).toBeGreaterThanOrEqual(2)
		expect(ProjectileConfig.MinSpeedMultiplier).toBeLessThan(ProjectileConfig.MaxSpeedMultiplier)
		expect(ProjectileConfig.MinPower).toBeLessThan(ProjectileConfig.MaxPower)
	end)

	it("keeps the projectile plane inside the enemy body height", function()
		-- Shots must be able to hit an enemy standing on the floor.
		expect(ProjectileConfig.PlaneHeight).toBeGreaterThan(0)
		expect(ProjectileConfig.PlaneHeight).toBeLessThan(EnemyConfig.BodyHeight)
		expect(ProjectileConfig.PlaneHeight).toBeLessThan(RoomConfig.WallHeight)
	end)

	it("pays an extraction more than a defeat and caps the payout", function()
		expect(RewardConfig.DefeatMultiplier).toBeGreaterThan(0)
		expect(RewardConfig.DefeatMultiplier).toBeLessThan(1)
		expect(RewardConfig.ExtractionBonus).toBeGreaterThan(0)
		expect(RewardConfig.MaxPerRun).toBeGreaterThan(
			RunConfig.RoomCount() * RewardConfig.PerRoomCleared + RewardConfig.ExtractionBonus + RewardConfig.EliteBonus
		)
	end)
end)

describe("persistence configuration", function()
	it("keeps development and production scopes apart", function()
		expect(PlayerDataConfig.DevelopmentScope).never().toBe(PlayerDataConfig.ProductionScope)
		expect(#PlayerDataConfig.DevelopmentScope).toBeGreaterThan(0)
		expect(#PlayerDataConfig.ProductionScope).toBeGreaterThan(0)
	end)

	it("has a migration for every version below the current one", function()
		for version = 1, PlayerDataConfig.SchemaVersion - 1 do
			expect(type(PlayerDataConfig.Migrations[version])).toBe("function")
		end
		-- No migration may exist at or beyond the current version; that would never run.
		expect(PlayerDataConfig.Migrations[PlayerDataConfig.SchemaVersion]).toBeNil()
	end)

	it("defines a default for every setting it will accept", function()
		local defaults = PlayerDataConfig.DefaultSettings()
		for name, spec in PlayerDataConfig.SettingSpecs do
			expect(defaults[name]).toBe(spec.Default)
			if spec.Kind == "number" then
				expect(spec.Min).toBeLessThan(spec.Max)
				expect(spec.Default).toBeGreaterThanOrEqual(spec.Min)
				expect(spec.Default).toBeLessThanOrEqual(spec.Max)
			end
		end
		expect(PlayerDataConfig.DefaultProfile().Settings).toEqual(defaults)
	end)

	it("retries with a bounded, growing backoff", function()
		expect(PlayerDataConfig.MaxRetries).toBeGreaterThan(1)
		expect(PlayerDataConfig.RetryBaseDelay).toBeGreaterThan(0)
		expect(PlayerDataConfig.RetryMaxDelay).toBeGreaterThan(PlayerDataConfig.RetryBaseDelay)
		expect(PlayerDataConfig.RunLedgerSize).toBeGreaterThan(0)
	end)
end)

describe("upgrade configuration", function()
	it("keeps every fusion prerequisite reachable", function()
		for _, card in UpgradeConfig.Cards do
			if card.Requires and card.Requires.Cards then
				for requiredId, needed in card.Requires.Cards do
					local prerequisite = UpgradeConfig.Get(requiredId)
					expect(prerequisite).toBeTruthy()
					-- A requirement above the prerequisite's own cap could never be met.
					expect(needed).toBeLessThanOrEqual(prerequisite.MaxStacks)
				end
			end
			if card.Requires and card.Requires.Stats then
				for stat in card.Requires.Stats do
					expect(UpgradeConfig.BaseStats[stat]).never().toBeNil()
				end
			end
		end
	end)

	it("gives every card a positive weight and a readable description", function()
		for _, card in UpgradeConfig.Cards do
			expect(UpgradeConfig.WeightOf(card)).toBeGreaterThan(0)
			expect(#card.Title).toBeGreaterThan(0)
			expect(#card.Description).toBeGreaterThan(10)
			-- Descriptions are read at a glance mid-run, so keep them short.
			expect(#card.Description).toBeLessThan(90)
		end
	end)

	it("can always fill an offer from a fresh profile", function()
		expect(#UpgradeConfig.Cards).toBeGreaterThanOrEqual(UpgradeConfig.OffersPerEvent)
		expect(UpgradeConfig.ChoiceTimeout).toBeGreaterThan(0)
		expect(UpgradeConfig.OffersPerEvent).toBe(3)
	end)
end)
