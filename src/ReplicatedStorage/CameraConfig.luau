-- High-angle tactical camera used during a run, so bank angles off walls read clearly.
return {
	-- Starting view: degrees below the horizon (90 would be straight down) and heading around
	-- +Y. Players can turn both; aiming reads the live camera, so it follows any rotation.
	Pitch = 60,
	Yaw = 0,
	MinPitch = 40,
	MaxPitch = 80,
	-- Degrees per pixel of right-mouse drag, and per pixel of a one-finger touch drag.
	RotateSensitivity = 0.3,
	-- Degrees per second while Q or E is held.
	KeyRotateSpeed = 110,
	-- Distance from the focus point along the view ray, in studs.
	DefaultDistance = 64,
	MinDistance = 42,
	MaxDistance = 96,
	-- Studs per mouse-wheel notch.
	ZoomStep = 6,
	FieldOfView = 50,
	-- Exponential follow rate (1/s); higher is snappier.
	FollowRate = 10,
	ZoomRate = 12,
	-- A focus jump bigger than this (a teleport between rooms) snaps instead of gliding.
	SnapDistance = 40,
}
