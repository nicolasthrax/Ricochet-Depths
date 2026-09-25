-- A small "Lv N · Title" plate over every character, so players can see each other's level in the lobby
-- and in co-op runs. Built on the server, so every client sees the same plate. Idempotent: call
-- Update as often as you like; it only touches the plate when something changed.
local Nameplates = {}

local PLATE_NAME = "LevelPlate"
local TEXT_COLOR = Color3.fromRGB(255, 226, 150)
local STROKE_COLOR = Color3.fromRGB(20, 16, 8)

local function build(head)
	local plate = Instance.new("BillboardGui")
	plate.Name = PLATE_NAME
	plate.Size = UDim2.fromOffset(120, 24)
	-- Above the default name display, which sits just over the head.
	plate.StudsOffset = Vector3.new(0, 3.1, 0)
	plate.MaxDistance = 80
	plate.LightInfluence = 0

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextScaled = true
	label.TextColor3 = TEXT_COLOR
	label.TextStrokeColor3 = STROKE_COLOR
	label.TextStrokeTransparency = 0.35
	label.Text = ""
	label.Parent = plate

	plate.Parent = head
	return plate
end

-- Shows `level` (and a cosmetic title, if one is worn) over the player's current character, if
-- it has a head yet.
function Nameplates.Update(player, level, title)
	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head then
		return false
	end
	local plate = head:FindFirstChild(PLATE_NAME) or build(head)
	local label = plate:FindFirstChild("Text")
	local text = "Lv " .. tostring(level)
	if type(title) == "string" and title ~= "" then
		text ..= "  ·  " .. title
	end
	if label and label.Text ~= text then
		label.Text = text
	end
	return true
end

return Nameplates
