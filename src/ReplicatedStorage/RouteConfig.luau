-- The route through a run: the doors offered after each room (which room comes next, and what
-- it gives), and the challenges a room can carry. Numbers and text only.
local RouteConfig = {}

-- How many doors are offered after a room (fewer if the next slot has fewer rooms to draw from).
RouteConfig.Doors = 2

-- What a door promises. Weight is how often it is offered.
RouteConfig.Rewards = {
	Heal = {
		Id = "Heal",
		Title = "Mending Spring",
		Text = "Everyone heals 50% on entering.",
		Weight = 3,
		HealFraction = 0.5,
		Color = Color3.fromRGB(122, 224, 146),
	},
	Treasure = {
		Id = "Treasure",
		Title = "Treasure Cache",
		Text = "A pile of coins when the room is cleared.",
		Weight = 3,
		-- Coins per zone step (Ruins 1, Foundry 2, Abyss 3).
		CoinsPerZone = 30,
		Color = Color3.fromRGB(255, 214, 120),
	},
	Arsenal = {
		Id = "Arsenal",
		Title = "Armoury",
		Text = "The next card choice shows four cards, one Rare or better.",
		Weight = 3,
		Cards = 4,
		Color = Color3.fromRGB(120, 200, 255),
	},
	Surge = {
		Id = "Surge",
		Title = "Surge Well",
		Text = "Start the room with a Surge perk to pick.",
		Weight = 2,
		Color = Color3.fromRGB(255, 120, 200),
	},
	Challenge = {
		Id = "Challenge",
		Title = "Trial",
		Text = "A challenge. Beat it for coins and a Surge perk.",
		Weight = 2,
		Color = Color3.fromRGB(255, 150, 70),
	},
	Gallery = {
		Id = "Gallery",
		Title = "Trick Shot Gallery",
		Text = "A bonus room first: bank shots at targets for coins.",
		Weight = 1,
		Color = Color3.fromRGB(255, 200, 80),
	},
}
RouteConfig.RewardOrder = { "Heal", "Treasure", "Arsenal", "Surge", "Challenge", "Gallery" }

-- The bonus room a Gallery door inserts before the next room.
RouteConfig.GalleryRoom = {
	Id = "TrickRange",
	DisplayName = "Trick Shot Gallery",
	Layout = "Cistern",
	Zone = "Ruins",
	Tier = 0,
	Kind = "Bonus",
	Spawns = {},
	Objective = {
		Kind = "Gallery",
		Spots = {
			Vector2.new(-40, 40), Vector2.new(40, 40), Vector2.new(-40, -40), Vector2.new(40, -40),
			Vector2.new(0, 26), Vector2.new(0, -26), Vector2.new(-24, 0), Vector2.new(24, 0),
			Vector2.new(-46, 12), Vector2.new(46, -12),
		},
	},
}

-- Room challenges. A Trial door always brings one; a normal room has Chance of one anyway.
RouteConfig.ChallengeChance = 0.15
RouteConfig.Challenges = {
	BankOnly = { Id = "BankOnly", Text = "Trick shots only: every shot kill must come off a bounce" },
	Untouchable = { Id = "Untouchable", Text = "Untouchable: nobody takes damage" },
	Swift = { Id = "Swift", Text = "Swift: clear the room in 35 seconds", Seconds = 35 },
	Combo = { Id = "Combo", Text = "Frenzy: reach a 14-kill combo", Count = 14 },
}
RouteConfig.ChallengeOrder = { "BankOnly", "Untouchable", "Swift", "Combo" }
-- A beaten challenge pays every participant this many coins per zone step, and a Surge perk.
RouteConfig.ChallengeCoinsPerZone = 25

return RouteConfig
