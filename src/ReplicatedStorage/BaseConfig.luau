-- The home base: a 4x4 grid of tiles above the pit where each player raises twelve buildings
-- with the coins they bring home. Buildings are where earnable power lives now (the Armory's
-- stat upgrades moved here), plus the offline workers and the trophies friends come to see.
-- Pure data and pure helpers; BaseService (server) is the only thing that spends or pays.
--
-- Building levels are store-owned: they sit in the profile's MetaUpgrades under each building's
-- id and change only through PlayerDataService's purchase path. A building's shown level is its
-- StartLevel plus the levels bought, so the Hearth everyone starts with needs no purchase.
local BaseConfig = {}

BaseConfig.GridSize = 4
BaseConfig.Tiles = BaseConfig.GridSize * BaseConfig.GridSize
-- Studs per tile, and the border of path around the grid inside the fence.
BaseConfig.TileSize = 12
BaseConfig.Border = 6

-- Offline workers: the Salvage Yard fills while you are away, up to a cap, and is emptied by a
-- claim. One active run is worth several claims: a full yard holds a few hundred coins at most,
-- about what one good descent pays.
BaseConfig.Offline = {
	BaseCapHours = 8,
	-- The cap can never pass this, whatever adds to it.
	MaxCapHours = 12,
	-- A claim smaller than this is not worth a write.
	MinClaim = 1,
}

-- Friend visits. Cheering someone's base once a day pays both of you a little; the owner is paid
-- for at most MaxPaidCheers a day and a visitor for at most MaxPaidVisits.
BaseConfig.Visits = {
	CheerCoins = 15, -- to the base's owner
	VisitCoins = 10, -- to the visitor
	MaxPaidCheers = 10,
	MaxPaidVisits = 5,
}

-- Plots in the Outpost: two rows beyond the hall's north wall, reached by teleport. A server
-- should be set to at most this many players (docs/RELEASE_CHECKLIST.md); anyone past it still
-- has a base, managed from the panel, just no plot to walk around.
BaseConfig.Plots = {
	Count = 8,
	Columns = 4,
	Spacing = 80,
	-- From RunConfig.LobbyPosition to the centre of the plot rows.
	Offset = Vector3.new(0, 0, -280),
	RowGap = 90,
}

-- How a plot looks. Profile.Base.Theme and Profile.Base.Sign hold one of these ids ("" is the
-- default); the cosmetics that unlock them are sold in ShopConfig (Kind "Theme" / "Sign").
BaseConfig.Themes = {
	Default = {
		Title = "Frontier",
		Ground = Color3.fromRGB(84, 96, 70),
		Path = Color3.fromRGB(120, 108, 88),
		Fence = Color3.fromRGB(96, 72, 52),
		Trim = Color3.fromRGB(255, 196, 120),
	},
	Moss = {
		Title = "Mossy Ruins",
		Ground = Color3.fromRGB(58, 92, 62),
		Path = Color3.fromRGB(96, 110, 96),
		Fence = Color3.fromRGB(80, 90, 82),
		Trim = Color3.fromRGB(140, 236, 168),
	},
	Frost = {
		Title = "Frost Camp",
		Ground = Color3.fromRGB(196, 214, 230),
		Path = Color3.fromRGB(150, 170, 196),
		Fence = Color3.fromRGB(110, 130, 160),
		Trim = Color3.fromRGB(170, 230, 255),
	},
	Gilded = {
		Title = "Gilded Outpost",
		Ground = Color3.fromRGB(70, 56, 40),
		Path = Color3.fromRGB(150, 120, 70),
		Fence = Color3.fromRGB(200, 160, 70),
		Trim = Color3.fromRGB(255, 214, 90),
	},
}

BaseConfig.Signs = {
	Default = { Title = "Plank", Back = Color3.fromRGB(70, 52, 38), Text = Color3.fromRGB(250, 236, 210) },
	Slate = { Title = "Slate", Back = Color3.fromRGB(34, 38, 50), Text = Color3.fromRGB(150, 220, 255) },
	Banner = { Title = "Explorer Banner", Back = Color3.fromRGB(28, 70, 120), Text = Color3.fromRGB(255, 222, 120) },
}

function BaseConfig.ThemeOf(themeId)
	return BaseConfig.Themes[themeId] or BaseConfig.Themes.Default
end

function BaseConfig.SignOf(signId)
	return BaseConfig.Signs[signId] or BaseConfig.Signs.Default
end

-- The Trophy Hall shows one pillar per claimed achievement, up to this many.
BaseConfig.MaxTrophies = 8

-- Hearth level gates what can be built: HearthLevels[n] is the Hearth level building level n
-- needs. Role groups buildings in the panel: Power (run stats), Economy, Heart.
BaseConfig.Buildings = {
	{
		Id = "Hearth",
		Title = "Camp Hearth",
		Label = "Heart of camp",
		Description = "The heart of your camp. Raising it unlocks new buildings and higher levels.",
		Role = "Heart",
		Color = Color3.fromRGB(255, 170, 90),
		StartLevel = 1,
		-- Where it stands until moved: near the middle of the grid.
		DefaultTile = 6,
		Costs = { 200, 500, 1000, 1800 },
		HearthLevels = { 1, 2, 3, 4 },
	},
	{
		Id = "SalvageYard",
		Title = "Salvage Yard",
		Label = "Earns while away",
		Description = "Workers sort salvage while you are away. Claim the coins when you come back.",
		Role = "Economy",
		Color = Color3.fromRGB(226, 196, 120),
		Costs = { 60, 150, 300, 550, 900 },
		HearthLevels = { 1, 1, 2, 3, 4 },
		Production = { 10, 15, 20, 25, 30 }, -- coins per hour at each level
	},
	{
		Id = "Storehouse",
		Title = "Storehouse",
		Label = "Holds more salvage",
		Description = "The Salvage Yard keeps working one hour longer per level before it fills up.",
		Role = "Economy",
		Color = Color3.fromRGB(170, 140, 110),
		Costs = { 250, 600 },
		HearthLevels = { 2, 3 },
		CapHours = 1, -- per level
	},
	{
		Id = "Forge",
		Title = "Forge",
		Label = "Harder hitting orbs",
		Description = "Every shot deals 0.05 more damage per level.",
		Role = "Power",
		Color = Color3.fromRGB(255, 120, 70),
		Costs = { 120, 260, 450, 700, 1000 },
		HearthLevels = { 1, 2, 2, 3, 4 },
		Effect = { Stat = "Damage", PerLevel = 0.05 },
	},
	{
		Id = "Infirmary",
		Title = "Infirmary",
		Label = "More max health",
		Description = "+10 maximum health at the start of every run, per level.",
		Role = "Power",
		Color = Color3.fromRGB(140, 236, 168),
		Costs = { 80, 160, 260, 380, 520 },
		HearthLevels = { 1, 1, 2, 3, 4 },
		Effect = { Stat = "MaxHealthBonus", PerLevel = 10 },
	},
	{
		Id = "Bootworks",
		Title = "Bootworks",
		Label = "Faster on foot",
		Description = "+1 walk speed at the start of every run, per level.",
		Role = "Power",
		Color = Color3.fromRGB(120, 200, 255),
		Costs = { 60, 140, 240 },
		HearthLevels = { 1, 2, 3 },
		Effect = { Stat = "MoveSpeedBonus", PerLevel = 1 },
	},
	{
		Id = "RailLab",
		Title = "Rail Lab",
		Label = "Faster flying shots",
		Description = "Shots fly 2% faster per level.",
		Role = "Power",
		Color = Color3.fromRGB(120, 235, 255),
		Costs = { 80, 160, 280, 420, 600 },
		HearthLevels = { 1, 2, 2, 3, 4 },
		Effect = { Stat = "SpeedMultiplier", PerLevel = 0.02 },
	},
	{
		Id = "Springhouse",
		Title = "Springhouse",
		Label = "Heal between fights",
		Description = "+0.5 health per second of regeneration between fights, per level.",
		Role = "Power",
		Color = Color3.fromRGB(110, 255, 200),
		Costs = { 120, 240, 400, 600 },
		HearthLevels = { 2, 2, 3, 4 },
		Effect = { Stat = "RegenBonus", PerLevel = 0.5 },
	},
	{
		Id = "MagnetMast",
		Title = "Magnet Mast",
		Label = "Pulls coins closer",
		Description = "+3 studs of reach when pulling in coins, per level.",
		Role = "Power",
		Color = Color3.fromRGB(255, 214, 120),
		Costs = { 100, 220, 380 },
		HearthLevels = { 1, 2, 3 },
		Effect = { Stat = "MagnetBonus", PerLevel = 3 },
	},
	{
		Id = "OrbKiln",
		Title = "Orb Kiln",
		Label = "Orbs roll home",
		Description = "Dropped orbs roll back to you 6% faster per level.",
		Role = "Power",
		Color = Color3.fromRGB(226, 160, 255),
		Costs = { 150, 300, 500, 750 },
		HearthLevels = { 2, 3, 3, 4 },
		Effect = { Stat = "OrbReturnMultiplier", PerLevel = 0.06 },
	},
	{
		Id = "TrainingYard",
		Title = "Training Yard",
		Label = "More XP earned",
		Description = "+5% experience from every run, per level.",
		Role = "Economy",
		Color = Color3.fromRGB(196, 202, 216),
		Costs = { 150, 320, 550, 800 },
		HearthLevels = { 1, 2, 3, 4 },
		Effect = { Stat = "XpMultiplier", PerLevel = 0.05 },
	},
	{
		Id = "TrophyHall",
		Title = "Trophy Hall",
		Label = "Shows your trophies",
		Description = "Shows off your achievements to visitors, and earns +5% coins per level.",
		Role = "Economy",
		Color = Color3.fromRGB(255, 206, 72),
		Costs = { 250, 500, 900 },
		HearthLevels = { 2, 3, 4 },
		Effect = { Stat = "RewardMultiplier", PerLevel = 0.05 },
	},
}

local byId = {}
for index, building in BaseConfig.Buildings do
	assert(byId[building.Id] == nil, "duplicate building id " .. building.Id)
	building.Order = index
	building.StartLevel = building.StartLevel or 0
	byId[building.Id] = building
end

function BaseConfig.Get(buildingId)
	return byId[buildingId]
end

-- Highest level a building can reach.
function BaseConfig.MaxLevel(building)
	return building.StartLevel + #building.Costs
end

-- The level shown for `bought` purchased levels, clamped to what exists.
local function levelFrom(building, bought)
	bought = math.clamp(math.floor(tonumber(bought) or 0), 0, #building.Costs)
	return building.StartLevel + bought
end

-- A building's level from the profile's MetaUpgrades.
function BaseConfig.LevelOf(levels, buildingId)
	local building = byId[buildingId]
	if not building then
		return 0
	end
	return levelFrom(building, type(levels) == "table" and levels[buildingId] or 0)
end

-- The price of reaching `level`, or nil past the max (or for a level that is free).
function BaseConfig.CostFor(building, level)
	return building.Costs[level - building.StartLevel]
end

-- The Hearth level needed for `level`, or nil past the max.
function BaseConfig.HearthNeeded(building, level)
	return building.HearthLevels[level - building.StartLevel]
end

-- Run stat deltas from built levels: { [stat] = amount }. Unknown ids are ignored and levels are
-- clamped, so a stale or tampered profile can never grant more than the base sells.
function BaseConfig.ComputeBonuses(levels)
	local bonuses = {}
	for _, building in BaseConfig.Buildings do
		local effect = building.Effect
		if effect then
			local level = BaseConfig.LevelOf(levels, building.Id)
			if level > 0 then
				bonuses[effect.Stat] = (bonuses[effect.Stat] or 0) + effect.PerLevel * level
			end
		end
	end
	return bonuses
end

-- Coins per hour from the Salvage Yard at its current level.
function BaseConfig.ProductionPerHour(levels)
	local building = byId.SalvageYard
	local level = BaseConfig.LevelOf(levels, "SalvageYard")
	return level > 0 and building.Production[level] or 0
end

-- Hours the yard fills for before it stops. extraHours comes from passes.
function BaseConfig.CapHours(levels, extraHours)
	local hours = BaseConfig.Offline.BaseCapHours
		+ BaseConfig.LevelOf(levels, "Storehouse") * byId.Storehouse.CapHours
		+ math.max(tonumber(extraHours) or 0, 0)
	return math.min(hours, BaseConfig.Offline.MaxCapHours)
end

-- Coins waiting in the yard: production over the time since the last claim, capped.
function BaseConfig.OfflineCoins(levels, lastClaimAt, now, extraHours)
	local perHour = BaseConfig.ProductionPerHour(levels)
	if perHour <= 0 or type(lastClaimAt) ~= "number" or lastClaimAt <= 0 then
		return 0, 0
	end
	local cap = BaseConfig.CapHours(levels, extraHours) * 3600
	local elapsed = math.clamp((tonumber(now) or 0) - lastClaimAt, 0, cap)
	return math.floor(perHour * elapsed / 3600), elapsed / cap
end

--// the grid ---------------------------------------------------------------------

function BaseConfig.ValidTile(tile)
	return type(tile) == "number" and tile == math.floor(tile) and tile >= 1 and tile <= BaseConfig.Tiles
end

-- Column and row (1-based) of a tile.
function BaseConfig.TileCoords(tile)
	local index = tile - 1
	return index % BaseConfig.GridSize + 1, math.floor(index / BaseConfig.GridSize) + 1
end

-- A tile's centre relative to the plot's centre, on the ground plane (X, Z).
function BaseConfig.TileOffset(tile)
	local column, row = BaseConfig.TileCoords(tile)
	local half = (BaseConfig.GridSize + 1) / 2
	return Vector2.new((column - half) * BaseConfig.TileSize, (row - half) * BaseConfig.TileSize)
end

-- Plot footprint, fence to fence.
function BaseConfig.PlotSize()
	return BaseConfig.GridSize * BaseConfig.TileSize + BaseConfig.Border * 2
end

-- The world centre of plot `index` (1..Plots.Count), at floor level.
function BaseConfig.PlotCentre(index, lobbyPosition)
	local plots = BaseConfig.Plots
	local column = (index - 1) % plots.Columns
	local row = math.floor((index - 1) / plots.Columns)
	local x = (column - (plots.Columns - 1) / 2) * plots.Spacing
	local z = (row - 0.5) * plots.RowGap
	return lobbyPosition + plots.Offset + Vector3.new(x, 0, z)
end

-- The layout cleaned against the built buildings: every built building on a distinct valid
-- tile, nothing placed that is not built. Buildings with no tile (bought on another server, or
-- a tampered layout) take the first free tiles in catalogue order.
function BaseConfig.NormaliseLayout(layout, levels)
	local result, taken = {}, {}
	layout = type(layout) == "table" and layout or {}
	for _, building in BaseConfig.Buildings do
		local tile = layout[building.Id]
		if BaseConfig.LevelOf(levels, building.Id) > 0 and BaseConfig.ValidTile(tile) and not taken[tile] then
			result[building.Id] = tile
			taken[tile] = true
		end
	end
	for _, building in BaseConfig.Buildings do
		local preferred = building.DefaultTile
		if BaseConfig.LevelOf(levels, building.Id) > 0 and result[building.Id] == nil and preferred and not taken[preferred] then
			result[building.Id] = preferred
			taken[preferred] = true
		end
	end
	for _, building in BaseConfig.Buildings do
		if BaseConfig.LevelOf(levels, building.Id) > 0 and result[building.Id] == nil then
			for tile = 1, BaseConfig.Tiles do
				if not taken[tile] then
					result[building.Id] = tile
					taken[tile] = true
					break
				end
			end
		end
	end
	return result
end

-- The building on `tile`, or nil.
function BaseConfig.BuildingAt(layout, tile)
	for buildingId, placed in layout do
		if placed == tile then
			return buildingId
		end
	end
	return nil
end

-- What the next coins should go to: the cheapest buildable level, for the results screen's
-- "your haul builds" preview. Returns { Id, Title, Level, Cost } or nil when everything is maxed
-- or locked behind the Hearth.
function BaseConfig.NextBuild(levels)
	local hearth = BaseConfig.LevelOf(levels, "Hearth")
	local best = nil
	for _, building in BaseConfig.Buildings do
		local nextLevel = BaseConfig.LevelOf(levels, building.Id) + 1
		local cost = BaseConfig.CostFor(building, nextLevel)
		local needed = BaseConfig.HearthNeeded(building, nextLevel)
		if cost and needed and needed <= hearth and (not best or cost < best.Cost) then
			best = { Id = building.Id, Title = building.Title, Level = nextLevel, Cost = cost }
		end
	end
	return best
end

return BaseConfig
