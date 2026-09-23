-- Drag-to-aim tuning and the look of the aim UI.
return {
	-- Drag length in pixels that corresponds to full power.
	MaxDragPixels = 220,
	-- Drags shorter than this are ignored, so a plain tap never fires.
	DeadzonePixels = 14,

	LineMinLength = 40,
	LineMaxLength = 170,
	LineThickness = 5,
	LineColor = Color3.fromRGB(120, 235, 255),
	LineTransparency = 0,
	-- Shown while the shot would be refused for cooldown.
	CooldownColor = Color3.fromRGB(150, 158, 178),

	-- World-space line drawn on the projectile plane from the muzzle (where the server spawns
	-- the shot, ProjectileConfig.MuzzleOffset ahead of the character) along the shot (studs).
	WorldLineMinLength = 8,
	WorldLineMaxLength = 28,
	WorldLineThickness = 0.35,
	WorldLineTransparency = 0,
	WorldTipSize = 1.1,

	-- Depth cues on the floor: the line's shadow, a drop line from the tip and a target reticle.
	GroundLineWidth = 0.5,
	GroundLineTransparency = 0.6,
	DropLineWidth = 0.12,
	DropLineTransparency = 0.35,
	ReticleSize = 3.2,
	ReticleTransparency = 0.55,
	ReticleCoreSize = 1.1,
	-- Lift above the floor so ground cues never z-fight with it or the grid.
	GroundLift = 0.06,

	PowerBarSize = Vector2.new(180, 10),
	PowerBarOffsetY = -60,
	PowerBarBackColor = Color3.fromRGB(20, 22, 30),
	PowerBarFillColor = Color3.fromRGB(120, 235, 255),
}
