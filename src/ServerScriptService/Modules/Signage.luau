-- Signs that render reliably. Boards print on a SurfaceGui on the front face of a thin part, so
-- they sit in the world like real signage and are never occluded by the part they hang from.
-- Floating labels are BillboardGuis sized in studs (not pixels), offset in world space, so they
-- scale with distance like everything else.
local Signage = {}

local FONT = Enum.Font.GothamBlack

local function label(parent, text, color)
	local textLabel = Instance.new("TextLabel")
	textLabel.Name = "Text"
	textLabel.Size = UDim2.fromScale(0.94, 0.86)
	textLabel.Position = UDim2.fromScale(0.03, 0.07)
	textLabel.BackgroundTransparency = 1
	textLabel.Font = FONT
	textLabel.TextScaled = true
	textLabel.TextColor3 = color
	textLabel.TextStrokeTransparency = 0.5
	textLabel.Text = text
	textLabel.Parent = parent
	return textLabel
end

-- A board of `size` (X wide, Y tall, Z thin) at `position`, its printed face turned towards
-- `facing` (a flat direction).
function Signage.Board(parent, name, size, position, facing, text, textColor, backColor)
	local board = Instance.new("Part")
	board.Name = name
	board.Size = size
	board.CFrame = CFrame.lookAt(position, position + facing)
	board.Position = position
	board.Color = backColor
	board.Material = Enum.Material.SmoothPlastic
	board.Anchored = true
	board.CanCollide = false
	board.CanQuery = false
	board.CanTouch = false
	board.CastShadow = false
	board.Parent = parent

	local gui = Instance.new("SurfaceGui")
	gui.Name = "Face"
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.Parent = board
	label(gui, text, textColor)
	return board
end

-- A floating label `sizeStuds` (Vector2) big, `offset` studs from `part` in world space.
function Signage.Floating(part, name, text, color, sizeStuds, offset)
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Size = UDim2.new(sizeStuds.X, 0, sizeStuds.Y, 0)
	gui.StudsOffsetWorldSpace = offset
	gui.LightInfluence = 0
	gui.AlwaysOnTop = false
	gui.MaxDistance = 220
	gui.Parent = part
	label(gui, text, color)
	return gui
end

-- Changes the text on a board or floating label.
function Signage.SetText(holder, text)
	local gui = holder:IsA("BasePart") and holder:FindFirstChildOfClass("SurfaceGui") or holder
	local textLabel = gui and gui:FindFirstChild("Text")
	if textLabel and textLabel.Text ~= text then
		textLabel.Text = text
	end
end

return Signage
