--!strict
-- The one network interface between server and clients. Every remote is declared here once,
-- with its direction, its payload type and (client -> server) its validator and rate limit.
-- No other module creates or looks up a RemoteEvent or RemoteFunction by name.
--
-- Rules:
--   * Client -> server payloads are untrusted. Each is rate limited per player, then rebuilt by
--     its validator; the server handler only ever sees a clean, typed payload. Rejected packets
--     are dropped silently (see setRejectionHandler for telemetry).
--   * Each client -> server remote has exactly one server owner (one `connect`), so exactly one
--     service is responsible for each input.
--   * Server -> client remotes carry display state only. The server is the authority for damage,
--     haul, XP, health and picks: DamageReport is server -> client, never a client claim.
--   * No RemoteFunction is ever invoked on a client. The only RemoteFunction is a client ->
--     server read (FetchRunSnapshot) used to resync after a respawn or a late join.
--   * Positions are lane space (see GameConfig). Shot payloads carry plain numbers: clients draw
--     each shot as straight segments between the bounces the server reports (ShotsBounced), so
--     they never run collision themselves.
--
-- The server creates the remotes in ReplicatedStorage.NetworkRemotes the first time Network is
-- used on the server; call Network.mountServer() early in the server bootstrap so clients
-- never wait. Clients wait for each remote on first use.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Types = require(script.Parent.Source.Types)
local GameConfig = require(script.Parent.Source.GameConfig)
local ModifierDefinitions = require(script.Parent.Source.ModifierDefinitions)
local Guard = require(script.Parent.Source.Guard)

type ModifierId = Types.ModifierId
type BaseModifierId = Types.BaseModifierId
type FusedModifierId = Types.FusedModifierId

-- Runtime-only folder, so no remote ever exists in the place file without a declaration here.
local CONTAINER_NAME = "NetworkRemotes"
local MAX_ID = 2 ^ 31 - 1

---------------------------------------------------------------------------------------------
-- Public types: wrappers
---------------------------------------------------------------------------------------------

export type RateLimit = {
	perSecond: number, -- sustained packets per second
	burst: number, -- packets allowed back to back
}

export type RejectReason = "RateLimited" | "InvalidPayload"

-- Client -> server event. Clients call :fire(); one server service calls :connect().
export type ClientToServer<T> = {
	name: string,
	fire: (self: ClientToServer<T>, payload: T) -> (),
	connect: (self: ClientToServer<T>, handler: (player: Player, payload: T) -> ()) -> RBXScriptConnection,
}

-- Server -> client event. The server fires to one player, a party, or everyone; clients listen.
export type ServerToClient<T> = {
	name: string,
	fireTo: (self: ServerToClient<T>, player: Player, payload: T) -> (),
	fireToList: (self: ServerToClient<T>, players: { Player }, payload: T) -> (),
	fireAll: (self: ServerToClient<T>, payload: T) -> (),
	connect: (self: ServerToClient<T>, handler: (payload: T) -> ()) -> RBXScriptConnection,
}

-- Client -> server request with a reply (RemoteFunction). :invoke() returns nil on any failure.
export type ClientRequest<Req, Res> = {
	name: string,
	invoke: (self: ClientRequest<Req, Res>, request: Req) -> Res?,
	setHandler: (self: ClientRequest<Req, Res>, handler: (player: Player, request: Req) -> Res?) -> (),
}

---------------------------------------------------------------------------------------------
-- Public types: payloads (client -> server)
---------------------------------------------------------------------------------------------

export type NoPayload = {}

export type FireProjectilePayload = {
	originX: number, -- rail position the client fired from; honoured only near the server's own
	direction: Vector2, -- lane space; normalised by the validator
	sequence: number, -- client shot counter, echoed in ShotsSpawned for prediction matching
}

export type RailInputPayload = {
	x: number, -- desired rail position in lane space (clamped and speed-checked by the server)
	sequence: number, -- unreliable: older sequences than the last accepted one are ignored
}

export type SelectUpgradePayload = {
	offerId: number,
	modifierId: BaseModifierId,
}

export type RerollUpgradePayload = {
	offerId: number,
}

export type ContextActionPayload = {
	verb: Types.ContextVerb, -- must match the verb the server last sent in ContextVerbChanged
}

export type ExtractDecisionPayload = {
	choice: Types.ExtractChoice,
}

export type SetPausedPayload = {
	paused: boolean, -- honoured in solo runs only
}

export type ReportFunnelStepPayload = {
	step: Types.ClientFunnelStep,
}

---------------------------------------------------------------------------------------------
-- Public types: payloads (server -> client)
---------------------------------------------------------------------------------------------

-- The run's phase and framing. Sent on every change; small.
export type RunState = {
	runId: number,
	phase: Types.RunPhase,
	depth: number,
	roomIndex: number, -- 1-based
	roomCount: number,
	isFtue: boolean, -- the scripted first descent; the client staggers HUD disclosure from it
	timeScale: number, -- 1 normally; GameConfig.Upgrades.coopWorldTimeScale during co-op picks
	paused: boolean,
	partyUserIds: { number },
	serverTime: number, -- workspace:GetServerTimeNow() when the state was taken
	laneOrigin: CFrame, -- this player's lane: rail centre on the floor, LookVector up the lane
}

export type ShotSnapshot = {
	shotId: number,
	parentShotId: number?, -- set for shards split off another shot
	ownerUserId: number,
	sequence: number, -- the owner's FireProjectile sequence (0 for shards)
	x: number, -- lane space
	y: number,
	dirX: number, -- unit
	dirY: number,
	speed: number,
	radius: number,
	tint: Types.ShotTint,
	at: number, -- server time at (x, y); a late client fast-forwards along the direction
}

export type ShotsSpawnedPayload = {
	shots: { ShotSnapshot },
}

-- A shot changed course: from (x, y) at server time `at` it travels along (dirX, dirY).
export type ShotBounce = {
	shotId: number,
	x: number,
	y: number,
	dirX: number,
	dirY: number,
	speed: number,
	at: number,
}

export type ShotsBouncedPayload = {
	bounces: { ShotBounce },
}

export type ShotEnd = {
	shotId: number,
	x: number,
	y: number,
}

export type ShotsEndedPayload = {
	ends: { ShotEnd },
}

export type DamageHit = {
	shotId: number?, -- nil for burn ticks
	targetId: number,
	amount: number,
	hpAfter: number, -- 0 means the target broke
	source: Types.DamageSource,
	x: number, -- lane space
	y: number,
}

export type DamageReportPayload = {
	hits: { DamageHit }, -- every hit of one simulation step, in order
}

export type TargetSnapshot = {
	targetId: number,
	kind: Types.TargetKind,
	column: number, -- 1-based, leftmost column the target covers
	row: number, -- 1 is the back wall row
	widthColumns: number,
	hp: number,
	maxHp: number,
}

export type TargetsSpawnedPayload = {
	targets: { TargetSnapshot },
}

export type TargetMove = {
	targetId: number,
	row: number,
}

export type TargetsAdvancedPayload = {
	pulse: number,
	moves: { TargetMove }, -- only targets that moved (chilled ones stay put)
	breached: { number }, -- target ids that crossed the danger line and were removed
}

export type AttackTelegraphPayload = {
	attackerId: number,
	column: number,
	widthColumns: number,
	windupSeconds: number,
	startsAt: number, -- server time
}

export type HealthChangedPayload = {
	userId: number,
	pips: number,
	maxPips: number,
	downed: boolean,
}

export type HaulChangedPayload = {
	haul: number,
	delta: number,
	fromTargetId: number?, -- gems fly from this target to the avatar
}

export type XpChangedPayload = {
	fraction: number, -- 0..1 towards the next pick; the HUD shows no numbers
	level: number,
}

export type UpgradeChoice = {
	modifierId: BaseModifierId,
	recommended: boolean,
	isNew: boolean, -- never seen by this player before
	fusesInto: FusedModifierId?, -- set when picking this would complete a fusion
}

export type UpgradeOfferedPayload = {
	offerId: number,
	level: number,
	choices: { UpgradeChoice },
	rerollsLeft: number,
	rerollVisible: boolean, -- false during the FTUE
	timeoutSeconds: number?, -- nil in solo; co-op auto-picks the recommended card
	inputLockSeconds: number,
}

export type UpgradeResolvedPayload = {
	offerId: number,
	modifierId: BaseModifierId,
	autoPicked: boolean,
}

export type LoadoutEntry = {
	id: ModifierId,
	stacks: number,
	fusionReady: boolean, -- gold pulse on the badge
}

export type FusionEvent = {
	first: BaseModifierId,
	second: BaseModifierId,
	result: FusedModifierId,
}

export type LoadoutChangedPayload = {
	userId: number, -- sent to the whole party so teammates' picks show as avatar dots
	modifiers: { LoadoutEntry },
	fusion: FusionEvent?, -- set when this change was a fusion (plays the 0.8s merge)
}

export type ContextVerbChangedPayload = {
	verb: Types.ContextVerb?, -- nil hides the context button
}

export type GoalPreview = {
	buildingId: string,
	progress: number, -- 0..1 of the build cost the haul would cover
}

export type ExtractOfferedPayload = {
	depth: number,
	haul: number,
	bankBonus: number, -- fraction added if the haul is banked now
	goal: GoalPreview?,
}

export type RunEndedPayload = {
	runId: number,
	outcome: Types.RunOutcome,
	depth: number,
	haulBanked: number,
	haulLost: number,
	bestCombo: number,
	fusions: number,
	discoveries: { ModifierId }, -- first-time finds, starred on the tally
	xpGained: number,
}

-- Everything a client needs to redraw a run from scratch (join, respawn, script restart).
export type RunSnapshot = {
	state: RunState,
	targets: { TargetSnapshot },
	health: HealthChangedPayload,
	haul: number,
	xp: XpChangedPayload,
	loadout: { LoadoutEntry },
}

---------------------------------------------------------------------------------------------
-- Internals
---------------------------------------------------------------------------------------------

type RemoteClass = "RemoteEvent" | "UnreliableRemoteEvent" | "RemoteFunction"

local isServer = RunService:IsServer()
local declared: { [string]: RemoteClass } = {}
local declaredOrder: { string } = {}
local container: Instance? = nil
local rejectionHandler: ((player: Player, remoteName: string, reason: RejectReason) -> ())? = nil

-- Per player, per remote token buckets. Cleared when the player leaves.
type Bucket = { tokens: number, stamp: number }
local buckets: { [Player]: { [string]: Bucket } } = {}

local function declare(name: string, class: RemoteClass)
	assert(declared[name] == nil, `remote {name} is declared twice`)
	assert(container == nil, `remote {name} was declared after the remotes were mounted`)
	declared[name] = class
	table.insert(declaredOrder, name)
end

-- Server: builds every declared remote, then parents the folder once so clients see it whole.
local function createContainer(): Instance
	local existing: Instance? = ReplicatedStorage:FindFirstChild(CONTAINER_NAME)
	local folder: Instance = if existing then existing else Instance.new("Folder")
	for _, name in declaredOrder do
		if not folder:FindFirstChild(name) then
			local class = declared[name]
			local remote: Instance = if class == "RemoteFunction"
				then Instance.new("RemoteFunction")
				elseif class == "UnreliableRemoteEvent" then Instance.new("UnreliableRemoteEvent")
				else Instance.new("RemoteEvent")
			remote.Name = name
			remote.Parent = folder
		end
	end
	folder.Name = CONTAINER_NAME
	folder.Parent = ReplicatedStorage
	Players.PlayerRemoving:Connect(function(player: Player)
		buckets[player] = nil
	end)
	return folder
end

local function mount(): Instance
	local existing = container
	if existing then
		return existing
	end
	local folder: Instance = if isServer then createContainer() else ReplicatedStorage:WaitForChild(CONTAINER_NAME)
	container = folder
	return folder
end

local function getRemote(name: string): Instance
	return mount():WaitForChild(name)
end

local function reject(player: Player, name: string, reason: RejectReason)
	local handler = rejectionHandler
	if handler then
		handler(player, name, reason)
	end
end

local function allow(player: Player, name: string, rate: RateLimit): boolean
	local now = os.clock()
	local perPlayer = buckets[player]
	if perPlayer == nil then
		perPlayer = {}
		buckets[player] = perPlayer
	end
	local bucket = perPlayer[name]
	if bucket == nil then
		bucket = { tokens = rate.burst, stamp = now }
		perPlayer[name] = bucket
	end
	bucket.tokens = math.min(rate.burst, bucket.tokens + (now - bucket.stamp) * rate.perSecond)
	bucket.stamp = now
	if bucket.tokens < 1 then
		return false
	end
	bucket.tokens -= 1
	return true
end

local function clientToServer<T>(
	name: string,
	options: { validate: (value: unknown) -> T?, rate: RateLimit, unreliable: boolean? }
): ClientToServer<T>
	local unreliable = options.unreliable == true
	declare(name, if unreliable then "UnreliableRemoteEvent" else "RemoteEvent")
	local owner: RBXScriptConnection? = nil

	local event: ClientToServer<T> = {
		name = name,
		fire = function(_self: ClientToServer<T>, payload: T)
			assert(not isServer, `{name} is client -> server; the server cannot fire it`)
			local remote = getRemote(name)
			if unreliable then
				(remote :: UnreliableRemoteEvent):FireServer(payload)
			else
				(remote :: RemoteEvent):FireServer(payload)
			end
		end,
		connect = function(_self: ClientToServer<T>, handler: (player: Player, payload: T) -> ()): RBXScriptConnection
			assert(isServer, `{name} is client -> server; only the server can listen`)
			assert(owner == nil or not owner.Connected, `{name} already has a server owner`)
			local remote = getRemote(name)
			local function receive(player: Player, raw: unknown)
				if not allow(player, name, options.rate) then
					reject(player, name, "RateLimited")
					return
				end
				local payload = options.validate(raw)
				if payload == nil then
					reject(player, name, "InvalidPayload")
					return
				end
				handler(player, payload)
			end
			local connection = if unreliable
				then (remote :: UnreliableRemoteEvent).OnServerEvent:Connect(receive)
				else (remote :: RemoteEvent).OnServerEvent:Connect(receive)
			owner = connection
			return connection
		end,
	}
	-- Frozen through `any`: the new solver would otherwise type the result read-only.
	table.freeze(event :: any)
	return event
end

local function serverToClient<T>(name: string): ServerToClient<T>
	declare(name, "RemoteEvent")

	local event: ServerToClient<T> = {
		name = name,
		fireTo = function(_self: ServerToClient<T>, player: Player, payload: T)
			assert(isServer, `{name} is server -> client; only the server can fire it`)
			local remote = getRemote(name) :: RemoteEvent
			remote:FireClient(player, payload)
		end,
		fireToList = function(_self: ServerToClient<T>, players: { Player }, payload: T)
			assert(isServer, `{name} is server -> client; only the server can fire it`)
			local remote = getRemote(name) :: RemoteEvent
			for _, player in players do
				remote:FireClient(player, payload)
			end
		end,
		fireAll = function(_self: ServerToClient<T>, payload: T)
			assert(isServer, `{name} is server -> client; only the server can fire it`)
			local remote = getRemote(name) :: RemoteEvent
			remote:FireAllClients(payload)
		end,
		connect = function(_self: ServerToClient<T>, handler: (payload: T) -> ()): RBXScriptConnection
			assert(not isServer, `{name} is server -> client; only clients can listen`)
			local remote = getRemote(name) :: RemoteEvent
			return remote.OnClientEvent:Connect(handler)
		end,
	}
	-- Frozen through `any`: the new solver would otherwise type the result read-only.
	table.freeze(event :: any)
	return event
end

local function clientRequest<Req, Res>(
	name: string,
	options: { validate: (value: unknown) -> Req?, rate: RateLimit }
): ClientRequest<Req, Res>
	declare(name, "RemoteFunction")

	local request: ClientRequest<Req, Res> = {
		name = name,
		invoke = function(_self: ClientRequest<Req, Res>, request: Req): Res?
			assert(not isServer, `{name} is a client request; the server cannot invoke it`)
			local remote = getRemote(name) :: RemoteFunction
			local ok, result = pcall(remote.InvokeServer, remote, request)
			return if ok then result :: Res? else nil
		end,
		setHandler = function(_self: ClientRequest<Req, Res>, handler: (player: Player, request: Req) -> Res?)
			assert(isServer, `{name} is a client request; only the server can answer it`)
			local remote = getRemote(name) :: RemoteFunction
			remote.OnServerInvoke = function(player: Player, raw: unknown): Res?
				if not allow(player, name, options.rate) then
					reject(player, name, "RateLimited")
					return nil
				end
				local request = options.validate(raw)
				if request == nil then
					reject(player, name, "InvalidPayload")
					return nil
				end
				return handler(player, request)
			end
		end,
	}
	-- Frozen through `any`: the new solver would otherwise type the result read-only.
	table.freeze(request :: any)
	return request
end

---------------------------------------------------------------------------------------------
-- Validators (client -> server)
---------------------------------------------------------------------------------------------

local CONTEXT_VERBS: { Types.ContextVerb } = { "Revive", "Fuse", "Extract" }
local EXTRACT_CHOICES: { Types.ExtractChoice } = { "Descend", "BankLoot" }
local CLIENT_FUNNEL_STEPS: { Types.ClientFunnelStep } = { "first_goal_seen", "tally_skip" }
local NO_PAYLOAD: NoPayload = {}
table.freeze(NO_PAYLOAD)

-- The fastest legal fire rate plus headroom for jitter. The shot service enforces the real
-- per-player cooldown; this only stops floods.
local FIRE_RATE: RateLimit = {
	perSecond = math.ceil(1 / GameConfig.Shot.minCooldownSeconds) + 2,
	burst = 4,
}

local function validateFireProjectile(value: unknown): FireProjectilePayload?
	local t = Guard.record(value)
	if t == nil then
		return nil
	end
	local originX = Guard.number(t.originX, GameConfig.Rail.minX, GameConfig.Rail.maxX)
	local direction = Guard.direction(t.direction)
	local sequence = Guard.integer(t.sequence, 0, MAX_ID)
	if originX == nil or direction == nil or sequence == nil then
		return nil
	end
	return { originX = originX, direction = direction, sequence = sequence }
end

local function validateRailInput(value: unknown): RailInputPayload?
	local t = Guard.record(value)
	if t == nil then
		return nil
	end
	-- Out-of-range positions are rejected, not clamped: a legitimate client never sends one.
	local x = Guard.number(t.x, GameConfig.Rail.minX, GameConfig.Rail.maxX)
	local sequence = Guard.integer(t.sequence, 0, MAX_ID)
	if x == nil or sequence == nil then
		return nil
	end
	return { x = x, sequence = sequence }
end

local function validateSelectUpgrade(value: unknown): SelectUpgradePayload?
	local t = Guard.record(value)
	if t == nil then
		return nil
	end
	local offerId = Guard.integer(t.offerId, 1, MAX_ID)
	local modifierId: BaseModifierId? = ModifierDefinitions.parseBaseId(t.modifierId)
	if offerId == nil or modifierId == nil then
		return nil
	end
	return { offerId = offerId, modifierId = modifierId }
end

local function validateRerollUpgrade(value: unknown): RerollUpgradePayload?
	local t = Guard.record(value)
	if t == nil then
		return nil
	end
	local offerId = Guard.integer(t.offerId, 1, MAX_ID)
	if offerId == nil then
		return nil
	end
	return { offerId = offerId }
end

local function validateContextAction(value: unknown): ContextActionPayload?
	local t = Guard.record(value)
	if t == nil then
		return nil
	end
	local verb = Guard.oneOf(t.verb, CONTEXT_VERBS)
	if verb == nil then
		return nil
	end
	-- oneOf only returns members of the list; the cast is for the old solver, which widens T.
	return { verb = verb :: Types.ContextVerb }
end

local function validateExtractDecision(value: unknown): ExtractDecisionPayload?
	local t = Guard.record(value)
	if t == nil then
		return nil
	end
	local choice = Guard.oneOf(t.choice, EXTRACT_CHOICES)
	if choice == nil then
		return nil
	end
	-- oneOf only returns members of the list; the cast is for the old solver, which widens T.
	return { choice = choice :: Types.ExtractChoice }
end

local function validateSetPaused(value: unknown): SetPausedPayload?
	local t = Guard.record(value)
	if t == nil then
		return nil
	end
	local paused = Guard.boolean(t.paused)
	if paused == nil then
		return nil
	end
	return { paused = paused }
end

local function validateReportFunnelStep(value: unknown): ReportFunnelStepPayload?
	local t = Guard.record(value)
	if t == nil then
		return nil
	end
	local step = Guard.oneOf(t.step, CLIENT_FUNNEL_STEPS)
	if step == nil then
		return nil
	end
	-- oneOf only returns members of the list; the cast is for the old solver, which widens T.
	return { step = step :: Types.ClientFunnelStep }
end

local function validateNoPayload(value: unknown): NoPayload?
	if value == nil or Guard.record(value) ~= nil then
		return NO_PAYLOAD
	end
	return nil
end

---------------------------------------------------------------------------------------------
-- The remotes
---------------------------------------------------------------------------------------------

local Network = {
	-- Client -> server --------------------------------------------------------------------

	-- Right thumb release: fire one shot in a lane-space direction.
	FireProjectile = clientToServer("FireProjectile", {
		validate = validateFireProjectile,
		rate = FIRE_RATE,
	}),
	-- Left thumb: the avatar's rail position, streamed while it moves (unreliable, ~20 Hz).
	RailInput = clientToServer("RailInput", {
		validate = validateRailInput,
		rate = { perSecond = GameConfig.Rail.sendRateHz * 1.5, burst = 10 },
		unreliable = true,
	}),
	-- Tap a card in the 3-card pick.
	SelectUpgrade = clientToServer("SelectUpgrade", {
		validate = validateSelectUpgrade,
		rate = { perSecond = 4, burst = 4 },
	}),
	-- Spend a reroll token on the open offer.
	RerollUpgrade = clientToServer("RerollUpgrade", {
		validate = validateRerollUpgrade,
		rate = { perSecond = 2, burst = 2 },
	}),
	-- The context button: Revive, Fuse or Extract.
	ContextAction = clientToServer("ContextAction", {
		validate = validateContextAction,
		rate = { perSecond = 4, burst = 4 },
	}),
	-- At an extract point: Descend (primary CTA) or Bank loot.
	ExtractDecision = clientToServer("ExtractDecision", {
		validate = validateExtractDecision,
		rate = { perSecond = 2, burst = 2 },
	}),
	-- The pause button (solo only).
	SetPaused = clientToServer("SetPaused", {
		validate = validateSetPaused,
		rate = { perSecond = 2, burst = 3 },
	}),
	-- Funnel steps only the client can see (goal card seen, tally skipped).
	ReportFunnelStep = clientToServer("ReportFunnelStep", {
		validate = validateReportFunnelStep,
		rate = { perSecond = 1, burst = 3 },
	}),

	-- Client -> server request ---------------------------------------------------------------

	-- Full run state for a client that (re)joins mid-run. Returns nil outside a run.
	FetchRunSnapshot = clientRequest("FetchRunSnapshot", {
		validate = validateNoPayload,
		rate = { perSecond = 1, burst = 3 },
	}) :: ClientRequest<NoPayload, RunSnapshot>,

	-- Server -> client ----------------------------------------------------------------------

	RunStateChanged = serverToClient("RunStateChanged") :: ServerToClient<RunState>,
	ShotsSpawned = serverToClient("ShotsSpawned") :: ServerToClient<ShotsSpawnedPayload>,
	ShotsBounced = serverToClient("ShotsBounced") :: ServerToClient<ShotsBouncedPayload>,
	ShotsEnded = serverToClient("ShotsEnded") :: ServerToClient<ShotsEndedPayload>,
	DamageReport = serverToClient("DamageReport") :: ServerToClient<DamageReportPayload>,
	TargetsSpawned = serverToClient("TargetsSpawned") :: ServerToClient<TargetsSpawnedPayload>,
	TargetsAdvanced = serverToClient("TargetsAdvanced") :: ServerToClient<TargetsAdvancedPayload>,
	AttackTelegraph = serverToClient("AttackTelegraph") :: ServerToClient<AttackTelegraphPayload>,
	HealthChanged = serverToClient("HealthChanged") :: ServerToClient<HealthChangedPayload>,
	HaulChanged = serverToClient("HaulChanged") :: ServerToClient<HaulChangedPayload>,
	XpChanged = serverToClient("XpChanged") :: ServerToClient<XpChangedPayload>,
	UpgradeOffered = serverToClient("UpgradeOffered") :: ServerToClient<UpgradeOfferedPayload>,
	UpgradeResolved = serverToClient("UpgradeResolved") :: ServerToClient<UpgradeResolvedPayload>,
	LoadoutChanged = serverToClient("LoadoutChanged") :: ServerToClient<LoadoutChangedPayload>,
	ContextVerbChanged = serverToClient("ContextVerbChanged") :: ServerToClient<ContextVerbChangedPayload>,
	ExtractOffered = serverToClient("ExtractOffered") :: ServerToClient<ExtractOfferedPayload>,
	RunEnded = serverToClient("RunEnded") :: ServerToClient<RunEndedPayload>,
}

-- Create every remote now (server). Idempotent; any server use of Network also mounts.
function Network.mountServer()
	assert(isServer, "mountServer is server-only")
	mount()
end

-- Called for every dropped client packet, e.g. to feed an anti-exploit counter. Keep it cheap:
-- a flooding client calls it at the flood rate.
function Network.setRejectionHandler(handler: ((player: Player, remoteName: string, reason: RejectReason) -> ())?)
	assert(isServer, "setRejectionHandler is server-only")
	rejectionHandler = handler
end

-- Every declared remote name and class, in declaration order (for tests and tooling).
function Network.listRemotes(): { { name: string, class: string } }
	local list: { { name: string, class: string } } = {}
	for _, name in declaredOrder do
		local class: string = declared[name]
		table.insert(list, { name = name, class = class })
	end
	return list
end

table.freeze(Network)
return Network
