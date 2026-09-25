-- The Outpost: a row of home-base plots beyond the hall, one per player on the server. Each plot
-- is a fenced 4x4 grid with a sign board, an entry pad whose prompt returns to the hall, and the
-- owner's buildings as procedural part stacks that grow a storey per level. The Hearth carries
-- the "Manage base" and "Cheer" prompts, so they move with it; an open plot has neither.
--
-- Built at runtime and display only: every decision about what is built, where and at what level
-- is BaseService's, and Refresh is handed a finished view of it.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local BaseConfig = require(ReplicatedStorage:WaitForChild("BaseConfig"))
local RoomConfig = require(ReplicatedStorage:WaitForChild("RoomConfig"))
local Signage = require(script.Parent.Signage)

local BaseBuilder = {}
BaseBuilder.__index = BaseBuilder

local STOREY = 2.2
-- Ground margin round the plots, and the invisible walls that keep everyone on it.
local MARGIN = 24
local BARRIER_HEIGHT = 80
local FENCE_HEIGHT = 2.4
local ENTRY_GAP = 10
local SOUTH = Vector3.new(0, 0, 1)
local LABEL_TEXT = Color3.fromRGB(240, 242, 250)

local function block(parent, name, size, position, color, material, solid)
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.Position = position
	part.Color = color
	part.Material = material or Enum.Material.SmoothPlastic
	part.Anchored = true
	part.CanCollide = solid == true
	part.CanQuery = false
	part.CanTouch = false
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function prompt(parent, name, action, object, distance)
	local proximity = Instance.new("ProximityPrompt")
	proximity.Name = name
	proximity.ActionText = action
	proximity.ObjectText = object
	proximity.HoldDuration = 0
	proximity.MaxActivationDistance = distance or 12
	proximity.RequiresLineOfSight = false
	proximity.Parent = parent
	return proximity
end

-- options:
--   onManage(player, owner): someone used a plot's "Manage base" prompt (owner may be nil).
--   onCheer(player, owner): someone used a plot's "Cheer" prompt.
--   onReturn(player): someone used an entry pad's prompt to go back to the hall.
function BaseBuilder.new(parent, lobbyPosition, options)
	options = options or {}
	local self = setmetatable({
		_origin = lobbyPosition,
		_options = options,
		_plots = {},
		_owners = {}, -- plot index -> player
		_plotOf = {}, -- player -> plot index
	}, BaseBuilder)

	local folder = Instance.new("Folder")
	folder.Name = "Outpost"
	folder.Parent = parent
	self.folder = folder
	self:_buildGround()
	for index = 1, BaseConfig.Plots.Count do
		self._plots[index] = self:_buildPlot(index)
	end
	return self
end

-- One ground slab under every plot, and a barrier round it.
function BaseBuilder:_buildGround()
	local plots = BaseConfig.Plots
	local rows = math.ceil(plots.Count / plots.Columns)
	local plotSize = BaseConfig.PlotSize()
	local spanX = (plots.Columns - 1) * plots.Spacing + plotSize + MARGIN * 2
	local spanZ = (rows - 1) * plots.RowGap + plotSize + MARGIN * 2
	-- PlotCentre spreads the rows evenly either side of Offset.
	local centre = self._origin + plots.Offset + Vector3.new(0, RoomConfig.FloorY, 0)
	local ground = block(self.folder, "OutpostGround", Vector3.new(spanX, 1, spanZ), centre - Vector3.new(0, 0.5, 0),
		Color3.fromRGB(54, 60, 50), Enum.Material.Ground, true)
	ground.CanQuery = true
	self.groundCentre = centre

	local barrier = Instance.new("Folder")
	barrier.Name = "Barrier"
	barrier.Parent = self.folder
	local y = RoomConfig.FloorY + BARRIER_HEIGHT / 2
	local walls = {
		{ "North", Vector3.new(spanX, BARRIER_HEIGHT, 2), Vector3.new(0, 0, -spanZ / 2 - 1) },
		{ "South", Vector3.new(spanX, BARRIER_HEIGHT, 2), Vector3.new(0, 0, spanZ / 2 + 1) },
		{ "East", Vector3.new(2, BARRIER_HEIGHT, spanZ), Vector3.new(spanX / 2 + 1, 0, 0) },
		{ "West", Vector3.new(2, BARRIER_HEIGHT, spanZ), Vector3.new(-spanX / 2 - 1, 0, 0) },
	}
	for _, wall in walls do
		local part = block(barrier, "OutpostWall" .. wall[1], wall[2], Vector3.new(centre.X, y, centre.Z) + wall[3],
			Color3.new(0, 0, 0), Enum.Material.SmoothPlastic, true)
		part.Transparency = 1
		part.CastShadow = false
	end
end

function BaseBuilder:_buildPlot(index)
	local centre = BaseConfig.PlotCentre(index, self._origin) + Vector3.new(0, RoomConfig.FloorY, 0)
	local theme = BaseConfig.ThemeOf("")
	local size = BaseConfig.PlotSize()
	local half = size / 2

	local folder = Instance.new("Folder")
	folder.Name = "Plot" .. index
	folder:SetAttribute("PlotIndex", index)
	folder.Parent = self.folder

	local ground = block(folder, "Ground", Vector3.new(size, 0.4, size), centre + Vector3.new(0, 0.2, 0),
		theme.Ground, Enum.Material.Grass, true)
	ground.CanQuery = true

	local tiles = Instance.new("Folder")
	tiles.Name = "Tiles"
	tiles.Parent = folder
	for tile = 1, BaseConfig.Tiles do
		local offset = BaseConfig.TileOffset(tile)
		local part = block(tiles, "Tile" .. tile, Vector3.new(BaseConfig.TileSize - 1, 0.1, BaseConfig.TileSize - 1),
			centre + Vector3.new(offset.X, 0.45, offset.Y), theme.Path, Enum.Material.Cobblestone)
		part:SetAttribute("Tile", tile)
	end

	-- The fence, with a gap on the south side where the entry pad is.
	local fence = Instance.new("Folder")
	fence.Name = "Fence"
	fence.Parent = folder
	local railY = FENCE_HEIGHT / 2 + 0.4
	local sideLength = (size - ENTRY_GAP) / 2
	local rails = {
		{ "North", Vector3.new(size, FENCE_HEIGHT, 0.6), Vector3.new(0, railY, -half) },
		{ "East", Vector3.new(0.6, FENCE_HEIGHT, size), Vector3.new(half, railY, 0) },
		{ "West", Vector3.new(0.6, FENCE_HEIGHT, size), Vector3.new(-half, railY, 0) },
		{ "SouthWest", Vector3.new(sideLength, FENCE_HEIGHT, 0.6), Vector3.new(-half + sideLength / 2, railY, half) },
		{ "SouthEast", Vector3.new(sideLength, FENCE_HEIGHT, 0.6), Vector3.new(half - sideLength / 2, railY, half) },
	}
	for _, rail in rails do
		block(fence, "Rail" .. rail[1], rail[2], centre + rail[3], theme.Fence, Enum.Material.WoodPlanks, true)
	end

	local entry = block(folder, "EntryPad", Vector3.new(ENTRY_GAP - 2, 0.3, BaseConfig.Border - 1),
		centre + Vector3.new(0, 0.55, half - BaseConfig.Border / 2), theme.Trim, Enum.Material.Neon)
	local returnPrompt = prompt(entry, "ReturnPrompt", "Back to the hall", "Outpost", 10)
	returnPrompt.Triggered:Connect(function(player)
		if self._options.onReturn then
			self._options.onReturn(player)
		end
	end)

	-- The sign stands outside the fence, facing the path.
	local signStyle = BaseConfig.SignOf("")
	local sign = Signage.Board(folder, "Sign", Vector3.new(14, 2.6, 0.3),
		centre + Vector3.new(0, 4.2, half + 2.5), SOUTH, "OPEN PLOT", signStyle.Text, signStyle.Back)
	block(folder, "SignPostWest", Vector3.new(0.5, 5.6, 0.5), centre + Vector3.new(-6.5, 2.8, half + 2.6),
		theme.Fence, Enum.Material.WoodPlanks, true)
	block(folder, "SignPostEast", Vector3.new(0.5, 5.6, 0.5), centre + Vector3.new(6.5, 2.8, half + 2.6),
		theme.Fence, Enum.Material.WoodPlanks, true)

	local buildings = Instance.new("Folder")
	buildings.Name = "Buildings"
	buildings.Parent = folder

	return {
		index = index,
		folder = folder,
		centre = centre,
		ground = ground,
		tiles = tiles,
		fence = fence,
		entry = entry,
		sign = sign,
		buildings = buildings,
	}
end

-- Gives the player the first free plot. Returns its index, or nil when every plot is taken (the
-- base still works from the panel). Assigning an already assigned player returns their plot.
function BaseBuilder:Assign(player)
	local existing = self._plotOf[player]
	if existing then
		return existing
	end
	for index = 1, #self._plots do
		if not self._owners[index] then
			self._owners[index] = player
			self._plotOf[player] = index
			local plot = self._plots[index]
			plot.folder:SetAttribute("OwnerUserId", player.UserId)
			player:SetAttribute("PlotIndex", index)
			Signage.SetText(plot.sign, string.upper(player.Name) .. "'S OUTPOST")
			return index
		end
	end
	return nil
end

-- Frees the player's plot and clears it back to an open plot.
function BaseBuilder:Release(player)
	local index = self._plotOf[player]
	if not index then
		return
	end
	self._plotOf[player] = nil
	self._owners[index] = nil
	local plot = self._plots[index]
	plot.buildings:ClearAllChildren()
	plot.folder:SetAttribute("OwnerUserId", nil)
	self:_applyStyle(plot, "", "")
	Signage.SetText(plot.sign, "OPEN PLOT")
	player:SetAttribute("PlotIndex", nil)
end

function BaseBuilder:PlotFor(player)
	local index = self._plotOf[player]
	return index and self._plots[index] or nil, index
end

function BaseBuilder:OwnerOf(index)
	return self._owners[index]
end

-- Where a teleport to plot `index` lands: on its entry pad, facing in.
function BaseBuilder:EntryPosition(index)
	local plot = self._plots[index]
	if not plot then
		return nil
	end
	return plot.entry.Position
end

function BaseBuilder:_applyStyle(plot, themeId, signId)
	local theme = BaseConfig.ThemeOf(themeId)
	plot.ground.Color = theme.Ground
	for _, tile in plot.tiles:GetChildren() do
		tile.Color = theme.Path
	end
	for _, rail in plot.fence:GetChildren() do
		rail.Color = theme.Fence
	end
	plot.entry.Color = theme.Trim
	local style = BaseConfig.SignOf(signId)
	plot.sign.Color = style.Back
	local face = plot.sign:FindFirstChildOfClass("SurfaceGui")
	local text = face and face:FindFirstChild("Text")
	if text then
		text.TextColor3 = style.Text
	end
end

-- "Manage base" and "Cheer" on the Hearth. They are made with the Hearth's model and destroyed
-- with it, so a rebuild or a release never leaves a prompt behind.
function BaseBuilder:_hearthPrompts(plot, roof)
	local index = plot.index
	local manage = prompt(roof, "ManagePrompt", "Manage base", "Hearth")
	local cheer = prompt(roof, "CheerPrompt", "Cheer", "Hearth")
	cheer.KeyboardKeyCode = Enum.KeyCode.F
	manage.Triggered:Connect(function(player)
		if self._options.onManage then
			self._options.onManage(player, self._owners[index])
		end
	end)
	cheer.Triggered:Connect(function(player)
		local owner = self._owners[index]
		if owner and self._options.onCheer then
			self._options.onCheer(player, owner)
		end
	end)
	plot.manage, plot.cheer = manage, cheer
end

-- One building: a foundation, a storey per level (narrowing as it rises), a roof in the theme's
-- trim, and a floating "Forge Lv3" label.
function BaseBuilder:_buildBuilding(plot, building, level, tile, theme)
	local offset = BaseConfig.TileOffset(tile)
	local base = plot.centre + Vector3.new(offset.X, 0.5, offset.Y)
	local model = Instance.new("Folder")
	model.Name = building.Id
	model:SetAttribute("Level", level)
	model:SetAttribute("Tile", tile)
	model.Parent = plot.buildings

	local width = BaseConfig.TileSize - 2
	block(model, "Foundation", Vector3.new(width, 0.6, width), base + Vector3.new(0, 0.3, 0),
		theme.Path:Lerp(Color3.new(0, 0, 0), 0.25), Enum.Material.Slate, true)
	local top = 0.6
	for storey = 1, level do
		local inset = math.min(storey * 0.6, 4)
		local color = building.Color:Lerp(Color3.new(1, 1, 1), (storey - 1) * 0.06)
		block(model, "Storey" .. storey, Vector3.new(width - 2 - inset, STOREY, width - 2 - inset),
			base + Vector3.new(0, top + STOREY / 2, 0), color, Enum.Material.Brick, true)
		top += STOREY
	end
	local roof = block(model, "Roof", Vector3.new(width - 3, 0.5, width - 3), base + Vector3.new(0, top + 0.25, 0),
		theme.Trim, Enum.Material.Neon)
	Signage.Floating(roof, "Label", string.format("%s Lv%d", building.Title, level), LABEL_TEXT,
		Vector2.new(9, 1.6), Vector3.new(0, 2.2, 0))

	if building.Id == "Hearth" then
		local fire = Instance.new("Fire")
		fire.Size = 3 + level
		fire.Color = building.Color
		fire.Parent = roof
		self:_hearthPrompts(plot, roof)
	end
	return model
end

-- A pillar per trophy round the Trophy Hall, capped at MaxTrophies.
function BaseBuilder:_buildTrophies(model, plot, tile, count, theme)
	local offset = BaseConfig.TileOffset(tile)
	local base = plot.centre + Vector3.new(offset.X, 0.5, offset.Y)
	local reach = BaseConfig.TileSize / 2 - 1
	for index = 1, math.min(count, BaseConfig.MaxTrophies) do
		local angle = (index - 1) / BaseConfig.MaxTrophies * math.pi * 2
		local spot = Vector3.new(math.cos(angle) * reach, 0, math.sin(angle) * reach)
		block(model, "Trophy" .. index, Vector3.new(0.8, 3, 0.8), base + spot + Vector3.new(0, 1.5, 0),
			theme.Trim, Enum.Material.Neon)
	end
end

-- Rebuilds a player's plot from a BaseService view: { Levels, Layout, Theme, Sign, Trophies }.
-- Returns false when the player has no plot.
function BaseBuilder:Refresh(player, view)
	local plot = self:PlotFor(player)
	if not plot or type(view) ~= "table" then
		return false
	end
	plot.buildings:ClearAllChildren()
	self:_applyStyle(plot, view.Theme or "", view.Sign or "")
	local theme = BaseConfig.ThemeOf(view.Theme or "")
	for _, building in BaseConfig.Buildings do
		local level = view.Levels and view.Levels[building.Id] or 0
		local tile = view.Layout and view.Layout[building.Id]
		if level > 0 and BaseConfig.ValidTile(tile) then
			local model = self:_buildBuilding(plot, building, level, tile, theme)
			if building.Id == "TrophyHall" then
				self:_buildTrophies(model, plot, tile, tonumber(view.Trophies) or 0, theme)
			end
		end
	end
	return true
end

return BaseBuilder
