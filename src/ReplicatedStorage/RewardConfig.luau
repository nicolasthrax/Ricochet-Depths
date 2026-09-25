-- Run payout. Coins are collected from kills during the run; clearing rooms adds a bonus on top.
-- 3.0: the haul is at risk. Only extracting (beating the run, or banking the loot at an extract
-- point) keeps everything; a run that is lost, timed out or left keeps a share.
local RewardConfig = {}

-- Stored under the profile's original field name, so balances from earlier builds carry over.
RewardConfig.CurrencyId = "Salvage"
RewardConfig.CurrencyName = "Coins"

RewardConfig.PerRoomCleared = 10
RewardConfig.EliteBonus = 50
RewardConfig.ExtractionBonus = 200
-- A failed run earns only this share of the clear bonus.
RewardConfig.DefeatMultiplier = 0.5
-- ...and keeps only this share of the coins it collected. The rest of the haul is lost in the
-- depths, which is what makes banking it early a real choice.
RewardConfig.DefeatHaulShare = 0.5

-- Banking the loot at an extract point (a "Bank loot" door after a mini-boss) ends the run as an
-- extraction, with a bonus that grows with the zone it was banked in. Beating the whole descent
-- still pays the full ExtractionBonus.
RewardConfig.BankBonusByZone = { Ruins = 60, Foundry = 120, Abyss = 160 }

-- Playing together pays more and solo never pays less: each member past the first adds to the
-- coin multiplier, up to MaxBonus, and a party with a Roblox friend in it adds FriendBonus.
RewardConfig.Party = {
	PerExtraMember = 0.05,
	MaxBonus = 0.15,
	FriendBonus = 0.1,
}

-- Ceiling on a single run's payout, as a guard against a bug minting currency.
RewardConfig.MaxPerRun = 5000

return RewardConfig
