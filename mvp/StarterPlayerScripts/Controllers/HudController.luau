--!strict
-- The in-run HUD (design section 05): HP pips top left, depth/room and the XP bar top centre, the
-- haul and the pause button top right, the modifier badge column down the left gutter, and the
-- ROOM CLEAR / RUN OVER banners. Numbers appear only where the design allows them (room, haul).
--
-- Listens to the server's remotes only; it never reads combat state directly.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local Types = require(ReplicatedStorage.Source.Types)
local GameConfig = require(ReplicatedStorage.Source.GameConfig)
local ModifierDefinitions = require(ReplicatedStorage.Source.ModifierDefinitions)
local Network = require(ReplicatedStorage.Network)

local Palette = GameConfig.Palette
local HudConfig = GameConfig.Hud

local TOUCH = HudConfig.minTouchTargetPoints
local PANEL_COLOR = Color3.fromRGB(10, 18, 26)
local PANEL_TRANSPARENCY = 0.25
local TEXT_COLOR = Color3.fromRGB(235, 242, 248)
local MUTED_TEXT = Color3.fromRGB(140, 156, 170)
local EMPTY_PIP = Color3.fromRGB(46, 58, 70)
local BADGE_SIZE = 40
local BADGE_GAP = 6
-- The layout is drawn for a 420pt-tall screen and scaled up on taller ones (never down, so
-- touch targets stay at least 44pt).
local REFERENCE_HEIGHT = 420
local MAX_SCALE = 1.75
local BANNER_TWEEN = TweenInfo.new(0.2, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)
local BAR_TWEEN = TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.Out)

type Pips = { Frame }

local gui: ScreenGui? = nil
local pips: Pips = {}
local roomLabel: TextLabel? = nil
local xpFill: Frame? = nil
local haulLabel: TextLabel? = nil
local pauseButton: TextButton? = nil
local badgeColumn: ScrollingFrame? = nil
local banner: TextLabel? = nil
local bannerSubtitle: TextLabel? = nil
local state: Network.RunState? = nil
local bannerToken = 0

local HudController = {}

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

---------------------------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------------------------

local function corner(parent: GuiObject, radius: UDim)
	local instance = Instance.new("UICorner")
	instance.CornerRadius = radius
	instance.Parent = parent
end

local function stroke(parent: GuiObject, color: Color3, thickness: number): UIStroke
	local instance = Instance.new("UIStroke")
	instance.ApplyStrokeMode = Enum.ApplyStrokeMode.Border
	instance.Color = color
	instance.Thickness = thickness
	instance.Parent = parent
	return instance
end

local function panel(name: string, size: UDim2, position: UDim2, anchor: Vector2, parent: Instance): Frame
	local frame = Instance.new("Frame")
	frame.Name = name
	frame.Size = size
	frame.Position = position
	frame.AnchorPoint = anchor
	frame.BackgroundColor3 = PANEL_COLOR
	frame.BackgroundTransparency = PANEL_TRANSPARENCY
	frame.BorderSizePixel = 0
	corner(frame, UDim.new(0, 10))
	frame.Parent = parent
	return frame
end

local function label(name: string, text: string, size: UDim2, parent: Instance): TextLabel
	local instance = Instance.new("TextLabel")
	instance.Name = name
	instance.BackgroundTransparency = 1
	instance.Size = size
	instance.FontFace = Font.fromEnum(Enum.Font.GothamBold)
	instance.TextColor3 = TEXT_COLOR
	instance.TextScaled = true
	instance.Text = text
	instance.Parent = parent
	return instance
end

---------------------------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------------------------

local function build(playerGui: PlayerGui): ScreenGui
	local screen = Instance.new("ScreenGui")
	screen.Name = "LaneHud"
	screen.ResetOnSpawn = false
	screen.IgnoreGuiInset = false
	screen.ScreenInsets = Enum.ScreenInsets.CoreUISafeInsets
	screen.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	screen.DisplayOrder = 5

	local scale = Instance.new("UIScale")
	scale.Parent = screen
	local function rescale()
		local camera = Workspace.CurrentCamera
		local height = if camera then camera.ViewportSize.Y else REFERENCE_HEIGHT
		scale.Scale = math.clamp(height / REFERENCE_HEIGHT, 1, MAX_SCALE)
	end
	rescale()
	local camera = Workspace.CurrentCamera
	if camera then
		camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
	end

	-- HP pips, top left.
	local health = panel("Health", UDim2.fromOffset(20 + GameConfig.Player.hpPips * 22, 32), UDim2.fromOffset(8, 8), Vector2.zero, screen)
	local pipLayout = Instance.new("UIListLayout")
	pipLayout.FillDirection = Enum.FillDirection.Horizontal
	pipLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	pipLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	pipLayout.Padding = UDim.new(0, 6)
	pipLayout.Parent = health
	table.clear(pips)
	for index = 1, GameConfig.Player.hpPips do
		local pip = Instance.new("Frame")
		pip.Name = `Pip{index}`
		pip.LayoutOrder = index
		pip.Size = UDim2.fromOffset(16, 16)
		pip.BackgroundColor3 = Palette.Harm
		pip.BorderSizePixel = 0
		corner(pip, UDim.new(0.5, 0))
		pip.Parent = health
		table.insert(pips, pip)
	end

	-- Depth / room and the XP bar, top centre.
	local progress = panel("Progress", UDim2.fromOffset(200, 40), UDim2.new(0.5, 0, 0, 8), Vector2.new(0.5, 0), screen)
	local room = label("Room", "", UDim2.new(1, -16, 0, 18), progress)
	room.Position = UDim2.fromOffset(8, 3)
	roomLabel = room
	local bar = Instance.new("Frame")
	bar.Name = "XpBar"
	bar.Size = UDim2.new(1, -16, 0, 8)
	bar.Position = UDim2.new(0, 8, 1, -12)
	bar.BackgroundColor3 = EMPTY_PIP
	bar.BorderSizePixel = 0
	corner(bar, UDim.new(0.5, 0))
	bar.Parent = progress
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Palette.Xp
	fill.BorderSizePixel = 0
	corner(fill, UDim.new(0.5, 0))
	fill.Parent = bar
	xpFill = fill

	-- Haul and pause, top right.
	local pause = Instance.new("TextButton")
	pause.Name = "Pause"
	pause.Size = UDim2.fromOffset(TOUCH, TOUCH)
	pause.Position = UDim2.new(1, -8, 0, 8)
	pause.AnchorPoint = Vector2.new(1, 0)
	pause.BackgroundColor3 = PANEL_COLOR
	pause.BackgroundTransparency = PANEL_TRANSPARENCY
	pause.BorderSizePixel = 0
	pause.AutoButtonColor = true
	pause.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
	pause.TextColor3 = TEXT_COLOR
	pause.TextSize = 18
	pause.Text = "II"
	corner(pause, UDim.new(0, 10))
	pause.Parent = screen
	pause.Activated:Connect(function()
		local current = state
		if current == nil or current.phase == "Ended" then
			return
		end
		Network.SetPaused:fire({ paused = not current.paused })
	end)
	pauseButton = pause

	local haul = panel("Haul", UDim2.fromOffset(96, 32), UDim2.new(1, -(16 + TOUCH), 0, 8), Vector2.new(1, 0), screen)
	local haulText = label("Amount", "◆ 0", UDim2.new(1, -16, 1, -8), haul)
	haulText.Position = UDim2.fromOffset(8, 4)
	haulText.TextColor3 = Palette.Gem
	haulText.TextXAlignment = Enum.TextXAlignment.Right
	haulLabel = haulText

	-- Modifier badges, down the left gutter.
	local column = Instance.new("ScrollingFrame")
	column.Name = "Modifiers"
	column.BackgroundTransparency = 1
	column.BorderSizePixel = 0
	column.Position = UDim2.fromOffset(8, 48)
	column.Size = UDim2.fromOffset(BADGE_SIZE + 8, HudConfig.modifierSlots * (BADGE_SIZE + BADGE_GAP))
	column.CanvasSize = UDim2.new()
	column.AutomaticCanvasSize = Enum.AutomaticSize.Y
	column.ScrollBarThickness = 3
	column.ScrollingDirection = Enum.ScrollingDirection.Y
	column.Parent = screen
	local columnLayout = Instance.new("UIListLayout")
	columnLayout.FillDirection = Enum.FillDirection.Vertical
	columnLayout.Padding = UDim.new(0, BADGE_GAP)
	columnLayout.SortOrder = Enum.SortOrder.LayoutOrder
	columnLayout.Parent = column
	local columnPadding = Instance.new("UIPadding")
	columnPadding.PaddingTop = UDim.new(0, 3)
	columnPadding.PaddingLeft = UDim.new(0, 3)
	columnPadding.Parent = column
	badgeColumn = column

	-- Centre banner.
	local title = label("Banner", "", UDim2.fromOffset(360, 56), screen)
	title.AnchorPoint = Vector2.new(0.5, 0.5)
	title.Position = UDim2.fromScale(0.5, 0.36)
	title.FontFace = Font.fromEnum(Enum.Font.GothamBlack)
	title.TextTransparency = 1
	title.Visible = false
	local titleStroke = Instance.new("UIStroke")
	titleStroke.Thickness = 2
	titleStroke.Color = Color3.new(0, 0, 0)
	titleStroke.Transparency = 0.4
	titleStroke.Parent = title
	banner = title
	local subtitle = label("Subtitle", "", UDim2.new(1, 0, 0, 22), title)
	subtitle.Position = UDim2.new(0, 0, 1, 4)
	subtitle.FontFace = Font.fromEnum(Enum.Font.GothamMedium)
	subtitle.TextColor3 = MUTED_TEXT
	subtitle.TextTransparency = 1
	bannerSubtitle = subtitle

	screen.Parent = playerGui
	return screen
end

---------------------------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------------------------

local function showBanner(text: string, subtitle: string, color: Color3, seconds: number?)
	local title, sub = banner, bannerSubtitle
	if title == nil or sub == nil then
		return
	end
	bannerToken += 1
	local token = bannerToken
	title.Text = text
	title.TextColor3 = color
	sub.Text = subtitle
	title.Visible = true
	title.TextTransparency = 1
	sub.TextTransparency = 1
	TweenService:Create(title, BANNER_TWEEN, { TextTransparency = 0 }):Play()
	TweenService:Create(sub, BANNER_TWEEN, { TextTransparency = 0 }):Play()
	if seconds then
		task.delay(seconds, function()
			if bannerToken == token then
				HudController.hideBanner()
			end
		end)
	end
end

function HudController.hideBanner()
	bannerToken += 1
	local title = banner
	if title then
		title.Visible = false
	end
end

local function setHealth(pipsLeft: number, maxPips: number)
	for index, pip in pips do
		pip.Visible = index <= maxPips
		pip.BackgroundColor3 = if index <= pipsLeft then Palette.Harm else EMPTY_PIP
	end
end

local function setXp(fraction: number)
	local fill = xpFill
	if fill then
		TweenService:Create(fill, BAR_TWEEN, { Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1) }):Play()
	end
end

local function setHaul(haul: number)
	local text = haulLabel
	if text then
		text.Text = `◆ {haul}`
	end
end

local function makeBadge(entry: Network.LoadoutEntry, order: number): Frame
	local definition = ModifierDefinitions.get(entry.id)
	local color = rarityColor(definition.rarity)
	local badge = Instance.new("Frame")
	badge.Name = definition.id
	badge.LayoutOrder = order
	badge.Size = UDim2.fromOffset(BADGE_SIZE, BADGE_SIZE)
	badge.BackgroundColor3 = PANEL_COLOR
	badge.BackgroundTransparency = 0.1
	badge.BorderSizePixel = 0
	corner(badge, UDim.new(0, 8))
	local border = stroke(badge, if entry.fusionReady then Palette.Fusion else color, if entry.fusionReady then 3 else 2)
	local text = label("Badge", definition.badge, UDim2.new(1, -8, 1, -8), badge)
	text.Position = UDim2.fromOffset(4, 4)
	text.TextColor3 = color
	if entry.stacks > 1 then
		local count = label("Stacks", `x{entry.stacks}`, UDim2.fromOffset(18, 12), badge)
		count.AnchorPoint = Vector2.new(1, 1)
		count.Position = UDim2.new(1, -2, 1, -1)
		count.TextColor3 = TEXT_COLOR
	end
	if entry.fusionReady then
		-- The gold pulse: this card can fuse with the next copy picked.
		TweenService:Create(
			border,
			TweenInfo.new(0.7, Enum.EasingStyle.Sine, Enum.EasingDirection.InOut, -1, true),
			{ Transparency = 0.6 }
		):Play()
	end
	return badge
end

local function setLoadout(modifiers: { Network.LoadoutEntry }, fusion: Network.FusionEvent?)
	local column = badgeColumn
	if column == nil then
		return
	end
	for _, child in column:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	for index, entry in modifiers do
		makeBadge(entry, index).Parent = column
	end
	if fusion then
		local fused = ModifierDefinitions.get(fusion.result)
		showBanner(`{string.upper(fused.label)}!`, fused.effectText, Palette.Fusion, GameConfig.Presentation.fusionFlashSeconds + 0.8)
	end
end

local function roomText(current: Network.RunState): string
	return `DEPTH {current.depth} · ROOM {current.roomIndex}/{current.roomCount}`
end

local PHASE_BANNERS: { [string]: { text: string, color: Color3 } } = {
	RoomClear = { text = "ROOM CLEAR", color = Palette.Gem },
}

function HudController.applyState(current: Network.RunState)
	local previous = state
	state = current
	local room = roomLabel
	if room then
		room.Text = roomText(current)
	end
	local pause = pauseButton
	if pause then
		pause.Text = if current.paused then "▶" else "II"
		pause.Visible = current.phase ~= "Ended"
	end
	local phase: Types.RunPhase = current.phase
	local changed = previous == nil or previous.phase ~= phase or previous.paused ~= current.paused
	if not changed then
		return
	end
	if current.paused then
		showBanner("PAUSED", "Tap ▶ to resume", TEXT_COLOR, nil)
		return
	end
	local phaseBanner = PHASE_BANNERS[phase]
	if phaseBanner then
		showBanner(phaseBanner.text, roomText(current), phaseBanner.color, GameConfig.Rooms.clearDelaySeconds)
	elseif phase == "Combat" and previous and (previous.paused or previous.phase == "Ended") then
		HudController.hideBanner()
	elseif phase == "Combat" and previous and previous.roomIndex ~= current.roomIndex then
		showBanner(`ROOM {current.roomIndex}`, `DEPTH {current.depth}`, TEXT_COLOR, 1)
	end
end

function HudController.applySnapshot(snapshot: Network.RunSnapshot)
	HudController.applyState(snapshot.state)
	setHealth(snapshot.health.pips, snapshot.health.maxPips)
	setXp(snapshot.xp.fraction)
	setHaul(snapshot.haul)
	setLoadout(snapshot.loadout, nil)
end

function HudController.init()
	local player = Players.LocalPlayer
	local playerGui = player:WaitForChild("PlayerGui") :: PlayerGui
	gui = build(playerGui)

	Network.HealthChanged:connect(function(payload: Network.HealthChangedPayload)
		if payload.userId == player.UserId then
			setHealth(payload.pips, payload.maxPips)
		end
	end)
	Network.XpChanged:connect(function(payload: Network.XpChangedPayload)
		setXp(payload.fraction)
	end)
	Network.HaulChanged:connect(function(payload: Network.HaulChangedPayload)
		setHaul(payload.haul)
	end)
	Network.LoadoutChanged:connect(function(payload: Network.LoadoutChangedPayload)
		if payload.userId == player.UserId then
			setLoadout(payload.modifiers, payload.fusion)
		end
	end)
	Network.RunEnded:connect(function(payload: Network.RunEndedPayload)
		local banked = payload.outcome == "Banked"
		local title = if banked then "LOOT BANKED" else "RUN OVER"
		local color = if banked then Palette.Gem else Palette.Harm
		showBanner(title, `Banked ◆ {payload.haulBanked} · Lost ◆ {payload.haulLost} · Best combo {payload.bestCombo}`, color, GameConfig.Run.restartDelaySeconds)
	end)
end

-- The HUD's ScreenGui (nil before init).
function HudController.getGui(): ScreenGui?
	return gui
end

table.freeze(HudController)
return HudController
