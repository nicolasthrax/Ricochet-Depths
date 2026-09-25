-- Lobby: the hall, the two multiplayer gates, the solo portal, the shop kiosks, the invisible
-- barrier, and signs that actually render.
local LobbyBuilder = __require("LobbyBuilder")
local PartyRooms = __require("PartyRooms")
local RunConfig = __require("RunConfig")

-- Positions keyed by player; `nil` means no character.
local function positionsOf(map)
	return function(player)
		return map[player]
	end
end

local function room(id)
	return { Id = id or "GateI", Center = Vector3.new(0, 0, 0), HalfSize = Vector2.new(7, 7), Capacity = 8, MinPlayers = 2 }
end

local function players(count, inside)
	local list, positions = {}, {}
	for index = 1, count do
		local player = { Name = "P" .. index }
		table.insert(list, player)
		positions[player] = inside and Vector3.new(index % 5 - 2, 3, 1) or Vector3.new(40, 3, 40)
	end
	return list, positions
end

local function stepFor(rooms, list, positions, from, seconds)
	local result
	local now = from
	for _ = 1, math.ceil(seconds / 0.1) do
		now += 0.1
		result = rooms:Step(now, list, positionsOf(positions))
	end
	return result, now
end

describe("PartyRooms", function()
	local config = RunConfig.Lobby

	it("never starts a gate with one player in it", function()
		local rooms = PartyRooms.new({ room() })
		local list, positions = players(1, true)
		local result = stepFor(rooms, list, positions, 0, config.GateCountdown + 5)
		expect(result.GateI.Start).toBe(false)
		expect(result.GateI.Countdown).toBeNil()
		expect(#result.GateI.Members).toBe(1)
	end)

	it("starts two players after the countdown, exactly once", function()
		local rooms = PartyRooms.new({ room() })
		local list, positions = players(2, true)
		local first = rooms:Step(0, list, positionsOf(positions))
		expect(first.GateI.Countdown).toBeCloseTo(config.GateCountdown)
		local starts, now = 0, 0
		for _ = 1, math.ceil((config.GateCountdown + 2) / 0.1) do
			now += 0.1
			if rooms:Step(now, list, positionsOf(positions)).GateI.Start then
				starts += 1
			end
		end
		expect(starts).toBe(1)
	end)

	it("shortens the countdown when the gate fills", function()
		local rooms = PartyRooms.new({ room() })
		local list, positions = players(8, true)
		local result = rooms:Step(0, list, positionsOf(positions))
		expect(result.GateI.Countdown).toBeCloseTo(config.FullCountdown)
		expect(config.FullCountdown).toBeLessThan(config.GateCountdown)
	end)

	it("holds at most eight and reports the rest as overflow", function()
		local rooms = PartyRooms.new({ room() })
		local list, positions = players(10, true)
		local result = rooms:Step(0, list, positionsOf(positions))
		expect(#result.GateI.Members).toBe(8)
		expect(#result.GateI.Overflow).toBe(2)
	end)

	it("cancels the countdown when the gate drops below two", function()
		local rooms = PartyRooms.new({ room() })
		local list, positions = players(2, true)
		local _, now = stepFor(rooms, list, positions, 0, config.GateCountdown / 2)
		positions[list[2]] = Vector3.new(50, 3, 50)
		local result = rooms:Step(now + 0.1, list, positionsOf(positions))
		expect(result.GateI.Countdown).toBeNil()
		positions[list[2]] = Vector3.new(0, 3, 0)
		result = rooms:Step(now + 0.2, list, positionsOf(positions))
		-- A fresh countdown, not the one that was half spent.
		expect(result.GateI.Countdown).toBeCloseTo(config.GateCountdown)
	end)

	it("keeps each gate's players separate, and skips anyone it is told is busy", function()
		local rooms = PartyRooms.new({ room("GateI"), { Id = "GateII", Center = Vector3.new(30, 0, 0), HalfSize = Vector2.new(7, 7), Capacity = 8, MinPlayers = 2 } })
		local list, positions = players(3, true)
		positions[list[3]] = Vector3.new(30, 3, 0)
		local result = rooms:Step(0, list, positionsOf(positions), function(player)
			return player == list[2]
		end)
		expect(#result.GateI.Members).toBe(1)
		expect(#result.GateII.Members).toBe(1)
	end)
end)

-- XZ bounds of a part, allowing for a yaw turn.
local function bounds(part)
	local cframe = part.CFrame
	local right, look = cframe.RightVector, cframe.LookVector
	local size = part.Size
	local hx = math.abs(right.X) * size.X / 2 + math.abs(look.X) * size.Z / 2
	local hz = math.abs(right.Z) * size.X / 2 + math.abs(look.Z) * size.Z / 2
	return { minX = part.Position.X - hx, maxX = part.Position.X + hx, minZ = part.Position.Z - hz, maxZ = part.Position.Z + hz }
end

local function overlaps(a, b, margin)
	return a.minX < b.maxX + margin and b.minX < a.maxX + margin and a.minZ < b.maxZ + margin and b.minZ < a.maxZ + margin
end

local function inside(point, part)
	local b = bounds(part)
	local halfY = part.Size.Y / 2
	return point.X > b.minX and point.X < b.maxX and point.Z > b.minZ and point.Z < b.maxZ
		and point.Y > part.Position.Y - halfY and point.Y < part.Position.Y + halfY
end

describe("lobby layout", function()
	local world = Instance.new("Folder")
	local lobby, soloPrompt, parts = LobbyBuilder.Build(world)
	local dressing = lobby:FindFirstChild("Dressing")

	it("has a solo portal, two gates, the Outpost portal and the Cosmetics kiosk, each with its prompt", function()
		expect(soloPrompt.ClassName).toBe("ProximityPrompt")
		expect(soloPrompt.Parent.Name).toBe("DescentPedestal")
		expect(#parts.gates).toBe(2)
		for _, gate in parts.gates do
			expect(gate.zone:IsA("BasePart")).toBe(true)
			expect(gate.zone.CanCollide).toBe(false)
			expect(gate.board).toBeTruthy()
			expect(gate.capacity).toBe(RunConfig.Lobby.GateCapacity)
		end
		expect(parts.outpostPrompt.Parent.Name).toBe("OutpostKiosk")
		expect(parts.cosmeticsPrompt.Parent.Name).toBe("CosmeticsKiosk")
	end)

	it("puts the gates on the west side and the shops on the east", function()
		local origin = RunConfig.LobbyPosition
		for _, gate in parts.gates do
			expect(gate.zone.Position.X - origin.X).toBeLessThan(-20)
		end
		expect(lobby:FindFirstChild("OutpostKiosk").Position.X - origin.X).toBeGreaterThan(20)
		expect(lobby:FindFirstChild("CosmeticsKiosk").Position.X - origin.X).toBeGreaterThan(20)
	end)

	it("has solid pillars and lamp posts, not ones players walk through", function()
		local dressing = lobby:FindFirstChild("Dressing")
		local checked = 0
		for _, part in dressing:GetChildren() do
			if part.Name:find("^Pillar%d") or part.Name:find("^LampPost") then
				checked += 1
				expect(part.CanCollide).toBe(true)
			end
		end
		expect(checked).toBe(14)
	end)

	it("is sealed by an invisible barrier and ceiling nobody can jump over", function()
		local barrier = lobby:FindFirstChild("Barrier")
		expect(barrier).toBeTruthy()
		local walls, ceiling = 0, false
		for _, part in barrier:GetChildren() do
			expect(part.Transparency).toBe(1)
			expect(part.CanCollide).toBe(true)
			if part.Name:find("^BarrierWall") then
				walls += 1
				expect(part.Size.Y).toBeGreaterThanOrEqual(60)
			elseif part.Name == "BarrierCeiling" then
				ceiling = true
			end
		end
		expect(walls).toBe(4)
		expect(ceiling).toBe(true)
		-- Everything a player can stand on sits inside the barrier.
		local floor = lobby:FindFirstChild("LobbyFloor")
		for _, part in barrier:GetChildren() do
			if part.Name:find("^BarrierWall") then
				expect(overlaps(bounds(part), bounds(floor), -0.01)).toBe(false)
			end
		end
	end)

	it("keeps props clear of the spawn, portal, gates and kiosks", function()
		local keepClear = {
			lobby:FindFirstChild("LobbySpawn"),
			lobby:FindFirstChild("DescentPedestal"),
			lobby:FindFirstChild("OutpostKiosk"),
			lobby:FindFirstChild("CosmeticsKiosk"),
		}
		for _, gate in parts.gates do
			table.insert(keepClear, gate.zone)
		end
		for _, prop in dressing:GetDescendants() do
			if prop:IsA("BasePart") and prop.Size.Y > 1 then
				for _, feature in keepClear do
					if overlaps(bounds(prop), bounds(feature), 2) then
						error(("%s crowds %s"):format(prop.Name, feature.Name))
					end
				end
			end
		end
	end)

	it("lights the hall and shows a banner for each zone", function()
		local lamps, banners = 0, 0
		for _, part in dressing:GetDescendants() do
			if part:IsA("PointLight") then
				lamps += 1
			end
			if part.Name:find("^ZoneBanner") then
				banners += 1
			end
		end
		expect(lamps).toBeGreaterThanOrEqual(4)
		expect(banners).toBe(3)
	end)
end)

describe("lobby signs", function()
	local lobby, _, parts = LobbyBuilder.Build(Instance.new("Folder"))

	it("prints every board on a SurfaceGui with real text", function()
		local boards = 0
		for _, gui in lobby:GetDescendants() do
			if gui.ClassName == "SurfaceGui" then
				boards += 1
				local label = gui:FindFirstChild("Text")
				expect(label).toBeTruthy()
				expect(#label.Text).toBeGreaterThan(0)
				expect(label.TextScaled).toBe(true)
				expect(gui.Parent:IsA("BasePart")).toBe(true)
			end
		end
		-- Two gates, the Outpost and Cosmetics kiosks, three zone banners, the solo portal.
		expect(boards).toBeGreaterThanOrEqual(8)
		for _, text in { "YOUR OUTPOST", "COSMETICS", "SOLO DESCENT" } do
			local found = false
			for _, gui in lobby:GetDescendants() do
				if gui.ClassName == "TextLabel" and gui.Text == text then
					found = true
				end
			end
			if not found then
				error("no sign reads " .. text)
			end
		end
	end)

	it("sizes floating labels in studs and never buries them inside a part", function()
		local solids = {}
		for _, part in lobby:GetDescendants() do
			if part:IsA("BasePart") and part.Transparency < 1 then
				table.insert(solids, part)
			end
		end
		for _, gui in lobby:GetDescendants() do
			if gui.ClassName == "BillboardGui" then
				-- Scale, not pixels: the label grows and shrinks with distance like the world.
				expect(gui.Size.X.Scale).toBeGreaterThan(0)
				expect(gui.Size.X.Offset).toBe(0)
				local anchor = gui.Parent.Position + gui.StudsOffsetWorldSpace
				for _, part in solids do
					if part ~= gui.Parent and inside(anchor, part) then
						error(("%s's label sits inside %s"):format(gui.Parent.Name, part.Name))
					end
				end
			end
		end
	end)

	it("updates a gate's board with its count and countdown", function()
		local gate = parts.gates[1]
		LobbyBuilder.SetGateStatus(gate, 3, 12)
		expect(gate.board:FindFirstChildOfClass("SurfaceGui"):FindFirstChild("Text").Text).toBe("GATE I  3/8  ·  12s")
		LobbyBuilder.SetGateStatus(gate, 1, nil)
		expect(gate.board:FindFirstChildOfClass("SurfaceGui"):FindFirstChild("Text").Text).toBe("GATE I  1/8  ·  need 2")
	end)
end)
