-- Room set-dressing and zone lighting: purely cosmetic, and never where a shot can go.
local RoomBuilder = __require("RoomBuilder")
local RoomConfig = __require("RoomConfig")
local RoomDressing = __require("RoomDressing")
local RunConfig = __require("RunConfig")
local ZoneAmbienceConfig = __require("ZoneAmbienceConfig")

describe("room dressing", function()
	it("dresses every room with props in its zone's style", function()
		for layoutId, layout in RoomConfig.Layouts do
			local room = RoomBuilder.Build(Instance.new("Folder"), layoutId)
			local dressing = room:FindFirstChild("Dressing")
			if not dressing then
				error(layoutId .. " has no dressing")
			end
			expect(#dressing:GetChildren()).toBeGreaterThanOrEqual(8)
			expect(dressing:GetAttribute("Zone")).toBe(layout.Zone)
		end
	end)

	it("is inert: no raycasts, collisions or touches", function()
		for layoutId in RoomConfig.Layouts do
			local room = RoomBuilder.Build(Instance.new("Folder"), layoutId)
			for _, part in room:FindFirstChild("Dressing"):GetDescendants() do
				if part:IsA("BasePart") then
					expect(part.CanQuery).toBe(false)
					expect(part.CanCollide).toBe(false)
					expect(part.CanTouch).toBe(false)
					expect(part.Anchored).toBe(true)
				end
			end
		end
	end)

	it("stays out of the play space: above the walls, beyond them, or in sealed corners", function()
		for layoutId, layout in RoomConfig.Layouts do
			local room = RoomBuilder.Build(Instance.new("Folder"), layoutId)
			for _, part in room:FindFirstChild("Dressing"):GetDescendants() do
				if part:IsA("BasePart") then
					local reason = RoomDressing.Placement(layout, part.Position, part.Size)
					if not reason then
						error(("%s: %s stands in the play space at (%.1f, %.1f, %.1f)"):format(
							layoutId, part.Name, part.Position.X, part.Position.Y, part.Position.Z))
					end
				end
			end
		end
	end)
end)

describe("zone ambience", function()
	it("sets lighting for the lobby and every zone", function()
		local keys = { "Ambient", "OutdoorAmbient", "Brightness", "ClockTime", "AtmosphereColor", "AtmosphereDensity" }
		for _, id in { "Lobby", "Ruins", "Foundry", "Abyss" } do
			local ambience = ZoneAmbienceConfig.For(id)
			for _, key in keys do
				if ambience[key] == nil then
					error(id .. " ambience has no " .. key)
				end
			end
		end
		for zoneId in RunConfig.Zones do
			expect(ZoneAmbienceConfig.Zones[zoneId]).toBeTruthy()
		end
		-- Tweens run straight between values: all in the evening, so none sweeps through noon.
		for id, ambience in ZoneAmbienceConfig.Zones do
			if ambience.ClockTime < 17 or ambience.ClockTime > 24 then
				error(id .. " ClockTime would tween through daylight")
			end
		end
		-- Unknown zones fall back to the lobby look rather than failing.
		expect(ZoneAmbienceConfig.For("Nowhere")).toBe(ZoneAmbienceConfig.Zones.Lobby)
	end)
end)
