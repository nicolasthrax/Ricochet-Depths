-- Floating damage numbers over enemy hits. A fixed pool of billboards is built up front and
-- recycled; when every one is in flight a new number is simply dropped. Client-only.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local EffectConfig = require(ReplicatedStorage:WaitForChild("EffectConfig"))

local DamagePopups = {}
DamagePopups.__index = DamagePopups

local function buildPopup(folder, index, config)
	local anchor = Instance.new("Part")
	anchor.Name = "Popup" .. index
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Transparency = 1
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.CastShadow = false
	anchor.Position = config.StoragePosition
	anchor.Parent = folder

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Billboard"
	billboard.Size = UDim2.fromOffset(90, 40)
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.Enabled = false
	billboard.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Name = "Amount"
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextScaled = true
	label.TextStrokeTransparency = 0.3
	label.Text = ""
	label.Parent = billboard

	return { anchor = anchor, billboard = billboard, label = label }
end

-- config: PoolSize, Duration, Rise, StoragePosition, plus the colours and texts from
-- EffectConfig.Popups for anything not given.
function DamagePopups.new(parent, config)
	local defaults = EffectConfig.Popups
	config = setmetatable(config or {}, { __index = defaults })
	local self = setmetatable({ _config = config, _free = {}, _active = {} }, DamagePopups)

	local folder = Instance.new("Folder")
	folder.Name = "DamagePopups"
	folder.Parent = parent
	self.Folder = folder

	for index = 1, config.PoolSize do
		self._free[index] = buildPopup(folder, index, config)
	end
	return self
end

local function formatAmount(amount)
	if amount == math.floor(amount) then
		return tostring(math.floor(amount))
	end
	return string.format("%.1f", amount)
end

-- kind is "Hit", "Kill", "Block", or a shot effect: "Crit", "Arc", "Burn" or "Blast".
-- Returns false when the pool is dry.
function DamagePopups:Show(position, amount, kind, now)
	local count = #self._free
	if count == 0 then
		return false
	end
	local popup = self._free[count]
	self._free[count] = nil

	local config = self._config
	if kind == "Block" then
		popup.label.Text = config.BlockedText
		popup.label.TextColor3 = config.BlockColor
	elseif kind == "Crit" then
		popup.label.Text = formatAmount(amount) .. "!"
		popup.label.TextColor3 = config.CritColor
	else
		popup.label.Text = formatAmount(amount)
		popup.label.TextColor3 = kind == "Kill" and config.KillColor
			or kind == "Arc" and config.ArcColor
			or kind == "Burn" and config.BurnColor
			or kind == "Blast" and config.BlastColor
			or config.HitColor
	end
	popup.label.TextTransparency = 0
	popup.label.TextStrokeTransparency = 0.3
	popup.billboard.Enabled = true
	popup.origin = position
	popup.anchor.Position = position
	popup.startedAt = now
	table.insert(self._active, popup)
	return true
end

-- Rises and fades each live popup; returns finished ones to the pool.
function DamagePopups:Step(now)
	local config = self._config
	for index = #self._active, 1, -1 do
		local popup = self._active[index]
		local alpha = (now - popup.startedAt) / config.Duration
		if alpha >= 1 then
			popup.billboard.Enabled = false
			popup.anchor.Position = config.StoragePosition
			table.remove(self._active, index)
			table.insert(self._free, popup)
		else
			popup.anchor.Position = popup.origin + Vector3.new(0, config.Rise * alpha, 0)
			popup.label.TextTransparency = alpha * alpha
			popup.label.TextStrokeTransparency = 0.3 + 0.7 * alpha
		end
	end
end

function DamagePopups:GetFreeCount()
	return #self._free
end

-- The text of the index-th live popup, oldest first. For tests and the debug overlay.
function DamagePopups:GetActiveText(index)
	local popup = self._active[index]
	return popup and popup.label.Text or nil
end

return DamagePopups
