-- An in-memory DataStore with the one property the earlier inline fakes lacked: serialisation.
--
-- A real DataStore stores a serialised copy and hands back a fresh copy on every read, so nothing
-- a script holds is ever the stored value. The inline fakes stored and returned the same table,
-- which meant a profile mutated in memory with no save at all appeared to be persisted. That
-- could make a test pass while the save path it claimed to test did nothing.
--
-- Also mirrors the engine in rejecting values a DataStore cannot hold (functions, threads,
-- non-string/number keys, cycles), and treats a nil transform result as a cancelled write.

local FakeDataStore = {}
FakeDataStore.__index = FakeDataStore

local function serialise(value, seen)
	local kind = type(value)
	if kind == "table" then
		seen = seen or {}
		if seen[value] then
			error("cannot store a cyclic table in a DataStore", 0)
		end
		seen[value] = true
		local copy = {}
		for key, child in pairs(value) do
			local keyKind = type(key)
			if keyKind ~= "string" and keyKind ~= "number" then
				error("DataStore table keys must be strings or numbers, got " .. keyKind, 0)
			end
			copy[key] = serialise(child, seen)
		end
		seen[value] = nil
		return copy
	elseif kind == "function" or kind == "thread" or kind == "userdata" then
		error("cannot store a " .. kind .. " in a DataStore", 0)
	end
	return value
end

function FakeDataStore.new()
	return setmetatable({
		data = {}, -- the backend: serialised copies, never shared with callers
		calls = 0, -- every UpdateAsync, including failed ones
		writes = 0, -- successful writes only
		failing = false, -- fail every call while set
		alwaysFail = false, -- alias kept for older tests
		failuresRemaining = 0, -- fail this many calls, then recover
		conflicts = 0, -- simulate another server writing between our read and our write
		externalWrite = nil, -- what that other server writes: function(storedCopy) -> newValue

		-- Latency, in virtual seconds, before the read and before the commit. Zero keeps every
		-- call synchronous; anything above zero makes the caller yield on the harness scheduler.
		readLatency = 0,
		writeLatency = 0,

		versions = {}, -- per-key commit counter, for optimistic concurrency
		inFlight = {}, -- per-key calls currently between read and commit
		peakInFlight = {}, -- the most concurrent calls ever seen on each key
		transformReruns = 0, -- transforms re-run because another write committed first
	}, FakeDataStore)
end

function FakeDataStore:UpdateAsync(key, transform)
	self.calls += 1
	if self.failing or self.alwaysFail then
		error("simulated datastore failure", 0)
	end
	if self.failuresRemaining > 0 then
		self.failuresRemaining -= 1
		error("simulated datastore failure", 0)
	end

	self.inFlight[key] = (self.inFlight[key] or 0) + 1
	self.peakInFlight[key] = math.max(self.peakInFlight[key] or 0, self.inFlight[key])

	local ok, result = pcall(function()
		if self.readLatency > 0 then
			task.wait(self.readLatency)
		end

		if self.conflicts > 0 then
			self.conflicts -= 1
			if self.externalWrite then
				self.data[key] = serialise(self.externalWrite(serialise(self.data[key])))
				self.versions[key] = (self.versions[key] or 0) + 1
			end
		end

		-- Optimistic concurrency, as the engine does it: if another write to this key commits
		-- while this one is in flight, the transform is run again against the newer value.
		for _ = 1, 10 do
			local readVersion = self.versions[key] or 0
			-- The transform works on a copy, and what is kept is a copy of what it returns,
			-- taken at the moment it returns.
			local updated = transform(serialise(self.data[key]))
			if updated == nil then
				return nil -- a nil result cancels the write, as in the engine
			end
			local encoded = serialise(updated)

			if self.writeLatency > 0 then
				task.wait(self.writeLatency)
			end

			if (self.versions[key] or 0) == readVersion then
				self.data[key] = encoded
				self.versions[key] = readVersion + 1
				self.writes += 1
				return serialise(encoded)
			end
			self.transformReruns += 1
		end
		error("UpdateAsync gave up after repeated write conflicts", 0)
	end)

	self.inFlight[key] -= 1
	if not ok then
		error(result, 0)
	end
	return result
end

-- A copy of what is stored under key, for assertions. Reading it cannot affect the store.
function FakeDataStore:Peek(key)
	return serialise(self.data[key])
end

__FakeDataStore = FakeDataStore
