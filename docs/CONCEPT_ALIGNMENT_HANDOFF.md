# Concept alignment: handoff

Goal: make Ricochet Depths match the original concept in `steam-to-roblox.xlsx` (Overview,
Roblox Playbook, Concept MVP sheets) in full. Branch: `claude/concept-alignment`, started from
`claude/vigilant-keller-xt8dly` at `04e2266` (2.0.0).

State at handoff: **all checks green** (`./scripts/check.sh`: syntax, lint, Rojo build, 666
headless tests). Two work items have been done. `BaseService` exists but **is not wired into
`GameBootstrap` yet**, so nothing about the base shows up in-game so far.

## Tooling

`check.sh` needs `luau`, `luau-compile`, `luau-analyze` and `rojo` on PATH. Put them on PATH, or
point the `LUAU_BIN` / `LUAU_COMPILE_BIN` / `LUAU_ANALYZE_BIN` / `ROJO_BIN` variables at them:

- Luau: https://github.com/luau-lang/luau/releases/latest (`luau-ubuntu.zip`, `luau-macos.zip`, ...)
- Rojo 7.4.4: https://github.com/rojo-rbx/rojo/releases/tag/v7.4.4

## Done

### 1. Persistence, schema v9 (`0534ef4`)
- `PlayerDataConfig.Currencies = { "Salvage", "Rerolls", "ReviveTokens" }`. `Salvage` is the
  coin balance. All three are store-owned.
- `PlayerDataService:GrantReward(player, key, coins, xp, extras)`: `extras = { Rerolls = n,
  ReviveTokens = n }` goes into the same ledgered grant. `Payout.Grant(..., extras)` passes it
  through.
- `SpendOnUpgrade(player, itemId, level, cost, currencyId)`: a purchase can charge any currency.
  To spend a consumable, buy the next level of a use counter, e.g.
  `SpendOnUpgrade(p, "RerollUse", used + 1, 1, "Rerolls")`. The commit-time checks and
  cross-server reconciliation apply per currency. `GetBalance(player, currencyId)`.
- New profile fields:
  - `Base = { Layout, LastClaimAt, Theme, Sign, Cheers = { Day, Given, Received } }`
  - `Presets` (use **string** slot keys: "1", "2", ...)
  - `Nameplate`
  - `Limits = { ModifierDay, AdDay, AdCount, VisitDay, Visits }`
  - `Flags.FirstDescentDone`
  - `Flags.Funnel` (step id -> true)
- The v8 -> v9 migration refunds every Armory stat level in coins. The prices are in
  `PlayerDataConfig.LegacyArmoryCosts`. Earnable power now comes from buildings. Trails are kept.
- `GetPublicProfile` now also returns `Rerolls`, `ReviveTokens`, `Base`, `Presets` and
  `Nameplate`.
- Tests: `tests/currencies.test.luau`.
- Round-trip rule (enforced by `persistence.test`): every **top-level** profile default must be
  a table or a string, never a number.

### 2. Home base, started (uncommitted at handoff, included in the handoff commit)
- `src/ReplicatedStorage/BaseConfig.luau`:
  - A 4x4 grid (16 tiles) and 12 buildings: Hearth, SalvageYard, Storehouse, Forge, Infirmary,
    Bootworks, RailLab, Springhouse, MagnetMast, OrbKiln, TrainingYard, TrophyHall.
  - Per building: costs, Hearth gates and effects. Levels are stored in `MetaUpgrades[buildingId]`
    as *levels bought*. Shown level = `StartLevel + bought`, so the Hearth starts at 1 for free.
  - Helpers: `LevelOf`, `CostFor`, `HearthNeeded`, `ComputeBonuses`, `ProductionPerHour`,
    `CapHours` (8h base, +1h per Storehouse level, pass extra, 12h max), `OfflineCoins`,
    `NormaliseLayout`, `TileOffset`, `PlotCentre` (8 plots, 280 studs north of the lobby),
    `NextBuild` (for the results screen's "your haul builds" preview).
- `src/ServerScriptService/Modules/BaseService.luau`:
  - `GetState`, `GetRunBonuses`, `EnsureLayout`.
  - `Upgrade(player, id, tile)`: builds (placing on a tile) or upgrades. Goes through the
    purchase path. Before a yard or storehouse upgrade it auto-claims, so a new rate is never
    paid backwards.
  - `Move` (swaps with whatever is on the target tile).
  - `Claim`: ledger key `offline:<LastClaimAt>`, so two servers claiming the same stretch of
    time pay once.
  - `Cheer(visitor, owner)`: once a day per pair. Payout keys `visit:<day>:<owner>` and
    `cheer:<day>:<visitor>`, capped by `BaseConfig.Visits`.
- `UpgradeConfig.BaseStats.XpMultiplier` (Training Yard), applied in
  `RewardService.Experience`.
- `FeatureFlags.BaseBuilding = true`. No UI or remote reaches it yet.

### 3. Section A: base finished (server side)
- `tests/base.test.luau`: every case listed under A.1, plus BaseBuilder plots and the base remotes.
- `BaseBuilder` (server): the Outpost (ground, barrier, 8 plots). Hearth prompts ("Manage base",
  "Cheer") are created with the Hearth model on every `Refresh`. The stub cannot reparent an
  instance that already has a parent, so nothing is moved between parents.
- `GameBootstrap`: `BaseService` + `BaseBuilder` wired in; `pushBase` fires `BaseSync` and rebuilds
  the plot; plot assigned after profile load and released on leave; `metaProvider` reads building
  bonuses plus `shop:GetTrail`. `systems.base` / `systems.builder` returned for tests.
- Remotes `UpgradeBuilding`, `MoveBuilding`, `ClaimBase`, `VisitBase`, `CheerBase`, `RequestBase`
  (C->S) and `BaseSync` (S->C), with rate rules and sanitising in `RemoteRouter:_bindBase`.
- Armory removed: no `Kind = "Stat"` items, `ShopConfig.ComputeBonuses` and
  `ShopService:GetRunBonuses` gone (`GetTrail` instead). The lobby's Armory kiosk is now the
  **Outpost kiosk** (`OpenOutpostPrompt`, teleports to your plot), which covers B's "hub portal".
  `ShopView` tabs are Cosmetics + Store. `shop.test` moved its multi-level cases onto buildings.
- `MonetizationService:GetExtraCapHours` (sums `ExtraCapHours` on owned passes; used by D).
- Harness: `Players:GetPlayerByUserId` added to the stub.
- Still to come for the base: the client `BaseView` (F).

## Remaining work, in order

### A. Finish the base (task 2): DONE, see "Done" 3 above
1. **Tests** in `tests/base.test.luau`:
   - Build / upgrade / Hearth gate / max level / insufficient coins / read-only refusal
     / in-run refusal.
   - Tile rules, and move-with-swap.
   - `NormaliseLayout` with a tampered layout, and with a building bought on another server.
   - Claim math, the cap, and idempotency across two servers (same `LastClaimAt`).
   - Auto-claim before a yard upgrade.
   - Cheer once a day, per-day caps, the day rollover, and refusing to cheer your own base.
   - `ComputeBonuses` clamping.
2. **`BaseBuilder`** (new server module, world plots):
   - `BaseBuilder.new(parent, RunConfig.LobbyPosition)` builds the "Outpost" folder with
     `BaseConfig.Plots.Count` plots. Each plot: ground, a 4x4 tile grid, a fence, a sign board
     (`Signage.Board`), an entry pad with a "Return to the Outpost" `ProximityPrompt`, and
     "Manage base" and "Cheer" prompts at the Hearth.
   - `:Assign(player)`, `:Release(player)`, `:PlotFor(player)`, `:EntryPosition(index)`.
   - `:Refresh(player, view)`: rebuilds the building models. Each is a procedural part stack
     whose height grows with level, with a label billboard "Forge Lv3", the theme palette, the
     sign style, and trophy pillars in the Trophy Hall from claimed achievements.
   - Set a `PlotIndex` attribute on the player so the client can find its plot.
   - The stub (`tests/harness/RobloxStub.luau`) supports Part, WedgePart, Folder,
     ProximityPrompt, BillboardGui and SurfaceGui instances.
3. **Wire into `GameBootstrap`**:
   - `BaseService.new(persistence, { canManage = not in a match, extraCapHours = pass bonus,
     onChanged = pushProfile + builder:Refresh, onFirstBuild = funnel })`.
   - Assign a plot on join and release it on leave.
   - In `metaProvider`, replace `shop:GetRunBonuses(player).stats` with `base:GetRunBonuses`.
   - Add a `BaseSync` push next to `MetaSync`.
4. **Remotes** (in `Remotes.luau` + `RunConfig.RemoteRules` + `RemoteRouter`):
   - Client to server: `UpgradeBuilding(id, tile?)`, `MoveBuilding(id, tile)`, `ClaimBase`,
     `VisitBase(userId|nil)` (teleport to a plot entry, lobby only), `CheerBase(userId)`,
     `RequestBase`.
   - Server to client: `BaseSync`.
5. **Remove the Armory:**
   - Delete the `Kind = "Stat"` items from `ShopConfig`, and the Armory kiosk and tab.
   - `tests/shop.test.luau` uses Vitality, Velocity and Stride about 69 times as a vehicle for
     purchase-path tests. Move the multi-level cases onto buildings via `BaseService`, and keep
     trails for the single-level cases.
   - Other references: `lobby.test`, `match.test`, `projectile.test`, `zz_bootstrap.test`,
     `coins`, `soak`, `shot_effects`, `redesign`.

### B. Hub redesign (task 3): DONE
Done: `GateCapacity = 4`; the spawn pad faces north at the well (`lobby.test`); `TitleScreen`
deleted (module, `ClientMain` use, its `meta.test` case); `FeatureFlags.FirstDescent` and
`GameBootstrap._wantsFirstDescent`: a loaded, writable profile with `FirstDescentDone == false`
waits for its character, then `startSolo(player, now, { firstDescent = true })`.
`ArenaDirector:StartGroup(players, now, options)` -> `MatchService:RequestStart(player, now,
options)`, stored as `match._runOptions`; C3 turns it into the scripted plan. The Outpost kiosk is
the hub portal; the HUD BASE button is part of F. Max players 8 is in `RELEASE_CHECKLIST.md`.
Harness: `Signal:Wait` added to the stub.

Original notes:
- In `LobbyBuilder`, gates hold 1-4 players (`RunConfig.Lobby.GateCapacity = 4`, min 2; the
  solo portal covers 1). Update `lobby.test`.
- Players spawn facing the pit. Add a hub portal / HUD "BASE" button that teleports you to your
  plot.
- **No lobby wall:**
  - Remove the blocking `TitleScreen` from `ClientMain` (delete the module if nothing else uses
    it).
  - When a profile loads with `Flags.FirstDescentDone == false` and the player is not in a
    match, auto-start a solo **first descent** (see C3).
- `RELEASE_CHECKLIST.md`: set the server's max players to 8, to match the plot count.

### C. Run changes (task 4): DONE (server side; card-picker/results UI is F)
Done, all covered by `tests/runloop.test.luau`:
- C1 `RewardConfig.DefeatHaulShare = 0.5` (`RewardService.HaulShare/HaulKept`; Aborted keeps all,
  leaving mid-run keeps the share). `ExtractPoint` on ColossusHall, ForgeHall and the tutorial's
  FirstElite; `MatchRoute:_rollDoors` appends the `RouteConfig.BankLoot` door (always last, so a
  tie keeps descending); winning it sets `_banked` and `MatchService.Step` finishes "Extracted"
  with `RewardConfig.BankBonusByZone[zone]`. Summary gains `Haul`, `HaulLost`, `Banked`.
- C2 `DailyModifierConfig` (7 modifiers, `ForDay(day % 7)`, `Today`, `Describe`, `Bonus`).
  `deps.dailyModifiers` (ArenaDirector reads `FeatureFlags.DailyModifiers`) and `deps.wallClock`.
  Stats in `_refreshMeta`; enemy health/champions in `_applyPact`; bonus once a day via
  `Limits.ModifierDay` + ledger key `dailymod:<day>` (summary `DailyBonus`). Lobby
  `ModifierBoard` (printed by `refreshModifierSign`), `MetaSync.Modifier`, run snapshot `Modifier`.
- C3 `RunConfig.FirstDescent` + Tier-0 rooms FirstPit/FirstPair/FirstElite (`CoinBurst`,
  `ExtractPoint`). `MatchService:_planFor` prepends them (slots `false`); ForceCards via
  `BuildOffer(..., { force })`; banner Notify Callout at room 1; `Flags.FirstDescentDone` set in
  `_finish`; no Gallery doors in the tutorial; snapshot `FirstDescent = true`.
- C4 Card `Label`/`Icon`/`UnlockLevel` (the `FACES` table in `UpgradeConfig`), `IsFusionPart`,
  `UpgradeService.Recommend` (offer.recommended, payload `Recommended`, `ResolveExpired` picks it),
  `Reroll`, `Reopen` (respec), `ClearSettled`. `MatchFlow:RerollOffer` (free once a run
  (`RunConfig.Cards`), then `SpendOnUpgrade(p, "RerollUse", n+1, 1, "Rerolls")`) and
  `RespecCard` (rounds 1-2, once a run). Remotes `RerollOffer`, `RespecCard`. Offer payload has
  `FreeRerolls`, `Rerolls`, `CanRespec`. Level reaches runs as `meta.level` -> `PlayerState.level`.
- C5 `RewardConfig.Party` (+5% per extra member, max +15%, +10% friend) in `_partyBonus`;
  `RunConfig.PartyScaling.EnemyHealthPerExtra = 0.35` (there was no party scaling before).
  `FriendCache` (background `IsFriendsWith`, never yields in a run) wired in `GameBootstrap`.
- C6 `./scripts/dryrun.sh` (probing bot): full-run floor 389 s (6.5 min) vs target 420 s; median
  rooms 1-3 ~164 s (bank at ColossusHall ~3 min), rooms 1-6 ~255 s (bank at ForgeHall ~4.5 min).
  Record in PROGRESS.md (G). Bots cannot bank-shot: these are floors, not predictions.

Original notes:
1. **Haul at risk + Bank loot:**
   - On defeat, keep only `RewardConfig.DefeatHaulShare = 0.5` of the coins collected. Today
     coins are kept in full; see `RewardService.Compute` and the tests that assume full coins.
   - Add `ExtractPoint = true` to the tutorial elite, `ColossusHall` and `ForgeHall`.
   - After an extract point, `MatchRoute:_rollDoors` adds a "Bank loot" door
     (`Reward = "BankLoot"`). If it wins, `_finish("Extracted")` with a depth-scaled extraction
     bonus.
   - The results CTAs are "DESCEND" (start again) and "BANK LOOT" / go to base.
2. **Daily biome modifiers:**
   - New `DailyModifierConfig`: 7 modifiers, indexed by `MetaConfig.DayOf(now) % 7`. For
     example: Bouncy Walls (+2 bounces), Glass Depths, Gold Rush (+25% coins), Champion Hunt,
     Heavy Orbs, Quick Feet, Surge Day.
   - Apply them in `MatchService:RequestStart` / `_refreshMeta` (player stats) and in
     `_applyPact` (enemy modifiers, champion bonus).
   - Pay a once-a-day bonus keyed `dailymod:<day>`.
   - Show the modifier on a hub sign and on the HUD.
3. **First 60 seconds (tutorial plan):**
   - Add `ArenaDirector:StartGroup(players, now, { plan = ... })` and
     `MatchService:RequestStart(..., options)`.
   - Plan: `FirstPit` (a clustered safe target group, first hit within 5-15s), then `FirstPair`
     (the offer includes SplitShot again, so Fusillade becomes an obvious fusion), then
     `FirstElite` (a mini-elite that bursts into coins, with an extract point). The normal
     `RunShape` follows.
   - Add `ForceCards` per room to `UpgradeService:BuildOffer`.
   - Banner: "Bounce shots. Break everything."
   - At the end, set `Flags.FirstDescentDone`.
4. **Cards:**
   - Give every card a `Label` of 3 words or fewer and an icon, and add a test.
   - Mark one card `Recommended` per offer (a fused card, else a prerequisite toward a fusion,
     else the rarest). `ResolveExpired` auto-picks the recommended card instead of `cards[1]`.
   - **Free early respec:** during the first two upgrade rounds, once per run, undo the last
     main card. `PlayerState` recomputes stats from stacks, so decrement the stack and remove it
     from `upgradeOrder`.
   - **Reroll:** one free per run, then spend `Rerolls` via the use counter.
   - **Gradual unlocks:** add `UnlockLevel` per card. The player's level goes through meta into
     `PlayerState.level`, and `UpgradeService.IsEligible` checks it. A `nil` level means no
     gating, so existing tests keep passing.
5. **Party / friend bonus:**
   - +5% `CoinMultiplier` per extra member (max +15%), plus +10% if the party includes a Roblox
     friend (`player:IsFriendsWith`).
   - Solos are never penalised. Check that enemy scaling by party size exists in `EnemyService`.
6. **Pacing:** target 6-8 minutes for a full run. Short runs come from the Bank-loot points.
   Re-run `./scripts/dryrun.sh` and record the numbers in `PROGRESS.md`.

### D. Monetization to the concept's launch economy (task 5): DONE (server side; Store/cosmetics UI is F)
Done (`tests/monetization.test.luau`, `tests/shop.test.luau` "cosmetic kinds", `tests/economy.test.luau`):
- `MonetizationConfig`: ExplorerPass (129 R$, PresetSlots 1), SupporterPack (349 R$, PresetSlots 2,
  ExtraCapHours 2, ChatTag "Supporter"); products Revive (29 R$, Kind "Revive", +1 ReviveToken)
  and RerollBundle (59 R$, +5 Rerolls); `Ads` (RewardProductId, MaxPerDay 3, 40 coins). All ids 0.
  Coin packs, 2x Coins, VIP and **the Premium coin bonus** removed (all were coins for money).
- `MonetizationService`: `GetExtraCapHours`, `GetPresetSlots`, `GetPerk`; receipts grant `Extras`
  only; a Revive receipt calls `onRevive` (bootstrap -> `match:UseReviveToken`); the ad product is
  acknowledged without paying; `productEnabled` hides Revive while `FeatureFlags.PaidRevive` is off.
- Revive tokens: `MatchService:UseReviveToken` (Combat, downed, once a run, spends "ReviveUse"
  counter in ReviveTokens); `_holdForRevive` waits `RunConfig.Revive.GraceSeconds` when everyone
  is down and someone holds a token (or `deps.canBuyRevive`), sending Notify `ReviveOffer`.
  Remote `UseRevive`.
- `ShopConfig`: Kinds Trail/Theme/Sign/Emote/Nameplate, each earned by `Costs`, `UnlockLevel` or
  `RequiresPass` (free); `ShopConfig.Owns`. `ShopService`: `Owns`, generic `Equip(player, id, now,
  kind)`, `GetTrail`/`GetBaseStyle`/`GetNameplate` (only still-owned items), `PlayEmote`.
  `EmoteBurst` (server billboard). Remote `PlayEmote`; `EquipShopItem` takes a kind.
- `LoadoutService:PresetSlots/SavePreset/ApplyPreset` (`MetaConfig.Presets` 2 free, max 5; string
  slot keys). Remotes `SavePreset`, `ApplyPreset`. Public profile gains `PresetSlots`.
- `RewardedAds` (named so it does not shadow Roblox's AdService): pcall-wrapped
  availability/show, fixed bonus via `Payout.Grant` key `ad:<day>:<n>`, `Limits.AdDay/AdCount`.
  Remote `WatchAd` bound only when `FeatureFlags.RewardedVideo`.
- Private server: `GameBootstrap._ownsPrivateServer`; remote `FeatureBase(userId)` prints the
  lobby `FeaturedBoard` and enables its "Visit featured base" prompt.
- Chat tag: `ChatTag` attribute (was `VIP`); nameplate shows the worn title.
- Season pass and UGC limiteds not built (deliberate, per the concept): document in G.

Original notes:
- Remove the coin packs and the 2x Coins pass from `MonetizationConfig` and
  `MonetizationService` (coins that buy buildings would be paid power). VIP folds into the
  Supporter Pack.
- New catalogue (all ids 0 until the owner fills them in):
  - `ExplorerPass`, 99-149 R$: +1 loadout slot, a permanent "Explorer" nameplate and the Banner
    base sign.
  - `SupporterPack`, 299-399 R$: the Gold trail, the Gilded base theme and the Cheer emote, +2
    presets, +2h offline storage (`extraCapHours`), and a supporter badge / chat tag.
  - Products: `Revive`, 29 R$, one per run, only while downed, behind
    `FeatureFlags.PaidRevive = false` until playtested. `RerollBundle`, 49-79 R$ (+5 `Rerolls`,
    via a receipt grant with `extras`).
- Rewarded video: add an `AdService` wrapper under pcall behind `FeatureFlags.RewardedVideo`. It
  pays a fixed material bonus at the end of a run (no random rewards, so no odds disclosure is
  needed), limited per day via `Limits.AdDay` / `AdCount`.
- Private server: detect it with `game.PrivateServerId ~= ""`. The owner (`PrivateServerOwnerId`)
  can feature a base on the hub sign. The price is set in Creator Hub.
- Cosmetics: `ShopConfig` gains `Kind` values `Theme`, `Sign`, `Emote` and `Nameplate`. Each is
  earnable (coins or a level) or comes from a pass entitlement. Equip through `ShopService:Equip`,
  which is already generic for trails. Add a `PlayEmote` remote (lobby only, rate limited, a
  billboard burst).
- Loadout presets: add `SavePreset(slot)` and `ApplyPreset(slot)` to `LoadoutService`. 2 slots
  free, plus pass slots.
- Not built, per the concept: the season pass (no 4-week content pipeline yet) and UGC limiteds
  ("not MVP-first"). Document both as deliberate.

### E. Daily loop, social, telemetry (task 6)
- Forgiving 7-day track: in `MetaService.ClaimDaily` and `GetState`, the streak advances on every
  claim and **never resets** on a missed day. Update `meta.test`. Add a revive token or rerolls
  to the day 5 and day 7 rewards via `extras`.
- Friend join reward: covered by C5. Invites already exist.
- Funnel: `Join`, `FirstInput`, `FirstHit`, `FirstUpgrade`, `FirstFusion`, `FirstRunEnd`,
  `FirstBaseUpgrade`. Log each once ever, via `Flags.Funnel`, to `TelemetryService` **and**
  Roblox `AnalyticsService:LogOnboardingFunnelStepEvent` (pcall). Also send
  `LogEconomyEvent` for coin sources and sinks.
- Go / no-go metrics: write them up in a doc (bounce, D1, D7, play days, co-play days, payer
  conversion, ARPPU).

### F. Client UI (task 7)
- `BaseView`: a 4x4 grid; building cards grouped by role, with level, cost and the Hearth gate;
  tap a card then a tile to build or move; an upgrade button; the claim button with fill %;
  and a visit list of players on the server, with Visit and Cheer.
- Add a BASE entry to `MenuDock` and a HUD shortcut.
- Store tab: the new passes and products. Cosmetics tabs: trails, themes, signs, emotes,
  nameplates.
- Results: the 3-second base preview (camera to your plot using `PlotIndex`), the "your haul
  builds X" text from `NextBuild`, and the DESCEND / BANK LOOT buttons.
- Card picker: the 3-word labels and icons, the RECOMMENDED tag, and REROLL (free / count) and
  RESPEC buttons.
- HUD: the daily modifier chip. Onboarding banner: "Bounce shots. Break everything."

### G. Docs and wrap-up (task 8)
- Write a concept-to-code traceability doc: every row of the concept's Loop stack, MVP plan,
  Launch economy, Risks, First 60 seconds and Go / no-go sections, mapped to the module and
  test that covers it (or noted as deliberately deferred per the concept).
- Update `README.md`, `docs/PROGRESS.md` (changelog 3.0.0) and `docs/RELEASE_CHECKLIST.md`
  (new Creator Hub ids, max players 8, private server price, regional pricing, Studio checks for
  plots and the tutorial).
- Bump `RunConfig.Version` to "3.0.0".

## Notes
- Anything that moves money must go through `PlayerDataService` grants or spends. `Update()`
  refuses to touch `Currency`, `GrantedRuns`, `MetaUpgrades` or `Progression`.
- Module names must be unique repo-wide (`tests/run.py` bundles them flat).
- Nothing on this branch has been run in Roblox Studio.
