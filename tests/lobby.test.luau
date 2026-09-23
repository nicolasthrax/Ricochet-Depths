-- Lobby: the four-pad co-op ready-up zone and the shop kiosk.
local LobbyBuilder = __require("LobbyBuilder")
local LobbyReady = __require("LobbyReady")
local RunConfig = __require("RunConfig")

local function pads(count)
	local out = {}
	for index = 1, count do
		table.insert(out, { Center = Vector3.new(index * 10, 0, 0), HalfSize = Vector2.new(3, 3) })
	end
	return out
end

-- Positions keyed by player; `nil` means no character.
local function positionsOf(map)
	return function(player)
		return map[player]
	end
end

local function onPad(index)
	return Vector3.new(index * 10 + 1, 3, -1)
end

describe("LobbyBuilder ready zone and kiosk", function()
	it("builds four ready pads and a shop kiosk with its own prompt", function()
		local lobby, startPrompt, extras = LobbyBuilder.Build(Instance.new("Folder"))
		expect(startPrompt).toBeTruthy()
		expect(#extras.readyPads).toBe(RunConfig.Lobby.ReadyPadCount)
		expect(RunConfig.Lobby.ReadyPadCount).toBe(4)
		for index, pad in extras.readyPads do
			expect(pad.Name).toBe("ReadyPad" .. index)
			expect(pad.Parent).toBe(lobby:FindFirstChild("ReadyZone"))
		end

		local kiosk = lobby:FindFirstChild("ShopKiosk")
		expect(kiosk).toBeTruthy()
		expect(extras.shopPrompt.ClassName).toBe("ProximityPrompt")
		expect(extras.shopPrompt.Parent).toBe(kiosk)
		expect(extras.shopPrompt).never().toBe(startPrompt)
	end)

	it("keeps the pads apart and clear of the lobby spawn", function()
		local lobby, _, extras = LobbyBuilder.Build(Instance.new("Folder"))
		local spawn = lobby:FindFirstChild("LobbySpawn")
		for index, pad in extras.readyPads do
			local gap = Vector3.new(pad.Position.X - spawn.Position.X, 0, pad.Position.Z - spawn.Position.Z)
			expect(gap.Magnitude).toBeGreaterThan(8)
			for other = index + 1, #extras.readyPads do
				local between = extras.readyPads[other].Position - pad.Position
				expect(Vector3.new(between.X, 0, between.Z).Magnitude).toBeGreaterThan(pad.Size.X)
			end
		end
	end)

	it("describes each pad's footprint for the ready check", function()
		local _, _, extras = LobbyBuilder.Build(Instance.new("Folder"))
		local footprints = LobbyReady.PadsFromParts(extras.readyPads)
		expect(#footprints).toBe(4)
		expect(footprints[1].HalfSize.X).toBeCloseTo(extras.readyPads[1].Size.X / 2)
	end)
end)

describe("LobbyReady", function()
	it("never starts an empty lobby", function()
		local ready = LobbyReady.new(pads(4), { countdown = 1 })
		local snapshot = ready:Step(10, {}, positionsOf({}))
		expect(snapshot.Start).toBe(false)
		expect(snapshot.Total).toBe(0)
	end)

	it("counts down once everyone is on a pad and starts exactly once", function()
		local ready = LobbyReady.new(pads(4), { countdown = 3 })
		local a, b = { Name = "A" }, { Name = "B" }
		local where = positionsOf({ [a] = onPad(1), [b] = onPad(2) })

		local first = ready:Step(0, { a, b }, where)
		expect(first.Ready).toBe(2)
		expect(first.Total).toBe(2)
		expect(first.Countdown).toBeCloseTo(3)
		expect(first.Start).toBe(false)
		expect(ready:Step(2.9, { a, b }, where).Start).toBe(false)

		local fired = ready:Step(3, { a, b }, where)
		expect(fired.Start).toBe(true)
		expect(fired.Starter).toBe(a)
		expect(ready:Step(3.1, { a, b }, where).Start).toBe(false)
	end)

	it("holds while anyone is off a pad and resets the countdown when someone steps off", function()
		local ready = LobbyReady.new(pads(4), { countdown = 2 })
		local a, b = { Name = "A" }, { Name = "B" }
		local map = { [a] = onPad(1), [b] = Vector3.new(500, 3, 500) }
		local where = positionsOf(map)

		local waiting = ready:Step(0, { a, b }, where)
		expect(waiting.Ready).toBe(1)
		expect(waiting.Countdown).toBeNil()

		map[b] = onPad(3)
		ready:Step(1, { a, b }, where)
		map[b] = nil -- respawning: no character counts as not ready
		expect(ready:Step(2.5, { a, b }, where).Countdown).toBeNil()
		map[b] = onPad(3)
		expect(ready:Step(3, { a, b }, where).Countdown).toBeCloseTo(2)
		expect(ready:Step(4.9, { a, b }, where).Start).toBe(false)
		expect(ready:Step(5, { a, b }, where).Start).toBe(true)
	end)

	it("counts two players crowding one pad as one pad filled", function()
		local ready = LobbyReady.new(pads(4), { countdown = 1 })
		local a, b = { Name = "A" }, { Name = "B" }
		local snapshot = ready:Step(0, { a, b }, positionsOf({ [a] = onPad(1), [b] = onPad(1) }))
		expect(snapshot.Ready).toBe(1)
		expect(snapshot.Countdown).toBeNil()
	end)

	it("starts with every pad filled even if more players are in the lobby than pads", function()
		local ready = LobbyReady.new(pads(4), { countdown = 1 })
		local players, map = {}, {}
		for index = 1, 5 do
			local player = { Name = "P" .. index }
			players[index] = player
			map[player] = index <= 4 and onPad(index) or Vector3.new(0, 3, 300)
		end
		ready:Step(0, players, positionsOf(map))
		expect(ready:Step(1, players, positionsOf(map)).Start).toBe(true)
	end)

	it("reports which pads are occupied, for lighting them up", function()
		local ready = LobbyReady.new(pads(4), { countdown = 1 })
		local a = { Name = "A" }
		local snapshot = ready:Step(0, { a }, positionsOf({ [a] = onPad(3) }))
		expect(snapshot.Occupied[3]).toBe(true)
		expect(snapshot.Occupied[1]).toBe(false)
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

describe("lobby hub", function()
	local world = Instance.new("Folder")
	local lobby = LobbyBuilder.Build(world)
	local dressing = lobby:FindFirstChild("Dressing")

	it("is walled in on all four sides, so nobody walks off into the void", function()
		expect(dressing).toBeTruthy()
		local walls = 0
		for _, part in dressing:GetChildren() do
			if part.Name:find("^HallWall") then
				walls += 1
				expect(part.CanCollide).toBe(true)
				expect(part.Size.Y).toBeGreaterThanOrEqual(8)
			end
		end
		expect(walls).toBe(4)
	end)

	it("keeps props clear of the spawn, pedestal, ready pads and kiosk", function()
		local keepClear = { lobby:FindFirstChild("LobbySpawn"), lobby:FindFirstChild("DescentPedestal"), lobby:FindFirstChild("ShopKiosk") }
		for _, pad in lobby:FindFirstChild("ReadyZone"):GetChildren() do
			table.insert(keepClear, pad)
		end
		for _, prop in dressing:GetDescendants() do
			-- Floor-level glow (the well ring) may run under things; anything standing may not.
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

	it("labels every ready pad", function()
		for _, pad in lobby:FindFirstChild("ReadyZone"):GetChildren() do
			expect(pad:FindFirstChild("PadLabel")).toBeTruthy()
		end
	end)
end)
