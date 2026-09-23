-- Enemy models: multi-part bodies built on the client over the server's hitboxes. Purely
-- cosmetic, so every part must stay out of raycasts, collisions and touches.
local EnemyConfig = __require("EnemyConfig")
local EnemyModels = __require("EnemyModels")
local EnemyVisualConfig = __require("EnemyVisualConfig")

local function partCount(visual)
	local count = #visual.Parts
	for _, ring in visual.Rings or {} do
		count += ring.Count
	end
	return count
end

describe("EnemyVisualConfig", function()
	it("gives every archetype a model of several parts", function()
		for id in EnemyConfig.Archetypes do
			local visual = EnemyVisualConfig.Archetypes[id]
			if not visual then
				error("no model for archetype " .. id)
			end
			expect(partCount(visual)).toBeGreaterThanOrEqual(4)
		end
	end)

	it("keeps every model inside its hitbox's height so it reads where it can be hit", function()
		for id, visual in EnemyVisualConfig.Archetypes do
			local archetype = EnemyConfig.Archetypes[id]
			if archetype then
				local half = archetype.Size.Y / 2
				for _, spec in visual.Parts do
					expect(math.abs(spec.Offset.Y) + spec.Size.Y / 2).toBeLessThanOrEqual(half + (visual.Bob or 0))
				end
			end
		end
	end)
end)

describe("EnemyModels.Build", function()
	it("builds inert, anchored parts for each archetype", function()
		for id in EnemyVisualConfig.Archetypes do
			local model = EnemyModels.Build(id, Instance.new("Folder"))
			local parts = model:GetChildren()
			expect(#parts).toBe(partCount(EnemyVisualConfig.Archetypes[id]))
			for _, part in parts do
				expect(part.Anchored).toBe(true)
				expect(part.CanQuery).toBe(false)
				expect(part.CanCollide).toBe(false)
				expect(part.CanTouch).toBe(false)
			end
		end
	end)
end)

describe("EnemyModels.Pose", function()
	local visual = EnemyVisualConfig.Archetypes.Chaser

	it("is deterministic for the same inputs", function()
		local a = EnemyModels.Pose(visual, Vector3.new(4, 3, 2), Vector3.new(0, 0, -1), 1.25, 7)
		local b = EnemyModels.Pose(visual, Vector3.new(4, 3, 2), Vector3.new(0, 0, -1), 1.25, 7)
		for index, pose in a do
			expect((pose.position - b[index].position).Magnitude).toBeCloseTo(0)
		end
	end)

	it("turns with the facing: a part offset forward stays in front of the body", function()
		local frontIndex
		for index, spec in visual.Parts do
			if spec.Offset.Z < -0.5 then
				frontIndex = index
				break
			end
		end
		expect(frontIndex).toBeTruthy()
		local body = Vector3.new(0, 3, 0)
		for _, facing in { Vector3.new(1, 0, 0), Vector3.new(0, 0, 1), Vector3.new(-1, 0, 0) } do
			local poses = EnemyModels.Pose(visual, body, facing, 0, 1)
			local offset = poses[frontIndex].position - body
			expect(Vector3.new(offset.X, 0, offset.Z).Unit:Dot(facing)).toBeGreaterThan(0.5)
		end
	end)

	it("spins ring parts around the body over time", function()
		local warden = EnemyVisualConfig.Archetypes.WardenCore
		local ringStart = #warden.Parts + 1
		local body = Vector3.new(0, 3, 0)
		local early = EnemyModels.Pose(warden, body, Vector3.new(0, 0, -1), 0, 1)
		local later = EnemyModels.Pose(warden, body, Vector3.new(0, 0, -1), 0.5, 1)
		expect((early[ringStart].position - later[ringStart].position).Magnitude).toBeGreaterThan(0.1)
		local ring = warden.Rings[1]
		local radial = early[ringStart].position - body
		expect(Vector3.new(radial.X, 0, radial.Z).Magnitude).toBeCloseTo(ring.Radius, 1)
	end)
end)

describe("EnemyModels.IsParked", function()
	it("treats pooled bodies at the storage position as hidden", function()
		expect(EnemyModels.IsParked(EnemyConfig.StoragePosition)).toBe(true)
		expect(EnemyModels.IsParked(Vector3.new(10, 3, -4))).toBe(false)
	end)
end)
