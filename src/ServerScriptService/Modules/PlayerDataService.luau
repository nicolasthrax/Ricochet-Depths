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
		_stats = { loads = 0, loadFailures = 0, staleLoads = 0, saves = 0, saveFailures = 0, retries = 0 },
		_loadGeneration = 0,
	}, PlayerDataService)
end

-- Returned by Load when its result arrived after the player left or a newer load took over.
PlayerDataService.STALE_LOAD = "stale load"

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

-- stillWanted, if given, is checked before every attempt: a load whose player has gone should
-- stop spending request budget rather than retry for a session that no longer exists.
function PlayerDataService:_retry(label, operation, stillWanted)
	local delay = PlayerDataConfig.RetryBaseDelay
	local lastError

	for attempt = 1, PlayerDataConfig.MaxRetries do
		if stillWanted and not stillWanted() then
			return false, PlayerDataService.STALE_LOAD
		end
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

-- Sessions are keyed by account, not by Player object. Roblox hands a rejoining player a new
-- Player object; keying by that object allowed two sessions for one DataStore key, which is how a
-- rejoin could read a profile from before the old session's save had landed.
local function accountOf(player)
	return player.UserId
end

-- The session this Player object currently owns, or nil. When a rejoin takes a session over, the
-- departed player's handle stops resolving to it, so a late call through it changes nothing.
function PlayerDataService:_sessionFor(player)
	if player == nil then
		return nil
	end
	local session = self._sessions[accountOf(player)]
	if session and session.player == player then
		return session
	end
	return nil
end

function PlayerDataService:GetSession(player)
	return self:_sessionFor(player)
end

-- Every mutation bumps a session's revision, and each save records the revision it wrote. A
-- change landing while a write is in flight is therefore still ahead of it afterwards: pending,
-- never silently cleared. This replaces a boolean dirty flag, which the completing save reset
-- to false even when a newer change had arrived during its yield.
local function markChanged(session)
	session.revision += 1
end

function PlayerDataService:IsDirty(player)
	local session = self:_sessionFor(player)
	return session ~= nil and session.revision > session.savedRevision
end

function PlayerDataService:IsLoaded(player)
	local session = self:_sessionFor(player)
	return session ~= nil and session.loaded and not session.failed
end

function PlayerDataService:Load(player)
	local account = accountOf(player)
	local existing = self._sessions[account]

	if existing and existing.loaded then
		if existing.player ~= player then
			-- A rejoin while the old session is still live, usually because its leave-save is
			-- still in flight. That session is newer than anything in the store, so the rejoin
			-- takes it over instead of reading a profile that may predate the save.
			existing.player = player
		end
		return existing.profile
	end

	-- Every load starts a new generation. Anything still in flight for this account is
	-- superseded, and will find its token no longer current when it returns.
	self._loadGeneration += 1
	local token = self._loadGeneration
	local session = {
		player = player,
		account = account,
		storeKey = keyFor(player),
		token = token,
		loaded = false,
		failed = false,
		profile = nil,
		revision = 0, -- bumped by every change
		savedRevision = 0, -- the highest revision known to be in the store
		saving = false, -- true while this session's one permitted write chain is running
		lastSave = 0,
		lastAutosaveAt = 0,
	}
	self._sessions[account] = session

	local function stillCurrent()
		local current = self._sessions[account]
		return current ~= nil and current.token == token and current.player == player
	end

	local ok, result = self:_retry("load", function()
		return self._store:UpdateAsync(session.storeKey, function(stored)
			return PlayerDataService.Normalise(stored)
		end)
	end, stillCurrent)

	if not stillCurrent() then
		-- The player left, or rejoined and a newer load took over, while this one was in the
		-- network layer. The result belongs to nobody: drop it rather than revive an orphaned
		-- session or overwrite the one that replaced it.
		self._stats.staleLoads += 1
		return nil, PlayerDataService.STALE_LOAD
	end

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
	local session = self:_sessionFor(player)
	if not session or not session.loaded or session.failed then
		return nil, "profile not loaded"
	end
	mutator(session.profile)
	markChanged(session)
	return session.profile
end

-- One UpdateAsync attempt sequence for the session's current state.
function PlayerDataService:_writeOnce(session, now)
	local profile = session.profile
	local writtenRevision = session.revision

	local ok, result = self:_retry("save", function()
		return self._store:UpdateAsync(session.storeKey, function(stored)
			-- Record exactly the revision this transform read. UpdateAsync may run it more than
			-- once, and only the run that commits is the one that counts.
			writtenRevision = session.revision

			local merged = PlayerDataService.Normalise(stored)
			-- Last write wins per field, but the run ledger is unioned so a concurrent write
			-- on another server can never resurrect an already-paid run.
			for runKey, value in profile.GrantedRuns do
				merged.GrantedRuns[runKey] = value
			end
			merged.Currency = profile.Currency
			merged.Unlocks = profile.Unlocks
			merged.Flags = profile.Flags
			merged.Settings = profile.Settings
			merged.Stats = profile.Stats
			merged.LastSaved = now or 0
			return merged
		end)
	end)

	if not ok then
		self._stats.saveFailures += 1
		return false, result
	end

	-- Take back only what the store owns: run keys recorded by other servers. The live profile
	-- is never replaced wholesale, because anything changed during the write is newer than what
	-- the store now holds, and replacing it would roll that change back.
	for runKey, value in result.GrantedRuns do
		if profile.GrantedRuns[runKey] == nil then
			profile.GrantedRuns[runKey] = value
		end
	end

	session.savedRevision = math.max(session.savedRevision, writtenRevision)
	session.lastSave = now or 0
	self._stats.saves += 1
	return true
end

-- Writes until the store has caught up with every change, including ones that arrived while
-- an earlier write in the chain was in flight. Capped, so a session changing continuously
-- cannot hold a write open forever; anything left over stays pending for the next save.
function PlayerDataService:_saveChain(session, now)
	session.saving = true
	local completed, ok, err = pcall(function()
		local chainOk, chainErr = true, nil
		for _ = 1, PlayerDataConfig.MaxChainedWrites do
			if session.revision <= session.savedRevision then
				break
			end
			chainOk, chainErr = self:_writeOnce(session, now)
			if not chainOk then
				break
			end
		end
		return chainOk, chainErr
	end)
	-- Always released, even on an unexpected error, or every later save of this player would
	-- wait on it forever.
	session.saving = false
	if not completed then
		return false, ok
	end
	return ok, err
end

-- At most one write per session is ever in flight. A request that arrives while one is running
-- waits for it. That chain writes again for anything changed in the meantime, so for a later
-- request waiting is usually all there is to do; it writes itself only if something is still
-- pending, for instance because the chain it waited on failed.
function PlayerDataService:Save(player, now)
	local session = self:_sessionFor(player)
	if not session or not session.loaded or session.failed then
		return false, "profile not loaded"
	end
	return self:_saveSession(session, now)
end

function PlayerDataService:_saveSession(session, now)
	while session.saving do
		task.wait()
	end
	if session.revision <= session.savedRevision then
		return true
	end
	return self:_saveChain(session, now)
end

-- Idempotent payout. A run key is only ever credited once per profile, whatever replays,
-- reconnects or duplicate completion events occur.
function PlayerDataService:GrantReward(player, runKey, amount)
	if type(amount) ~= "number" or amount ~= amount or amount <= 0 then
		return 0, "invalid amount"
	end
	local session = self:_sessionFor(player)
	if not session or not session.loaded or session.failed then
		return 0, "profile not loaded"
	end
	if session.profile.GrantedRuns[runKey] then
		return 0, "already granted"
	end

	local profile = session.profile
	profile.GrantedRuns[runKey] = math.floor(amount)
	profile.Currency.Salvage += math.floor(amount)
	markChanged(session)

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

-- Settings arrive from the client, so they are sanitised against the spec before storage.
function PlayerDataService:ApplySettings(player, incoming)
	local session = self:_sessionFor(player)
	if not session or not session.loaded or session.failed then
		return nil, "profile not loaded"
	end

	local sanitised = PlayerDataConfig.SanitiseSettings(incoming, session.profile.Settings)
	session.profile.Settings = sanitised
	markChanged(session)
	return sanitised
end

function PlayerDataService:GetPublicProfile(player)
	local session = self:_sessionFor(player)
	if not session or not session.profile then
		return nil
	end
	local profile = session.profile
	return {
		Salvage = profile.Currency.Salvage,
		Settings = table.clone(profile.Settings),
		Flags = table.clone(profile.Flags),
		Stats = table.clone(profile.Stats),
		ReadOnly = session.failed == true,
	}
end

function PlayerDataService:SetFlag(player, name, value)
	return self:Update(player, function(profile)
		profile.Flags[name] = value
	end)
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
		-- Finishing a run, win or lose, counts as having been onboarded.
		profile.Flags.OnboardingSeen = true
	end)
end

-- Starts a save without blocking the caller. The run loop calls this from inside Heartbeat,
-- where a yield would let the next frame's Step run while this one is suspended part-way
-- through its work. A failed save leaves the session dirty, so leave, autosave or shutdown
-- still get another chance at it.
function PlayerDataService:SaveInBackground(player, now)
	if not self:IsLoaded(player) then
		return false
	end
	task.spawn(function()
		self:Save(player, now)
	end)
	return true
end

function PlayerDataService:Release(player, now)
	local session = self:_sessionFor(player)
	if not session then
		-- Nothing live belongs to this handle: never loaded, already released, or taken over by
		-- a rejoin. Leaving must not touch a session someone else now owns.
		return false, "profile not loaded"
	end

	if not session.loaded then
		-- Still loading, or read-only. Removing it is what tells an in-flight load it is stale.
		self._sessions[session.account] = nil
		return false, "profile not loaded"
	end

	local ok, err = self:_saveSession(session, now)
	-- A rejoin may have taken the session over while that save was in flight. If so, it stays.
	if self._sessions[session.account] == session and session.player == player then
		self._sessions[session.account] = nil
	end
	return ok, err
end

function PlayerDataService:SaveAll(now)
	local failures = {}
	-- A snapshot: saves yield, and a player leaving in the meantime removes their session.
	local sessions = {}
	for _, session in self._sessions do
		table.insert(sessions, session)
	end
	for _, session in sessions do
		if session.loaded and not session.failed then
			local ok, err = self:_saveSession(session, now)
			if not ok then
				table.insert(failures, { player = session.player, error = err })
			end
		end
	end
	return failures
end

-- Called every frame from Heartbeat. Saves start in the background and are never waited on
-- here: a save yields, and doing it inline would let the next frame begin a second save of the
-- same session while the first is still in flight. A session already saving is skipped.
function PlayerDataService:StepAutosave(now)
	local started = 0
	for _, session in self._sessions do
		if
			session.loaded
			and not session.failed
			and not session.saving
			and session.revision > session.savedRevision
			and now - session.lastAutosaveAt >= PlayerDataConfig.AutosaveInterval
		then
			session.lastAutosaveAt = now
			self:SaveInBackground(session.player, now)
			started += 1
		end
	end
	return started
end

function PlayerDataService:GetStats()
	return table.clone(self._stats)
end

return PlayerDataService
