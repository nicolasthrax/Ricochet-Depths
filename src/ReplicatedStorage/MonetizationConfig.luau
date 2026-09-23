-- Robux purchases. Every id ships as 0: create the passes and developer products in Creator Hub
-- (Monetization), paste their ids here, and they appear in the Store tab. Anything left at 0 is
-- never offered, checked or granted.
--
-- Passes are permanent. CoinBonus adds to the payout multiplier (the 2x Coins pass adds 1, so a
-- run pays double). VIP also unlocks the Gold trail in Cosmetics.
-- Products are one-off coin packs, granted exactly once per receipt.
return {
	Passes = {
		DoubleCoins = {
			Id = 0,
			Title = "2x Coins",
			Description = "Double the coins from every run, forever.",
			CoinBonus = 1,
		},
		VIP = {
			Id = 0,
			Title = "VIP",
			Description = "+10% coins and the exclusive Gold trail.",
			CoinBonus = 0.1,
		},
	},
	Products = {
		{ Key = "Coins500", Id = 0, Coins = 500, Title = "500 Coins" },
		{ Key = "Coins1500", Id = 0, Coins = 1500, Title = "1,500 Coins" },
		{ Key = "Coins5000", Id = 0, Coins = 5000, Title = "5,000 Coins" },
	},
}
