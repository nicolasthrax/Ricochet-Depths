--!strict
-- Shared type vocabulary for the lane game. Types only: this module has no runtime
-- dependencies, so any module (config, network, server, client) can import it without cycles.

local Types = {}

---------------------------------------------------------------------------------------------
-- Modifiers
---------------------------------------------------------------------------------------------

-- The eight cards that can be offered. Ids are persisted (run summaries, telemetry), never rename.
export type BaseModifierId =
	"Splitshot"
	| "Ember"
	| "Bigshot"
	| "Quickdraw"
	| "Frostbite"
	| "Spark"
	| "Drill"
	| "Echo"

-- Fused variants are never offered; they only come out of a FusionRecipes entry.
export type FusedModifierId =
	"Shatter"
	| "Inferno"
	| "Boulder"
	| "Gatling"
	| "Glacier"
	| "Tempest"
	| "Auger"
	| "Resonance"

export type ModifierId = BaseModifierId | FusedModifierId

-- Card frame. Rarity is shown three ways (band colour, pip count, written label) for colourblind
-- players; "Fused" outranks every rarity and always uses the gold frame.
export type Rarity = "Common" | "Rare" | "Epic" | "Fused"

export type ModifierKind = "Base" | "Fused"

-- One icon silhouette per family, reused on the card and the HUD badge.
export type ModifierFamily = "Split" | "Burn" | "Size" | "Tempo" | "Chill" | "Arc" | "Pierce" | "Bounce"

-- How a shot is drawn. Visual only; Inferno is the "visibly bigger and orange" FTUE shot.
export type ShotTint = "Default" | "Ember" | "Inferno"

export type SplitOnBounceEffect = {
	kind: "SplitOnBounce",
	shardCount: number, -- shards spawned per trigger
	shardDamageScale: number, -- shard damage as a fraction of the parent shot
	spreadDegrees: number, -- total fan angle the shards leave in
	everyBounce: boolean, -- false: first bounce only
}

export type BurnOnHitEffect = {
	kind: "BurnOnHit",
	damagePerSecond: number,
	durationSeconds: number,
	blastRadius: number, -- studs; 0 is no blast
	blastDamageScale: number, -- blast damage as a fraction of the hit
	shotTint: ShotTint, -- visual only
}

export type ShotSizeEffect = {
	kind: "ShotSize",
	radiusScale: number,
	flatDamage: number, -- added to every hit
}

export type FireRateEffect = {
	kind: "FireRate",
	cooldownScale: number, -- multiplies GameConfig.Shot.cooldownSeconds
}

export type ChillOnHitEffect = {
	kind: "ChillOnHit",
	skipSteps: number, -- pulses the target does not advance
	wholeRow: boolean, -- true: every target in the hit target's row
}

export type ArcOnHitEffect = {
	kind: "ArcOnHit",
	arcCount: number,
	arcDamageScale: number,
	arcRangeCells: number, -- grid cells, measured centre to centre
}

export type PierceEffect = {
	kind: "Pierce",
	pierceCount: number, -- targets passed through before the shot bounces off one
	damageScale: number,
}

export type ExtraBounceEffect = {
	kind: "ExtraBounce",
	extraBounces: number,
	damagePerBounce: number, -- fraction added per bounce already taken (0.15 = +15%)
}

-- What a modifier does, as data. A base card and its fused variant share an effect kind, so
-- combat code has exactly one branch per kind and fusion is only ever "bigger numbers + flags".
export type ModifierEffect =
	SplitOnBounceEffect
	| BurnOnHitEffect
	| ShotSizeEffect
	| FireRateEffect
	| ChillOnHitEffect
	| ArcOnHitEffect
	| PierceEffect
	| ExtraBounceEffect

export type ModifierEffectKind =
	"SplitOnBounce"
	| "BurnOnHit"
	| "ShotSize"
	| "FireRate"
	| "ChillOnHit"
	| "ArcOnHit"
	| "Pierce"
	| "ExtraBounce"

export type ModifierDefinition = {
	id: ModifierId,
	kind: ModifierKind,
	rarity: Rarity,
	family: ModifierFamily,
	label: string, -- card name, 12 characters at most
	badge: string, -- 2-3 letters for the HUD gutter
	effectText: string, -- verb-led, 3 words at most
	tip: string, -- the one-line hold-for-details tip
	offerWeight: number, -- relative draw weight; 0 for fused variants
	effect: ModifierEffect,
}

export type FusionRecipe = {
	first: BaseModifierId,
	second: BaseModifierId,
	result: FusedModifierId,
}

---------------------------------------------------------------------------------------------
-- Run flow
---------------------------------------------------------------------------------------------

export type RunPhase =
	"Intro" -- camera easing in, aim line only
	| "Combat"
	| "UpgradePick" -- solo: world frozen; co-op: world at GameConfig.Upgrades.coopWorldTimeScale
	| "RoomClear"
	| "ExtractChoice" -- Descend (primary) or Bank loot (secondary)
	| "Extracting" -- lift ride; camera still locked
	| "Ended"

export type RunOutcome = "Banked" | "Defeated" | "Abandoned"

-- The single context button shows at most one verb at a time.
export type ContextVerb = "Revive" | "Fuse" | "Extract"

export type ExtractChoice = "Descend" | "BankLoot"

export type TargetKind = "Block" | "Elite"

-- How a point of damage was dealt, so the client can pick the right hit effect.
export type DamageSource = "Direct" | "Shard" | "Burn" | "Blast" | "Arc"

-- Funnel steps only the client can observe. Everything else (first_hit, first_upgrade, ...)
-- is recorded server-side from authoritative events and never trusted from a client.
export type ClientFunnelStep = "first_goal_seen" | "tally_skip"

return Types
