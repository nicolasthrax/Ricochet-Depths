# Ricochet Depths — Progress

Original IP. Nothing in this project copies names, art, layouts, wording, enemies, cards or
presentation from any existing game.

## Current milestone

**3.0.0: concept alignment. The game now matches the original concept (steam-to-roblox.xlsx):
the Outpost home base with 12 buildings, offline claims and friend visits; runs of 1–4; the haul
at risk with "Bank loot" extract points; 7 daily modifiers; the first-60-seconds opening
descent; card labels, a recommended card, reroll and early respec; the party and friend bonus;
the launch economy with no paid power; a forgiving 7-day track; onboarding-funnel and economy
telemetry; and the UI for all of it. Green on every gate: syntax, lint, Rojo build and
815 headless tests. Nothing in 3.0 has run in Studio yet; see section 2d of the release
checklist. `docs/CONCEPT_TRACEABILITY.md` maps every concept item to code and tests.**

Before it: **2.0.0: the redesign. Orbs, bounce power, the dash, combo, Surge, waves and swarms, ricochet-
aware enemies, barrels, boost pads and portals, objective rooms, doors, Trials and two
mini-bosses. Green on every gate: syntax, lint, Rojo build and 655 headless tests. Nothing in
2.0 has run in Studio yet; see the 2.0 section of the release checklist.**

Before it: **1.3.0: the depth build. Shot effects and evolutions, champion enemies, six rigs, the Depth
Pact (Heat), co-op revives, achievements and the Codex. Green on every gate: syntax, lint, Rojo
build and 612 headless tests. Awaiting Studio and published-server validation (V9, V10, V11 and
the launch checklist).** The research behind it is in `docs/DESIGN_RESEARCH.md`.

This build answers the third playtest's notes and adds what a public launch needs:

- **Multiplayer.** Two gates of 2–8 players plus a Solo Portal. Each group plays in its own
  arena on the same server (`ArenaDirector`), so several runs happen at once.
- **Economy.** Coins drop from kills and are spent in the Armory (permanent upgrades) and
  Cosmetics (trails). Robux passes (2x Coins, VIP) and coin packs are wired but ship inert until
  real ids are set.
- **Feel.** The shielded Bulwark's shield turns on its own. Health regenerates between fights.
  A descent cinematic plays when a run starts and between rooms. A night sky tints to each zone.
- **Lobby.** Readable signs, an invisible barrier and ceiling, and no upgrades panel in the lobby.

`docs/RELEASE_CHECKLIST.md` lists what remains: Studio, multiplayer, datastore and purchase
validation, plus the owner's Creator Hub steps (sounds, Robux ids, icon, max players).

### Where the stub is more forgiving than the engine

These are the places a headless pass **cannot** fail but the real engine might. They are the
highest-value targets for the first Studio session, in rough order of risk. None is a known
defect; each is an untested assumption.

| # | Assumption the stub makes | What the engine does instead | Watch for |
|---|---|---|---|
| 1 | *Now modelled.* The harness scheduler makes `task.wait` really suspend, and the fake DataStore holds writes in flight, so retry cost and shutdown timing are tested headlessly. Shutdown saves now run in parallel under a 25s budget. | Real DataStore latency, throttling under load and the exact BindToClose behaviour are still assumptions. | Studio step V6b; a shutdown with a slow store. |
| 2 | *Now modelled.* Loads, saves, leaves and rejoins interleave under the scheduler, and every race in `docs/PERSISTENCE_SHUTDOWN_PLAN.md` (P1–P5) has a regression test and a fix. | Real request ordering, and two genuinely separate servers, are still simulated with two service instances sharing one fake store. | A real cross-server rejoin during playtest. |
| 3 | *Fixed in 0.6.0-dev.* A participant whose character respawns mid-run (a reset, a fall, or a room start that caught them mid-respawn) is sent back to the current room by `HandleCharacterAdded`. | Whether `CharacterAdded` and the root part arrive in the order assumed. | A player stuck in the lobby during a run. |
| 4 | RemoteEvent arguments pass by reference with no serialisation. | Roblox deep-copies and drops non-string/number keys, functions and metatables, with a 1MB cap. Payloads were reviewed and are all primitives, but nothing tests this. | Malformed or empty payloads client-side. |
| 5 | One shared virtual clock across "server" and "client". | `os.clock()` is per-process and unrelated across machines. *(This one did bite — see the upgrade countdown fix in 0.5.1-dev.)* | Any other cross-machine time comparison. |
| 6 | Raycasts only see boxes the test registered. | The Include filter covers everything under `Arena`, including the `Room` folder's floor and spawn pad and the enemy pool folder. | Shots stopping on geometry the tests never modelled. |

### Verified headless vs requires Studio

Everything below is stated against a **stubbed engine**. The stub models axis-aligned box
raycasting, the engine's origin-inside-a-part behaviour, RaycastParams filtering, CanQuery,
signals, instance parenting and a virtual clock. It does **not** model the real physics solver,
replication, character controllers, rendering, input, or DataStore.

| Area | Verified headless | Still requires Studio |
|---|---|---|
| Ricochet maths | Reflection law across heading and incidence sweeps; containment in all four layouts at 36 headings; anti-tunnelling; same-frame multi-projectile resolution | That the real solver moves parts the way the stub assumes, and that it looks right |
| Pools | Exact size held across 25 runs, ~3600 frames of fire and 200 enemy churn cycles | Instance counts in a live Explorer tree |
| Enemies | Spawn, damage, shield arc, contact cadence, bounds, telegraph phases, cleanup | Whether the behaviour reads clearly on screen |
| Run loop | Full four-room run, defeat, replay, four soft-lock guards, every state transition legal under 25 random 1200-event sequences | Teleports landing players somewhere sensible |
| Co-op | 2/3/4-player runs, per-player offers, late join, partial-team death | Real clients, real replication, real latency |
| Persistence | Schema migration, retries, read-only fallback, reward ledger, autosave | Actual DataStore behaviour and quotas |
| Room geometry | 45° bevels and reflectors built from one `RoomGeometry` description; rotated-box raycasting in the harness; reflection off a 45° face; containment in all four layouts; spawn, marker and flank clearance | That the engine's collision agrees with the harness's rotated boxes |
| Shop and meta | Purchases, refusals, max level, read-only refusal, cross-server double-spend and overspend, grant-then-buy in one save, schema v5 migration, bonuses reaching a run, trails on pooled shots, the remote path end to end through `GameBootstrap` | Real DataStore behaviour under a purchase |
| Lobby | Ready-pad countdown, reset, crowding, over-full lobby; pads and kiosk built; a run starting from a pad through the real bootstrap | Walking onto the pads, the kiosk prompt |
| Audio and juice | Pitch and volume curves, pooled voices, throttling, inert placeholders; camera shake decay and cap; damage-popup pooling; impact payload classification | Everything audible and visible |
| UI | `ShopView` renders prices, levels and actions from a profile. Other views are constructed but never rendered | All of it: layout, scaling, touch, readability |
| Input | Aim gesture tracking, touch zones and deadzones as pure functions | The gestures themselves on a real device |
| Performance | Instance counts and pool accounting only | Frame time, replication cost, mobile headroom |

## Completed milestones

### Phase 1 — Prototype
- Rojo scaffold, `rojo build` clean.
- Drag-to-aim (mouse + touch), server-validated fire requests.
- Pooled projectiles with swept-segment ricochet, bounce and lifetime budgets.
- Muzzle clearance so a shot taken against a wall never spawns inside it.
- Batched cosmetic impact events instead of one remote per contact.

### Milestone 4 — Complete run loop
- Lobby with a `ProximityPrompt` pedestal to begin a descent (works on mouse, touch and gamepad).
- Explicit state machine: `Lobby → Starting → Combat → UpgradeChoice → Transition → … → Results → Cleanup`.
- Three normal rooms plus one elite room, all built at runtime from `RoomConfig` layouts.
- Room-clear detection based on what actually spawned, plus a room time limit and a hard run
  time limit, so a run cannot soft-lock.
- Inter-room transition with player repositioning and revival of downed players.
- Extraction, defeat, timeout and abandonment outcomes.
- Results screen: rooms cleared, enemies defeated, best ricochet chain, shots, damage taken,
  duration, upgrades taken and salvage earned.
- Return-to-lobby flow that resets run state and returns every pooled instance.

### Milestone 5 — Enemies and combat readability
- `Drifter` (sentry, teaches ricochet), `Chaser` (pressure), `Bulwark` (front-shielded, must be
  hit from the flank or behind), `WardenCore` (elite, built from the same systems).
- Telegraphed lunges: the enemy roots itself and changes colour before committing.
- Server-authoritative movement, contact damage on a per-enemy cooldown, arena bounds clamping.
- Player health, invulnerability windows, down state and revive-at-next-room.
- Caps on active enemies, active projectiles and impact effects per batch.

### Milestone 6 — Strategic upgrades
- 15 cards across Projectile / Power / Survival / Salvage.
- Every card has a stable ID, title, player-facing description, rarity weight, stack cap,
  eligibility condition and pure-data effects.
- Fusion is expressed as an ordinary eligibility requirement on prerequisite stacks
  (`Fusillade` needs `SplitShot` ×2, `Caroms` needs `LongBounce` ×2), so it needs no separate UI.
- No-op choices are suppressed: `TightGroup` is only offered once you fire more than one projectile.
- Three weighted choices per event, drawn without replacement, with a 10s auto-pick.
- Active upgrades shown in the HUD.

### Milestone 7 — Co-op foundation
- Shared run ownership: one player starting pulls in everyone in the lobby.
- Late join rule: a player arriving mid-run is queued and admitted at the next room boundary
  with a fresh state, never mid-fight and never mid-upgrade-round.
- Upgrade policy **A**: each player receives their own offer with its own timer. The round ends
  when all offers resolve; an unanswered offer auto-picks, so one idle player cannot deadlock.
- Downed players stay down for the room and return at the start of the next; defeat requires
  every participant to be down.
- Leaving clears offers, rate-limit buckets, fire cooldowns and telemetry identity. The run ends
  only when the last participant leaves.

### Milestone 8 — Persistence and rewards
- Versioned profile schema (now v4) with safe defaults and ordered forward migrations.
- `UpdateAsync` writes with capped exponential backoff; a failed load yields a read-only session
  where the run still plays but nothing is written and no reward is persisted.
- Two-layer reward idempotency: an in-memory per-server ledger and a bounded per-profile run
  ledger, with the ledger unioned on save so a concurrent write cannot resurrect a paid run.
- Separate `dev_v1` datastore scope for development builds; save on leave, autosave of dirty
  sessions only, and `BindToClose`.

### Milestone 9 — Onboarding, UI and mobile
- Contextual hints that appear in the moment and retire once the player finishes a run; no modal
  tutorial before the first shot.
- HUD for health, room progress, objective and active upgrades; card picker with countdown;
  results screen.
- Options panel: reduced flash, effect intensity, screen shake. Settings are sanitised
  server-side against a spec before storage.
- The effective fire cooldown is sent to the client so a refused shot is visible before it is
  sent, rather than vanishing silently.
- Touch and mouse share one aim path; 48px minimum touch targets; scale-based card layout.

### Milestone 10 — Quality and performance
- `MatchService` split into MatchService / MatchMembership / MatchFlow / MatchCombat /
  MatchBroadcast, none over 210 lines.
- Developer overlay on F3, gated by `DebugConfig` so it is inert for normal players in a
  published build, fed by a server stats push.
- Soak tests: 25 consecutive runs with a flat instance count, ~3600 frames of continuous fire
  with the pool constant, 200 enemy spawn/clear cycles.
- Caps: 150 projectiles, 28 active enemies (36 pooled), 24 impacts per batch, all configurable.
  Every cap degrades by refusing or dropping, never by allocating.

### Milestone 11 — Release package
- `README.md`, `docs/PLAYTEST.md`, `docs/RELEASE_CHECKLIST.md`.
- `FeatureFlags.luau`: anything off is inert — no UI entry point, no remote handler, no data.
- Build version surfaced in the Options panel.
- Telemetry funnel: run start, room start, room clear, card offered, card chosen, shot fired,
  enemy defeated, player down, late join, run end with outcome, plus categorised errors. Rate
  limited per event. No event carries a player identity.

## Known limitations

| # | Limitation | Impact |
|---|---|---|
| 1 | **Studio coverage is partial.** Two Play Solo sessions covered bootstrap, aiming, firing and ricochets. Everything in 0.6.0-dev and 0.7.0-dev is headless-only, and UI and input have no headless coverage at all. | Blocker for playtest. |
| 2 | Co-op is verified only headlessly. 2–4 real clients have never connected. | Blocker for playtest. |
| 3 | Balance numbers are first-pass guesses. The simulated floor suggests runs are well under the 6–8 minute target, but that is a bot estimate, not a measurement. | Tune from playtest data only. |
| 3a | The dry-run bots cannot plan bank shots, so they understate how fast a skilled player clears cover-heavy rooms and overstate how lethal room 3 is. | Inherent to the tool; stated wherever its numbers appear. |
| 4 | Audio hooks are wired (fire, bounces with rising pitch, hits, blocks, shatter, card pick, room clear), but every `SoundConfig` id is an empty placeholder and `FeatureFlags.Audio` is off, so the game is silent. | Upload original assets, fill the ids, flip the flag. |
| 5 | Enemies clamp to arena bounds but do not path around pillars or reflectors. They are held out of the sealed triangle behind each corner bevel. | Revisit if playtests flag it. |
| 5a | The dry-run bots walk through cover and cannot bank, so they measure nothing about flank geometry; Room 3's layout changes are checked by geometry tests, not by the bots. | Inherent to the tool. |
| 6 | Telemetry only prints to the Studio output; no external transport is wired. | Needs a destination chosen. |
| 7 | Impact bursts are still placeholder parts, not particles. Damage numbers and camera shake are in. | Post-playtest polish. |
| 7a | Enemy models are client-side parts that follow the server hitbox each frame. Their silhouettes roughly match their hitboxes but are not identical, so a shot can visibly graze a model and miss. | Check in V8.5; tighten models if players notice. |
| 7b | Sweepers and breakables are modelled statically in the dry run's physics (sweepers at rest, breakables never break), and orbs are blocked by a broken breakable's footprint until the room ends. | Minor; the dry run is an estimate anyway. |
| 7c | The Warden Prime's numbers (80 health, orb rings, summons) are first guesses; bots killed a 36-health version in ~6s. | Tune from playtest data. |
| 8 | `MatchService` and its four installed halves use a mixin pattern; a method name collision between them would silently overwrite. Names are currently distinct. | Acceptable; noted for future edits. |
| 9 | **Accepted MVP tradeoff, not a bug.** Any participant can dismiss the results screen for the whole team, possibly while others are still reading their summary. Shared run, shared results. | Revisit only if playtesters report it. |
| 10a | Profile `Stats` (runs started, best chain and so on) are still last-write-wins across servers, so two servers finishing runs for one account at once can undercount them. Not money, and not in the approved plan. | Candidate follow-up: counters as deltas, bests merged with `max`. |
| 10 | *Resolved headlessly.* The persistence data-loss races (P1–P5) are fixed and regression-tested; see *Persistence plan progress*. What remains is confirming the model against a real DataStore. | Studio step V6b, then a playtest with salvage enabled. |
| 11 | Duplicate small idioms across modules: flattening a Vector3 to XZ (five places), point-in-box tests (`EnemyService.FindEnclosingMover`, `RoomService.GetSpawnPoint`), and list removal. | Flagged only; consolidating would move code between modules, which needs approval. |

## Manual Studio validation still required

**None of it has been done.** The ordered procedure lives in
`docs/STUDIO_VALIDATION_CHECKLIST.md`, with the exact thing to click, the exact output to expect,
and the likely cause of each failure.

- [ ] V0 Rojo connects and the instance tree matches
- [ ] V1 Lobby loads with HUD, pedestal prompt and options panel
- [ ] V2 A run reaches room 2: aiming, firing, visible ricochet, kills, upgrade pick
- [ ] V3 Both pools hold their exact configured size throughout sustained fire
- [ ] V4 Results screen dismisses without error *(engine-side confirmation of the closure fix)*
- [ ] V5 Co-op with 2–4 clients, per-player offers, and the late-join boundary
- [ ] V6a Read-only fallback with API services off: playable, warned, pays nothing
- [ ] V6b Persistence with API services on: salvage survives a restart, no double-credit

Deferred to a later Studio session: mobile emulation, sustained performance, escort-respawn
detail, full shield-arc sweep, and anything to do with balance.

## Persistence plan progress

Implementing `docs/PERSISTENCE_SHUTDOWN_PLAN.md` one step at a time, each test-first, with a
report after every step.

| Step | Change | Fixes | Status |
|---|---|---|---|
| 1 | Save immediately on reward grant | Most of P1's real-world impact | **Landed** |
| 2 | One save in flight per session, change counter instead of a dirty flag | P2, P3 | **Landed** |
| 3 | Generation tokens discard stale loads; sessions keyed by `UserId` | P4, same-server P5 | **Landed** |
| 4 | Grant-based currency applied inside the save transform; time-ordered, capped ledger | Cross-server P5, ledger double-pay and growth | **Landed** |
| 5 | Parallel shutdown saves under a shared 25s deadline, deadline-aware retries, isolated workers | P1 | **Landed** |

**All five steps have landed; the persistence overhaul is complete.** Every problem in the plan
has a regression test that failed before its fix. What none of it can prove headlessly is how a
real DataStore behaves under load, so Studio step V6b and a salvage-enabled playtest remain the
final checks.

The interim P3 exposure Step 1 introduced is closed by Step 2.

The harness now has a cooperative scheduler: `task.spawn` returns at the thread's first yield,
`task.wait` genuinely suspends, and the fake DataStore holds writes in flight and re-runs
transforms on conflict as the engine does. Concurrency bugs are now reproducible headlessly.
It is still a model: real DataStore latency, throttling and ordering must be confirmed in
Studio (V6b).

## Simulated run length

From `./scripts/dryrun.sh`. **Lower-bound estimates, not measurements.** The bots know exactly
where every enemy is, never hesitate, and cannot plan a bank shot — the game's central skill.

Since 0.7.0-dev, rooms are drawn at random per run, so columns are run-shape slots rather than
fixed rooms (the dry run seeds its plans, so these repeat exactly).

### 3.0.0

Nine rooms, with the Colossus and Forge halls as mid-run bosses. The bots never take the Bank
loot door, so every run shown goes the full depth. The dry run does not switch on depth pressure
(merged from PR #13 after this table was measured), which makes a room that drags more dangerous but does not change when it clears. "Reached the end" counts runs that cleared the
Throne; the rest were defeated.

| Bot | R1 | R2 | Colossus | F1 | F2 | Forge | A1 | Vault | Throne | Full run (median) | Floor | Reached the end |
|---|---|---|---|---|---|---|---|---|---|---|---|---|
| Direct fire, exact aim | 22.2s | 51.3s | 86.5s | 33.8s | 43.0s | 28.6s | 30.1s | 19.6s | 66.8s | 459s | 405s | 40% |
| Direct fire with aim error | 30.5s | 45.7s | 90.4s | 32.6s | 41.8s | 25.0s | 29.3s | 16.0s | 55.1s | 392s | 389s | 28% |
| Probing | 25.8s | 58.6s | 80.0s | 26.8s | 36.7s | 27.6s | 26.9s | 15.8s | 67.6s | 388s | 389s | 40% |

The target is `RunConfig.TargetRunSeconds` = 420s. The modelled floor (6.5–6.8 min) sits just
under it, and bots are faster than people, so real full runs should land at or above 7 minutes.
Banking is the short way out: after the Colossus hall is about 3 minutes in, and after the Forge
hall about 4.5. Most defeats happen in room 2 and in the Throne. Room 2 is where Chasers and
Mirrors deal the most damage (63–80 per run). A human-played defeat rate is the first number to
measure in Studio.

### 1.0.2

| Bot | Ruins 1 | Ruins 2 | Foundry 1 | Foundry 2 | Abyss 1 | Vault | Throne | Extracted | Runs reaching the boss |
|---|---|---|---|---|---|---|---|---|---|
| Direct fire, exact aim | 7.0s | 7.8s | 6.5s | 9.5s | 6.3s | 5.3s | 56.6s | 93% | 60 of 60 |
| Direct fire with aim error | 8.0s | 8.6s | 7.7s | 9.2s | 7.9s | 5.7s | 44.9s | 100% | 40 of 40 |
| Probing (throws shots off-angle when blocked) | 6.6s | 8.0s | 6.9s | 9.6s | 6.4s | 5.3s | 45.5s | 98% | 40 of 40 |

Medians, 1.0.2, with bots that move (earlier tables measured bots that never left the spawn
pad; see the 1.0.2 changelog). The bots see every enemy and kite perfectly, so they now take
almost no damage before the boss and usually beat it; the runs they lose run out of time in the
Throne. People will not play this well, so the boss's win rate for real players is still the
first number to measure after launch.

\* The exact-aim bot never probes. It stalls against targets behind cover until the room's 150s
limit clears the room. That is a bot limitation, not a room defect.

### Room 3 audit (0.6.0-dev)

The dry run now reports who deals the damage in each room. Room 3 was the audit target:

| Room 3 | Runs ending there (aim error / probing, of 40) | Damage from Bulwarks |
|---|---|---|
| Before: old layout, 4 Chasers + 2 Bulwarks | 34 / 32 | ~100% (Chasers ~1%) |
| New layout, 4 Chasers + 2 Bulwarks | 39 / 40 | 100% |
| New layout, 3 Chasers + 2 Bulwarks | 40 / 35 | 100% |
| **New layout, 4 Chasers + 1 Bulwark (shipped)** | **33 / 27** | 100% |

Two Bulwarks lunging together was the wall; the Chasers were not. Room 3 now fields four Chasers
and one Bulwark, posted away from the spawn with open ground around it. The layout was also
reworked so the spawn has all eight directions open and the Bulwark has most approach angles
free, both enforced by `tests/geometry.test.luau`. The bots cannot use flank geometry at all
(they fire straight and walk through cover), so the layout's value is for human players and
unmeasured until a playtest.

Hypotheses for playtest:

1. **Room 3 is still the hardest room.** About two thirds of probing-bot runs still end there,
   down from four fifths. A human who banks shots should do far better; watch it in playtest.
2. **Runs may be far shorter than the 420s target.** Even allowing for human aiming and full
   upgrade timers, the floor is well under target. Change nothing until real timings exist.
3. **Ricochets are load-bearing, as intended.** The probing bot clears rooms 1 and 2 roughly six
   times faster than the strictly-straight one.

With strictly direct fire, 23 rooms were force-cleared by the 150s room time limit, so the
soft-lock guard is doing real work.

## Changelog

### 3.0.0 — concept alignment

Goal: match everything in the original concept (the Overview, Roblox Playbook and Concept MVP
sheets). Built in sections A–G; `docs/CONCEPT_ALIGNMENT_HANDOFF.md` has the detail.

- **Schema v10** (`PlayerDataConfig`): Rerolls and ReviveTokens balances beside coins, all
  store-owned and ledgered; base, presets, nameplate, daily limits and funnel flags; the v8 → v9
  migration refunds every Armory level in coins, exactly once. v9 → v10 cleans up a profile
  saved by the 2.x haul build (PR #13), which also called itself v9: it drops DepthRank and
  refunds any Armory levels still held, Deep Quiver included.
- **Merged with PR #13** (the haul, Surface Lift, depth pressure and Deepen). Depth pressure is
  kept (`RunConfig.Pressure`, `FeatureFlags.Pressure`, `tests/pressure.test.luau`). The Surface
  Lift, the 40% haul share, Deep Quiver and Deepen are replaced by this release's Bank loot, 50%
  share and base buildings, since the concept puts earnable power in the base.
- **The Outpost** (`BaseConfig`, `BaseService`, `BaseBuilder`, `BaseView`): a 4x4 plot per player
  (8 plots; max players is now 8), 12 buildings bought through the purchase path and gated by
  the Camp Hearth, where earnable power now lives (the Armory is gone); a Salvage Yard with an
  8 h offline cap (Storehouse and the Supporter Pack raise it, 12 h max), claimed once per stretch
  of time across servers; a Trophy Hall; themes and signs; visits and once-a-day cheers. The
  lobby's Armory kiosk is now the Outpost portal; BASE is on the menu rail and the HUD.
- **Hub:** gates of 2–4 (solo portal for 1); spawn facing the well; no title screen.
- **Haul at risk:** a lost, timed-out or abandoned run keeps half the coins it collected;
  ColossusHall, ForgeHall and the tutorial's Hoard Keeper are extract points whose doors include
  **Bank loot** (whole haul plus a depth bonus of 60/120/160 by zone). Results show banked or
  lost coins, "your haul builds X", a 3 s look at your plot, and DESCEND / BUILD AT BASE.
- **Daily biome modifier** (`DailyModifierConfig`): 7 modifiers by UTC day, on stats, enemies and
  champions; a once-a-day bonus; the hall's TODAY board and a HUD chip.
- **First 60 seconds** (`RunConfig.FirstDescent`): a new player drops into the First Pit (a tight
  pack of harmless Drifters), is offered Split Shot twice, gets Fusillade at once ("try it now"),
  then meets the Hoard Keeper, who bursts into coins at the first Bank loot choice. A banner and a
  pulsing aim line lead the way; `Flags.FirstDescentDone` records it.
- **Cards:** every card has an icon and a three-word label; one card per offer is RECOMMENDED
  (and is the timeout's auto-pick); one free reroll per run, then Reroll tokens; a free respec in
  the first two rounds; cards unlock gradually with account level.
- **Party and friends:** +5% coins per extra member (max +15%), +10% with a Roblox friend
  (`FriendCache`, looked up off the run loop); enemies gain 35% health per extra member. A solo
  run is unchanged. The door vote cap is now 10 s, as the concept specifies.
- **Launch economy** (`MonetizationConfig`): Explorer Pass and Supporter Pack (presets, offline
  hours, cosmetics, a chat tag); Revive and Reroll-bundle products granted as tokens; revive
  tokens spent while down, once a run, with a grace window when everyone is down; cosmetics
  (trails, themes, signs, emotes, nameplate titles) earned by coins, level or pass; loadout
  presets (2 free); rewarded video (`RewardedAds`); private-server base featuring. Removed: coin
  packs, 2x Coins, VIP and the Premium coin bonus (all were coins for money). The paid Revive
  and rewarded video are flagged off until checked live.
- **Daily loop:** the 7-day track never resets on a missed day; day 5 adds a Revive token and
  day 7 rerolls.
- **Telemetry** (`FunnelService`): the seven onboarding steps once ever per account, to
  AnalyticsService and our telemetry; an economy event for every grant and spend. Metrics and
  decisions in `docs/GO_NO_GO.md`.
- **Tests:** new `base`, `runloop`, `economy`, `funnel`, `views` and `currencies` files;
  `shop.test` moved its multi-level purchase cases onto buildings. The stub gained
  `Players:GetPlayerByUserId` and `Signal:Wait`.
- **Deferred by the concept:** the season pass, UGC limiteds and the weekly guild target.

### 2.0.0 — the redesign

Owner brief: "the fighting rooms just lack something. It feels a little dull." The diagnosis
(numbers from the code and the dry run): shots were free (0.18s cooldown, ~640 shots and 0.10
kills per shot per run), so spraying beat aiming and the bank shot was optional; enemies had
1–4 health and every room was one wave of the same job, cleared in ~7s; and the player had one
verb. 2.0 rebuilds the combat loop around the ricochet.

- **Orbs** (`OrbDrops`, `MatchArsenal`, `ArsenalConfig.Orbs`). Three orbs; a throw spends one,
  the middle projectile of a fan carries it, and it drops where the shot stops. Walk over it,
  or it rolls home after a second. A kill off two or more wall bounces returns it at once
  ("TRICK SHOT!"). Every room starts with a full hand. Cards: Extra Orb, Homecoming, Recall.
- **Bounce power.** Every wall, cover or reflector bounce adds +50% damage (the BouncePower
  stat), +8% speed (capped at 1.5x), and grows and heats the shot's colour. Enemy health rose to
  match: a straight shot needs two hits where a banked one needs one. Cards: Overcharge, and the
  Ricochet Storm evolution.
- **Dash** (client-moved, server-authorised). 2.2s cooldown, 15 studs, 0.35s of invulnerability.
  Q, Left Shift, gamepad B or the DASH button. Cards: Blink Strike, Quick Step, Recall, and the
  Phantom evolution.
- **Combo.** Kills within 3.5s chain; ricochet kills count double; a hit halves it. Tiers at 6,
  14, 26 and 45 multiply coin drops and kill experience (x1.5 to x4) and are called out.
- **Surge.** Kills (more for ricochets and big enemies) fill a meter; full, it offers three
  minor perks from their own pool, taken with 1/2/3 or a tap while the fight goes on, and auto-
  picked after 9s. Perks stay out of the card list, the Codex and room offers.
- **Waves and swarms.** Rooms fight in two or three waves, each announced by pulsing floor
  circles 1.4s before it lands. Mites (one hit, packs of five or six) make chain kills pay.
- **Enemies that care how you shoot:** Mirror (only banked shots hurt it), Sponge (eats a
  shot's bounces), Magnet (bends shots toward itself), Splitter King (splits into Splitters),
  Treasure Runner (flees with 45 coins, escapes after 16s, never holds a room open). Enemies
  with 3+ health show a health bar once hurt.
- **Rooms you can play with:** explosive barrels that chain (Smelter, Forge Hall), boost pads
  (Conveyor), a portal pair (Rift), loot crates (Crucible, Forgeworks).
- **Objective rooms:** Crystal Hunt (Sunken Reliquary: only banked shots crack crystals), Hold
  the Beacon (Signal Tower), and the Trick Shot Gallery bonus room (points double per bounce).
- **Doors.** After each room the group votes between two doors: a different room of the next
  slot where one exists, each with a promise (Mending Spring, Treasure Cache, Armoury, Surge
  Well, Trial, Trick Shot Gallery). The vote closes when everyone has voted or after 14s.
- **Trials:** Trick shots only, Untouchable, Swift, Frenzy. A Trial door always brings one, and
  15% of other normal rooms do. Beating one pays coins and a Surge perk.
- **Mini-bosses:** the Colossus (Ruins: spinning shield, stomp rings, Mites when hurt) and the
  Forge Press (Foundry: a hovering press whose slam zone flashes red on the floor). The run is
  now nine rooms: Ruins 1, Ruins 2, Colossus, Foundry 1, Foundry 2, Forge Press, Abyss 1, Warden
  Vault, Throne.
- **Feel:** enemies shatter into shards of their colour; a room clear flashes, stamps "ROOM
  CLEARED" and kicks the camera; callouts kick it too; your floor orbs glow while teammates' are
  dimmed; wave circles pulse. All of it respects Reduced Flash and Effect Intensity.
- **HUD:** orb pips, the Surge meter, a combo counter with its draining timer, wave and
  objective lines, the Trial line, and a DASH button with its cooldown. Hints for every new
  system, and for the first Mirror, Magnet, Sponge and Treasure Runner a player meets; unlike
  the 1.x hints, these show for veterans too.
- **Lifetime stats** BestCombo and TrickShots; achievements Unstoppable, Godlike and Trick Shot
  Artist.
- **Every system has its own flag** (`Orbs`, `Surge`, `Combo`, `Dash`, `Doors`, `Challenges`,
  `RoomEvents`); a match built without them plays as 1.3 did, which is also how the older
  tests still run.
- **Tests:** 41 new in `redesign.test.luau`; run-through helpers now clear every wave through the
  shared `__clearRoom`; the stub gained `CFrame.Angles` and CFrame composition.

Dry run (bots now throw orbs, fetch them when empty, and dash away when touched; they still
cannot plan a bank shot, which 2.0 rewards more than ever, so read these as a floor on skill):

| Bot | Median extracted run | Extraction rate | Where runs ended |
|---|---|---|---|
| Direct fire, exact aim | 459s | 40% | room 2: 18, room 5: 9, room 9: 27 of 60 |
| Direct fire with aim error | 392s | 28% | room 2: 15, room 5: 6, room 9: 13 of 40 |
| Probing | 388s | 40% | room 2: 10, room 5: 8, room 9: 19 of 40 |

The run now lands on the 420s target. Room 2's deaths are mostly Chasers and Mirrors against
bots that cannot bank; tuned twice already (Chaser health 3 to 2.5, Mirrors slower and softer,
waves wait until one enemy is left). **Playtest room 2 first.**

### 1.3.0 — the depth build

Owner brief: research what makes games like this complete, compare it with the repo, and make
the game far better. The research and gap analysis are in `docs/DESIGN_RESEARCH.md`. In short,
the genre's best games (Ball x Pit, Hades, Brotato, Risk of Rain 2) have build-defining effects
and evolutions, unlockable starting kits, player-chosen difficulty for bigger rewards, and a
collection to complete. 1.2.0 had none of them.

- **Shot effects.** Ten new cards and four evolutions (`UpgradeConfig`, numbers in
  `CombatConfig`): Keen Edge, Trick Shot, Ignite, Chain Arc, Volatile, Frostbite, Siphon, Hunter,
  Second Wind, Fleet Foot; Storm Conduit, Wildfire, Absolute Zero, Deadeye. A new mixin,
  `MatchEffects`, is the one damage path after a contact: arcs, explosions and burn ticks all
  count kills, drop coins, fire callouts and chain the same way. Elemental damage ignores
  shields. An evolution the player qualifies for is always in the next offer.
- **Champions.** `EnemyService` spawns Armored, Swift, Volatile (orb ring on death) and Mending
  variants. `RoomService` rolls them per enemy from a separate seeded RNG, so existing layouts
  are unchanged. They pay 3x coins and bonus experience; clients show a glow and name tag.
  Burning and chilled enemies glow too (`Burning` and `Chilled` part attributes).
- **Rigs** (`RigConfig`, `RigView`): six loadouts unlocked by level. Their stats fold in before
  cards, like the Armory's. Saved as `SelectedRig`; a locked or unknown rig resolves to Striker.
- **Depth Pact** (`PactConfig`, `PactView`): seven conditions, Heat 0–16, +10% coins and XP per
  Heat, opened by the first extraction. `MatchService:_applyPact` sets enemy modifiers, the
  champion bonus, Frailty, Drought and Narrow Path. Groups run each condition at the lowest rank
  anyone chose. Reset to Heat 0 when the arena returns to the lobby.
- **Co-op revives** (`MatchCombat:_stepRevives`): a teammate within 9 studs revives a downed
  player in 3.5s (faster with more helpers) at 40% health. Downed players crawl at 6 speed. The
  HUD shows who is down and the progress.
- **Journal** (`AchievementConfig`, `JournalView`, `LoadoutService:ClaimAchievement`): 13
  achievements, each paid once through `Payout.Grant` and marked in `Achievements`; a Codex of
  cards taken and enemies defeated.
- **Schema v8** adds `SelectedRig`, `Pact`, `Achievements`, `Codex` and the stats
  `ChampionsDefeated`, `BossesDefeated`, `Revives`, `BestHeat` and `RigsExtracted`. The migration is
  additive; nothing existing is touched.
- **Remotes** `SelectRig`, `SetPact` and `ClaimAchievement`, rate-limited, validated, and lobby-only.
  `FeatureFlags.Loadouts` turns all of it off (Striker, Heat 0, no buttons).
- **Feel.** Element-coloured bursts, 2.6x explosion bursts, crit popups with "!", pitch-shifted
  hits, "CHAMPION SLAIN" and "SECOND WIND!" callouts. The lobby menu is now a two-column grid.
- **Bug found by the new tests:** a burn missed its final tick, so a 3s burn dealt 2.5s of damage.
  Fixed before release.
- 49 new tests (`shot_effects`, `loadout`); 612 in total.

### 1.2.0 — the polish build

Owner note: "it only looks halfway finished". This build adds what players expect from a
finished Roblox action game, modelled on the loops of the genre's most-played games.

- **Come-back loop.** Daily login rewards on a 7-day streak (resets if a day is missed), three
  daily quests drawn per player per UTC day, promo codes (`MetaConfig.Codes`), and badges
  (`MetaConfig.Badges`, inert until ids are set). All server-side in `MetaService`; every payout
  goes through the idempotent grant ledger, and the claim markers make rejoins and repeats pay
  nothing. Experience from these levels players up like runs do (`Payout`). Schema v7.
- **Global leaderboards.** Top levels, most defeated and most extractions, printed on framed
  boards on the lobby's south wall from OrderedDataStores, with batched writes and an offline
  message when the store is unreachable.
- **Lobby.** A `RICOCHET DEPTHS` marquee and tagline, fire braziers, turning and bobbing
  crystals over the well, rising motes and drifting dust, a lit walkway from the spawn, and the
  leaderboards.
- **Rooms.** Particle weather per zone: dust in the Ruins, embers in the Foundry, motes in the
  Abyss, from above the walls so it never enters the play space.
- **UI.** A new theme (lit panels, outlined buttons that press in and glow, gold primary
  buttons, a display font for titles), a title screen with PLAY, a side menu (Daily, Quests,
  Codes, Invite) with claim dots, modal windows for each, a profile card behind the level badge,
  toasts, and `DOUBLE KILL` / `RICOCHET x5` callouts.
- **Audio on.** Every cue now plays a sound built into the Roblox client, plus UI click,
  reward, combo and level-up cues, and a Sound volume option.
- **Social.** `[Lv N]` and `[VIP]` chat tags, an invite button, and a 10% coin bonus for Roblox
  Premium members.
- **Store art.** `marketing/`: icon, three thumbnails and the store description.
- **Tooling.** Two engine-only bugs were caught in review before shipping: a DataStore is
  userdata, so reading `store.Available` on it would have thrown and left the leaderboards
  permanently offline; and a real Player is userdata, so a `type(...) == "table"` check would
  have silenced every kill callout. Both now read defensively.

### 1.1.0 — levels, and coins that always save

Owner playtest notes: the lobby spawn pad was visible, coins did not save after dying, and the
game needed levels.

- **Coins did not save (Studio).** Every payout is keyed by run, and the key is remembered in
  the profile so a run can never pay twice. Studio has no `JobId`, so every Studio session used
  the prefix `studio` and its first run got the key `studio-a1-1` — a key the first session had
  already paid. The ledger refused it and the coins vanished; dying ended most runs, so it
  looked like a death bug. Studio sessions now get a fresh GUID prefix
  (`GameBootstrap._runKeyPrefix`); live servers keep their `JobId`.
- **Coins on the floor are banked when a run ends.** Previously a lost room's uncollected
  coins were discarded. They now go to the nearest participant, downed or not.
- **Levels (XP).** Every run earns experience: 4 per kill, 25 per room cleared, 60 for the
  elite, 150 for extracting (`ProgressionConfig`). Dying keeps everything except the extraction
  award, and leaving mid-run pays what was earned. Levels 1–100 on a rising curve, and each new
  level pays coins (250 on every tenth). Experience travels with the run's coins in the same
  idempotent grant, so neither can be paid twice or without the other. Profile schema v6
  (`Progression.Xp`, store-owned like currency).
- **Where levels show.** A level badge and XP bar in the lobby HUD, a "LEVEL UP" banner, experience
  and level-up rows on the results screen (now scrollable), a `Level` column first in the
  player list, and a "Lv N" plate over every character.
- **Lobby spawn is invisible.** Transparent, no collision, no raycast hits; players still spawn
  there, standing on the hall floor.
- **Save warning.** A player whose profile could not load (read-only session, e.g. Studio with
  API access off) now sees "Progress is not saving right now" instead of losing coins silently.

### 1.0.2 — the first room loads under you

Studio playtest: every run dropped the player into the void at the first room (Upper Ruins),
over and over.

- **Cause.** `RoomBuilder.translate` moved each room part into its arena slot twice: once by
  setting `CFrame`, then again by setting `Position`. In the engine those are one property, so
  slot 1's room was built at X=1000 while players were sent to X=500, over empty space. Rooms
  now move with a single `part.CFrame + offset`, which also keeps each part's full rotation.
- **Why the tests missed it.** In the test stub, a part's `CFrame` and `Position` were separate
  fields, so the first move never happened there. The stub now stores them as one value, like
  the engine. With that change the old code fails three tests by exactly 500 studs, and the fix
  passes them. New tests check that every room, in every arena slot, has its floor under the
  spawn point, its cover and its enemies.
- **Fall rescue.** A player more than 30 studs below the room's floor during a run is put back
  on the spawn pad instead of dying (`RunConfig.FallRescueDepth`). Teleports also stop the
  character's fall speed.
- **The boss could be outlasted.** The 150s soft-lock timer cleared the boss room like any
  other, so hiding from the Warden Prime won the run with the full extraction bonus. The boss
  room now has 300s, and running out of time ends the run as Out of Time.
- **Dry-run bots never moved.** They moved by setting `CFrame`, which the old stub ignored, so
  every earlier dry run measured bots standing on the spawn pad. The table below is re-measured
  with bots that walk and kite. Balance tuned in 1.0.0 was measured against the stationary
  bots.

### 1.0.1 — pre-Studio audit

The 1.0 code was read against the real engine rather than the test stub. Fixes:

- **Lobby HUD on join.** Lobby players belong to no match, so no run state reached them before
  their first descent. The HUD started blank, with the empty upgrades panel showing, and the
  lobby hint never appeared. `HudView` now starts in the lobby layout, and `ClientMain` shows the
  lobby hint once the first profile says whether it has been seen.
- **Coins lay flat.** `CoinVisuals` tipped each coin's axis upright, which lays a cylinder on its
  face, where its spin is invisible. Coins now stand on edge and visibly spin.
- **Daylight flash in the Abyss.** Its ClockTime was 0.5, and a tween from 18.1 runs back
  through noon. It is now 23.6. A test keeps every zone in the evening.
- **Streaming off.** `default.project.json` sets `Workspace.StreamingEnabled = false`. Arenas
  are 500+ studs from the lobby, and a teleported player could land before the room streamed in.
- **Place warnings.** At startup the server warns in Output (and changes nothing) if streaming
  is on, the template `Baseplate` is still there (its top is level with every floor, so they
  flicker), or a SpawnLocation sits outside the lobby.
- **Solid props.** Lobby pillars and lamp posts could be walked through; they are solid now.

### 1.0.0 — launch build

Built on `claude/launch-ready-1.0`, one commit per step, each green on `scripts/check.sh`.

- **Bulwark.** The shield turns at 70°/s on its own (`EnemyService.ShieldFacing`). The arc is
  62° (was 72°) and lunges deal 12 (was 16). The Warden core's shield turns too.
- **Lobby.**
  - Two gates on the west side (`PartyRooms`): 2–8 players, 15s countdown, 5s when full.
    Overflow is moved back out.
  - A Solo Portal at the north end, and Armory and Cosmetics kiosks on the east.
  - An invisible 100-stud barrier and a ceiling.
  - Signs are printed on SurfaceGui boards (`Signage`); the old shop and zone labels were buried
    inside parts.
- **Concurrent arenas.** `ArenaDirector` gives each group a slot, each with its own rooms,
  enemies, projectiles and match, at X = index × 500 (up to 6 slots).
  - Rooms, spawns, markers, orb cover and mechanics all honour the slot origin.
  - Broadcasts and effects reach only that match's players.
  - Payout keys are unique per slot.
- **Coins.**
  - Coins drop per archetype, are pulled in by a magnet and swept to players at room clear.
  - Payout is coins plus a clear bonus (the bonus is halved on defeat), times Fortune and the
    2x Coins pass.
  - Leavers are paid for what they collected, once.
  - Leaderstats show Coins and Best Depth. The profile field is still `Salvage`, so no
    migration was needed.
- **Regen.** Players heal 1.5 HP/s (plus Mending) after 4s without damage. Clearing the Warden
  Vault heals everyone to full before the Throne.
- **Shops and Robux.**
  - The Armory adds Mending, Coin Magnet and Fortune. Cosmetics adds the Frost and Toxic trails,
    plus a VIP-only Gold trail.
  - `ShopView` has Armory, Cosmetics and Store tabs.
  - `MonetizationService` handles passes and coin-pack receipts. Receipts are paid exactly once,
    after a confirmed save.
- **Cinematic, HUD and sky.**
  - `DescentCinematic` and `DescentPlan` add the shaft plunge and the title cards.
  - The upgrades panel shows only during a run; the STORE button only in the lobby.
  - Night sky and per-zone lighting; `SkyConfig` takes optional custom skybox ids.
- **Tuning (dry run).** Every bot run now reaches the Warden Prime, and 5–10% beat it. The boss
  has 60 health, contact damage every 1.6s and 6-damage orbs.

### 0.7.0-dev — Milestone 13: playtest fixes and the content pass

Studio feedback, then content. One commit per phase, each green on `scripts/check.sh`.

- **Playtest fixes.**
  - The tactical camera turns (right-drag, Q/E, two-finger twist), tilts within 40–80° and
    zooms (wheel, pinch). Aiming reads the live camera, and a touch camera gesture drops any
    aim in progress.
  - The cursor drag line is removed.
  - Floor decor layers step 0.08 studs (up from 0.02). The aim ground cues float above every
    floor layer, bank-shot trims sit above wall trims where they overlap, and the spawn pad is
    a low plinth with a neon ring that casts no shadow.
  - New test: no two overlapping visible top faces in any layout sit within 0.05 studs.
- **Enemy models.** `EnemyVisualConfig` describes a multi-part model per archetype, and
  `EnemyVisuals` draws it on the client over the server hitbox. Models follow and face the
  hitbox, bob and spin, and take its live colour so telegraphs flash. Turn them off with
  `FeatureFlags.EnemyModels`.
- **Zones and random runs.**
  - Three zones (Upper Ruins, The Foundry, The Abyss), each with its own floor, grid and wall
    style.
  - Eight new layouts (Cistern, Smelter, Conveyor, Crucible, Forgeworks, Rift, Spire,
    Hollow) plus the Throne boss arena.
  - `RunPlanner` draws each run from `RunConfig.RunShape`: two Ruins rooms, two Foundry rooms,
    one Abyss room, the Warden Vault, then the Throne.
  - New layout rules: the spawn is open 20 studs in all eight directions, and every shielded
    post is flankable and 36+ studs from the spawn.
- **Room mechanics** (`RoomMechanics`):
  - sweeping reflectors;
  - laser gates, which burn players on a telegraphed cycle and never block shots;
  - breakable cover;
  - amp pads, which add +1 damage to a shot that crosses them.
- **New enemies and a boss.**
  - Splitter, which dies into two Shards.
  - Sentinel, a turret firing pooled, dodgeable orbs that die on cover.
  - Phaser, which blinks out, is untouchable while blinking, and reappears near a player.
  - Warden Prime: its shield spins, then tracks the player while it summons Shards and fires
    orb rings, then drops while it fires faster spiral rings.
  - The HUD shows a boss bar.
- **Lobby and dressing.**
  - The lobby is now a walled hall with pillars, lamps, a well ring round the pedestal,
    numbered pads, a kiosk canopy and zone banners.
  - Rooms get per-zone dressing (`RoomDressing`), held outside the play space by a tested rule.
  - Lighting tweens per zone (`ZoneAmbience`).

### 0.6.0-dev — Milestone 12: content, juice, touch and the salvage shop
Includes the post-Studio fixes from PRs #1 and #2 (desktop aim line, tactical camera, aim
ground cues, arena decor and lighting).

- **Bank-shot geometry.** New `RoomGeometry` turns each layout into solids: walls, pillars, four
  45° corner bevels and free-standing 45° reflectors. `RoomBuilder`, the spawn-point search and
  the headless collision model all build from it, and the harness now raycasts rotated boxes.
  Enemies are clamped out of the sealed corner behind each bevel.
- **Arena look.** Two-tone checker floor, a glowing border inside each wall, metal bumpers with
  amber hazard trim on every bevel and reflector.
- **Room 3.** Audited with a new per-enemy damage breakdown in the dry run (see *Room 3 audit*):
  one Bulwark instead of two, open flanks, a spawn that is not boxed in. Spawn groups can now pin
  markers (`Markers` in `RunConfig.Rooms`), resolved by `RoomService.AssignSpawns`.
- Fixed a regression caught by the dry run: the first Gallery reflector placement blocked direct
  fire from the spawn; they now sit at the top of the side lanes.
- **Audio.** `SoundConfig` (cues with briefs for asset authors, bounce pitch
  `min(2.0, 1.0 + bounces * 0.15)`, distance falloff) and a pooled `SoundPlayer`. Hooked to
  firing, impact batches, kills, card picks and room clears. Silent until assets exist.
- **Juice.** Impact batches now carry what was struck (wall, hit, block, kill), the bounce count
  and the damage. `DamagePopups` (pooled billboards) and trauma-based `CameraShake` (scaled by
  the Screen shake setting) use them.
- **Touch.** Left 40% of the screen belongs to the dynamic thumbstick; aiming starts only on the
  right. A 28px touch deadzone (14px for the mouse) stops taps firing.
- **Salvage shop.** `ShopConfig` (max health, walk speed, +1% projectile speed, three cosmetic
  trails) and `ShopService`, opened from a lobby kiosk with a `ShopView`. Purchases are applied
  like grants: optimistically in memory, then re-checked against the stored balance inside the
  save transform, so two servers can neither double-charge a level nor overspend a balance; a
  refused purchase is rolled back and reported. Profile schema v5 adds `MetaUpgrades`
  (store-owned) and `EquippedTrail`. `FeatureFlags.SalvageShop` gates all of it.
- **Lobby.** A four-pad ready zone: when every lobby player stands on a pad (or all four pads
  are taken) a three-second countdown starts the descent. Pads light as they fill; the HUD shows
  progress.
- Harness: rotated boxes, `Sound`, `ProximityPrompt.Triggered`, button `Activated`,
  `ColorSequence` and `NumberSequence`; the profile round-trip guard now covers string fields.
  A `GameBootstrap` smoke test drives the real wiring end to end.
- 290 → 385 tests.

### 0.5.7-dev — persistence step 5; overhaul complete
- Fixed P1: shutdown saved players one after another, so the flush took the sum of every save.
  Four players at 3s each took 12s, and one hanging write stretched it to 43s, past Roblox's 30s
  cutoff, losing every save queued after it. `SaveAllOnShutdown` gives each session with
  something to write its own worker and waits until all finish or a shared 25s budget runs out,
  whichever is first. It returns a report naming any save that timed out.
- Retries honour the deadline: no attempt starts after it, and no backoff starts unless it plus
  one more write (`ExpectedWriteSeconds`) still fits. A doomed retry no longer sleeps into the
  cutoff.
- Workers are isolated: an error in one is recorded as that player's failure and cannot stop
  another player's save or escape the handler. The scan that picks which sessions to save runs
  per session under `pcall` too, after the test showed one corrupt session could take the whole
  handler down before any worker had started.
- `BindToClose` logs timed-out saves as `ShutdownSaveTimedOut`, separately from other failures.
- `SaveAll` remains, returning just the failure list, now backed by the parallel flush.
- Fixed stale docs: the Studio checklist expected `schema=v3` in the Output window, which would
  have made two correct steps look failed after the v4 bump.

### 0.5.6-dev — persistence step 4
- Fixed cross-server P5: currency was written as an absolute balance, last write wins, so a
  server that loaded before another server's payout landed overwrote it on its next save (A's
  +100 then B's +50 ended at 50). Sessions now hold per-run pending grants, and the save
  transform adds each to whatever the store holds at commit time, skipping any run the stored
  ledger already records. After a save, memory reconciles to the stored balance plus anything
  still pending, which is also how a server learns of other servers' grants.
- Fixed a double payment: the ledger was pruned alphabetically, and run keys begin with a random
  server id, so a run could be dropped the moment it was paid and then paid again. Pruning is now
  strictly oldest-first by the wall-clock time of the grant.
- Fixed unbounded ledger growth: saves unioned the in-memory ledger into the store and never
  trimmed the stored copy. The transform now prunes the stored copy to the same cap, and no longer
  re-adds pruned runs from memory.
- Schema v4: ledger entries become `{ Amount, At }` records. Migration from v3 stamps old entries
  `At = 0`, so they are pruned first; entries already in record form pass through.
- Currency and the ledger are store-owned: `Update` now refuses to change them, restoring the
  profile and raising an error rather than letting a direct edit be silently dropped.
- Saves copy every profile field except a declared store-owned set, so a newly added field is
  persisted without being added to a list. This is the root cause of the earlier Settings bug.

### 0.5.5-dev — persistence step 3
- Sessions are keyed by `UserId` with an owning `Player` and a load token, instead of by `Player`
  object. Every public method resolves a session through an ownership check.
- Fixed P4: a load that resolved after its player left marked its orphaned session loaded and
  reported success. It now returns `"stale load"`, touches no session, and stops retrying as soon
  as nobody wants the result.
- Rapid rejoin: of two overlapping loads for one account, only the newest can attach, whichever
  resolves first.
- Fixed the same-server form of P5: a player who rejoined while their leave-save was still in
  flight read the store before that save landed, got the pre-payout profile, and the next save
  overwrote the payout. The rejoin now takes over the live session, and the old leave no longer
  tears it down. A late call through the departed player's handle changes nothing.
- The cross-server form of P5 remains; that is Step 4.

### 0.5.4-dev — persistence step 2
- Harness: a deterministic cooperative scheduler (`task.spawn`/`wait`/`delay`/`defer`/`cancel`),
  errors in spawned threads fail the test, and a fake DataStore with latency, optimistic
  concurrency and per-key in-flight tracking. Committed separately; no production change.
- Fixed P3: the completing save replaced the live profile with what it had written and cleared a
  boolean dirty flag, so any reward or settings change made during its yield was rolled back and
  never saved. Sessions now carry a revision counter; a save records the revision its transform
  read, and merges back only store-owned ledger entries.
- Fixed P2: concurrent save requests (post-run save, leave, autosave, shutdown) each wrote,
  up to six writes for one change and two in flight for one key. Each session now allows one
  write chain at a time; later requests wait for it, and the chain writes again for anything
  changed meanwhile, capped at `MaxChainedWrites` (3).
- Fixed: `StepAutosave` saved inline inside Heartbeat, blocking the frame for the whole write and
  letting the next frame start a second save of the same session. It now saves in the background
  and skips sessions already saving.

### 0.5.3-dev — persistence step 1, a settings bug, and a doc correction
- Fixed: **accessibility settings were never saved.** `Save` writes back an explicit field list
  and `Settings` was not on it, so options reset every session. Every inline fake DataStore had
  stored and returned the same table, so the session's profile and "the store" were one object,
  and the test claiming to verify settings persistence passed on that alias alone.
- The harness now has one serialising `FakeDataStore` (copies in and out, rejects unstorable
  values). All four aliasing fakes replaced; no other false passes were hiding behind them.
- A round-trip guard fails naming any profile field `Save` drops.
- Persistence plan Step 1: a run's payout and stats are written in one request as soon as the run
  ends, off the Heartbeat thread, instead of waiting for autosave, leave or shutdown.
- Doc correction: three blocks reported as added to this file in 0.5.0-dev never landed — the
  simulated run-length section, the V0–V6 Studio checklist summary, and the bot-caveat
  limitation rows. The editing script used unchecked replacements that silently matched
  nothing. Restored here; doc edits now fail loudly on a non-match.

### 0.5.2-dev — late-join credit
- Fixed: a late joiner was credited with every room the team had cleared before they arrived, so a
  player could wait out a run and join at the elite room to collect four rooms' payout for one.
  `roomsCleared` now counts only rooms the player was present for, and `joinedAtRoom` records
  where they entered. Also flows through to the persisted `BestRoomsCleared` stat, which was
  inflated the same way.
- Added `docs/PERSISTENCE_SHUTDOWN_PLAN.md`: a reviewed-before-built proposal for bounding
  shutdown saves and handling loads and saves that overlap a leave or rejoin. No persistence code
  was changed.
- Recorded results-dismiss-for-everyone as an accepted MVP tradeoff.

### 0.5.1-dev — post-split review pass
- Fixed: a room that fails to build left the run in Combat with no room to clear, hanging until
  the 900s hard limit. It now ends the run with an `Aborted` outcome and an error telemetry
  event.
- Fixed: the upgrade countdown sent an absolute server `os.clock()` timestamp and the client
  compared it against its own clock. Per-process clocks are unrelated across machines, so the
  timer would have shown nonsense. The payload now carries a duration and the client builds its
  own deadline.
- Fixed: contact damage was evaluated against a one-frame-stale clock, because enemies step
  before the run loop does. `EnemyService` now passes its step clock through.
- Fixed: the spawn-point search returned the room centre when no clear ground was found — the
  one point already known to be blocked. It now returns the least-bad sampled point.
- Verified the lint filter hides nothing real: all 464 suppressed findings are the standalone
  analyzer not knowing Roblox globals.
- Documented where the stub is more forgiving than the engine, as a Studio priority list.

### 0.5.0-dev — headless hardening
- Harness upgraded from four infinite planes to box-accurate raycasting, reproducing the
  engine's origin-inside-a-part behaviour, face normals, filters and CanQuery.
- Fixed: a moving enemy could slide over a projectile and take no damage, because the next
  swept cast started inside its body.
- Fixed: exhausting the per-frame bounce allowance could push a projectile out of the arena.
- Fixed: two of four layouts had cover on the room centre, where players are teleported. Both
  layouts adjusted, and the spawn point now searches outward for clear ground.
- Added property-based fuzzing over projectile, enemy and upgrade configuration, plus random
  event sequences checked against an explicit legal state-transition set.
- Added direct coverage for RemoteGuard, RemoteRouter, TelemetryService, RoomBuilder,
  RoomService, LobbyBuilder, DataStoreProvider, PartPool, RunSummary and EnemyBehaviour.
- Added the dry-run simulator and `docs/STUDIO_VALIDATION_CHECKLIST.md`.
- 120 → 225 tests.

### 0.4.0-dev — co-op, persistence, release package
- Co-op membership with an explicit late-join rule and per-player upgrade offers.
- Versioned persistent profiles with retries, migrations and a two-layer reward ledger.
- Accessibility settings, sanitised server-side; onboarding hints that retire after a run.
- Developer overlay, soak tests, `MatchService` split into five focused modules.
- `FeatureFlags`, README, playtest guide and release checklist.

### 0.4.0-dev — run loop, enemies, upgrades
- Added `MatchService`, `RoomService`, `EnemyService`, `UpgradeService`, `RewardService`,
  `TelemetryService`, `RemoteGuard`, `RemoteRouter`, `PlayerState`, `WorldAdapter`,
  `LobbyBuilder`, `GameBootstrap`.
- Added `RunConfig`, `EnemyConfig`, `UpgradeConfig`, `RewardConfig`, `UiConfig`, `DebugConfig`;
  `RoomConfig` now holds four named layouts.
- Added client views: HUD, card picker, results, onboarding hints, all under `UiTheme`.
- Aiming is gated on the combat state and drops a gesture if the run moves on mid-drag.
- Fixed: the results dismiss callback captured a global instead of its local view.

### 0.3.0-dev — test harness and fixes
- Added a Roblox API stub plus a bundler so production modules run under the plain Luau CLI.
- Fixed projectiles escaping through corners (swept collision + cast back-step).
- Fixed shots fired against a wall spawning inside it (muzzle clearance).
- Replaced per-contact impact remotes with interval batching and a per-batch cap.

### 0.2.0-dev — aim and fire
- Drag-to-aim client, server-validated fire, pooled ricochet projectiles.

### 0.1.0-dev — scaffold
- Rojo project and source layout.
