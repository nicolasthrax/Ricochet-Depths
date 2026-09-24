-- Short contextual prompts for a first session. Nothing blocks play: each hint appears in the
-- moment it applies and retires as soon as the player has done the thing.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local OnboardingView = {}
OnboardingView.__index = OnboardingView

local HINTS = {
	Lobby = "Step into a Gate with friends (2-8), or use the Solo Portal. Claim free rewards in Daily and Quests!",
	Aim = "Drag away from your target, then release to fire.",
	Ricochet = "Shots bounce. Bank them off walls to reach what you cannot see.",
	Shield = "Shields turn slowly. Shoot the open side, or bank a shot round the back.",
	Upgrade = "Pick one upgrade. If you wait too long, one is chosen for you.",
}

function OnboardingView.new(playerGui)
	local self = setmetatable({}, OnboardingView)
	self._seen = {}

	self.gui = UiTheme.screenGui("RicochetOnboarding", playerGui, 15)
	local panel = UiTheme.panel("HintPanel", self.gui)
	panel.AnchorPoint = Vector2.new(0.5, 1)
	panel.Position = UDim2.new(0.5, 0, 1, -110)
	panel.Size = UDim2.fromOffset(420, 44)
	panel.Visible = false
	UiTheme.padding(panel, 10)
	self.panel = panel

	local constraint = Instance.new("UISizeConstraint")
	constraint.MaxSize = Vector2.new(440, 60)
	constraint.Parent = panel

	self.label = UiTheme.label("Hint", panel, "", UiConfig.Text.Small, UiConfig.Colors.Accent)
	self.label.Size = UDim2.fromScale(1, 1)
	self.label.TextXAlignment = Enum.TextXAlignment.Center
	self.label.TextWrapped = true

	return self
end

-- Shows a hint at most once per session, so it never nags.
function OnboardingView:Show(hintId, duration)
	local text = HINTS[hintId]
	if not text or self._seen[hintId] then
		return false
	end
	self._seen[hintId] = true

	self.label.Text = text
	self.panel.Visible = true
	self._token = (self._token or 0) + 1
	local token = self._token
	task.delay(duration or 6, function()
		if self._token == token then
			self.panel.Visible = false
		end
	end)
	return true
end

function OnboardingView:Hide()
	self._token = (self._token or 0) + 1
	self.panel.Visible = false
end

-- Used when the profile says this player has already completed a run.
function OnboardingView:MarkAllSeen()
	for hintId in HINTS do
		self._seen[hintId] = true
	end
	self:Hide()
end

function OnboardingView:Destroy()
	self.gui:Destroy()
end

return OnboardingView
