-- Promo code entry. The server checks the code and answers with a toast.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UiTheme = require(script.Parent.UiTheme)

local CodesView = {}
CodesView.__index = CodesView

function CodesView.new(playerGui, onRedeem)
	local self = setmetatable({}, CodesView)
	self.modal = UiTheme.modal("RicochetCodes", playerGui, "CODES", Vector2.new(420, 270))
	local content = self.modal.content

	local hint = UiTheme.label("Hint", content, "Codes are posted on our group and socials. Enter one for free rewards!",
		UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	hint.Size = UDim2.new(1, 0, 0, 36)
	hint.TextWrapped = true

	local box = Instance.new("TextBox")
	box.Name = "CodeBox"
	box.Position = UDim2.new(0, 0, 0, 44)
	box.Size = UDim2.new(1, 0, 0, UiConfig.MinTouchTarget)
	box.BackgroundColor3 = UiConfig.Colors.Track
	box.BorderSizePixel = 0
	box.Font = UiConfig.FontBold
	box.TextSize = UiConfig.Text.CardTitle
	box.TextColor3 = UiConfig.Colors.Text
	box.PlaceholderText = "Enter code"
	box.PlaceholderColor3 = UiConfig.Colors.TextMuted
	box.Text = ""
	box.ClearTextOnFocus = false
	box.Parent = content
	UiTheme.corner(box)
	UiTheme.stroke(box, UiConfig.Colors.Accent, 1.5, 0.4)
	self.box = box

	self.redeemButton = UiTheme.button("Redeem", content, "REDEEM", "Primary")
	self.redeemButton.AnchorPoint = Vector2.new(0.5, 0)
	self.redeemButton.Position = UDim2.new(0.5, 0, 0, 104)
	self.redeemButton.Size = UDim2.fromOffset(200, 50)
	self.redeemButton.Activated:Connect(function()
		local code = self.box.Text
		if #code > 0 then
			onRedeem(code)
			self.box.Text = ""
		end
	end)
	return self
end

function CodesView:Open()
	self.modal.Open()
end

function CodesView:Close()
	self.modal.Close()
end

return CodesView
