-- Server-only persistence. Writes go through UpdateAsync with retries and backoff; a profile
-- that fails to load enters a controlled read-only session rather than silently using defaults
-- that would later overwrite real data.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataConfig = require(ReplicatedStorage:WaitForChild("PlayerDataConfig"))

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

-- store must expose UpdateAsync(key, transform) and may yield, exactly like a Roblox DataStore.
function PlayerDataService.new(store, options)
	return setmetatable({
		_store = store,
		_sessions = {},
		_options = options or {},
		_stats = { loads = 0, loadFailures = 0, saves = 0, saveFailures = 0, retries = 0 },
	}, PlayerDataService)
end

local function keyFor(player)
	return PlayerDataConfig.KeyPrefix .. tostring(player.UserId)
end

local function deepDefault(value, default)
	if type(default) ~= "table" then
		return value ~= nil and value or default
	end
	local out = type(value) == "table" and value or {}
	for key, defaultValue in default do
		out[key] = deepDefault(out[key], defaultValue)
	end
	return out
end

-- Fills in anything missing and walks the profile forward to the current schema version.
function PlayerDataService.Normalise(stored)
	local profile = deepDefault(stored, PlayerDataConfig.DefaultProfile())
	local version = tonumber(profile.SchemaVersion) or 1

	while version < PlayerDataConfig.SchemaVersion do
		local migrate = PlayerDataConfig.Migrations[version]
		if migrate then
			profile = migrate(profile) or profile
		end
		version += 1
	end

	profile.SchemaVersion = PlayerDataConfig.SchemaVersion
	return profile
end

function PlayerDataService:_retry(label, operation)
	local delay = PlayerDataConfig.RetryBaseDelay
	local lastError

	for attempt = 1, PlayerDataConfig.MaxRetries do
		local ok, result = pcall(operation)
		if ok then
			return true, result
		end
		lastError = result
		if attempt < PlayerDataConfig.MaxRetries then
			self._stats.retries += 1
			-- Exponential backoff, capped, so a struggling datastore is not hammered.
			task.wait(math.min(delay, PlayerDataConfig.RetryMaxDelay))
			delay *= 2
		end
	end

	return false, string.format("%s failed after %d attempts: %s", label, PlayerDataConfig.MaxRetries, tostring(lastError))
end

function PlayerDataService:GetSession(player)
	return self._sessions[player]
end

function PlayerDataService:IsLoaded(player)
	local session = self._sessions[player]
	return session ~= nil and session.loaded and not session.failed
end

function PlayerDataService:Load(player)
	local existing = self._sessions[player]
	if existing and existing.loaded then
		return existing.profile
	end

	local session = { loaded = false, failed = false, dirty = false, lastSave = 0, profile = nil }
	self._sessions[player] = session

	local ok, result = self:_retry("load", function()
		return self._store:UpdateAsync(keyFor(player), function(stored)
			return PlayerDataService.Normalise(stored)
		end)
	end)

	if not ok then
		-- Read-only session: the player can still play, but nothing is written and no reward is
		-- persisted, so a transient outage can never clobber or duplicate real data.
		session.failed = true
		session.error = result
		session.profile = PlayerDataConfig.DefaultProfile()
		self._stats.loadFailures += 1
		return session.profile, result
	end

	session.profile = result
	session.loaded = true
	self._stats.loads += 1
	return session.profile
end

-- mutator receives the profile and may change it in place; the change is then persisted.
function PlayerDataService:Update(player, mutator)
	local session = self._sessions[player]
	if not session or not session.loaded or session.failed then
		return nil, "profile not loaded"
	end
	mutator(session.profile)
	session.dirty = true
	return session.profile
end

function PlayerDataService:Save(player, now)
	local session = self._sessions[player]
	if not session or not session.loaded or session.failed then
		return false, "profile not loaded"
	end
	if not session.dirty then
		return true
	end

	local snapshot = session.profile
	local ok, result = self:_retry("save", function()
		return self._store:UpdateAsync(keyFor(player), function(stored)
			local merged = PlayerDataService.Normalise(stored)
			-- Last write wins per field, but the run ledger is unioned so a concurrent write
			-- on another server can never resurrect an already-paid run.
			for runKey, value in snapshot.GrantedRuns do
				merged.GrantedRuns[runKey] = value
			end
			merged.Currency = snapshot.Currency
			merged.Unlocks = snapshot.Unlocks
			merged.Flags = snapshot.Flags
			merged.Stats = snapshot.Stats
			merged.LastSaved = now or 0
			return merged
		end)
	end)

	if not ok then
		self._stats.saveFailures += 1
		return false, result
	end

	session.profile = result
	session.dirty = false
	session.lastSave = now or 0
	self._stats.saves += 1
	return true
end

-- Idempotent payout. A run key is only ever credited once per profile, whatever replays,
-- reconnects or duplicate completion events occur.
function PlayerDataService:GrantReward(player, runKey, amount)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0, "invalid amount"
	end
	local session = self._sessions[player]
	if not session or not session.loaded or session.failed then
		return 0, "profile not loaded"
	end
	if session.profile.GrantedRuns[runKey] then
		return 0, "already granted"
	end

	local profile = session.profile
	profile.GrantedRuns[runKey] = math.floor(amount)
	profile.Currency.Salvage += math.floor(amount)
	session.dirty = true

	self:_trimLedger(profile)
	return math.floor(amount)
end

-- Keeps the ledger bounded so a long-lived profile cannot grow without limit.
function PlayerDataService:_trimLedger(profile)
	local keys = {}
	for runKey in profile.GrantedRuns do
		table.insert(keys, runKey)
	end
	if #keys <= PlayerDataConfig.RunLedgerSize then
		return
	end
	table.sort(keys)
	for index = 1, #keys - PlayerDataConfig.RunLedgerSize do
		profile.GrantedRuns[keys[index]] = nil
	end
end

function PlayerDataService:RecordRunEnd(player, summary)
	return self:Update(player, function(profile)
		profile.Stats.RunsStarted += 1
		if summary.Outcome == "Extracted" then
			profile.Stats.RunsExtracted += 1
		end
		profile.Stats.EnemiesDefeated += summary.EnemiesDefeated
		profile.Stats.BestChain = math.max(profile.Stats.BestChain, summary.BestChain)
		profile.Stats.BestRoomsCleared = math.max(profile.Stats.BestRoomsCleared, summary.RoomsCleared)
	end)
end

function PlayerDataService:Release(player, now)
	local ok, err = self:Save(player, now)
	self._sessions[player] = nil
	return ok, err
end

function PlayerDataService:SaveAll(now)
	local failures = {}
	for player in self._sessions do
		local ok, err = self:Save(player, now)
		if not ok and err ~= "profile not loaded" then
			table.insert(failures, { player = player, error = err })
		end
	end
	return failures
end

function PlayerDataService:StepAutosave(now)
	local saved = 0
	for player, session in self._sessions do
		if session.loaded and session.dirty and now - session.lastSave >= PlayerDataConfig.AutosaveInterval then
			if self:Save(player, now) then
				saved += 1
			end
		end
	end
	return saved
end

function PlayerDataService:GetStats()
	return table.clone(self._stats)
end

return PlayerDataService
