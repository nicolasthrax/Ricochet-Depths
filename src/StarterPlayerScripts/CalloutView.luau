-- Big centre-screen callouts for kill streaks and long ricochets: "DOUBLE KILL", "RICOCHET x5".
-- Counts only this player's kills, from the EnemyDefeated event's shooter id.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local CalloutView = {}
CalloutView.__index = CalloutView

-- Kills closer together than this chain into a streak.
CalloutView.StreakWindow = 2.2
-- A kill off at least this many contacts earns a ricochet callout.
CalloutView.RicochetMinimum = 3

local STREAK_TEXT = { [2] = "DOUBLE KILL", [3] = "TRIPLE KILL", [4] = "QUAD KILL" }

-- The callout for a streak of `count` and a kill off `contacts` contacts, or nil.
function CalloutView.TextFor(count, contacts)
	if count >= 5 then
		return string.format("RAMPAGE x%d", count), UiConfig.Colors.Danger
	elseif STREAK_TEXT[count] then
		return STREAK_TEXT[count], UiConfig.Colors.Gold
	elseif (contacts or 0) >= CalloutView.RicochetMinimum then
		return string.format("RICOCHET x%d", contacts), UiConfig.Colors.Accent
	end
	return nil
end

function CalloutView.new(playerGui, clock)
	local self = setmetatable({}, CalloutView)
	self._clock = clock or os.clock
	self._streak = 0
	self._lastKillAt = -math.huge
	self.gui = UiTheme.screenGui("RicochetCallouts", playerGui, 20)

	local label = UiTheme.heading("Callout", self.gui, "", 44, UiConfig.Colors.Gold)
	label.AnchorPoint = Vector2.new(0.5, 0.5)
	label.Position = UDim2.fromScale(0.5, 0.26)
	label.Size = UDim2.fromOffset(600, 60)
	label.TextXAlignment = Enum.TextXAlignment.Center
	label.Visible = false
	self.label = label
	self._scale = Instance.new("UIScale")
	self._scale.Parent = label
	return self
end

-- A kill by this player off `contacts` contacts. Returns the callout shown, if any.
function CalloutView:OnKill(contacts)
	local now = self._clock()
	if now - self._lastKillAt <= CalloutView.StreakWindow then
		self._streak += 1
	else
		self._streak = 1
	end
	self._lastKillAt = now
	local text, color = CalloutView.TextFor(self._streak, contacts)
	if text then
		self:Show(text, color)
	end
	return text
end

function CalloutView:Show(text, color)
	local label = self.label
	label.Text = text
	label.TextColor3 = color or UiConfig.Colors.Gold
	label.TextTransparency = 0
	label.Visible = true
	self._scale.Scale = 1.5
	UiTheme.tween(self._scale, 0.25, { Scale = 1 }, Enum.EasingStyle.Back)
	self._token = (self._token or 0) + 1
	local token = self._token
	task.delay(1.1, function()
		if self._token == token then
			UiTheme.tween(label, 0.35, { TextTransparency = 1 })
			task.delay(0.35, function()
				if self._token == token then
					label.Visible = false
				end
			end)
		end
	end)
end

function CalloutView:Reset()
	self._streak = 0
	self._lastKillAt = -math.huge
end

return CalloutView
