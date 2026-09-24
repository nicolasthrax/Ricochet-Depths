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

-- 2.0's new systems. Shown once a session to everyone, veterans included, since none of them
-- existed when earlier runs retired the hints above.
local NEW_HINTS = {
	Orbs = "You carry 3 orbs. Walk over a thrown orb to pick it up; bank a kill off 2 walls to get it back at once.",
	Dash = "Press Q or Shift (or DASH) to dash through danger. You cannot be hit mid-dash.",
	Waves = "Red circles on the floor: another wave is about to arrive there.",
	Surge = "SURGE! Kills filled your meter. Pick a perk with 1 / 2 / 3 or a tap, and keep fighting.",
	Doors = "Choose the next room. Each door promises something different; the group votes.",
	Crystals = "Crystal Hunt: only a shot that has bounced can crack a crystal. Bank it!",
	Beacon = "Hold the Beacon: stand in the glowing ring until it fills.",
	Gallery = "Trick Shot Gallery: every bounce doubles a target's points.",
	Mirror = "Mirror! Straight shots glance off it. Bounce a shot off a wall first.",
	Magnet = "Magnet! It bends shots toward itself. Use it to curve round cover.",
	Sponge = "Sponge! It soaks up a shot's bounces. Hit it last, or head on.",
	TreasureRunner = "Treasure Runner! Catch it before it escapes with its coins.",
}
for hintId, text in NEW_HINTS do
	HINTS[hintId] = text
end

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
		if not NEW_HINTS[hintId] then
			self._seen[hintId] = true
		end
	end
	self:Hide()
end

function OnboardingView:Destroy()
	self.gui:Destroy()
end

return OnboardingView
