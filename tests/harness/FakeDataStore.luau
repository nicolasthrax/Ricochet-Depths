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

	if self.conflicts > 0 then
		self.conflicts -= 1
		if self.externalWrite then
			self.data[key] = serialise(self.externalWrite(serialise(self.data[key])))
		end
	end

	-- The transform works on a copy, and what is kept is a copy of what it returns.
	local updated = transform(serialise(self.data[key]))
	if updated == nil then
		return nil -- a nil result cancels the write, as in the engine
	end
	self.data[key] = serialise(updated)
	self.writes += 1
	return serialise(self.data[key])
end

-- A copy of what is stored under key, for assertions. Reading it cannot affect the store.
function FakeDataStore:Peek(key)
	return serialise(self.data[key])
end

__FakeDataStore = FakeDataStore
