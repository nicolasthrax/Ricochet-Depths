-- Accessibility and comfort options. Values are sent to the server, which sanitises and stores
-- them; this view never assumes its own change was accepted.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local SettingsView = {}
SettingsView.__index = SettingsView

-- Three steps rather than a slider: far easier to hit on a phone.
local LEVELS = { { label = "Off", value = 0 }, { label = "Low", value = 0.5 }, { label = "Full", value = 1 } }

local function levelIndexFor(value)
	local bestIndex, bestDistance = 3, math.huge
	for index, level in LEVELS do
		local distance = math.abs(level.value - (value or 1))
		if distance < bestDistance then
			bestIndex, bestDistance = index, distance
		end
	end
	return bestIndex
end

function SettingsView.new(playerGui, onChange)
	local self = setmetatable({}, SettingsView)
	self._onChange = onChange
	self._settings = { ReducedFlash = false, EffectIntensity = 1, ScreenShake = 1, SfxVolume = 1 }

	self.gui = UiTheme.screenGui("RicochetSettings", playerGui, 25)

	self.toggle = UiTheme.button("SettingsToggle", self.gui, "Options")
	self.toggle.AnchorPoint = Vector2.new(1, 1)
	self.toggle.Position = UDim2.new(1, -16, 1, -16)
	self.toggle.Size = UDim2.fromOffset(110, UiConfig.MinTouchTarget)
	self.toggle.TextSize = UiConfig.Text.Hud
	self.toggle.Activated:Connect(function()
		self:SetOpen(not self.panel.Visible)
	end)

	local panel = UiTheme.panel("Panel", self.gui)
	panel.AnchorPoint = Vector2.new(1, 1)
	panel.Position = UDim2.new(1, -16, 1, -76)
	panel.Size = UDim2.fromOffset(280, 266)
	panel.BackgroundTransparency = 0
	panel.Visible = false
	UiTheme.padding(panel, 12)
	self.panel = panel

	local title = UiTheme.heading("Title", panel, "Options", UiConfig.Text.CardTitle)
	title.Size = UDim2.new(1, 0, 0, 26)

	self._rows = {}
	self:_addRow(1, "ReducedFlash", "Reduced flash")
	self:_addRow(2, "EffectIntensity", "Effect intensity")
	self:_addRow(3, "ScreenShake", "Screen shake")
	self:_addRow(4, "SfxVolume", "Sound volume")

	self.version = UiTheme.label("Version", panel, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	self.version.Position = UDim2.new(0, 0, 1, -18)
	self.version.Size = UDim2.new(1, 0, 0, 16)

	return self
end

function SettingsView:_addRow(index, key, label)
	local y = 26 + (index - 1) * 52

	local caption = UiTheme.label(key .. "Label", self.panel, label, UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	caption.Position = UDim2.new(0, 0, 0, y)
	caption.Size = UDim2.new(1, 0, 0, 18)

	local button = UiTheme.button(key .. "Button", self.panel, "")
	button.Position = UDim2.new(0, 0, 0, y + 18)
	button.Size = UDim2.new(1, 0, 0, UiConfig.MinTouchTarget * 0.62)
	button.TextSize = UiConfig.Text.Small
	button.Activated:Connect(function()
		self:_cycle(key)
	end)

	self._rows[key] = button
end

function SettingsView:_cycle(key)
	local current = self._settings[key]
	if type(current) == "boolean" then
		self._settings[key] = not current
	else
		local nextIndex = levelIndexFor(current) % #LEVELS + 1
		self._settings[key] = LEVELS[nextIndex].value
	end
	self:_render()
	self._onChange(table.clone(self._settings))
end

function SettingsView:_render()
	for key, button in self._rows do
		local value = self._settings[key]
		if type(value) == "boolean" then
			button.Text = value and "On" or "Off"
		else
			button.Text = LEVELS[levelIndexFor(value)].label
		end
	end
end

-- Applies whatever the server says the settings are, which may differ from what was requested.
function SettingsView:Apply(settings)
	if type(settings) ~= "table" then
		return
	end
	for key in self._rows do
		if settings[key] ~= nil then
			self._settings[key] = settings[key]
		end
	end
	self:_render()
end

function SettingsView:SetVersion(text)
	self.version.Text = text
end

function SettingsView:SetOpen(open)
	self.panel.Visible = open
end

function SettingsView:GetSettings()
	return table.clone(self._settings)
end

function SettingsView:Destroy()
	self.gui:Destroy()
end

return SettingsView
