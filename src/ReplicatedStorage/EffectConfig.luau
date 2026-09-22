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
}
