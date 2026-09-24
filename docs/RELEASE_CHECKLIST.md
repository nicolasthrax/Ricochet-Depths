# 1.0 Launch Checklist

Gate for making Ricochet Depths public. Nothing here is a formality: an unchecked box that is not
explicitly waived blocks the launch.

**Build:** `2.0.0` · **Status:** feature-complete and green headlessly, **not yet verified in
Studio or on a published server.** Sections 2–5 below are the remaining work, and section 8 lists
the steps only the owner can do. The ordered Studio procedure is `docs/STUDIO_VALIDATION_CHECKLIST.md`
(V1–V9).

## 1. Build status

| Check | State | Notes |
|---|---|---|
| `luau-compile` on all sources | PASS | 100 sources + 38 test files |
| `luau-analyze` lint | PASS | zero findings in `src/` or `tests/` |
| `rojo build` | PASS | Rojo 7.7.0 |
| Headless test suite | PASS | 655 tests, 0 failures |
| 2.0 redesign | PASS | orbs (spend, drop, pickup, roll home, trick shot), bounce power, dash (i-frames, cooldown, Blink Strike, Recall), combo, Surge (pool, auto-pick), waves, Mirror/Sponge/Magnet/Runner, barrels (chains), boost pads, portals (exits clear of cover), loot, Crystal Hunt, Beacon, Gallery, doors and votes, Trials, mini-bosses, a full nine-room descent with everything on |
| Shot effects, champions | PASS | crits, burns (full duration), arcs, chained explosions, chill, Siphon, Second Wind; champion stats, orb ring, regen, reuse clears tags |
| Rigs, Pact, Journal | PASS | unlock rules, lobby-only, read-only refusals, group Pact merge, Heat reaching a real run, one claim per achievement, schema v8 migration |
| Co-op revives | PASS | revive in range, drain out of range, helper credit, solo never |
| Daily rewards, quests, codes | PASS | streaks and resets, once per day across rejoins, quest progress and single claim, codes once per account, read-only pays nothing |
| Leaderboards | PASS | batched writes, top-ten render, offline text when the store is unreachable |
| Levels | PASS | XP from runs, daily rewards, quests and codes; level-up coins; Level column and nameplates |
| Rooms load under the player | PASS | every room in every arena slot: floor under the spawn, cover and enemies on it; the stub now treats Position and CFrame as one property |
| Concurrent arenas | PASS | two groups run side by side, isolated; slots freed and reused; payout keys unique per slot |
| Multiplayer gates | PASS | 2-player minimum, 8-player cap with overflow, 15s/5s countdowns, cancel on leave |
| Coins | PASS | drops, magnet, collection, room-clear sweep, payout, defeat rules, leaver paid once |
| Robux receipts | PASS | granted once, only after save; unloaded profile and failed save retried; id 0 never sold |
| No z-fighting | PASS | no two overlapping visible top faces within 0.05 studs, in any layout |
| Geometry integrity | PASS | every layout: bevels and reflectors at 45°, spawn open in 8 directions, shielded posts flankable; rooms correct at any arena origin |
| Lobby | PASS | invisible 100-stud barrier and ceiling; props clear of spawn, portal, gates and kiosks; every sign prints on a SurfaceGui |
| Shop purchases | PASS | including cross-server double-charge and overspend; VIP-only item gated |
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
5. **Set max players to 20** (Game Settings → Players). Two gates of 8 plus solo players, each
   group in its own arena; up to 6 runs at once per server.
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
10. **Create the passes and products** (Creator Hub → Monetization): passes *2x Coins* and *VIP*,
    developer products *500 / 1,500 / 5,000 Coins*. Paste each id into `MonetizationConfig`.
    Test a purchase in the test experience first.
11. **Populate `DebugConfig.AllowedUserIds`** in the test build only, for the F3 overlay. Never
    commit real ids.
12. **Complete the experience questionnaire** (maturity and content) in Creator Hub before making
    the experience public.
13. **Check analytics after the first sessions** (Creator Hub → Analytics).
