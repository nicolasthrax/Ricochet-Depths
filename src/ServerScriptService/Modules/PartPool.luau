-- Generic fixed-size part pool. Parts are built once; Acquire never allocates, and a dry pool
-- returns nil so callers degrade instead of growing the instance count without bound.
local PartPool = {}
PartPool.__index = PartPool

function PartPool.new(name, parent, size, factory)
	local self = setmetatable({}, PartPool)

	self.Folder = Instance.new("Folder")
	self.Folder.Name = name
	self.Folder.Parent = parent

	self._size = size
	self._free = table.create(size)
	for index = 1, size do
		local part = factory()
		part.Parent = self.Folder
		self._free[index] = part
	end
	self._freeCount = size

	return self
end

function PartPool:Acquire()
	if self._freeCount == 0 then
		return nil
	end
	local part = self._free[self._freeCount]
	self._free[self._freeCount] = nil
	self._freeCount -= 1
	return part
end

function PartPool:Release(part)
	self._freeCount += 1
	self._free[self._freeCount] = part
end

function PartPool:GetFreeCount()
	return self._freeCount
end

function PartPool:GetSize()
	return self._size
end

function PartPool:GetActiveCount()
	return self._size - self._freeCount
end

function PartPool:Destroy()
	self.Folder:Destroy()
	table.clear(self._free)
	self._freeCount = 0
end

return PartPool
