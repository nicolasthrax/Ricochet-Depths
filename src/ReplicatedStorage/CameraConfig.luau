-- High-angle tactical camera used during a run, so bank angles off walls read clearly.
return {
	-- Degrees below the horizon; 90 would be straight down.
	Pitch = 60,
	-- Fixed heading in degrees around +Y. A fixed heading keeps screen-up == the same world
	-- direction for the whole room, which is what makes aiming by feel possible.
	Yaw = 0,
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
