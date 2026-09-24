-- Global leaderboards on the lobby wall: top levels, most enemies defeated, most extractions.
-- Each is an OrderedDataStore. Players' values are remembered as they change and written in a
-- batch now and then; the top ten are read back on a slower beat and printed on the boards.
-- Everything that touches the store is wrapped, so an outage (or Studio without API access)
-- only leaves the boards saying they are offline.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ProgressionConfig = require(ReplicatedStorage:WaitForChild("ProgressionConfig"))
local Signage = require(script.Parent.Signage)

local LeaderboardService = {}
LeaderboardService.__index = LeaderboardService

LeaderboardService.Boards = {
	{ Id = "Level", StoreName = "LB_Xp_v1", Format = function(value)
		return "Lv " .. (ProgressionConfig.LevelFor(value))
	end },
	{ Id = "Kills", StoreName = "LB_Kills_v1", Format = function(value)
		return tostring(value)
	end },
	{ Id = "Extractions", StoreName = "LB_Extractions_v1", Format = function(value)
		return tostring(value)
	end },
}

LeaderboardService.FlushInterval = 90
LeaderboardService.RefreshInterval = 120
LeaderboardService.Rows = 10
LeaderboardService.OfflineText = "Leaderboards go live\nonce the game is published"

-- options.getStore(storeName) -> OrderedDataStore (may error), options.boards: id -> board part,
-- options.getName(userId) -> display name (may yield or error), options.spawn(fn) runs work
-- off the caller's thread (task.spawn by default).
function LeaderboardService.new(options)
	local self = setmetatable({
		_getStore = options.getStore,
		_boards = options.boards or {},
		_getName = options.getName,
		_spawn = options.spawn or task.spawn,
		_stores = {},
		_pending = {}, -- boardId -> userId -> value, waiting to be written
		_names = {},
		_nextFlush = 0,
		_nextRefresh = 0,
		_busy = false,
	}, LeaderboardService)
	for _, spec in LeaderboardService.Boards do
		self._pending[spec.Id] = {}
	end
	return self
end

function LeaderboardService:_store(spec)
	local store = self._stores[spec.Id]
	if store == nil then
		local ok, result = pcall(self._getStore, spec.StoreName)
		store = ok and result or false
		self._stores[spec.Id] = store
	end
	return store or nil
end

-- Remembers a player's latest values: { Level = xp, Kills = n, Extractions = n }.
function LeaderboardService:Submit(player, values)
	if type(values) ~= "table" then
		return
	end
	self._names[player.UserId] = player.DisplayName or player.Name
	for id, value in values do
		local pending = self._pending[id]
		if pending and type(value) == "number" and value == value and value > 0 then
			pending[player.UserId] = math.floor(value)
		end
	end
end

-- Writes every remembered value. Yields.
function LeaderboardService:Flush()
	for _, spec in LeaderboardService.Boards do
		local store = self:_store(spec)
		local pending = self._pending[spec.Id]
		self._pending[spec.Id] = {}
		if store then
			for userId, value in pending do
				pcall(function()
					store:SetAsync(tostring(userId), value)
				end)
			end
		end
	end
end

function LeaderboardService:_nameFor(userId)
	local cached = self._names[userId]
	if cached then
		return cached
	end
	local ok, name = pcall(self._getName, userId)
	name = ok and type(name) == "string" and name or ("Player " .. tostring(userId))
	self._names[userId] = name
	return name
end

-- Reads each board's top rows and prints them. Yields.
function LeaderboardService:Refresh()
	for _, spec in LeaderboardService.Boards do
		local board = self._boards[spec.Id]
		if board then
			local store = self:_store(spec)
			local ok, rows = false, nil
			if store then
				ok, rows = pcall(function()
					local pages = store:GetSortedAsync(false, LeaderboardService.Rows)
					return pages:GetCurrentPage()
				end)
			end
			if ok and type(rows) == "table" then
				Signage.SetText(board, self:_render(spec, rows))
			else
				Signage.SetText(board, LeaderboardService.OfflineText)
			end
		end
	end
end

function LeaderboardService:_render(spec, rows)
	if #rows == 0 then
		return "Be the first on the board!"
	end
	local lines = {}
	for rank, row in rows do
		local userId = tonumber(row.key) or 0
		table.insert(lines, string.format("%d.  %s   %s", rank, self:_nameFor(userId), spec.Format(row.value)))
	end
	return table.concat(lines, "\n")
end

-- Called every frame; starts a flush or refresh when one is due, never two at once.
function LeaderboardService:Step(now)
	if self._busy then
		return
	end
	local flush, refresh = now >= self._nextFlush, now >= self._nextRefresh
	if not flush and not refresh then
		return
	end
	if flush then
		self._nextFlush = now + LeaderboardService.FlushInterval
	end
	if refresh then
		self._nextRefresh = now + LeaderboardService.RefreshInterval
	end
	self._busy = true
	self._spawn(function()
		if flush then
			self:Flush()
		end
		if refresh then
			self:Refresh()
		end
		self._busy = false
	end)
end

return LeaderboardService
