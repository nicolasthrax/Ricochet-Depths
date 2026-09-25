-- Run payout. Coins collected during a run are its haul; clearing rooms adds a bonus on top,
-- which a failed run only partly earns. With the haul at risk (FeatureFlags.Haul), a run that
-- is lost keeps only part of its haul, and one that gets out alive is paid more the deeper it
-- got: the choice between surfacing at a lift and pushing on is the point.
local RewardConfig = {}

-- Stored under the profile's original field name, so balances from earlier builds carry over.
RewardConfig.CurrencyId = "Salvage"
RewardConfig.CurrencyName = "Coins"

RewardConfig.PerRoomCleared = 10
RewardConfig.EliteBonus = 50
RewardConfig.ExtractionBonus = 200
-- A failed run keeps its coins but earns only this share of the clear bonus.
RewardConfig.DefeatMultiplier = 0.5

-- Haul at risk. A wipe or a run out of time keeps this share of the coins collected.
RewardConfig.DefeatCoinKeep = 0.4
-- A run that gets out (the Surface Lift, or the Throne) multiplies its haul by this much for
-- every zone boss beaten after the first: x1 after the Colossus, x1.25 after the Forge Press,
-- x1.5 after the Warden Prime.
RewardConfig.HaulDepthBonus = 0.25

-- Ceiling on a single run's payout, as a guard against a bug minting currency.
RewardConfig.MaxPerRun = 5000

return RewardConfig
