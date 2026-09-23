-- Run payout. Coins are collected from kills during the run and kept in full whatever the
-- outcome; clearing rooms adds a bonus on top, which a failed run only partly earns.
local RewardConfig = {}

-- Stored under the profile's original field name, so balances from earlier builds carry over.
RewardConfig.CurrencyId = "Salvage"
RewardConfig.CurrencyName = "Coins"

RewardConfig.PerRoomCleared = 10
RewardConfig.EliteBonus = 50
RewardConfig.ExtractionBonus = 200
-- A failed run keeps its coins but earns only this share of the clear bonus.
RewardConfig.DefeatMultiplier = 0.5

-- Ceiling on a single run's payout, as a guard against a bug minting currency.
RewardConfig.MaxPerRun = 5000

return RewardConfig
