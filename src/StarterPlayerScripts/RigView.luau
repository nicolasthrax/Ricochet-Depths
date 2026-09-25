-- The rig picker: every rig with what it changes, its unlock level, and a Select button, and
-- under them the loadout presets (rig, trail and Pact saved together: two free slots, more with
-- passes). Display only; the server checks the level and saves the choice, and the next
-- ProfileSync is what this shows as selected.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local MetaConfig = require(ReplicatedStorage:WaitForChild("MetaConfig"))
local RigConfig = require(ReplicatedStorage:WaitForChild("RigConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local RigView = {}
RigView.__index = RigView

local ROW_HEIGHT = 86

-- onPreset(action, slot), optional: action is "Save" or "Apply".
function RigView.new(playerGui, onSelect, onPreset)
	local self = setmetatable({}, RigView)
	self._onSelect = onSelect
	self._onPreset = onPreset
	self._presets = {}
	self._presetSlots = MetaConfig.Presets.FreeSlots
	self._level = 1
	self._selected = RigConfig.DefaultId
	self.modal = UiTheme.modal("RicochetRigs", playerGui, "RIGS", Vector2.new(560, 560))

	local list = Instance.new("ScrollingFrame")
	list.Name = "List"
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Size = UDim2.fromScale(1, 1)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = self.modal.content
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 8)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list

	self.rows = {}
	for index, rig in RigConfig.Rigs do
		local frame = UiTheme.panel(rig.Id, list)
		frame.LayoutOrder = index
		frame.BackgroundColor3 = UiConfig.Colors.PanelRaised
		frame.BackgroundTransparency = 0
		frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
		UiTheme.padding(frame, 10)

		local title = UiTheme.label("Title", frame, rig.Title, UiConfig.Text.CardTitle, rig.Color)
		title.Font = UiConfig.FontDisplay
		title.Size = UDim2.new(1, -130, 0, 24)
		local tagline = UiTheme.label("Tagline", frame, rig.Tagline, UiConfig.Text.Small, UiConfig.Colors.Text)
		tagline.Position = UDim2.new(0, 0, 0, 24)
		tagline.Size = UDim2.new(1, -130, 0, 18)
		tagline.TextWrapped = true
		local summary = UiTheme.label("Summary", frame, RigConfig.Summary(rig), UiConfig.Text.Small, UiConfig.Colors.TextMuted)
		summary.Position = UDim2.new(0, 0, 0, 44)
		summary.Size = UDim2.new(1, -130, 0, 22)
		summary.TextWrapped = true

		local button = UiTheme.button("Select", frame, "", "Primary")
		button.AnchorPoint = Vector2.new(1, 0.5)
		button.Position = UDim2.new(1, 0, 0.5, 0)
		button.Size = UDim2.fromOffset(116, UiConfig.MinTouchTarget)
		button.TextSize = UiConfig.Text.Small
		button.Activated:Connect(function()
			if RigConfig.IsUnlocked(rig, self._level) and self._selected ~= rig.Id then
				self._onSelect(rig.Id)
			end
		end)
		self.rows[rig.Id] = { frame = frame, button = button }
	end

	-- Presets: one tile per slot, with SAVE and LOAD. Slots past the player's count show how to
	-- get them.
	local presets = UiTheme.panel("Presets", list)
	presets.LayoutOrder = #RigConfig.Rigs + 1
	presets.BackgroundTransparency = 1
	presets.Size = UDim2.new(1, -8, 0, 128)
	local heading = UiTheme.heading("Heading", presets, "LOADOUT PRESETS", UiConfig.Text.Small + 2, UiConfig.Colors.Accent)
	heading.Size = UDim2.new(1, 0, 0, 20)
	local slots = Instance.new("Frame")
	slots.Name = "Slots"
	slots.BackgroundTransparency = 1
	slots.Position = UDim2.new(0, 0, 0, 24)
	slots.Size = UDim2.new(1, 0, 1, -24)
	slots.Parent = presets
	local slotLayout = Instance.new("UIListLayout")
	slotLayout.FillDirection = Enum.FillDirection.Horizontal
	slotLayout.Padding = UDim.new(0, 6)
	slotLayout.SortOrder = Enum.SortOrder.LayoutOrder
	slotLayout.Parent = slots
	self.presetTiles = {}
	for slot = 1, MetaConfig.Presets.MaxSlots do
		local tile = UiTheme.panel("Slot" .. slot, slots)
		tile.LayoutOrder = slot
		tile.BackgroundColor3 = UiConfig.Colors.PanelRaised
		tile.BackgroundTransparency = 0
		tile.Size = UDim2.new(1 / MetaConfig.Presets.MaxSlots, -6, 1, 0)
		UiTheme.padding(tile, 4)
		local label = UiTheme.label("Label", tile, "SLOT " .. slot, UiConfig.Text.Small - 2, UiConfig.Colors.TextMuted)
		label.Size = UDim2.new(1, 0, 0, 16)
		label.TextXAlignment = Enum.TextXAlignment.Center
		label.TextWrapped = true
		local save = UiTheme.button("Save", tile, "SAVE")
		save.Position = UDim2.new(0, 0, 0, 18)
		save.Size = UDim2.new(1, 0, 0, UiConfig.MinTouchTarget - 8)
		save.TextSize = UiConfig.Text.Small - 2
		save.Activated:Connect(function()
			if slot <= self._presetSlots and self._onPreset then
				self._onPreset("Save", slot)
			end
		end)
		local load = UiTheme.button("Load", tile, "LOAD", "Primary")
		load.AnchorPoint = Vector2.new(0, 1)
		load.Position = UDim2.new(0, 0, 1, 0)
		load.Size = UDim2.new(1, 0, 0, UiConfig.MinTouchTarget - 8)
		load.TextSize = UiConfig.Text.Small - 2
		load.Activated:Connect(function()
			if slot <= self._presetSlots and self._presets[tostring(slot)] and self._onPreset then
				self._onPreset("Apply", slot)
			end
		end)
		self.presetTiles[slot] = { label = label, save = save, load = load }
	end
	self:_render()
	return self
end

function RigView:_render()
	for _, rig in RigConfig.Rigs do
		local row = self.rows[rig.Id]
		local unlocked = RigConfig.IsUnlocked(rig, self._level)
		local selected = self._selected == rig.Id
		row.button.Text = selected and "SELECTED" or unlocked and "SELECT" or ("LEVEL " .. rig.Level)
		local actionable = unlocked and not selected
		row.button.AutoButtonColor = actionable
		row.button.BackgroundColor3 = actionable and UiConfig.Colors.PrimaryButton or UiConfig.Colors.PanelRaised
		row.button.TextColor3 = actionable and UiConfig.Colors.PrimaryText
			or selected and UiConfig.Colors.Health
			or UiConfig.Colors.TextMuted
		local stroke = row.frame:FindFirstChildOfClass("UIStroke")
		if stroke then
			stroke.Color = selected and rig.Color or UiConfig.Colors.Edge
		end
	end
	for slot, tile in self.presetTiles or {} do
		local open = slot <= self._presetSlots
		local preset = self._presets[tostring(slot)]
		local rig = type(preset) == "table" and RigConfig.Get(preset.Rig)
		tile.label.Text = not open and "PASS SLOT" or rig and rig.Title or ("SLOT " .. slot)
		tile.save.Visible = open
		tile.load.Visible = open and preset ~= nil
	end
end

-- profile is the ProfileSync payload.
function RigView:SetProfile(profile)
	if type(profile) ~= "table" then
		return
	end
	local progression = type(profile.Progression) == "table" and profile.Progression or {}
	self._level = tonumber(progression.Level) or 1
	self._selected = RigConfig.Resolve(profile.SelectedRig, self._level).Id
	self._presets = type(profile.Presets) == "table" and profile.Presets or {}
	self._presetSlots = tonumber(profile.PresetSlots) or MetaConfig.Presets.FreeSlots
	self:_render()
end

function RigView:GetSelected()
	return self._selected
end

function RigView:Open()
	self.modal.Open()
end

function RigView:Close()
	self.modal.Close()
end

return RigView
