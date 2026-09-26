--!strict
-- The 3-card pick (design section 06). Opens when the server offers an upgrade (the XP bar
-- filled), shows three cards styled by rarity from ModifierDefinitions, and sends the chosen card
-- back through SelectUpgrade. The server decides everything: what is offered, whether a pick
-- fuses, and when the pick is over (UpgradeResolved).
--
-- Card face, top to bottom: the rarity band (name and pips), the badge, the card name, the
-- verb-led effect text and the mono stat line. Chips: RECOMMENDED (at most one per draw), NEW
-- (never seen before) and a gold "FUSES → X" frame when the pick completes a fusion.
--
-- The cards ignore input for the offer's input lock (0.4s), so a thumb still held from aiming
-- cannot pick by accident. Keys 1/2/3 pick on keyboards; gamepads get GUI selection.
--
-- Decoupled from combat: this module only talks to the server and exposes Opened/Closed signals;
-- the client bootstrap uses them to switch combat input off and on.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Source.Types)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local ModifierDefinitions = require(ReplicatedStorage.Source.ModifierDefinitions)
local Network = require(ReplicatedStorage.Network)
local Signal = require(ReplicatedStorage.Modules.Signal)

local Palette = GameConfig.Palette

local CARD_WIDTH = 150
local CARD_HEIGHT = 214
local CARD_GAP = 12
local BAND_HEIGHT = 26
local PANEL_COLOR = Color3.fromRGB(14, 24, 34)
local TEXT_COLOR = Color3.fromRGB(235, 242, 248)
local MUTED_TEXT = Color3.fromRGB(150, 166, 180)
local LOCKED_TRANSPARENCY = 0.45
-- Drawn for a 420 x 560 point screen; scaled to fit.
local REFERENCE_HEIGHT = 420
local REFERENCE_WIDTH = 3 * CARD_WIDTH + 2 * CARD_GAP + 80
local CLOSE_DELAY = 0.18
local RESEND_AFTER = 1.5
local ACTION_KEYS = "UpgradePickKeys"
local RARITY_PIPS: { [string]: number } = { Common = 1, Rare = 2, Epic = 3, Fused = 3 }
local KEY_INDEX: { [Enum.KeyCode]: number } = {
	[Enum.KeyCode.One] = 1,
	[Enum.KeyCode.Two] = 2,
	[Enum.KeyCode.Three] = 3,
	[Enum.KeyCode.KeypadOne] = 1,
	[Enum.KeyCode.KeypadTwo] = 2,
	[Enum.KeyCode.KeypadThree] = 3,
}
local OPEN_TWEEN = TweenInfo.new(0.18, Enum.EasingStyle.Back, Enum.EasingDirection.Out)
local FADE_TWEEN = TweenInfo.new(0.15, Enum.EasingStyle.Linear)

type CardView = {
	button: TextButton,
	scale: UIScale,
	modifierId: Types.BaseModifierId,
}

type Offer = Network.UpgradeOfferedPayload

local gui: ScreenGui? = nil
local overlay: Frame? = nil
local levelLabel: TextLabel? = nil
local cardRow: Frame? = nil
local rerollButton: TextButton? = nil
local cards: { CardView } = {}
local offer: Offer? = nil
local unlockAt = 0
local sentOfferId: number? = nil
local sentAt = 0
local closeToken = 0
local runId: number? = nil

local UpgradeUIController = {}

local function rarityColor(rarity: Types.Rarity): Color3
	local colors = Palette.Rarity
	if rarity == "Rare" then
		return colors.Rare
	elseif rarity == "Epic" then
		return colors.Epic
	elseif rarity == "Fused" then
		return colors.Fused
	end
	return colors.Common
end

-- Fired when the pick opens (after being closed) and when it closes.
UpgradeUIController.Opened = Signal.new() :: Signal.Signal<number>
UpgradeUIController.Closed = Signal.new() :: Signal.Signal<>

---------------------------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------------------------

local function corner(parent: GuiObject, radius: UDim)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = radius
	instance.Parent = parent
end

local function stroke(parent: GuiObject, color: Color3, thickness: number)
	local instance = Instance.new("UIStroke")
	instance.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	instance.Color = color
	instance.Thickness = thickness
	instance.Parent = parent
end

local function text(name: string, value: string, font: Enum.Font, size: UDim2, position: UDim2, parent: Instance): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Size = size
	label.Position = position
	label.FontFace = Font.fromEnum(font)
	label.TextColor3 = TEXT_COLOR
	label.TextScaled = true
	label.TextWrapped = true
	label.Text = value
	label.Parent = parent
	return label
end

local function chip(name: string, value: string, color: Color3, position: UDim2, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.AnchorPoint = Vector2.new(0.5, 0.5)
	frame.Position = position
	frame.Size = UDim2.fromOffset(0, 18)
	frame.AutomaticSize = Enum.AutomaticSize.X
	frame.BackgroundColor3 = color
	frame.BorderSizePixel = 0
	frame.ZIndex = 3
	corner(frame, UDim.new(0.5, 0))
	local padding = Instance.new("UIPadding")
	padding.PaddingLeft = UDim.new(0, 8)
	padding.PaddingRight = UDim.new(0, 8)
	padding.Parent = frame
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.AutomaticSize = Enum.AutomaticSize.X
	label.Size = UDim2.fromScale(0, 1)
	label.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
	label.TextSize = 11
	label.TextColor3 = Color3.fromRGB(12, 16, 22)
	label.Text = value
	label.ZIndex = 3
	label.Parent = frame
	frame.Parent = parent
	return frame
end

local function pipsText(rarity: Types.Rarity): string
	local filled = RARITY_PIPS[rarity] or 1
	return string.rep("●", filled) .. string.rep("○", 3 - filled)
end

---------------------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------------------

local function build(playerGui: PlayerGui): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "UpgradePick"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = true
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 10
	screen.Enabled = false

	local dim = Instance.new("Frame")
	dim.Name = "Overlay"
	dim.Size = UDim2.fromScale(1, 1)
	dim.BackgroundColor3 = Color3.new(0, 0, 0)
	dim.BackgroundTransparency = 0.45
	dim.BorderSizePixel = 0
	dim.Active = true -- swallows touches so nothing behind the pick reacts
	dim.Parent = screen
	overlay = dim

	local content = Instance.new("Frame")
	content.Name = "Content"
	content.AnchorPoint = Vector2.new(0.5, 0.5)
	content.Position = UDim2.fromScale(0.5, 0.5)
	content.Size = UDim2.fromOffset(REFERENCE_WIDTH, CARD_HEIGHT + 120)
	content.BackgroundTransparency = 1
	content.Parent = dim
	local scale = Instance.new("UIScale")
	scale.Parent = content
	local function rescale()
		local camera = Workspace.CurrentCamera
		local viewport = if camera then camera.ViewportSize else Vector2.new(REFERENCE_WIDTH, REFERENCE_HEIGHT)
		local fit = math.min(viewport.Y / (CARD_HEIGHT + 150), viewport.X / REFERENCE_WIDTH)
		scale.Scale = math.clamp(fit, 0.6, 1.75)
	end
	rescale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	local level = text("Level", "", Enum.Font.GothamBlack, UDim2.new(1, 0, 0, 30), UDim2.fromOffset(0, 0), content)
	level.TextColor3 = Palette.Xp
	levelLabel = level
	local subtitle = text("Subtitle", "Pick one", Enum.Font.GothamMedium, UDim2.new(1, 0, 0, 18), UDim2.fromOffset(0, 32), content)
	subtitle.TextColor3 = MUTED_TEXT

	local row = Instance.new("Frame")
	row.Name = "Cards"
	row.BackgroundTransparency = 1
	row.AnchorPoint = Vector2.new(0.5, 0)
	row.Position = UDim2.new(0.5, 0, 0, 60)
	row.Size = UDim2.fromOffset(3 * CARD_WIDTH + 2 * CARD_GAP, CARD_HEIGHT)
	row.Parent = content
	local layout = Instance.new("UIListLayout")
	layout.FillDirection = Enum.FillDirection.Horizontal
	layout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Padding = UDim.new(0, CARD_GAP)
	layout.Parent = row
	cardRow = row

	local reroll = Instance.new("TextButton")
	reroll.Name = "Reroll"
	reroll.AnchorPoint = Vector2.new(0.5, 0)
	reroll.Position = UDim2.new(0.5, 0, 0, 60 + CARD_HEIGHT + 12)
	reroll.Size = UDim2.fromOffset(150, GameConfig.Hud.minTouchTargetPoints)
	reroll.BackgroundColor3 = PANEL_COLOR
	reroll.BorderSizePixel = 0
	reroll.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	reroll.TextColor3 = TEXT_COLOR
	reroll.TextSize = 16
	reroll.Visible = false
	corner(reroll, UDim.new(0, 10))
	stroke(reroll, MUTED_TEXT, 1)
	reroll.Parent = content
	reroll.Activated:Connect(function()
		UpgradeUIController.reroll()
	end)
	rerollButton = reroll

	screen.Parent = playerGui
	return screen
end

local function buildCard(choice: Network.UpgradeChoice, index: number, parent: Instance): CardView
	local definition = ModifierDefinitions.get(choice.modifierId)
	local color = rarityColor(definition.rarity)
	local fusion = choice.fusesInto

	local button = Instance.new("TextButton")
	button.Name = `Card{index}`
	button.LayoutOrder = index
	button.Size = UDim2.fromOffset(CARD_WIDTH, CARD_HEIGHT)
	button.BackgroundColor3 = PANEL_COLOR
	button.BorderSizePixel = 0
	button.AutoButtonColor = false
	button.Text = ""
	button.Selectable = true
	button.ClipsDescendants = false
	corner(button, UDim.new(0, 12))
	stroke(button, if fusion then Palette.Fusion else color, if fusion then 3 else 2)
	local scale = Instance.new("UIScale")
	scale.Scale = 0.85
	scale.Parent = button

	-- Rarity band.
	local band = Instance.new("Frame")
	band.Name = "Band"
	band.Size = UDim2.new(1, 0, 0, BAND_HEIGHT)
	band.BackgroundColor3 = color
	band.BorderSizePixel = 0
	corner(band, UDim.new(0, 12))
	band.Parent = button
	-- Square off the band's bottom corners.
	local bandFill = Instance.new("Frame")
	bandFill.Size = UDim2.new(1, 0, 0, 12)
	bandFill.Position = UDim2.new(0, 0, 1, -12)
	bandFill.BackgroundColor3 = color
	bandFill.BorderSizePixel = 0
	bandFill.Parent = band
	local rarityLabel = text("Rarity", `{string.upper(definition.rarity)}  {pipsText(definition.rarity)}`, Enum.Font.GothamBlack, UDim2.new(1, -16, 0, 14), UDim2.fromOffset(8, 6), band)
	rarityLabel.TextColor3 = Color3.fromRGB(12, 16, 22)
	rarityLabel.ZIndex = 2

	-- Badge.
	local badge = Instance.new("Frame")
	badge.Name = "Badge"
	badge.AnchorPoint = Vector2.new(0.5, 0)
	badge.Position = UDim2.new(0.5, 0, 0, BAND_HEIGHT + 14)
	badge.Size = UDim2.fromOffset(52, 52)
	badge.BackgroundColor3 = Color3.fromRGB(22, 36, 50)
	badge.BorderSizePixel = 0
	corner(badge, UDim.new(0.5, 0))
	stroke(badge, color, 2)
	badge.Parent = button
	local badgeText = text("Text", definition.badge, Enum.Font.GothamBlack, UDim2.new(1, -14, 1, -18), UDim2.fromOffset(7, 9), badge)
	badgeText.TextColor3 = color

	-- Name, effect, stats.
	text("Name", definition.label, Enum.Font.GothamBlack, UDim2.new(1, -16, 0, 22), UDim2.new(0, 8, 0, BAND_HEIGHT + 74), button)
	local effect = text("Effect", definition.effectText, Enum.Font.GothamMedium, UDim2.new(1, -16, 0, 18), UDim2.new(0, 8, 0, BAND_HEIGHT + 100), button)
	effect.TextColor3 = MUTED_TEXT
	local stats = text("Stats", ModifierDefinitions.statLine(definition.effect), Enum.Font.RobotoMono, UDim2.new(1, -16, 0, 26), UDim2.new(0, 8, 0, BAND_HEIGHT + 122), button)
	stats.TextColor3 = TEXT_COLOR

	-- Chips.
	if choice.recommended then
		chip("Recommended", "★ RECOMMENDED", Palette.Xp, UDim2.new(0.5, 0, 0, -2), button)
	end
	if choice.isNew then
		chip("New", "NEW", Palette.Gem, UDim2.new(1, -18, 0, BAND_HEIGHT + 16), button)
	end
	if fusion then
		local fused = ModifierDefinitions.get(fusion :: Types.ModifierId)
		chip("Fuses", `FUSES → {string.upper(fused.label)}`, Palette.Fusion, UDim2.new(0.5, 0, 1, -16), button)
	end

	-- Keyboard hint.
	if UserInputService.KeyboardEnabled then
		local hint = text("Key", tostring(index), Enum.Font.GothamBold, UDim2.fromOffset(14, 14), UDim2.new(0, 6, 1, -20), button)
		hint.TextColor3 = MUTED_TEXT
	end

	button.Parent = parent
	local view: CardView = { button = button, scale = scale, modifierId = choice.modifierId }
	button.Activated:Connect(function()
		UpgradeUIController.pick(index)
	end)
	return view
end

---------------------------------------------------------------------------------------------
-- Open / close
---------------------------------------------------------------------------------------------

local function isOpen(): boolean
	local screen = gui
	return screen ~= nil and screen.Enabled
end

local function setCardsLocked(locked: boolean)
	for _, card in cards do
		card.button.BackgroundTransparency = if locked then LOCKED_TRANSPARENCY else 0
		card.button.Active = not locked
	end
end

local function clearCards()
	for _, card in cards do
		card.button:Destroy()
	end
	table.clear(cards)
end

local function onKeys(_actionName: string, inputState: Enum.UserInputState, input: InputObject): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	local index = KEY_INDEX[input.KeyCode]
	if index then
		UpgradeUIController.pick(index)
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

local function close()
	local wasOpen = isOpen()
	offer = nil
	sentOfferId = nil
	closeToken += 1
	clearCards()
	local screen = gui
	if screen then
		screen.Enabled = false
	end
	ContextActionService:UnbindAction(ACTION_KEYS)
	if GuiService.SelectedObject and GuiService.SelectedObject:IsDescendantOf(screen or game) then
		GuiService.SelectedObject = nil
	end
	if wasOpen then
		UpgradeUIController.Closed:Fire()
	end
end

local function show(payload: Offer)
	local screen, row = gui, cardRow
	if screen == nil or row == nil then
		return
	end
	local wasOpen = isOpen()
	closeToken += 1
	offer = payload
	sentOfferId = nil
	clearCards()

	local level = levelLabel
	if level then
		level.Text = `LEVEL {payload.level}`
	end
	for index, choice in payload.choices do
		table.insert(cards, buildCard(choice, index, row))
	end
	-- Gamepad: left/right walks the cards; start on the recommended one.
	local startIndex = 1
	for index, card in cards do
		local left = cards[index - 1]
		local right = cards[index + 1]
		if left then
			card.button.NextSelectionLeft = left.button
		end
		if right then
			card.button.NextSelectionRight = right.button
		end
		if payload.choices[index].recommended then
			startIndex = index
		end
	end

	local reroll = rerollButton
	if reroll then
		reroll.Visible = payload.rerollVisible
		reroll.Text = `↻ Reroll ({payload.rerollsLeft})`
		reroll.Active = payload.rerollsLeft > 0
		reroll.TextTransparency = if payload.rerollsLeft > 0 then 0 else 0.5
	end

	screen.Enabled = true
	local dim = overlay
	if dim and not wasOpen then
		dim.BackgroundTransparency = 1
		TweenService:Create(dim, FADE_TWEEN, { BackgroundTransparency = 0.45 }):Play()
	end
	for _, card in cards do
		TweenService:Create(card.scale, OPEN_TWEEN, { Scale = 1 }):Play()
	end

	unlockAt = os.clock() + payload.inputLockSeconds
	setCardsLocked(true)
	local token = closeToken
	task.delay(payload.inputLockSeconds, function()
		if closeToken == token then
			setCardsLocked(false)
			if UserInputService.GamepadEnabled then
				local card = cards[startIndex]
				if card then
					GuiService.SelectedObject = card.button
				end
			end
		end
	end)

	ContextActionService:BindActionAtPriority(
		ACTION_KEYS,
		onKeys,
		false,
		Enum.ContextActionPriority.High.Value,
		Enum.KeyCode.One,
		Enum.KeyCode.Two,
		Enum.KeyCode.Three,
		Enum.KeyCode.KeypadOne,
		Enum.KeyCode.KeypadTwo,
		Enum.KeyCode.KeypadThree
	)

	if not wasOpen then
		UpgradeUIController.Opened:Fire(payload.offerId)
	end
end

local function onResolved(payload: Network.UpgradeResolvedPayload)
	local current = offer
	if current == nil or current.offerId ~= payload.offerId then
		return
	end
	-- Flash the picked card, then close, unless a queued offer replaces this one first.
	for _, card in cards do
		if card.modifierId == payload.modifierId then
			TweenService:Create(card.scale, FADE_TWEEN, { Scale = 1.06 }):Play()
		else
			card.button.BackgroundTransparency = 0.7
		end
	end
	closeToken += 1
	local token = closeToken
	task.delay(CLOSE_DELAY, function()
		if closeToken == token then
			close()
		end
	end)
end

---------------------------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------------------------

function UpgradeUIController.init()
	local player = Players.LocalPlayer
	gui = build(player:WaitForChild("PlayerGui") :: PlayerGui)

	Network.UpgradeOffered:connect(show)
	Network.UpgradeResolved:connect(onResolved)
	Network.RunEnded:connect(function(_payload: Network.RunEndedPayload)
		close()
	end)
end

-- Picks the card at `index` (1-3) of the open offer. Ignored during the input lock and while a
-- pick is already on its way.
function UpgradeUIController.pick(index: number)
	local current = offer
	if current == nil or os.clock() < unlockAt then
		return
	end
	local card = cards[index]
	if card == nil then
		return
	end
	if sentOfferId == current.offerId and os.clock() - sentAt < RESEND_AFTER then
		return
	end
	sentOfferId = current.offerId
	sentAt = os.clock()
	card.scale.Scale = 0.96
	TweenService:Create(card.scale, FADE_TWEEN, { Scale = 1 }):Play()
	Network.SelectUpgrade:fire({ offerId = current.offerId, modifierId = card.modifierId })
end

-- Spends a reroll token on the open offer; the server answers with a fresh offer.
function UpgradeUIController.reroll()
	local current = offer
	if current == nil or current.rerollsLeft <= 0 or os.clock() < unlockAt then
		return
	end
	Network.RerollUpgrade:fire({ offerId = current.offerId })
end

-- Follows the run: a new run (or the end of one) closes a stale pick.
function UpgradeUIController.applyState(state: Network.RunState)
	if runId ~= nil and state.runId ~= runId then
		close()
	end
	runId = state.runId
	if state.phase == "Ended" then
		close()
	end
end

function UpgradeUIController.isOpen(): boolean
	return isOpen()
end

table.freeze(UpgradeUIController)
return UpgradeUIController
