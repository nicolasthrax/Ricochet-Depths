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
	LineTransparency = 0.25,

	PowerBarSize = Vector2.new(180, 10),
	PowerBarOffsetY = -60,
	PowerBarBackColor = Color3.fromRGB(20, 22, 30),
	PowerBarFillColor = Color3.fromRGB(120, 235, 255),
}
