-- The Journal: achievements with progress and Claim buttons, and the Codex of every card and
-- enemy found so far. Drawn from the ProfileSync payload with the same AchievementConfig maths
-- the server uses, so it is always in step; every claim is still checked on the server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local AchievementConfig = require(ReplicatedStorage:WaitForChild("AchievementConfig"))
local EnemyConfig = require(ReplicatedStorage:WaitForChild("EnemyConfig"))
local UiConfig = require(ReplicatedStorage:WaitForChild("UiConfig"))
local UpgradeConfig = require(ReplicatedStorage:WaitForChild("UpgradeConfig"))
local UiTheme = require(script.Parent.UiTheme)

local JournalView = {}
JournalView.__index = JournalView

local ROW_HEIGHT = 78
local TABS = { "Achievements", "Codex" }

local function scrollingList(name, parent)
	local list = Instance.new("ScrollingFrame")
	list.Name = name
	list.BackgroundTransparency = 1
	list.BorderSizePixel = 0
	list.Position = UDim2.new(0, 0, 0, 56)
	list.Size = UDim2.new(1, 0, 1, -56)
	list.CanvasSize = UDim2.new()
	list.AutomaticCanvasSize = Enum.AutomaticSize.Y
	list.ScrollBarThickness = 4
	list.ScrollingDirection = Enum.ScrollingDirection.Y
	list.Parent = parent
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 6)
	layout.SortOrder = Enum.SortOrder.LayoutOrder
	layout.Parent = list
	return list
end

-- How many cards and enemy kinds a profile has found, out of how many exist.
function JournalView.CodexCounts(profile)
	local codex = type(profile) == "table" and type(profile.Codex) == "table" and profile.Codex or {}
	local cards, enemies = 0, 0
	local mainCards = UpgradeConfig.MainCards()
	for _, card in mainCards do
		if type(codex.Cards) == "table" and codex.Cards[card.Id] then
			cards += 1
		end
	end
	for _, archetypeId in AchievementConfig.EnemyIds do
		if type(codex.Enemies) == "table" and (tonumber(codex.Enemies[archetypeId]) or 0) > 0 then
			enemies += 1
		end
	end
	return cards, #mainCards, enemies, #AchievementConfig.EnemyIds
end

function JournalView.new(playerGui, onClaim)
	local self = setmetatable({}, JournalView)
	self._onClaim = onClaim
	self._tab = "Achievements"
	self.modal = UiTheme.modal("RicochetJournal", playerGui, "JOURNAL", Vector2.new(580, 600))
	local content = self.modal.content

	local tabs = Instance.new("Frame")
	tabs.Name = "Tabs"
	tabs.BackgroundTransparency = 1
	tabs.Size = UDim2.new(1, 0, 0, UiConfig.MinTouchTarget)
	tabs.Parent = content
	local tabLayout = Instance.new("UIListLayout")
	tabLayout.FillDirection = Enum.FillDirection.Horizontal
	tabLayout.Padding = UDim.new(0, 8)
	tabLayout.Parent = tabs
	self.tabButtons = {}
	for _, tab in TABS do
		local button = UiTheme.button(tab, tabs, string.upper(tab))
		button.Size = UDim2.new(0.5, -4, 1, 0)
		button.TextSize = UiConfig.Text.Small + 2
		button.Activated:Connect(function()
			self:ShowTab(tab)
		end)
		self.tabButtons[tab] = button
	end

	self.achievementList = scrollingList("Achievements", content)
	self.codexList = scrollingList("Codex", content)
	self.achievementRows = {}
	self.codexRows = {}
	self:ShowTab("Achievements")
	return self
end

function JournalView:ShowTab(tab)
	self._tab = tab
	self.achievementList.Visible = tab == "Achievements"
	self.codexList.Visible = tab == "Codex"
	for name, button in self.tabButtons do
		button.BackgroundColor3 = name == tab and UiConfig.Colors.Accent or UiConfig.Colors.PanelRaised
		button.TextColor3 = name == tab and UiConfig.Colors.PrimaryText or UiConfig.Colors.Text
	end
end

function JournalView:_achievementRow(index)
	local existing = self.achievementRows[index]
	if existing then
		return existing
	end
	local frame = UiTheme.panel("Achievement" .. index, self.achievementList)
	frame.LayoutOrder = index
	frame.BackgroundColor3 = UiConfig.Colors.PanelRaised
	frame.BackgroundTransparency = 0
	frame.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
	UiTheme.padding(frame, 8)
	local title = UiTheme.label("Title", frame, "", UiConfig.Text.Hud)
	title.Font = UiConfig.FontBold
	title.Size = UDim2.new(1, -130, 0, 20)
	local body = UiTheme.label("Body", frame, "", UiConfig.Text.Small, UiConfig.Colors.TextMuted)
	body.Position = UDim2.new(0, 0, 0, 20)
	body.Size = UDim2.new(1, -130, 0, 18)
	local track, fill = UiTheme.bar("Progress", frame, UiConfig.Colors.Gold)
	track.Position = UDim2.new(0, 0, 0, 42)
	track.Size = UDim2.new(1, -130, 0, 14)
	local count = UiTheme.label("Count", track, "", UiConfig.Text.Small - 2, UiConfig.Colors.Text)
	count.Size = UDim2.fromScale(1, 1)
	count.TextXAlignment = Enum.TextXAlignment.Center
	count.ZIndex = 3
	local button = UiTheme.button("Claim", frame, "", "Primary")
	button.AnchorPoint = Vector2.new(1, 0.5)
	button.Position = UDim2.new(1, 0, 0.5, 0)
	button.Size = UDim2.fromOffset(116, UiConfig.MinTouchTarget)
	button.TextSize = UiConfig.Text.Small
	local row = { title = title, body = body, fill = fill, count = count, button = button }
	button.Activated:Connect(function()
		if row.claimable and row.id then
			self._onClaim(row.id)
		end
	end)
	self.achievementRows[index] = row
	return row
end

function JournalView:_codexRow(index, text, color)
	local label = self.codexRows[index]
	if not label then
		label = UiTheme.label("Entry" .. index, self.codexList, "", UiConfig.Text.Small + 1)
		label.LayoutOrder = index
		label.Size = UDim2.new(1, -8, 0, 20)
		label.TextTruncate = Enum.TextTruncate.AtEnd
		self.codexRows[index] = label
	end
	label.Text = text
	label.TextColor3 = color or UiConfig.Colors.Text
	label.Visible = true
	return label
end

-- profile is the ProfileSync payload.
function JournalView:SetProfile(profile)
	if type(profile) ~= "table" then
		return
	end
	for index, entry in AchievementConfig.Describe(profile) do
		local row = self:_achievementRow(index)
		row.id = entry.Id
		row.title.Text = entry.Title
		row.body.Text = string.format("%s  Reward: %d coins, %d XP", entry.Description, entry.Coins, entry.Xp)
		row.fill.Size = UDim2.fromScale(math.clamp(entry.Progress / math.max(entry.Target, 1), 0, 1), 1)
		row.count.Text = string.format("%d / %d", entry.Progress, entry.Target)
		row.claimable = entry.Complete and not entry.Claimed
		row.button.Text = entry.Claimed and "DONE" or (entry.Complete and "CLAIM" or "LOCKED")
		row.button.AutoButtonColor = row.claimable
		row.button.BackgroundColor3 = row.claimable and UiConfig.Colors.PrimaryButton or UiConfig.Colors.PanelRaised
		row.button.TextColor3 = row.claimable and UiConfig.Colors.PrimaryText
			or entry.Claimed and UiConfig.Colors.Health
			or UiConfig.Colors.TextMuted
	end

	-- The Codex: undiscovered entries stay hidden behind question marks.
	local codex = type(profile.Codex) == "table" and profile.Codex or {}
	local seenCards = type(codex.Cards) == "table" and codex.Cards or {}
	local kills = type(codex.Enemies) == "table" and codex.Enemies or {}
	local cards, cardTotal, enemies, enemyTotal = JournalView.CodexCounts(profile)
	local index = 0
	local function add(text, color)
		index += 1
		self:_codexRow(index, text, color)
	end
	add(string.format("ENEMIES  %d / %d", enemies, enemyTotal), UiConfig.Colors.Gold)
	for _, archetypeId in AchievementConfig.EnemyIds do
		local count = tonumber(kills[archetypeId]) or 0
		local archetype = EnemyConfig.Get(archetypeId)
		if count > 0 then
			add(string.format("  %s  -  %d defeated", archetype.DisplayName, count))
		else
			add("  ???", UiConfig.Colors.TextMuted)
		end
	end
	add(string.format("UPGRADE CARDS  %d / %d", cards, cardTotal), UiConfig.Colors.Gold)
	for _, card in UpgradeConfig.MainCards() do
		if seenCards[card.Id] then
			add(string.format("  %s  -  %s", card.Title, card.Description))
		else
			add(string.format("  ???  (%s)", card.Rarity), UiConfig.Colors.TextMuted)
		end
	end
	for extra = index + 1, #self.codexRows do
		self.codexRows[extra].Visible = false
	end
end

function JournalView:Open()
	self.modal.Open()
end

function JournalView:Close()
	self.modal.Close()
end

return JournalView
