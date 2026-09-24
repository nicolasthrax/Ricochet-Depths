-- Player levels. Experience is earned from every run, win or lose, and is never lost. It is
-- stored as one lifetime total (Progression.Xp in the profile); the level is always derived
-- from that total, so the curve can be retuned without migrating anyone's data.
local ProgressionConfig = {}

ProgressionConfig.MaxLevel = 100

-- What a run pays in experience. Counted from server-tracked run state only.
ProgressionConfig.Xp = {
	PerKill = 4,
	PerRoomCleared = 25,
	EliteCleared = 60,
	Extracted = 150,
	-- A run that ends any other way still keeps everything above, just not the extraction.
}

-- Experience needed to go from `level` to `level + 1`. Early levels come every run or two;
-- later ones take an evening.
function ProgressionConfig.XpToNext(level)
	return 100 + (level - 1) * 50
end

-- Coins paid once for reaching `level`. Paid with the run that crossed it, so it is saved and
-- ledgered exactly like the run's own coins.
function ProgressionConfig.LevelReward(level)
	if level % 10 == 0 then
		return 250 -- milestone levels
	end
	return 20 + level * 5
end

-- A whole, non-negative experience total; anything malformed counts as none.
local function sanitise(totalXp)
	local xp = tonumber(totalXp)
	if not xp or xp ~= xp or xp < 0 then
		return 0
	end
	return math.floor(math.min(xp, 2 ^ 50))
end

-- The level a lifetime experience total reaches, and how far into that level it is.
-- Returns level, xpIntoLevel, xpToNext (xpToNext is 0 at the cap).
function ProgressionConfig.LevelFor(totalXp)
	local remaining = sanitise(totalXp)
	local level = 1
	while level < ProgressionConfig.MaxLevel do
		local need = ProgressionConfig.XpToNext(level)
		if remaining < need then
			return level, remaining, need
		end
		remaining -= need
		level += 1
	end
	return ProgressionConfig.MaxLevel, 0, 0
end

-- The coins owed for every level passed going from `fromXp` to `toXp`.
function ProgressionConfig.RewardBetween(fromXp, toXp)
	local before = ProgressionConfig.LevelFor(fromXp)
	local after = ProgressionConfig.LevelFor(toXp)
	local coins = 0
	for level = before + 1, after do
		coins += ProgressionConfig.LevelReward(level)
	end
	return coins, before, after
end

-- Everything a view needs to draw a level badge and bar.
function ProgressionConfig.Describe(totalXp)
	local level, into, need = ProgressionConfig.LevelFor(totalXp)
	return {
		Level = level,
		Xp = sanitise(totalXp),
		XpIntoLevel = into,
		XpToNext = need,
	}
end

return ProgressionConfig
