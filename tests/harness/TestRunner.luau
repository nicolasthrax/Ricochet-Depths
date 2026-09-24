-- Tiny describe/it/expect runner. Prints a summary and sets the process exit code.
local results = { passed = 0, failed = 0, failures = {}, suite = "" }

function describe(name, body)
	local previous = results.suite
	results.suite = previous ~= "" and (previous .. " > " .. name) or name
	body()
	results.suite = previous
end

function it(name, body)
	local label = results.suite ~= "" and (results.suite .. " > " .. name) or name
	Harness.resetScheduler()
	local ok, err = pcall(body)
	-- A spawned thread that errored is a failure of this test, even if the body returned cleanly.
	local threadErrors = Harness.takeTaskErrors()
	if ok and #threadErrors > 0 then
		ok, err = false, "error in a spawned thread: " .. threadErrors[1]
	end
	if ok then
		results.passed += 1
	else
		results.failed += 1
		table.insert(results.failures, { label = label, err = tostring(err) })
		print(string.format("  FAIL  %s\n        %s", label, tostring(err)))
	end
end

local function stringify(value)
	if type(value) == "table" then
		local mt = getmetatable(value)
		if mt and rawget(mt, "__tostring") then
			return tostring(value)
		end
		local parts = {}
		for k, v in pairs(value) do
			table.insert(parts, tostring(k) .. "=" .. tostring(v))
		end
		table.sort(parts)
		return "{" .. table.concat(parts, ", ") .. "}"
	end
	return tostring(value)
end

local function deepEqual(a, b)
	if a == b then
		return true
	end
	if type(a) ~= "table" or type(b) ~= "table" then
		return false
	end
	for key, value in pairs(a) do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in pairs(b) do
		if a[key] == nil then
			return false
		end
	end
	return true
end

function expect(actual)
	local matchers = {}

	function matchers.toBe(expected)
		if actual ~= expected then
			error(("expected %s to be %s"):format(stringify(actual), stringify(expected)), 3)
		end
	end

	function matchers.toEqual(expected)
		if not deepEqual(actual, expected) then
			error(("expected %s to deep-equal %s"):format(stringify(actual), stringify(expected)), 3)
		end
	end

	function matchers.toBeCloseTo(expected, tolerance)
		local limit = tolerance or 1e-6
		if math.abs(actual - expected) > limit then
			error(("expected %s to be within %s of %s"):format(stringify(actual), limit, stringify(expected)), 3)
		end
	end

	function matchers.toBeTruthy()
		if not actual then
			error(("expected %s to be truthy"):format(stringify(actual)), 3)
		end
	end

	function matchers.toBeFalsy()
		if actual then
			error(("expected %s to be falsy"):format(stringify(actual)), 3)
		end
	end

	function matchers.toBeNil()
		if actual ~= nil then
			error(("expected %s to be nil"):format(stringify(actual)), 3)
		end
	end

	function matchers.toBeGreaterThan(limit)
		if not (actual > limit) then
			error(("expected %s to be greater than %s"):format(stringify(actual), stringify(limit)), 3)
		end
	end

	function matchers.toBeLessThan(limit)
		if not (actual < limit) then
			error(("expected %s to be less than %s"):format(stringify(actual), stringify(limit)), 3)
		end
	end

	function matchers.toBeGreaterThanOrEqual(limit)
		if not (actual >= limit) then
			error(("expected %s to be >= %s"):format(stringify(actual), stringify(limit)), 3)
		end
	end

	function matchers.toBeLessThanOrEqual(limit)
		if not (actual <= limit) then
			error(("expected %s to be <= %s"):format(stringify(actual), stringify(limit)), 3)
		end
	end

	function matchers.toHaveLength(expected)
		if #actual ~= expected then
			error(("expected length %d, got %d"):format(expected, #actual), 3)
		end
	end

	function matchers.toThrow()
		local ok = pcall(actual)
		if ok then
			error("expected function to throw", 3)
		end
	end

	function matchers.never()
		local inverted = {}
		for key, matcher in pairs(matchers) do
			if key ~= "never" then
				inverted[key] = function(...)
					local args = table.pack(...)
					local ok = pcall(function()
						matcher(table.unpack(args, 1, args.n))
					end)
					if ok then
						error(("expected %s NOT to satisfy %s"):format(stringify(actual), key), 3)
					end
				end
			end
		end
		return inverted
	end

	return matchers
end

__testResults = results

function __finishTests()
	print(string.format("\n%d passed, %d failed", results.passed, results.failed))
	if results.failed > 0 then
		print("FAILURES:")
		for _, failure in results.failures do
			print("  - " .. failure.label)
		end
		error("test suite failed", 0)
	end
end

-- Clears a room completely through the caller's own functions: every wave, and any objective.
-- killAll() kills whatever is alive; step(seconds) advances the match (so a wave announced on
-- the floor has time to arrive). Objective rooms are marked done: RoomObjectives has its own
-- tests, and a run-through test only needs the room behind it.
function __clearRoom(rooms, killAll, step)
	for _ = 1, 16 do
		local objective = rooms.GetObjective and rooms:GetObjective()
		if objective and not objective:IsComplete() then
			objective._complete = true
		end
		killAll()
		if not (rooms.HasPendingWaves and rooms:HasPendingWaves()) then
			return
		end
		step(1.6)
	end
end
