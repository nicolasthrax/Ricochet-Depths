--!strict
-- Runtime checks for untrusted values (remote payloads). Every function takes `unknown` and
-- returns the narrowed value, or nil when the value is not acceptable. Validators build a fresh
-- payload from these results, so extra keys, metatables and wrong types never reach game code.

local Guard = {}

-- A plain table (no metatable). Returns it typed for field access, or nil.
function Guard.record(value: unknown): { [unknown]: unknown }?
	if type(value) ~= "table" then
		return nil
	end
	local tbl = value :: { [unknown]: unknown }
	if getmetatable(tbl :: any) ~= nil then
		return nil
	end
	return tbl
end

-- A finite number (no NaN or infinity), optionally inside [min, max].
function Guard.number(value: unknown, min: number?, max: number?): number?
	if type(value) ~= "number" then
		return nil
	end
	local n = value :: number
	if n ~= n or n == math.huge or n == -math.huge then
		return nil
	end
	if (min ~= nil and n < min) or (max ~= nil and n > max) then
		return nil
	end
	return n
end

-- A whole number inside [min, max].
function Guard.integer(value: unknown, min: number, max: number): number?
	local n = Guard.number(value, min, max)
	if n == nil or n % 1 ~= 0 then
		return nil
	end
	return n
end

-- A boolean. Note that `false` is a valid result: compare against nil, not falsiness.
function Guard.boolean(value: unknown): boolean?
	if type(value) ~= "boolean" then
		return nil
	end
	return value :: boolean
end

-- One of a fixed set of strings (an enum-like string union).
function Guard.oneOf<T>(value: unknown, options: { T }): T?
	if type(value) ~= "string" then
		return nil
	end
	for _, option in options do
		if (option :: any) == value then
			return option
		end
	end
	return nil
end

-- A finite, non-zero Vector2, returned normalised to unit length.
function Guard.direction(value: unknown): Vector2?
	if typeof(value) ~= "Vector2" then
		return nil
	end
	local v = value :: Vector2
	local x = Guard.number(v.X)
	local y = Guard.number(v.Y)
	if x == nil or y == nil then
		return nil
	end
	local length = math.sqrt(x * x + y * y)
	if length < 1e-4 then
		return nil
	end
	return Vector2.new(x / length, y / length)
end

table.freeze(Guard)
return Guard
