-- Cosmetic impact burst. Client-only; pooled exactly like server projectiles.
return {
	PoolSize = 60,
	StartSize = Vector3.new(1.6, 1.6, 0.4),
	EndSize = Vector3.new(5, 5, 0.4),
	Color = Color3.fromRGB(190, 245, 255),
	Duration = 0.22,
	StoragePosition = Vector3.new(0, -500, 0),
}
