# 1.0 Launch Checklist

Gate for making Ricochet Depths public. Nothing here is a formality: an unchecked box that is not
explicitly waived blocks the launch.

**Build:** `3.0.0` (concept alignment) · **Status:** feature-complete and green headlessly, **not
yet verified in Studio or on a published server.** Section 2d is the 3.0 Studio pass. Sections 2–5 below are the remaining work, and section 8 lists
the steps only the owner can do. The ordered Studio procedure is `docs/STUDIO_VALIDATION_CHECKLIST.md`
(V1–V9).

## 1. Build status

| Check | State | Notes |
|---|---|---|
| `luau-compile` on all sources | PASS | 127 sources + 44 test files |
| `luau-analyze` lint | PASS | zero findings in `src/` or `tests/` |
| `rojo build` | PASS | Rojo 7.7.0 |
| Headless test suite | PASS | 815 tests, 0 failures |
| 3.0 home base | PASS | build/upgrade through the purchase path, Hearth gates, tiles and swaps, layouts cleaned against what is built, offline claims (math, cap, two-server idempotency, auto-claim before a yard upgrade), cheers (daily, caps), 8 plots, remotes sanitised |
| 3.0 run changes | PASS | haul share on defeat and leaving, Bank loot door after extract points (depth bonus, tie keeps descending), 7 daily modifiers and the once-a-day bonus, the first descent (clustered opener, forced Split Shot, fusion "try it now", Hoard Keeper, flag set on finish), card labels/icons, RECOMMENDED + auto-pick, reroll (free, then tokens), respec, unlock levels, party and friend bonus, party enemy scaling |
| 3.0 economy | PASS | no coins or stats sold (Premium coin bonus removed), passes as entitlements, Revive/Reroll receipts as tokens, revive tokens (once a run, grace window), cosmetics by coins/level/pass, presets, rewarded video (flagged off), private server feature |
| 3.0 daily loop and telemetry | PASS | forgiving 7-day track (never resets; day 5/7 extras), funnel steps once ever, economy events for every grant and spend |
| 2.0 redesign | PASS | orbs (spend, drop, pickup, roll home, trick shot), bounce power, dash (i-frames, cooldown, Blink Strike, Recall), combo, Surge (pool, auto-pick), waves, Mirror/Sponge/Magnet/Runner, barrels (chains), boost pads, portals (exits clear of cover), loot, Crystal Hunt, Beacon, Gallery, doors and votes, Trials, mini-bosses, a full nine-room descent with everything on |
| Shot effects, champions | PASS | crits, burns (full duration), arcs, chained explosions, chill, Siphon, Second Wind; champion stats, orb ring, regen, reuse clears tags |
| Rigs, Pact, Journal | PASS | unlock rules, lobby-only, read-only refusals, group Pact merge, Heat reaching a real run, one claim per achievement, schema v8 migration |
| Co-op revives | PASS | revive in range, drain out of range, helper credit, solo never |
| Daily rewards, quests, codes | PASS | streaks and resets, once per day across rejoins, quest progress and single claim, codes once per account, read-only pays nothing |
| Leaderboards | PASS | batched writes, top-ten render, offline text when the store is unreachable |
| Levels | PASS | XP from runs, daily rewards, quests and codes; level-up coins; Level column and nameplates |
| Rooms load under the player | PASS | every room in every arena slot: floor under the spawn, cover and enemies on it; the stub now treats Position and CFrame as one property |
| Concurrent arenas | PASS | two groups run side by side, isolated; slots freed and reused; payout keys unique per slot |
| Multiplayer gates | PASS | 2-player minimum, 4-player cap with overflow, 15s/5s countdowns, cancel on leave |
| Coins | PASS | drops, magnet, collection, room-clear sweep, payout, defeat rules, leaver paid once |
| Robux receipts | PASS | granted once (as Reroll / Revive tokens), only after save; unloaded profile and failed save retried; id 0 never sold |
| No z-fighting | PASS | no two overlapping visible top faces within 0.05 studs, in any layout |
| Geometry integrity | PASS | every layout: bevels and reflectors at 45°, spawn open in 8 directions, shielded posts flankable; rooms correct at any arena origin |
| Lobby | PASS | invisible 100-stud barrier and ceiling; props clear of spawn, portal, gates and kiosks; every sign prints on a SurfaceGui |
| Shop purchases | PASS | including cross-server double-charge and overspend (now on buildings); pass items free with the pass, level items never sold |
| No binary files in git | PASS | lobby, arenas, enemy models and the descent shaft are all built at runtime |
| Property-based fuzz suite, soak | PASS | seeded; instance counts flat |
| No secrets, keys, cookies or private IDs in the repo | PASS | `DebugConfig.AllowedUserIds` and every Robux id ship empty/0 by design |
| Version string surfaced in-game | PASS | Options panel, from `RunConfig.Version` |

## 2. Studio validation (Play Solo and local servers)

Earlier sessions confirmed bootstrap, aiming, firing, ricochets, pooling and the read-only
fallback. Everything else is unverified.

- [x] Rojo connects and syncs with no errors
- [x] Drag-to-aim fires; the shot travels flat and ricochets visibly
- [ ] Lobby: signs readable from across the hall; cannot jump out anywhere (V9.1–9.2)
- [ ] Solo Portal starts a solo run with the descent cinematic (V9.3), and you land on the
      Upper Ruins spawn pad, not in empty space
- [ ] Coins drop, fly to you and count on the HUD; results show coins earned (V9.4, V9.8)
- [ ] Health regenerates after a few seconds without damage (V9.5)
- [ ] Bulwark shield turns on its own; its open side can be hit (V9.6)
- [ ] Upgrades panel hidden in the lobby; Store button hidden in a run (V9.7)
- [ ] Armory and Cosmetics tabs sell and equip; balance updates after a run (V9.9)
- [ ] The whole V8 section (camera, flicker, models, zones, mechanics, boss)
- [ ] No errors or warnings in the Output window across a full run, including no `[place]`
      warnings at startup (streaming, template Baseplate, stray SpawnLocations)

## 2b. 1.3.0 features (Play Solo)

- [ ] Take Ignite and Chain Arc: burning enemies glow orange, arcs show blue bursts and numbers
- [ ] Volatile: a kill in a cluster chains explosions; the big orange burst reads clearly
- [ ] A champion in the Foundry has a glow and a name tag; a Volatile champion's orb ring is dodgeable
- [ ] Rigs: the RIGS menu shows locks by level; selecting one changes the next run (Scatter fires two)
- [ ] Pact: locked before the first extraction; after it, +/- set ranks, the HUD shows Heat, the
      results show the bonus, and Drought stops healing
- [ ] Journal: claim OutAlive after an extraction; the Codex fills in as you play
- [ ] Second Wind: a fatal hit shows "SECOND WIND!" and leaves you at half health

## 2c. 2.0 redesign (Play Solo). Highest risk first.

- [ ] **Dash:** Q / Shift / DASH moves the character about 15 studs quickly and smoothly
      (client LinearVelocity in Plane mode); it does not fling, stick, or fight the Humanoid;
      the button counts down
- [ ] **Orbs:** after three throws the aim line greys out; orbs lie on the floor glowing, are
      picked up by walking over them, and roll home after a second; a two-bounce kill shows
      "TRICK SHOT!" and the pip refills
- [ ] Bounce power reads: a banked shot visibly grows and changes colour, and hits harder
- [ ] Wave circles pulse on the floor before a wave lands, never under the player's feet
- [ ] Surge strip appears above the health panel, 1/2/3 and taps work, it never blocks aiming
- [ ] Doors: after the card, two doors show; the vote advances the run; Trick Shot Gallery works
- [ ] Barrels explode and chain; boost pads and the Rift portals move shots as described; a
      shot through a portal never leaves the room
- [ ] Crystal Hunt, Signal Tower and a Treasure Runner all play and clear
- [ ] The Colossus and the Forge Press: the slam ring shows before the slam; the boss bar shows
- [ ] Mirror: a straight shot does nothing, a banked one hurts; the first-sighting hint shows
- [ ] Health bars appear over hurt enemies; shatter shards and the room-clear flash look right,
      and disappear with Reduced Flash on
- [ ] Performance with 40 enemies alive and burning (Highlights are capped at ~31 by the engine)

## 2d. 3.0 concept alignment (Play Solo and local servers). Highest risk first.

The first descent and the Outpost are built at runtime and have only run against the stub.

- [ ] **First descent:** a fresh account (or a profile with `Flags.FirstDescentDone = false` in the
      dev datastore) spawns facing the well and, once the character exists, drops straight into
      the First Pit with no menu in the way. The banner reads "BOUNCE SHOTS. BREAK EVERYTHING.",
      and the aim hint line pulses ahead of the player until the first shot.
- [ ] First Pit: the Drifter pack is in view from the room spawn and the first hit lands within
      5-15 s. First card by ~30 s; Split Shot is offered after rooms 1 and 2; taking the second
      opens "FUSION! Try it now" with Fusillade alone. The Hoard Keeper bursts into coins, and
      its doors include BANK LOOT.
- [ ] Rejoin after the first descent: it does not start again (the flag saved).
- [ ] **Outpost plots:** the Outpost kiosk teleports you onto your plot's entry pad; the plot has
      your name on the sign, the Camp Hearth on tile 6, and "Manage base" / "Cheer" prompts on
      the Hearth. The entry pad's prompt returns you to the hall. The Outpost ground and barrier
      hold players in (walk to every edge). Plots do not overlap the hall or each other.
- [ ] **Base panel on a phone:** the 4x4 grid and the building list fit; tap a building then a
      tile builds or moves it, and the plot rebuilds straight away (storeys rise with levels,
      labels read "Forge Lv3"); CLAIM shows the yard's coins; VISIT and CHEER work between two
      players; a cheer toasts both players and pays once a day.
- [ ] **Results:** after a run the camera swings over your plot for 3 s and hands back cleanly;
      the haul line shows banked or lost coins; "Your haul builds ..." is right; DESCEND starts a
      new solo run once back in the hall; BUILD AT BASE teleports you to your plot.
- [ ] **Card picker:** emoji icons render on every card (Roblox emoji support varies by
      platform: check PC, phone and console), labels stay on one line, the RECOMMENDED tag is
      on one card, REROLL (FREE) then REROLL (n left) with tokens, and CHANGE MY CARD appears on
      the door stage in rounds 1-2 only.
- [ ] **Daily modifier:** the hall's "TODAY" board and the HUD chip agree; a Gold Rush / Bouncy
      Walls day visibly changes a run; the bonus toast appears once on the first run of the day.
- [ ] **Revive token:** with a token (day-5 reward, or grant one in the dev store) and solo, going
      down shows USE REVIVE for 8 s; using it stands you up at half health; once a run.
- [ ] **Emotes and cosmetics:** Wave plays over the head for 2.5 s in the hall, not in a run; a
      bought theme and sign recolour your plot at once; a nameplate title shows "Lv N · Title".
- [ ] **Presets:** SAVE in slot 1, change rig and trail, LOAD restores both.
- [ ] **Party bonus:** two Roblox friends in a gate both see +5% party and +10% friend coins
      (friendship lookups happen in the background: join, wait a few seconds, then descend).
- [ ] **Analytics:** after a first session, Creator Hub → Analytics → Onboarding shows the seven
      funnel steps, and Economy shows coin sources (run, daily, offline...) and sinks (buildings,
      cosmetics).
- [ ] With `FeatureFlags.PaidRevive` / `RewardedVideo` turned on in a **test** experience only:
      the Revive product prompts while down and revives on purchase; an ad shows at results
      (where eligible) and pays the fixed bonus up to 3 a day. Leave both off until this passes.
- [ ] **Private server:** the owner sees FEATURE IN HALL in the base panel's visit list; the
      hall's board then names the base and its prompt visits it.

## 3. Multiplayer validation (Studio → Test → Local Server with 2–4 players)

- [ ] Two players in Gate I start together after 15s; one player alone never starts (V9.10)
- [ ] A second group in Gate II starts while the first is still playing, in a separate arena (V9.11)
- [ ] Each player receives and resolves their own upgrade offer
- [ ] One player leaving mid-run does not disturb the others, and keeps their coins
- [ ] The last player leaving ends the run and frees the arena
- [ ] One player going down does not end the run; all going down does
- [ ] A 9th player stepping into a full gate is moved back out
- [ ] A downed player crawls; standing next to them revives them in about 3.5s, and the HUD
      shows "X is down!" to everyone else
- [ ] Two players with different Pacts run at the lower rank of each condition
- [ ] Door votes: both players see live vote counts; the vote closes once both have voted
- [ ] Each player sees their own floor orbs bright and a teammate's dimmed, and can only pick up
      their own

## 4. Datastore and purchases (published test experience)

Requires a separate test experience with **Enable Studio Access to API Services** on.
Development builds write to the `dev_v1` scope and can never touch live data.

- [ ] Coins persist across leave and rejoin; the leaderboard shows the balance
- [ ] `BindToClose` flushes on server shutdown
- [ ] An older profile keeps its balance (salvage became coins without migration)
- [ ] A shop purchase persists across leave and rejoin, and the balance matches
- [ ] With real ids set: a coin pack credits once; 2x Coins doubles a run's payout; VIP unlocks the Gold trail

## 5. Mobile validation

- [ ] iPhone emulation: HUD readable, nothing clipped; Store button and gate text fit
- [ ] iPad emulation: three cards fit on one row
- [ ] Touch aiming, twist to turn, pinch to zoom; a second finger never fires
- [ ] The shop panel and its tabs fit and scroll on the narrowest supported width
- [ ] Every button meets the 48px minimum target

## 6. Known issues at 1.3.0

| # | Issue | Severity | Plan |
|---|---|---|---|
| 1 | Nothing added since 0.6.0-dev has run in Studio or on a published server. | **Blocker** | Sections 2–4 before going public. |
| 2 | Audio uses sounds built into the Roblox client (`rbxasset://sounds/...`). They play with no uploads, but they are generic, and one missing on some client would simply be silent. There is no music. | Medium | Verify in V10.3; upload original sound effects and a lobby music loop when you can. |
| 3 | Robux items are inert until real ids are pasted into `MonetizationConfig`. | Launch step | Section 8, step 10. |
| 4 | Balance is tuned against bots, not people. The 1.0.0 tuning was measured against bots that (by a stub bug) never moved. Bots that walk and kite now beat the Warden Prime 93–100% of the time, but they see everything and dodge perfectly. How hard it is for people is unknown. | High | Playtest the boss before launch; tune `EnemyConfig.WardenPrime` from real deaths. |
| 5 | Run length: the dry run's floor is ~1.5 min for competent bots against a 6–8 minute target. Real players are much slower (aiming, cards, walking, the cinematic), but it is unmeasured. | Medium | Measure in analytics. |
| 6 | Enemies do not path around pillars. | Low | Revisit only if players notice. |
| 7 | Telemetry only prints to the Studio output; no transport. | Low | Wire once an analytics destination is chosen. |
| 8 | The sky is Roblox's built-in night sky, tinted per zone; no custom skybox art. | Low | Optional: paste six asset ids into `SkyConfig`. |
| 9 | Players in the lobby cannot watch a run in progress; there is no spectate. | Low | Post-launch. |
| 10 | 1.3.0 balance is untested with people: element cards, champions and Heat above ~6 are first guesses, and elemental damage ignoring shields may make the Warden Prime too easy for an Arcanist. | High | Playtest; tune `CombatConfig`, `PactConfig` and `RigConfig`. |
| 11 | Champion glows use `Highlight`, and Roblox draws only about 31 at once. The enemy cap is 28, so this fits, but a busy co-op room is the place to watch. | Low | Check in V11 with 4 players. |
| 12 | No onboarding hints yet for Rigs, the Pact or revives. | Medium | Add to `OnboardingView` hints. |
| 13 | 2.0 balance is bot-tuned. Room 2 (Mirrors and Chasers) ends a quarter of bot runs; bots cannot bank, players can. | High | Playtest room 2 and the two mini-bosses first; tune `EnemyConfig`, `ArsenalConfig`. |
| 14 | No music, so the combo cannot drive music intensity yet. | Medium | Upload a lobby loop and a layered combat loop. |

## 7. Rollback

Every step is a separate commit, and each one leaves the suite green, so reverting to any
earlier commit yields a working build.

- **A feature misbehaves:** turn its flag off in `FeatureFlags.luau` and republish.
- **The shops misbehave:** `FeatureFlags.SalvageShop = false` disables both kiosks and the shop
  remotes; owned levels stay in profiles untouched.
- **Robux purchases misbehave:** set the offending id back to 0 in `MonetizationConfig`, or
  `FeatureFlags.Monetization = false`. Receipts already granted stay granted.
- **Enemy models misbehave:** `FeatureFlags.EnemyModels = false` shows the plain hitboxes.
- **Persistence misbehaves:** `FeatureFlags.Persistence = false` makes every session read-only.
- **Never roll the schema version back.** Add a forward migration instead.

## 8. Manual steps in Roblox Studio / Creator Hub

These cannot be done from this repository and need a human with account access.

1. **Create the experience.** Build the place with `rojo build -o RicochetDepths.rbxlx`, open it
   in Studio, and publish it.
2. **Delete the Baseplate template's parts** (`Baseplate` and `SpawnLocation`) before publishing,
   if the place started from the Baseplate template. The lobby has its own spawn. The server
   prints a `[place]` warning in Output while either is still there.
   **Check that `Workspace.StreamingEnabled` is off.** The project sets it, but if Rojo's live
   sync cannot write it, untick it by hand; the server warns while it is on.
3. **Create a separate test experience** and publish the same place there for sections 2–4.
4. **Enable API services** on the test experience (Game Settings → Security).
5. **Set max players to 8** (Game Settings → Players). The Outpost has 8 home-base plots, one per
   player; two gates of 2–4 plus solo players, each group in its own arena.
6. **Enable the platforms** you intend to support (Game Settings → Places → Devices).
7. **Set the icon and thumbnails** (Creator Hub → Experience). Ready-made originals are in
   `marketing/`: `icon.png` (512×512) and `thumb1–3.png` (1920×1080). Add one or two real
   in-game screenshots as well once the game runs. The store description is in
   `marketing/STORE_PAGE.md`.
8. **Sounds work out of the box** with Roblox's built-in sounds. For a distinctive identity,
   upload your own and paste their ids into `SoundConfig`.
8a. **Create the badges** (Creator Hub → Engagement → Badges): Welcome, First Descent,
   Extracted, Bank Shot Artist, Level 10, Level 25, Level 50. Paste each id into
   `MetaConfig.Badges`. Until then no badge is awarded.
8b. **Promo codes** live in `MetaConfig.Codes` (RICOCHET, DEPTHS, LAUNCH, BANKSHOT ship). Post
   them on your group and socials; add new ones and republish; set `Expires` to retire one.
8c. **Make a Roblox group** for the game and link it on the experience page; that is where
   players look for codes and updates.
9. **Optional custom sky:** upload six skybox images and paste their ids into `SkyConfig`.
10. **Create the passes and products** (Creator Hub → Monetization), then paste each id into
    `MonetizationConfig` (anything left at 0 is never offered):
    - Game pass **Explorer Pass**, 99–149 R$ (129 suggested): +1 loadout preset, the Explorer
      nameplate and the Banner base sign. Describe exactly that.
    - Game pass **Supporter Pack**, 299–399 R$ (349 suggested): Gold trail, Gilded base theme,
      Cheer emote, +2 presets, +2 h offline storage, Supporter chat tag.
    - Developer product **Revive**, 29 R$: one revive, used while down, once a run. Leave
      `FeatureFlags.PaidRevive = false` until section 2d's check passes.
    - Developer product **5 Rerolls**, 49–79 R$ (59 suggested).
    - Developer product for the **rewarded video** reward (`MonetizationConfig.Ads.RewardProductId`),
      only if you enable `FeatureFlags.RewardedVideo`; check ad eligibility for the experience.
    - The retired 2x Coins / VIP passes and coin packs must **not** be recreated: the concept's
      launch economy sells no power. If they already exist from 2.0, take them off sale.
    Test every purchase in the test experience first.
10a. **Turn on regional pricing** for every pass and product (Creator Hub → Monetization →
    pricing), and use price optimization one item at a time (concept S18/S19).
10b. **Private servers:** enable them (Game Settings → Permissions / Monetization) at 49–99 R$ a
    month (the concept's range). Owners get base-showcase control (FEATURE IN HALL); public
    matchmaking must stay healthy, so watch public server fill after enabling.
11. **Populate `DebugConfig.AllowedUserIds`** in the test build only, for the F3 overlay. Never
    commit real ids.
12. **Complete the experience questionnaire** (maturity and content) in Creator Hub before making
    the experience public.
13. **Check analytics after the first sessions** (Creator Hub → Analytics): the onboarding funnel
    and economy events described in `docs/GO_NO_GO.md`. Do not scale acquisition until bounce
    and D1 are at or above the similar-experience benchmark shown there.
