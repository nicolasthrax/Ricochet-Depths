# Ricochet Depths

A 1–4 player co-op ricochet-shooting roguelite for Roblox. Aim bank shots that bounce off walls
and enemies, fuse upgrades between rooms, bank your haul at an extract point or risk it deeper,
then bring it home to a social base that grows with every run.

Original IP. Nothing here copies names, art, layouts, wording, enemies, cards or presentation
from any existing game.

**Status:** 3.0.0, concept alignment: the game now matches the original concept (home base,
haul at risk, daily modifiers, the first 60 seconds, the launch economy with no paid power,
onboarding telemetry). Every check below comes from static checks, a Rojo build and a
headless test suite of 815 tests. **Nothing in 3.0 has been run in Roblox Studio yet.**
`docs/RELEASE_CHECKLIST.md` lists what is left before going public,
[docs/PROGRESS.md](docs/PROGRESS.md) gives the honest state of things, and
[docs/CONCEPT_TRACEABILITY.md](docs/CONCEPT_TRACEABILITY.md) maps every concept item to code.

## Features

- **Ricochet combat.** Drag to aim, release to throw one of your **orbs**; they bank off walls,
  reflectors and enemies, **grow stronger with every bounce**, and drop where they stop, to be
  picked up again. A kill off two bounces sends the orb straight home. **Dash** (Q / Shift /
  DASH) through danger. A **combo meter** multiplies what kills pay.
- **Rooms that fight back.** Waves announced by circles on the floor, swarms of Mites,
  enemies that care how you shoot (Mirrors, Sponges, Magnets, the Splitter King), explosive
  barrels, boost pads, portals and loot crates, objective rooms (Crystal Hunt, Hold the Beacon,
  the Trick Shot Gallery), Treasure Runners, and two mini-bosses: the Colossus and the Forge
  Press, before the Warden Prime.
- **Mid-fight Surge.** Kills fill a meter; a full one offers three quick perks you take with
  1/2/3 or a tap, without the fight stopping.
- **Your route.** After every room, pick a door: which room is next and what it promises (a
  heal, treasure, a bigger card choice, a Surge, a Trial, or the Trick Shot Gallery). The group
  votes, with a 10-second cap.
- **Haul at risk.** A lost run keeps only half the coins you picked up. After each mini-boss an
  extract point offers a **Bank loot** door: climb out now with everything, plus a bonus that
  grows with depth, or descend for more.
- **Depth pressure.** A normal room that drags past 60 seconds starts sending Swift hunters that
  drop nothing; a room the clock has to clear loses its door reward and its Trial.
- **The first 60 seconds.** No title screen: a new player spawns facing the pit and drops into
  a scripted first descent (a pack of easy targets, a duplicate card that makes a fusion
  obvious, a mini-elite that bursts into coins, the first Bank loot choice).
- **Roguelite runs.** Three zones (Ruins, Foundry, Abyss), randomised rooms, an upgrade card
  after each room, room mechanics (sweepers, laser gates, breakable cover, amp pads).
- **Builds.** 36 upgrade cards, each with an icon and a three-word label, including elemental
  shot effects (crits, burn, chain arcs, kill explosions, chill, lifesteal) and eight fusions.
  One card per offer is RECOMMENDED (and is the auto-pick). One free reroll a run (more with
  Reroll tokens), a free early respec, and cards that unlock gradually with your level.
  Champion enemies (Armored, Swift, Volatile, Mending) vary each run.
- **Daily biome modifier.** One twist a day for every run (Bouncy Walls, Glass Depths, Gold Rush,
  Champion Hunt, Heavy Orbs, Quick Feet, Surge Day), shown on a hall sign and the HUD, with a
  once-a-day bonus.
- **Rigs and the Depth Pact.** Six rigs, unlocked by level, each changing how you play; after the
  first extraction, the Pact's seven conditions raise Heat (up to 16) for +10% rewards per point.
- **Co-op that matters.** Stand next to a downed teammate to revive them mid-fight. Parties
  earn +5% coins per extra member (up to +15%), +10% with a Roblox friend; solo is never worse
  off, and enemies scale with party size.
- **The Outpost: your home base.** A 4x4 plot per player, 12 buildings raised with the coins
  you bring home (the Forge, Infirmary, Rail Lab and friends are where permanent power lives
  now), a Salvage Yard that earns while you are away (8 h cap), a Trophy Hall, base themes and
  signs, and friend visits: cheer a base once a day and you both earn a little.
- **The Journal.** 13 achievements with rewards and a Codex of every card and enemy found.
- **Solo or co-op.** A solo portal and two lobby gates for 2–4 players; several runs play at
  once on one server, each in its own arena.
- **Progression.** Coins from kills build the base; cosmetics (trails, base themes, signs,
  emotes, nameplate titles) are bought with coins or unlocked by level; levels (XP) from every
  run, with level-up coin rewards; loadout presets.
- **Come-back loop.** A forgiving 7-day reward track (a missed day never resets it; Revive token
  on day 5, rerolls on day 7), three daily quests, the daily modifier, the offline claim, promo
  codes, badges, and global leaderboards on the lobby wall.
- **Presentation.** A themed UI with animated menus and toasts, kill-streak and ricochet
  callouts, sound effects with a volume option, chat level and pass tags, a dressed lobby with
  fire, turning crystals and particle ambience, and particle weather in each zone.
- **Launch economy, no paid power (inert until ids are set).** Explorer Pass and Supporter Pack
  (presets, offline storage, cosmetics, a tag), a Reroll bundle, and a one-per-run Revive and
  rewarded video that stay switched off until checked live. Nothing sold changes a run's power.
- **Onboarding telemetry.** Join → first input → first hit → first upgrade → first fusion →
  first run end → first base upgrade, once per account, to Roblox's funnel analytics, plus
  economy events for every coin in and out ([docs/GO_NO_GO.md](docs/GO_NO_GO.md)).
- **Store art** in `marketing/`: an icon, three thumbnails and the store description.

## Setup

Requires [Rojo](https://rojo.space) 7.x and Roblox Studio with the Rojo plugin.
The test suite additionally needs Python 3 and the [Luau](https://luau.org) CLI
(`luau`, `luau-compile`, `luau-analyze`).

```bash
rojo serve                  # then connect from the Rojo plugin in Studio
rojo build -o build.rbxlx   # or produce a place file directly
```

## Commands

```bash
./scripts/check.sh                            # syntax + lint + rojo build + tests
python3 tests/run.py                          # tests only
python3 tests/run.py tests/match.test.luau    # a single test file
./scripts/dryrun.sh                           # simulated run-length estimate
```

Tool paths are overridable with `LUAU_BIN`, `LUAU_COMPILE_BIN`, `LUAU_ANALYZE_BIN` and `ROJO_BIN`.

## Architecture

The server is the sole authority for firing validation, projectile collisions, enemy damage and
death, card offers and selection, rewards, run state and every saved value. The client sends
only an aim direction, a power scalar, a card id and a few requests — all of which are
re-validated — and otherwise draws what it is told.

```
src/ReplicatedStorage/        shared config and data (no logic)
  *Config.luau                Run, Enemy, Upgrade, Reward, Progression, Meta, Projectile, Room,
                              Aim, Effect, Ui, Sound, PlayerData, Debug, plus FeatureFlags
  Remotes.luau                the one place remotes are created and looked up

src/ServerScriptService/
  Main.server.luau            entry point; calls GameBootstrap and nothing else
  Modules/
    GameBootstrap             constructs and wires every system
    RemoteRouter              the only client boundary: rate limit, validate, hand off
    RemoteGuard               per-player token buckets
    MatchService              run state machine
    MatchMembership           who is in a run, late-join queueing
    MatchFlow                 room-to-room progression, finish and teardown
    MatchCombat               fire requests, impacts, enemy contact, co-op revives
    MatchEffects              crits, burns, arcs, explosions: one damage path for every kill
    MatchArsenal              orbs, bounce power, the dash, combo and Surge
    MatchRoute                doors and votes, door rewards, Trials, objectives, barrels, loot
    OrbDrops                  orbs on the floor: drop, pick up, roll home, recall
    RoomObjectives            Crystal Hunt, Hold the Beacon, the Trick Shot Gallery
    LoadoutService            rigs, the Depth Pact, loadout presets and achievement claims
    BaseService / BaseBuilder the home base: buildings, offline claims, cheers; the Outpost's plots
    ShopService / EmoteBurst  cosmetics (coins, level or pass), equip by kind, lobby emotes
    MonetizationService       passes as entitlements, products as consumable tokens
    RewardedAds               rewarded video under pcall, fixed bonus, daily cap
    FunnelService             onboarding funnel steps and economy events (AnalyticsService)
    FriendCache               Roblox friendships looked up off the run loop (party bonus)
    MatchBroadcast            snapshots and client messaging
    RoomService / RoomBuilder room selection, runtime geometry, spawn orchestration
    EnemyService / Behaviour / Pool
    ProjectileService / Pool  swept ricochet resolution over a fixed pool
    FireValidator             direction, power, cooldown and liveness checks
    UpgradeService            offer generation, validation, application
    PlayerState               authoritative per-player run state
    PlayerDataService         versioned profiles, retries, ledger, autosave
    DataStoreProvider         datastore wrapper that degrades cleanly
    RewardService             payout maths (coins and experience) and per-server idempotency
    Payout                    one way to pay coins + XP under a ledger key, with level-up coins
    MetaService               daily rewards, daily quests, promo codes, badges
    LeaderboardService        global boards on the lobby wall (OrderedDataStores)
    LobbyBuilder / Signage    the Descent Hall, its landmarks, ambience and boards
    Leaderstats / Nameplates  player-list columns and the "Lv N" plate over each character
    TelemetryService          rate-limited, de-identified event logging
    EffectBroadcaster         batches cosmetic impacts
    WorldAdapter              character position and teleport, injected for testability
    PartPool                  generic fixed-size pool

src/StarterPlayerScripts/     client input and views (display only)
  AimController.client        drag-to-aim for mouse and touch
  ClientMain.client           owns every view and one connection per server event
  RigView / PactView / JournalView  rigs, the Depth Pact, achievements and the Codex
  SurgePickerView / RoomFx    the mid-fight perk strip; room-clear flash, stamp and camera kick
  HudView / CardPickerView / ResultsView / OnboardingView / SettingsView / ShopView
  MenuDock / DailyView / QuestsView / CodesView / StatsView
  BaseView / BasePreview      the base panel, and the results screen's look at your plot
  NotificationView / CalloutView   toasts, and kill-streak and ricochet callouts
  UiTheme                     panels, buttons, modals and tweens shared by every view
  LobbyAmbience.client        turns and bobs the lobby crystals
  ChatTags.client             [Lv N] and pass-tag chat prefixes
  ImpactEffects.client        pooled cosmetic bursts
  DebugOverlay.client         developer counters, inert for normal players
```

### Conventions

- Balance numbers live in config ModuleScripts, never inline in logic.
- `*.server.luau` → `Script`, `*.client.luau` → `LocalScript`, `*.luau` → `ModuleScript`.
- IDs (cards, enemies, rooms) are stable once persistence is live; treat them as permanent.
- Every pooled system returns to its configured size; nothing calls `Instance.new` per shot,
  per hit or per enemy at runtime.

## Testing

`tests/harness/` bundles the real production modules against a Roblox API stub so they run under
the plain Luau CLI. Roblox-style `require(Instance)` calls are rewritten to a flat module loader
and `os.clock` is redirected to a virtual clock, making time-dependent behaviour deterministic.
Game source is never modified for tests.

The stub models box raycasting (including the engine's origin-inside-a-part behaviour),
RaycastParams filtering, CanQuery, signals, instance parenting and a virtual clock. It does not
model the physics solver, replication, character controllers, rendering, input or DataStore, so
a green suite means the logic is consistent with those assumptions — not that the game works in
Roblox.

815 tests cover projectile physics and containment, the reflection law across heading and
incidence sweeps, moving-target and same-frame collisions, pool integrity, enemy lifecycle and
shielding, upgrade offers and stacking, the full run loop, soft-lock guards, co-op membership,
persistence and migration, reward idempotency, soak runs, config cross-references, the remote
boundary, property-based fuzzing over configuration and random event sequences, and (3.0) the
home base, the haul and Bank loot, daily modifiers, the first descent, card faces, rerolls and
respecs, the party bonus, the launch economy, the funnel, and the new views' logic. See
[docs/TEST_PLAN.md](docs/TEST_PLAN.md).

Views are tested only for what they show and what they ask the server; layout, input feel and
effects are Studio-only by nature.

## Documentation

- [docs/PROGRESS.md](docs/PROGRESS.md) — milestones, limitations, simulated timings, changelog
- [docs/STUDIO_VALIDATION_CHECKLIST.md](docs/STUDIO_VALIDATION_CHECKLIST.md) — ordered procedure for the first Studio session
- [docs/TEST_PLAN.md](docs/TEST_PLAN.md) — automated coverage and manual Studio cases
- [docs/PLAYTEST.md](docs/PLAYTEST.md) — what testers should do and report
- [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) — gate before a closed playtest
- [docs/CONCEPT_TRACEABILITY.md](docs/CONCEPT_TRACEABILITY.md) — every concept item mapped to code and tests
- [docs/GO_NO_GO.md](docs/GO_NO_GO.md) — the metrics that decide whether to scale
- [docs/CONCEPT_ALIGNMENT_HANDOFF.md](docs/CONCEPT_ALIGNMENT_HANDOFF.md) — how 3.0 was built, section by section

## What is deliberately not here

No paid power: nothing sold is a coin, a coin multiplier or a stat, and there are no loot boxes
or paid randomness. Deferred by the concept itself: the season pass, UGC limiteds and the weekly
guild target. Also not here: matchmaking, trading, PvP or a second boss. `FeatureFlags.luau`
lists what is switched off (the paid Revive and rewarded video among them); anything off is
inert, with no UI entry point, remote handler or stored data.
