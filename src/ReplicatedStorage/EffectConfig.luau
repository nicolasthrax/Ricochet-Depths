-- Cosmetic impact burst. Client-only; pooled exactly like server projectiles.
return {
	PoolSize = 60,
	StartSize = Vector3.new(1.6, 1.6, 0.4),
	EndSize = Vector3.new(5, 5, 0.4),
	Color = Color3.fromRGB(190, 245, 255),
	Duration = 0.22,
	StoragePosition = Vector3.new(0, -500, 0),

	-- Impacts are batched instead of sent per bounce: with 100 live projectiles a
	-- per-contact remote would mean hundreds of calls a second.
	BatchInterval = 0.05,
	-- Impacts beyond this in one batch are dropped. They are purely cosmetic.
	MaxImpactsPerBatch = 24,

	-- Camera shake (CameraShake). Trauma is 0..1; the offset grows with trauma squared.
	Shake = {
		MaxTrauma = 1,
		-- Trauma lost per second.
		Decay = 1.8,
		-- Studs of camera offset at full trauma, before the player's screen-shake setting.
		MaxOffset = 0.9,
		-- Wobble speed, radians per second.
		Frequency = 24,
	},
	-- Trauma added per event. Kills and hits on you land hardest; bounces are a light tick.
	ShakeImpulses = {
		Kill = 0.35,
		Hit = 0.12,
		Block = 0.08,
		Wall = 0.03,
		PlayerHurt = 0.5,
	},

	-- Floating damage numbers (DamagePopups).
	Popups = {
		PoolSize = 24,
		Duration = 0.7,
		-- Studs a number rises over its lifetime.
		Rise = 3.5,
		StoragePosition = Vector3.new(0, -500, 0),
		HitColor = Color3.fromRGB(255, 236, 200),
		KillColor = Color3.fromRGB(255, 150, 90),
		BlockColor = Color3.fromRGB(200, 214, 230),
		BlockedText = "BLOCKED",
	},
}
