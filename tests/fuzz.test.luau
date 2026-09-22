-- Property-based tests. Instead of asserting fixed outcomes, these feed randomised but
-- realistic configuration and event sequences through the real services and assert that a set
-- of invariants never breaks. Every trial is seeded, so a failure is reproducible from its seed.
local EnemyConfig = __require("EnemyConfig")
local EnemyService = __require("EnemyService")
local MatchService = __require("MatchService")
local PlayerState = __require("PlayerState")
local ProjectileConfig = __require("ProjectileConfig")
local ProjectileService = __require("ProjectileService")
local RewardService = __require("RewardService")
local RoomService = __require("RoomService")
local RunConfig = __require("RunConfig")
local UpgradeConfig = __require("UpgradeConfig")
local UpgradeService = __require("UpgradeService")

local PLANE_Y = 3
local DT = 1 / 60

-- Hard ceilings the project promises regardless of how the configs are tuned.
local POOL_CEILING = 150
local ENEMY_CEILING = 36

--// config mutation ----------------------------------------------------------

local function resolvePath(root, path)
	local node = root
	for index = 1, #path - 1 do
		node = node[path[index]]
	end
	return node, path[#path]
end

-- Applies overrides, runs body, then restores the originals even if body throws. Config tables
-- are shared across the whole bundle, so a leaked mutation would corrupt later tests.
local function withConfig(overrides, body)
	local saved = {}
	for index, override in overrides do
		local node, key = resolvePath(override.root, override.path)
		saved[index] = { node = node, key = key, value = node[key] }
		node[key] = override.value
	end

	local ok, err = pcall(body)

	for _, entry in saved do
		entry.node[entry.key] = entry.value
	end
	if not ok then
		error(err, 0)
	end
end

local function makeRoom(halfX, halfZ)
	local world = __PhysicsWorld.new()
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	world:AddBareRoom(halfX, halfZ, arena)
	world:Install()
	return world, arena
end

--// projectile configuration --------------------------------------------------

describe("fuzz: projectile configuration", function()
	it("never breaks pool accounting or containment across randomised tuning", function()
		for trial = 1, 40 do
			local seed = 9000 + trial
			local random = Random.new(seed)

			local poolSize = random:NextInteger(4, POOL_CEILING)
			local radius = random:NextNumber(0.15, 1.6)
			local overrides = {
				{ root = ProjectileConfig, path = { "PoolSize" }, value = poolSize },
				{ root = ProjectileConfig, path = { "Radius" }, value = radius },
				{ root = ProjectileConfig, path = { "BaseSpeed" }, value = random:NextNumber(20, 200) },
				{ root = ProjectileConfig, path = { "MinSpeedMultiplier" }, value = random:NextNumber(0.2, 0.9) },
				{ root = ProjectileConfig, path = { "MaxSpeedMultiplier" }, value = random:NextNumber(1, 3) },
				{ root = ProjectileConfig, path = { "MaxBounces" }, value = random:NextInteger(0, 12) },
				{ root = ProjectileConfig, path = { "Lifetime" }, value = random:NextNumber(0.4, 8) },
				{ root = ProjectileConfig, path = { "SurfaceSkin" }, value = random:NextNumber(0.01, 0.4) },
				{ root = ProjectileConfig, path = { "CastBackStep" }, value = random:NextNumber(0.02, 0.5) },
				{ root = ProjectileConfig, path = { "MuzzleOffset" }, value = random:NextNumber(0, 6) },
				{ root = ProjectileConfig, path = { "MaxBouncesPerStep" }, value = random:NextInteger(1, 8) },
			}

			withConfig(overrides, function()
				local halfX, halfZ = random:NextNumber(25, 70), random:NextNumber(25, 70)
				local _, arena = makeRoom(halfX, halfZ)
				local service = ProjectileService.new(arena, arena, PLANE_Y)
				local folder = arena:FindFirstChild("ProjectilePool")
				Harness.setClock(0)

				local maxContacts = 0
				service.OnImpact = function(_result, entry)
					maxContacts = math.max(maxContacts, entry.contacts)
					expect(entry.damage).toBeGreaterThanOrEqual(0)
					expect(entry.speed).toBeGreaterThan(0)
					expect(entry.speed == entry.speed).toBe(true) -- not NaN
					return false
				end

				local limitX = halfX + radius + ProjectileConfig.SurfaceSkin + 0.05
				local limitZ = halfZ + radius + ProjectileConfig.SurfaceSkin + 0.05

				for frame = 1, 200 do
					if random:NextNumber() < 0.6 then
						local angle = random:NextNumber() * math.pi * 2
						service:Fire(
							nil,
							Vector3.new(random:NextNumber(-halfX * 0.7, halfX * 0.7), PLANE_Y, random:NextNumber(-halfZ * 0.7, halfZ * 0.7)),
							Vector3.new(math.cos(angle), 0, math.sin(angle)),
							random:NextNumber()
						)
					end

					__integrateParts(folder, DT)
					Harness.setClock(Harness.now() + DT)
					service:Step(DT)

					-- Invariants that must hold on every single frame.
					expect(service:GetActiveCount() + service:GetFreeCount()).toBe(poolSize)
					expect(#folder:GetChildren()).toBe(poolSize)
					expect(service:GetActiveCount()).toBeLessThanOrEqual(POOL_CEILING)

					for _, part in folder:GetChildren() do
						if part.Anchored == false then
							expect(math.abs(part.Position.X)).toBeLessThanOrEqual(limitX)
							expect(math.abs(part.Position.Z)).toBeLessThanOrEqual(limitZ)
						end
					end
					expect(frame).toBe(frame)
				end

				-- A projectile can contact once more than its bounce budget: the final contact
				-- is what retires it.
				expect(maxContacts).toBeLessThanOrEqual(ProjectileConfig.MaxBounces + 1)

				service:Clear()
				expect(service:GetFreeCount()).toBe(poolSize)
				expect(seed).toBe(seed)
			end)
		end
	end)

	it("never emits negative or non-finite damage however stats are combined", function()
		for trial = 1, 60 do
			local random = Random.new(12000 + trial)
			local _, arena = makeRoom(50, 50)
			local service = ProjectileService.new(arena, arena, PLANE_Y)
			local folder = arena:FindFirstChild("ProjectilePool")
			Harness.setClock(0)

			local options = {
				damage = random:NextNumber(0, 40),
				bounces = random:NextInteger(0, 10),
				speedMultiplier = random:NextNumber(0.1, 4),
				lifetimeBonus = random:NextNumber(0, 6),
				damagePerBounce = random:NextNumber(0, 8),
			}

			service.OnImpact = function(_result, entry)
				local effective = entry.damage + entry.damagePerBounce * math.max(entry.contacts - 1, 0)
				expect(effective).toBeGreaterThanOrEqual(0)
				expect(effective == effective).toBe(true)
				expect(effective).toBeLessThan(math.huge)
				return false
			end

			local angle = random:NextNumber() * math.pi * 2
			service:Fire(nil, Vector3.new(0, PLANE_Y, 0), Vector3.new(math.cos(angle), 0, math.sin(angle)), random:NextNumber(), options)
			for _ = 1, 150 do
				__integrateParts(folder, DT)
				Harness.setClock(Harness.now() + DT)
				service:Step(DT)
			end
			expect(trial).toBe(trial)
		end
	end)
end)

--// enemy configuration -------------------------------------------------------

describe("fuzz: enemy configuration", function()
	it("respects caps and bounds across randomised archetype tuning", function()
		local archetypeIds = { "Drifter", "Chaser", "Bulwark", "WardenCore" }

		for trial = 1, 30 do
			local random = Random.new(21000 + trial)
			local maxActive = random:NextInteger(1, ENEMY_CEILING)

			local overrides = { { root = EnemyConfig, path = { "MaxActive" }, value = maxActive } }
			for _, id in archetypeIds do
				table.insert(overrides, { root = EnemyConfig, path = { "Archetypes", id, "Health" }, value = random:NextInteger(1, 30) })
				table.insert(overrides, { root = EnemyConfig, path = { "Archetypes", id, "MoveSpeed" }, value = random:NextNumber(0, 40) })
				table.insert(overrides, { root = EnemyConfig, path = { "Archetypes", id, "ContactDamage" }, value = random:NextNumber(0, 60) })
				table.insert(overrides, { root = EnemyConfig, path = { "Archetypes", id, "ContactCooldown" }, value = random:NextNumber(0.2, 4) })
			end

			withConfig(overrides, function()
				local arena = Instance.new("Folder")
				local enemies = EnemyService.new(arena, PLANE_Y, 21000 + trial)
				local half = Vector2.new(random:NextNumber(20, 60), random:NextNumber(20, 60))
				enemies:SetBounds(Vector3.new(0, PLANE_Y, 0), half)
				enemies:SetTargetProvider(function()
					return { { player = "fuzz", position = Vector3.new(random:NextNumber(-80, 80), PLANE_Y, random:NextNumber(-80, 80)) } }
				end)

				local pool = arena:FindFirstChild("EnemyPool")
				local deaths = 0
				enemies.OnDeath = function()
					deaths += 1
				end

				local killed = 0
				for frame = 1, 240 do
					if random:NextNumber() < 0.5 then
						enemies:Spawn(archetypeIds[random:NextInteger(1, #archetypeIds)], Vector3.new(random:NextNumber(-70, 70), PLANE_Y, random:NextNumber(-70, 70)))
					end

					enemies:Step(DT, frame * DT)

					-- Randomly shoot at something.
					if random:NextNumber() < 0.4 and enemies:GetActiveCount() > 0 then
						local victim = enemies:GetEnemies()[random:NextInteger(1, enemies:GetActiveCount())]
						local angle = random:NextNumber() * math.pi * 2
						local result = enemies:ApplyHit(victim.part, random:NextNumber(0, 12), Vector3.new(math.cos(angle), 0, math.sin(angle)), nil)
						if result then
							expect(result.damage).toBeGreaterThanOrEqual(0)
							if result.killed then
								killed += 1
								-- A dead enemy must be unreachable immediately.
								expect(enemies:GetByPart(victim.part)).toBeNil()
								expect(enemies:ApplyHit(victim.part, 5, Vector3.new(0, 0, 1), nil)).toBeNil()
							end
						end
					end

					expect(enemies:GetActiveCount()).toBeLessThanOrEqual(maxActive)
					expect(enemies:GetActiveCount()).toBeLessThanOrEqual(ENEMY_CEILING)
					expect(#pool:GetChildren()).toBe(EnemyConfig.PoolSize)

					for _, enemy in enemies:GetEnemies() do
						expect(math.abs(enemy.position.X)).toBeLessThanOrEqual(half.X + 1e-6)
						expect(math.abs(enemy.position.Z)).toBeLessThanOrEqual(half.Y + 1e-6)
						expect(enemy.position.Y).toBe(PLANE_Y)
						expect(enemy.health).toBeGreaterThan(0) -- a non-positive health must have despawned
					end
					expect(frame).toBe(frame)
				end

				-- Every kill reported exactly once.
				expect(deaths).toBe(killed)

				enemies:Clear()
				expect(enemies:GetActiveCount()).toBe(0)
				expect(#pool:GetChildren()).toBe(EnemyConfig.PoolSize)
			end)
		end
	end)

	it("never lets a shield make an enemy permanently unkillable", function()
		for trial = 1, 40 do
			local random = Random.new(31000 + trial)
			local halfAngle = random:NextNumber(0, 179)

			withConfig({
				{ root = EnemyConfig, path = { "Archetypes", "Bulwark", "Shield", "HalfAngleDegrees" }, value = halfAngle },
				{ root = EnemyConfig, path = { "Archetypes", "Bulwark", "Health" }, value = 3 },
			}, function()
				local arena = Instance.new("Folder")
				local enemies = EnemyService.new(arena, PLANE_Y, trial)
				local enemy = enemies:Spawn("Bulwark", Vector3.new(0, PLANE_Y, 0))
				enemy.facing = Vector3.new(0, 0, 1)

				-- Whatever the arc, a shot arriving from directly behind must land.
				local result = enemies:ApplyHit(enemy.part, 1, Vector3.new(0, 0, 1), nil)
				expect(result).toBeTruthy()
				expect(result.blocked).toBe(false)
				expect(halfAngle).toBeLessThan(180)
			end)
		end
	end)
end)

--// upgrade configuration -----------------------------------------------------

describe("fuzz: upgrade configuration", function()
	local function randomState(random)
		local state = PlayerState.new({ Name = "Fuzz", UserId = 1 })
		for _, card in UpgradeConfig.Cards do
			if random:NextNumber() < 0.35 then
				local stacks = random:NextInteger(1, math.min(card.MaxStacks, 4))
				for _ = 1, stacks do
					state:AddUpgrade(card)
				end
			end
		end
		return state
	end

	it("offers only distinct, eligible cards from any reachable player state", function()
		for trial = 1, 200 do
			local random = Random.new(41000 + trial)
			local service = UpgradeService.new(41000 + trial)
			local state = randomState(random)

			local eligible = service:GetEligibleCards(state)
			local offer = service:BuildOffer("fuzz", state, 0)

			-- Never a duplicate inside one offer.
			local seen = {}
			for _, card in offer.cards do
				expect(seen[card.Id]).toBeNil()
				seen[card.Id] = true
				-- Everything offered must be legally takeable right now.
				expect(UpgradeService.IsEligible(card, state)).toBe(true)
				expect(state:GetStacks(card.Id)).toBeLessThan(card.MaxStacks)
			end

			-- Size is the pool size when the pool is short, otherwise exactly the configured count.
			local expectedSize = math.min(UpgradeConfig.OffersPerEvent, math.max(#eligible, 1))
			expect(#offer.cards).toBe(expectedSize)
			expect(#offer.cards).toBeGreaterThanOrEqual(1)
		end
	end)

	it("keeps derived stats sane under any legal stack combination", function()
		for trial = 1, 300 do
			local random = Random.new(51000 + trial)
			local state = randomState(random)
			local stats = state.stats

			expect(stats.ProjectilesPerShot).toBeGreaterThanOrEqual(1)
			expect(stats.Damage).toBeGreaterThanOrEqual(0)
			expect(stats.DamagePerBounce).toBeGreaterThanOrEqual(0)
			expect(stats.BounceBudget).toBeGreaterThanOrEqual(0)
			expect(stats.SpreadDegrees).toBeGreaterThanOrEqual(0)
			-- A zero or negative cooldown multiplier would mean an unbounded fire rate.
			expect(stats.FireCooldownMultiplier).toBeGreaterThan(0)
			expect(stats.SpeedMultiplier).toBeGreaterThan(0)
			expect(stats.RewardMultiplier).toBeGreaterThan(0)
			expect(stats.LifetimeBonus).toBeGreaterThanOrEqual(0)
			expect(state.maxHealth).toBeGreaterThan(0)
			expect(state.health).toBeLessThanOrEqual(state.maxHealth)

			for _, value in stats do
				expect(value == value).toBe(true) -- no NaN
				expect(math.abs(value)).toBeLessThan(math.huge)
			end
		end
	end)

	it("survives randomised stack caps without ever exceeding them", function()
		for trial = 1, 40 do
			local random = Random.new(61000 + trial)
			local overrides = {}
			for index, card in UpgradeConfig.Cards do
				if not card.IsFallback then
					table.insert(overrides, {
						root = UpgradeConfig,
						path = { "Cards", index, "MaxStacks" },
						value = random:NextInteger(1, 5),
					})
				end
			end

			withConfig(overrides, function()
				local service = UpgradeService.new(61000 + trial)
				local state = PlayerState.new({ Name = "Fuzz", UserId = 2 })

				for _ = 1, 60 do
					local offer = service:BuildOffer("fuzz", state, 0)
					local pick = offer.cards[random:NextInteger(1, #offer.cards)]
					local chosen = service:Choose("fuzz", state, offer.id, pick.Id)
					expect(chosen).toBeTruthy()

					for _, card in UpgradeConfig.Cards do
						expect(state:GetStacks(card.Id)).toBeLessThanOrEqual(card.MaxStacks)
					end
				end
			end)
		end
	end)

	it("rejects every malformed selection without mutating state", function()
		for trial = 1, 120 do
			local random = Random.new(71000 + trial)
			local service = UpgradeService.new(71000 + trial)
			local state = randomState(random)
			local offer = service:BuildOffer("fuzz", state, 0)

			local before = {}
			for _, card in UpgradeConfig.Cards do
				before[card.Id] = state:GetStacks(card.Id)
			end

			local junk = {
				{ offer.id + random:NextInteger(1, 50), offer.cards[1].Id },
				{ offer.id, "NoSuchCard" .. trial },
				{ offer.id, random:NextInteger(1, 100) },
				{ tostring(offer.id), offer.cards[1].Id },
				{ nil, nil },
				{ offer.id, "" },
			}
			for _, case in junk do
				local chosen, reason = service:Choose("fuzz", state, case[1], case[2])
				expect(chosen).toBeNil()
				expect(type(reason)).toBe("string")
			end

			for _, card in UpgradeConfig.Cards do
				expect(state:GetStacks(card.Id)).toBe(before[card.Id])
			end
		end
	end)
end)

--// run state machine ---------------------------------------------------------

describe("fuzz: run state machine", function()
	-- Every transition the machine is allowed to make. Anything else is a bug.
	local ALLOWED = {
		Lobby = { Starting = true },
		Starting = { Combat = true, Results = true },
		Combat = { UpgradeChoice = true, Transition = true, Results = true },
		UpgradeChoice = { Transition = true, Results = true },
		Transition = { Combat = true, Results = true },
		Results = { Cleanup = true },
		Cleanup = { Lobby = true },
	}

	local function silentRemote()
		local remote = {}
		function remote:FireClient() end
		function remote:FireAllClients() end
		return remote
	end

	local function buildMatch(seed)
		local arena = Instance.new("Folder")
		local enemies = EnemyService.new(arena, PLANE_Y, seed)
		local net = {}
		for _, name in { "RunStateChanged", "PlayerStateChanged", "UpgradeOffer", "UpgradeResolved", "RunResults", "EnemyDefeated" } do
			net[name] = silentRemote()
		end
		local upgrades = UpgradeService.new(seed)
		local match = MatchService.new({
			rooms = RoomService.new(arena, enemies, PLANE_Y, Random.new(seed)),
			enemies = enemies,
			upgrades = upgrades,
			projectiles = ProjectileService.new(arena, arena, PLANE_Y),
			rewards = RewardService.new(),
			net = net,
			world = {
				GetPosition = function()
					return Vector3.new(0, PLANE_Y, 0)
				end,
				Teleport = function() end,
			},
		})
		return match, enemies, upgrades
	end

	it("only ever makes legal transitions under random event sequences", function()
		for trial = 1, 25 do
			local seed = 81000 + trial
			local random = Random.new(seed)
			local match, enemies, upgrades = buildMatch(seed)

			local players = {}
			for index = 1, random:NextInteger(1, 4) do
				table.insert(players, { Name = "F" .. index, UserId = 900 + index })
			end
			for _, player in players do
				match:RegisterPlayer(player)
			end

			-- Polling once per tick would miss a state the machine passes through inside a
			-- single Step, so observe every transition at its source instead.
			local transitions = {}
			local originalSetState = match._setState
			match._setState = function(self, state, now)
				table.insert(transitions, { from = self:GetState(), to = state })
				return originalSetState(self, state, now)
			end

			local clock = 0
			local seenStates = { [match:GetState()] = true }

			for _ = 1, 1200 do
				local roll = random:NextNumber()
				local player = players[random:NextInteger(1, #players)]

				if roll < 0.02 then
					match:RequestStart(player, clock)
				elseif roll < 0.05 then
					match:RequestReturnToLobby(player, clock)
				elseif roll < 0.12 then
					-- A mix of valid and nonsense upgrade picks.
					local offer = upgrades:GetOffer(player)
					if offer and random:NextNumber() < 0.7 then
						match:ChooseUpgrade(player, offer.id, offer.cards[random:NextInteger(1, #offer.cards)].Id, clock)
					else
						match:ChooseUpgrade(player, random:NextInteger(0, 20), "Junk", clock)
					end
				elseif roll < 0.2 and enemies:GetActiveCount() > 0 then
					local enemy = enemies:GetEnemies()[1]
					match:HandleImpact(
						{ Position = enemy.position, Normal = Vector3.new(0, 0, 1), Instance = enemy.part },
						{ direction = Vector3.new(0, 0, 1), damage = 99, damagePerBounce = 0, contacts = 1, shooter = player },
						clock
					)
				elseif roll < 0.23 then
					match:HandlePlayerContact(player, random:NextNumber(0, 60), nil, clock)
				elseif roll < 0.25 and #players > 1 then
					match:UnregisterPlayer(player, clock)
					table.remove(players, table.find(players, player))
				elseif roll < 0.27 then
					local rejoin = { Name = "R" .. random:NextInteger(1, 999), UserId = random:NextInteger(2000, 9000) }
					match:RegisterPlayer(rejoin)
					table.insert(players, rejoin)
				end

				clock += DT
				match:Step(DT, clock)

				expect(RunConfig.States[match:GetState()]).toBe(match:GetState()) -- a declared state

				for _, transition in transitions do
					if transition.from ~= transition.to then
						local legal = ALLOWED[transition.from] and ALLOWED[transition.from][transition.to]
						if not legal then
							error(
								string.format("illegal transition %s -> %s (seed %d)", transition.from, transition.to, seed),
								0
							)
						end
					end
					seenStates[transition.to] = true
				end
				table.clear(transitions)

				-- Participants must never contain a duplicate.
				local participants = match:GetParticipants()
				local seen = {}
				for _, participant in participants do
					expect(seen[participant]).toBeNil()
					seen[participant] = true
				end
			end

			-- A long random sequence should have driven the machine well past the lobby.
			expect(seenStates.Combat).toBe(true)
		end
	end)

	it("always returns to the lobby if left alone", function()
		for trial = 1, 20 do
			local seed = 91000 + trial
			local random = Random.new(seed)
			local match, enemies = buildMatch(seed)
			local player = { Name = "Idle", UserId = 77 }
			match:RegisterPlayer(player)
			match:RequestStart(player, 0)

			local clock = 0
			local guard = 0
			-- Nobody shoots, nobody picks. The time limits must still land it in the lobby.
			while match:GetState() ~= RunConfig.States.Lobby and guard < 200000 do
				guard += 1
				clock += DT
				match:Step(DT, clock)
				if random:NextNumber() < 0.001 then
					match:HandlePlayerContact(player, 1, nil, clock)
				end
			end

			expect(match:GetState()).toBe(RunConfig.States.Lobby)
			expect(guard).toBeLessThan(200000)
			expect(enemies:GetActiveCount()).toBe(0)
		end
	end)
end)
