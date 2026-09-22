# Ricochet Depths

A 1–4 player co-op ricochet-shooting roguelite for Roblox. Aim bank shots that bounce off walls
and enemies, chain kills, pick one of three upgrades between rooms, and extract before the
depths take you.

Original IP. Nothing here copies names, art, layouts, wording, enemies, cards or presentation
from any existing game.

**Status:** pre-playtest vertical slice. Every result below comes from static checks and a
headless test suite — the project has not yet been run inside Roblox Studio. See
[docs/PROGRESS.md](docs/PROGRESS.md) for the honest state of things.

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
```

Tool paths are overridable with `LUAU_BIN`, `LUAU_COMPILE_BIN`, `LUAU_ANALYZE_BIN` and `ROJO_BIN`.

## Architecture

The server is the sole authority for firing validation, projectile collisions, enemy damage and
death, card offers and selection, rewards, run state and every saved value. The client sends
only an aim direction, a power scalar, a card id and a few requests — all of which are
re-validated — and otherwise draws what it is told.

```
src/ReplicatedStorage/        shared config and data (no logic)
  *Config.luau                Run, Enemy, Upgrade, Reward, Projectile, Room, Aim, Effect,
                              Ui, PlayerData, Debug, plus FeatureFlags
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
    RewardService             payout maths and per-server idempotency
    TelemetryService          rate-limited, de-identified event logging
    EffectBroadcaster         batches cosmetic impacts
    WorldAdapter              character position and teleport, injected for testability
    PartPool                  generic fixed-size pool

src/StarterPlayerScripts/     client input and views (display only)
  AimController.client        drag-to-aim for mouse and touch
  ClientMain.client           owns every view and one connection per server event
  HudView / CardPickerView / ResultsView / OnboardingView / SettingsView / UiTheme
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

120 tests cover projectile physics and containment, pool integrity, enemy lifecycle and
shielding, upgrade offers and stacking, the full run loop, soft-lock guards, co-op membership,
persistence and migration, reward idempotency, and soak runs. See
[docs/TEST_PLAN.md](docs/TEST_PLAN.md).

## Documentation

- [docs/PROGRESS.md](docs/PROGRESS.md) — milestones, limitations, changelog
- [docs/TEST_PLAN.md](docs/TEST_PLAN.md) — automated coverage and manual Studio cases
- [docs/PLAYTEST.md](docs/PLAYTEST.md) — what testers should do and report
- [docs/RELEASE_CHECKLIST.md](docs/RELEASE_CHECKLIST.md) — gate before a closed playtest

## What is deliberately not here

No monetization of any kind: no game passes, developer products, premium currency, loot boxes or
paid randomness exist in the code. No base building, cosmetic store, matchmaking, trading, PvP or
second boss. `FeatureFlags.luau` lists these; anything switched off is inert, with no UI entry
point, remote handler or stored data.
