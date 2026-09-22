-- Run reward maths. Values are soft currency ("salvage") earned by finishing a descent.
local RewardConfig = {}

RewardConfig.CurrencyId = "Salvage"
RewardConfig.CurrencyName = "Salvage"

RewardConfig.PerRoomCleared = 25
RewardConfig.PerKill = 3
RewardConfig.EliteBonus = 120
RewardConfig.ExtractionBonus = 150
-- A failed run still pays something, so a loss is not a total waste of six minutes.
RewardConfig.DefeatMultiplier = 0.4

-- Ceiling on a single run's payout, as a guard against a bug minting currency.
RewardConfig.MaxPerRun = 5000

return RewardConfig
