-- Impact batching: one remote per interval, hard cap per batch, overflow counted not crashed.
local EffectConfig = __require("EffectConfig")
local EffectBroadcaster = __require("EffectBroadcaster")

local function newBroadcaster()
	local remote = Instance.new("RemoteEvent")
	return EffectBroadcaster.new(remote), remote
end

local function firedCount(remote)
	return #rawget(remote, "_fired")
end

describe("EffectBroadcaster", function()
	it("collapses many impacts into a single remote call", function()
		local broadcaster, remote = newBroadcaster()
		Harness.setClock(0)
		broadcaster:Step(0) -- arm the interval

		for index = 1, 10 do
			broadcaster:Queue(Vector3.new(index, 3, 0), Vector3.new(0, 0, 1))
		end
		expect(firedCount(remote)).toBe(0)

		Harness.setClock(EffectConfig.BatchInterval)
		expect(broadcaster:Step(Harness.now())).toBe(10)
		expect(firedCount(remote)).toBe(1)

		local payload = rawget(remote, "_fired")[1].args
		expect(#payload[1]).toBe(10)
		expect(#payload[2]).toBe(10)
		expect(payload[1][1].X).toBe(1)
	end)

	it("caps batch size and counts the overflow instead of growing without bound", function()
		local broadcaster = newBroadcaster()
		Harness.setClock(0)
		local accepted = 0
		for _ = 1, EffectConfig.MaxImpactsPerBatch + 40 do
			if broadcaster:Queue(Vector3.zero, Vector3.new(0, 1, 0)) then
				accepted += 1
			end
		end
		expect(accepted).toBe(EffectConfig.MaxImpactsPerBatch)
		expect(broadcaster:GetDroppedCount()).toBe(40)
	end)

	it("sends nothing when no impacts occurred", function()
		local broadcaster, remote = newBroadcaster()
		Harness.setClock(0)
		broadcaster:Step(0)
		Harness.setClock(10)
		expect(broadcaster:Step(Harness.now())).toBe(0)
		expect(firedCount(remote)).toBe(0)
	end)

	it("frees capacity again after a flush", function()
		local broadcaster = newBroadcaster()
		Harness.setClock(0)
		broadcaster:Step(0)
		for _ = 1, EffectConfig.MaxImpactsPerBatch do
			broadcaster:Queue(Vector3.zero, Vector3.new(0, 1, 0))
		end
		expect(broadcaster:Queue(Vector3.zero, Vector3.new(0, 1, 0))).toBe(false)
		Harness.setClock(EffectConfig.BatchInterval)
		broadcaster:Step(Harness.now())
		expect(broadcaster:Queue(Vector3.zero, Vector3.new(0, 1, 0))).toBe(true)
	end)
end)
