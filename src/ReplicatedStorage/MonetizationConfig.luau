-- Robux purchases: the concept's launch economy. Every id ships as 0: create the passes and
-- developer products in Creator Hub (Monetization), paste their ids here, and they appear in the
-- Store tab. Anything left at 0 is never offered, checked or granted.
--
-- No paid power. Coins build the base, and the base is where power lives, so nothing here sells
-- coins or a coin multiplier (3.0 retired the coin packs and the 2x Coins pass). Passes are
-- convenience and identity; products are a revive and rerolls, both also earnable for free.
--
-- Passes are permanent. Their perks are data read by the systems that honour them:
--   PresetSlots: extra loadout presets (LoadoutService).
--   ExtraCapHours: hours added to the Salvage Yard's offline cap (BaseService).
--   Cosmetics: ShopConfig items the pass unlocks (their RequiresPass names the pass): the
--   Explorer nameplate and Banner sign; the Gold trail, Gilded theme and Cheer emote.
--   ChatTag: the tag in front of the holder's chat messages (ChatTags).
-- Price is the suggested launch price in Robux, for the Creator Hub step; the ranges come from
-- the concept, and docs/RELEASE_CHECKLIST.md covers regional pricing.
return {
	Passes = {
		ExplorerPass = {
			Id = 0,
			Title = "Explorer Pass",
			Description = "+1 loadout preset, the Explorer nameplate and the Banner sign for your base.",
			Price = 129,
			PriceRange = { 99, 149 },
			PresetSlots = 1,
		},
		SupporterPack = {
			Id = 0,
			Title = "Supporter Pack",
			Description = "Gold trail, Gilded base theme, Cheer emote, +2 presets, +2h offline storage and a Supporter tag.",
			Price = 349,
			PriceRange = { 299, 399 },
			PresetSlots = 2,
			ExtraCapHours = 2,
			ChatTag = "Supporter",
		},
	},
	-- Kind "Revive": one ReviveToken, spent at once if the buyer is down in a run (once a run),
	-- otherwise kept for later. Kind "Grant": Extras added to the buyer's balances.
	Products = {
		{
			Key = "Revive",
			Id = 0,
			Kind = "Revive",
			Title = "Revive",
			Description = "Get back up where you fell. Once a run.",
			Price = 29,
			Extras = { ReviveTokens = 1 },
		},
		{
			Key = "RerollBundle",
			Id = 0,
			Kind = "Grant",
			Title = "5 Rerolls",
			Description = "Five card rerolls, kept until you use them.",
			Price = 59,
			PriceRange = { 49, 79 },
			Extras = { Rerolls = 5 },
		},
	},
	-- Rewarded video (FeatureFlags.RewardedVideo): a fixed bonus at the end of a run, never a
	-- random reward, so no odds disclosure is needed. RewardProductId is the developer product
	-- Roblox's AdService ties the ad to (created in Creator Hub like any product).
	Ads = {
		RewardProductId = 0,
		MaxPerDay = 3,
		Coins = 40,
		Rerolls = 0,
	},
}
