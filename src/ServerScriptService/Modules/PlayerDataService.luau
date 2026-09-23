-- Server-only persistence. Writes go through UpdateAsync with retries and backoff; a profile
-- that fails to load enters a controlled read-only session rather than silently using defaults
-- that would later overwrite real data.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local PlayerDataConfig = require(ReplicatedStorage:WaitForChild("PlayerDataConfig"))

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

-- store must expose UpdateAsync(key, transform) and may yield, exactly like a Roblox DataStore.
-- options.wallClock returns the time grants are stamped with. It must mean the same thing on
-- every server, which is why it is wall-clock time (os.time) and never os.clock, which is
-- per-process and unrelated across servers.
function PlayerDataService.new(store, options)
	options = options or {}
	return setmetatable({
		_store = store,
		_sessions = {},
		_options = options,
		_wallClock = options.wallClock or os.time,
		_stats = { loads = 0, loadFailures = 0, staleLoads = 0, saves = 0, saveFailures = 0, retries = 0 },
		_loadGeneration = 0,
	}, PlayerDataService)
end

-- Returned by Load when its result arrived after the player left or a newer load took over.
PlayerDataService.STALE_LOAD = "stale load"

-- Fields the store owns. A save never copies these from memory: currency and the run ledger
-- change only through grants applied inside the transform, and the rest are the save's own
-- bookkeeping. Every other profile field is copied, so a field added to the schema is saved
-- without anyone having to remember to add it here.
PlayerDataService.STORE_OWNED_FIELDS = {
	SchemaVersion = true,
	LastSaved = true,
	Currency = true,
	GrantedRuns = true,
}

local PROFILE_FIELDS = {}
for field in PlayerDataConfig.DefaultProfile() do
	table.insert(PROFILE_FIELDS, field)
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

-- A ledger entry's grant time. Tolerates a bare number, the pre-v4 format, as time zero.
local function entryAt(entry)
	return type(entry) == "table" and (entry.At or 0) or 0
end

local function countKeys(map)
	local count = 0
	for _ in map do
		count += 1
	end
	return count
end

-- Keeps the newest RunLedgerSize runs, dropping strictly oldest-first by grant time. Ties are
-- broken by key only so the order is deterministic. The old policy sorted keys alphabetically;
-- run keys begin with a random server id, so it could drop a run the moment it was paid and let
-- that run be paid again.
local function pruneLedger(ledger)
	local excess = countKeys(ledger) - PlayerDataConfig.RunLedgerSize
	if excess <= 0 then
		return
	end
	local entries = {}
	for runKey, entry in ledger do
		table.insert(entries, { key = runKey, at = entryAt(entry) })
	end
	table.sort(entries, function(a, b)
		if a.at ~= b.at then
			return a.at < b.at
		end
		return a.key < b.key
	end)
	for index = 1, excess do
		ledger[entries[index].key] = nil
	end
end

-- Value snapshots for Update's guard on store-owned money fields.
local function snapshotCurrency(currency)
	return table.clone(currency)
end

local function sameCurrency(before, currency)
	for key, value in before do
		if currency[key] ~= value then
			return false
		end
	end
	return countKeys(before) == countKeys(currency)
end

local function snapshotLedger(ledger)
	local copy = {}
	for runKey, entry in ledger do
		copy[runKey] = { Amount = type(entry) == "table" and entry.Amount or entry, At = entryAt(entry) }
	end
	return copy
end

local function sameLedger(before, ledger)
	if countKeys(before) ~= countKeys(ledger) then
		return false
	end
	for runKey, entry in before do
		local current = ledger[runKey]
		local amount = type(current) == "table" and current.Amount or current
		if current == nil or amount ~= entry.Amount or entryAt(current) ~= entry.At then
			return false
		end
	end
	return true
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
		-- Grants credited here but not yet written, keyed by run. Currency is written as these
		-- deltas, never as a balance, so two servers writing one account compose.
		pendingGrants = {},
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
-- Currency and the run ledger are refused here: they are written only as grants, so a direct
-- edit would never reach the store. Failing loudly beats a spend that silently evaporates.
function PlayerDataService:Update(player, mutator)
	local session = self:_sessionFor(player)
	if not session or not session.loaded or session.failed then
		return nil, "profile not loaded"
	end

	local profile = session.profile
	-- Snapshot by value: a mutator edits these tables in place, so keeping the table references
	-- alone would neither detect nor undo the change.
	local currencyTable, ledgerTable = profile.Currency, profile.GrantedRuns
	local currencyBefore = snapshotCurrency(currencyTable)
	local ledgerBefore = snapshotLedger(ledgerTable)

	mutator(profile)

	if
		profile.Currency ~= currencyTable
		or profile.GrantedRuns ~= ledgerTable
		or not sameCurrency(currencyBefore, currencyTable)
		or not sameLedger(ledgerBefore, ledgerTable)
	then
		-- Put everything back exactly as it was, into the original tables.
		profile.Currency, profile.GrantedRuns = currencyTable, ledgerTable
		table.clear(currencyTable)
		for key, value in currencyBefore do
			currencyTable[key] = value
		end
		table.clear(ledgerTable)
		for runKey, entry in ledgerBefore do
			ledgerTable[runKey] = { Amount = entry.Amount, At = entry.At }
		end
		error("currency and the run ledger change only through GrantReward, not Update", 2)
	end

	markChanged(session)
	return profile
end

-- One UpdateAsync attempt sequence for the session's current state.
function PlayerDataService:_writeOnce(session, now)
	local profile = session.profile
	local writtenRevision = session.revision
	local applied = {}

	local ok, result = self:_retry("save", function()
		return self._store:UpdateAsync(session.storeKey, function(stored)
			-- Record exactly what this transform read. UpdateAsync may run it more than once, and
			-- only the run that commits counts, so these are reset on every run.
			writtenRevision = session.revision
			applied = {}

			local merged = PlayerDataService.Normalise(stored)

			-- Currency is never written as a balance. Each pending grant is added to whatever the
			-- store holds right now, so a grant committed by another server in the meantime is
			-- kept rather than overwritten. A run already in the stored ledger has been paid,
			-- here or elsewhere, and is not added again.
			for runKey, grant in session.pendingGrants do
				if merged.GrantedRuns[runKey] == nil then
					merged.Currency.Salvage = (merged.Currency.Salvage or 0) + grant.Amount
					merged.GrantedRuns[runKey] = { Amount = grant.Amount, At = grant.At }
				end
				applied[runKey] = grant -- applied now, or found already paid: acknowledged either way
			end
			-- The stored copy is capped too. Nothing re-adds pruned runs from memory any more,
			-- which is what used to let this grow without limit across servers.
			pruneLedger(merged.GrantedRuns)

			for _, field in PROFILE_FIELDS do
				if not PlayerDataService.STORE_OWNED_FIELDS[field] then
					merged[field] = profile[field]
				end
			end
			merged.LastSaved = now or 0
			return merged
		end)
	end)

	if not ok then
		self._stats.saveFailures += 1
		return false, result
	end

	-- Acknowledge exactly the grants the committed write carried. Any granted during the write
	-- are still pending, and the revision counter guarantees another write follows for them.
	for runKey, grant in applied do
		if session.pendingGrants[runKey] == grant then
			session.pendingGrants[runKey] = nil
		end
	end

	-- Currency is store-owned now: what the store holds, plus whatever is still waiting to go.
	-- This is also how this server learns of grants other servers committed.
	local stillPending = 0
	for _, grant in session.pendingGrants do
		stillPending += grant.Amount
	end
	profile.Currency.Salvage = (result.Currency.Salvage or 0) + stillPending

	-- Take back the runs the store knows about, then keep memory within the same cap. The rest
	-- of the live profile is left alone: anything changed during the write is newer than what
	-- was written, and replacing it would roll that change back.
	for runKey, entry in result.GrantedRuns do
		if profile.GrantedRuns[runKey] == nil then
			profile.GrantedRuns[runKey] = entry
		end
	end
	pruneLedger(profile.GrantedRuns)

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
	-- Pending grants are checked too: pruning may drop a run from the in-memory ledger before it
	-- has been written, and it must still count as paid.
	if session.profile.GrantedRuns[runKey] or session.pendingGrants[runKey] then
		return 0, "already granted"
	end

	local grant = { Amount = math.floor(amount), At = self._wallClock() }
	local profile = session.profile
	profile.GrantedRuns[runKey] = { Amount = grant.Amount, At = grant.At }
	session.pendingGrants[runKey] = grant
	-- Shown to the player straight away; reconciled against the store on the next save.
	profile.Currency.Salvage += grant.Amount
	markChanged(session)

	pruneLedger(profile.GrantedRuns)
	return grant.Amount
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
