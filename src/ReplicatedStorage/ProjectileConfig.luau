-- Tuning values for projectiles and the object pool. Logic never hardcodes these.
return {
	-- Pool is pre-warmed at server start; the game never Instance.new()s a projectile at runtime.
	PoolSize = 150,

	Radius = 0.45,
	Color = Color3.fromRGB(120, 235, 255),
	Material = Enum.Material.Neon,

	-- Height of the horizontal plane all projectiles travel on (relative to room floor Y).
	PlaneHeight = 3,

	BaseSpeed = 95,
	-- Drag power (0..1) maps onto this speed multiplier range.
	MinSpeedMultiplier = 0.55,
	MaxSpeedMultiplier = 1.45,

	MaxBounces = 3,
	-- Shots ricochet off enemies as well as walls, which is what makes chain kills possible.
	-- Flip this to true to have a damaging hit swallow the projectile instead.
	ConsumeOnEnemyHit = false,
	Lifetime = 4,

	-- Distance the spawn point is pushed ahead of the shooter so the shot reads as leaving the body.
	-- Clamped at fire time so a shot taken against a wall never starts inside it.
	MuzzleOffset = 3,
	-- Collision casts start this far behind the projectile, so a surface it is sitting exactly on
	-- (an exact corner hit puts it flush against the perpendicular wall) is still detected.
	CastBackStep = 0.1,
	-- Gap kept between the projectile surface and a wall after a bounce, to stop re-hitting it.
	SurfaceSkin = 0.05,
	-- Safety cap on reflections resolved inside a single frame (corners can chain).
	MaxBouncesPerStep = 4,

	-- Server-side rate limit, seconds between accepted shots from one player.
	FireCooldown = 0.18,
	MinPower = 0.15,
	MaxPower = 1,

	-- Idle pool parts are parked here, invisible and anchored, so they cost no physics time.
	StoragePosition = Vector3.new(0, -500, 0),
}
