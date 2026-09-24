# Ricochet Depths

A 1–4 player co-op ricochet-shooting roguelite for Roblox. Aim bank shots that bounce off walls
and enemies, chain kills, pick one of three upgrades between rooms, and extract before the
depths take you.

Original IP. Nothing here copies names, art, layouts, wording, enemies, cards or presentation
from any existing game.

**Status:** launch candidate (1.2.0). Every check below comes from static checks, a Rojo build
and a headless test suite of 563 tests. The game has not yet been run end to end in Roblox
Studio. `docs/RELEASE_CHECKLIST.md` lists what is left before going public, and
[docs/PROGRESS.md](docs/PROGRESS.md) gives the honest state of things.

## Features

- **Ricochet combat.** Drag to aim, release to fire; shots bank off walls, reflectors and
  enemies. Shielded, splitting, phasing and sentinel enemies, and a boss, the Warden Prime.
- **Roguelite runs.** Three zones (Ruins, Foundry, Abyss), randomised rooms, an upgrade card
  after each room, room mechanics (sweepers, laser gates, breakable cover, amp pads).
- **Solo or co-op.** A solo portal and two lobby gates for 2–8 players; several runs play at
  once on one server, each in its own arena.
- **Progression.** Coins from kills, a permanent Armory, cosmetic trails, and levels (XP) from
  every run, with level-up coin rewards.
- **Come-back loop.** Daily login rewards on a 7-day streak, three daily quests, promo codes,
  badges, and global leaderboards on the lobby wall.
- **Presentation.** A title screen, a themed UI with animated menus and toasts, kill-streak and
  ricochet callouts, sound effects with a volume option, chat level and VIP tags, a dressed
  lobby with fire, turning crystals and particle ambience, and particle weather in each zone.
- **Monetization (inert until ids are set).** 2x Coins and VIP passes, coin packs, and a
  Premium coin bonus.
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
    MatchCombat               fire requests, impacts, enemy contact
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
  HudView / CardPickerView / ResultsView / OnboardingView / SettingsView / ShopView
  MenuDock / DailyView / QuestsView / CodesView / StatsView / TitleScreen
  NotificationView / CalloutView   toasts, and kill-streak and ricochet callouts
  UiTheme                     panels, buttons, modals and tweens shared by every view
  LobbyAmbience.client        turns and bobs the lobby crystals
  ChatTags.client             [Lv N] and [VIP] chat prefixes
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

290 tests cover projectile physics and containment, the reflection law across heading and
incidence sweeps, moving-target and same-frame collisions, pool integrity, enemy lifecycle and
shielding, upgrade offers and stacking, the full run loop, soft-lock guards, co-op membership,
persistence and migration, reward idempotency, soak runs, config cross-references, the remote
boundary, and property-based fuzzing over configuration and random event sequences. See
[docs/TEST_PLAN.md](docs/TEST_PLAN.md).

Views, input handling and effects have **no** headless coverage; they are Studio-only by nature.

## Documentation

- [docs/PROGRESS.md](docs/PROGRESS.md) — milestones, limitations, simulated timings, changelog
- [docs/STUDIO_VALIDATION_CHECKLIST.md](docs/STUDIO_VALIDATION_CHECKLIST.md) — ordered procedure for the first Studio session
- [docs/TEST_PLAN.md](docs/TEST_PLAN.md) — automated coverage and manual Studio cases
- [docs/PLAYTEST.md](docs/PLAYTEST.md) — what testers should do and report
- [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) — gate before a closed playtest

## What is deliberately not here

No monetization of any kind: no game passes, developer products, premium currency, loot boxes or
paid randomness exist in the code. No base building, cosmetic store, matchmaking, trading, PvP or
second boss. `FeatureFlags.luau` lists these; anything switched off is inert, with no UI entry
point, remote handler or stored data.
