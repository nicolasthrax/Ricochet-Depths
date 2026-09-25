-- An emote, played in the lobby: a burst of its glyph over the player's head that every client
-- sees, gone after a moment. Built on the server so nobody needs a remote to see it; purely
-- visual. ShopService decides whether the emote may be played.
local EmoteBurst = {}

local BURST_NAME = "EmoteBurst"
EmoteBurst.Seconds = 2.5

-- Shows `emote` ({ Text, Color }) over the player's character. Returns the billboard, or nil
-- when there is no character to show it on.
function EmoteBurst.Play(player, emote)
	local character = player.Character
	local anchor = character and (character:FindFirstChild("Head") or character:FindFirstChild("HumanoidRootPart"))
	if not anchor or type(emote) ~= "table" then
		return nil
	end
	local existing = anchor:FindFirstChild(BURST_NAME)
	if existing then
		existing:Destroy()
	end
	local burst = Instance.new("BillboardGui")
	burst.Name = BURST_NAME
	burst.Size = UDim2.fromScale(4, 4)
	burst.StudsOffset = Vector3.new(0, 5, 0)
	burst.MaxDistance = 120
	burst.LightInfluence = 0
	burst.AlwaysOnTop = true

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.TextScaled = true
	label.Text = emote.Text or "!"
	label.TextColor3 = emote.Color or Color3.new(1, 1, 1)
	label.Parent = burst
	burst.Parent = anchor

	task.delay(EmoteBurst.Seconds, function()
		if burst.Parent then
			burst:Destroy()
		end
	end)
	return burst
end

return EmoteBurst
