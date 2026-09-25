--!strict
-- Freezes a config table and everything under it, so no consumer can mutate shared tuning
-- at runtime (a mutated config desyncs server and client simulation silently).

local function freeze(value: unknown)
	if type(value) ~= "table" then
		return
	end
	local tbl = value :: { [unknown]: unknown }
	if table.isfrozen(tbl) then
		return
	end
	for _, child in tbl do
		freeze(child)
	end
	table.freeze(tbl)
end

local function deepFreeze<T>(value: T): T
	freeze(value)
	return value
end

return deepFreeze
