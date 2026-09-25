# Lane game (Phase 1 MVP): architecture

The lane redesign from the *Visual & Gameplay Design Proposal V1* (25 Sep 2026): a fixed 62°
tabletop camera, a 1D rail, a server-simulated flat 2D lane, geode targets that step forward,
and 3-card modifier picks with fusion. It lives in `mvp/` and builds as its own place:

```
rojo build mvp.project.json --output lane.rbxlx
```

The 3.0 arena game in `src/` (`default.project.json`) is untouched. Both trees share the headless
test harness (`tests/run.py`): `tests/mvp_*.test.luau` run against `mvp/`, the rest against
`src/`, so module names only need to be unique within each tree.

## Rules

- **`--!strict` everywhere in `mvp/`.** `tools/strict-check.sh` type-checks it with luau-lsp
  (pinned 1.70.0, fetched into `.cache/`) against the real Roblox definitions and a Rojo
  sourcemap, under both Luau solvers. `scripts/check.sh` runs it.
- **The server owns the game.** Shots are simulated on the server as 2D reflection math, with no
  Roblox physics. Clients send intent (aim, rail position, picks) and render what the server
  reports.
- **All remotes go through `ReplicatedStorage.Network`.** Nothing else creates or looks up a
  remote by name. Each client→server remote has one validator, one rate limit and exactly one
  owning server service.
- **Shared config is data only, frozen.** `GameConfig`, `ModifierDefinitions` and `FusionRecipes`
  are deep-frozen and check their own invariants when they load.
- **One entry script per side.** `Bootstrap.server` and `ClientBootstrap.client` are the only
  scripts; everything else is a ModuleScript with `init()`. Services and controllers talk through
  `Modules.Signal` signals and the remotes, never by reaching into each other's state.

## Hierarchy

✅ = exists now. The rest is planned and lands with the step that needs it.

```
Workspace
├── LaneSpawn                     ✅ invisible SpawnLocation behind lane slot 1
├── Lanes                            Folder, built at runtime: one Lane_<userId> per player
└── LaneView / AimGuide              client-only visuals (targets, telegraphs, shots, guide)

ReplicatedStorage
├── Network                       ✅ every remote, typed, validated, rate limited
├── NetworkRemotes                   Folder, created at runtime by the server (never in the place file)
├── Modules                       ✅ Folder
│   ├── Signal                    ✅ typed synchronous signal (decouples services and controllers)
│   └── ProjectilePool            ✅ client shot parts: Get(cf) / Release(part), capped at 80
└── Source                        ✅ Folder
    ├── Types                     ✅ shared type vocabulary; no runtime dependencies
    ├── DeepFreeze                ✅ recursive table.freeze for configs
    ├── Guard                     ✅ runtime narrowing of untrusted values (remote payloads)
    ├── GameConfig                ✅ lane, rail, shot, ricochet, sim, rooms, run, XP, upgrades, camera, HUD, palette
    ├── ModifierDefinitions       ✅ 8 base cards + 8 fused variants, stat lines, id parsing
    ├── FusionRecipes             ✅ unordered pair -> fused variant, with integrity checks
    └── Sim                       ✅ Folder: pure, deterministic 2D math shared by server and client
        ├── LaneGeometry          ✅ grid cells, target boxes, rail clamp, aim clamp, lane space <-> world
        ├── Ricochet              ✅ swept circles vs walls and rounded target boxes, bounces, aim trace
        └── ShotStats             ✅ folds a loadout into per-shot numbers (damage, radius, bounces, cooldown)

ServerScriptService
├── Bootstrap.server              ✅ Network.mountServer(), then UpgradeService, CombatService, RunDirector
├── Modules                       ✅ Folder
│   ├── TargetField               ✅ one run's targets: grid cells, HP, burn/chill, pulse advance, snapshots
│   ├── WaveGenerator             ✅ room plans: block rows, HP curve by room and depth, elite room
│   └── LaneBuilder               ✅ lane slots and the lane model (floor, neon walls, rail, danger line)
└── Services                      ✅ Folder
    ├── CombatService             ✅ FireProjectile + RailInput; fixed-step Heartbeat sim of every shot,
    │                                wall/target ricochets by normal reflection, hits, burn, chill, arcs,
    │                                blasts, shards, pierce; batched shot/damage events
    ├── UpgradeService            ✅ SelectUpgrade + RerollUpgrade; XP -> level -> 3-card offers,
    │                                recommended card, per-run loadout, fusion on a matching pick
    ├── RunDirector               ✅ SetPaused + FetchRunSnapshot; per-player runs, rooms, pulses,
    │                                breaches, elite telegraphs, rewards, defeat and restart
    ├── PartyService                 parties of 1-4, drop-in at the next room boundary
    ├── FtueDirector                 scripted first 60 s and its safety nets
    ├── ContextVerbService           the one context verb per player (Revive, Extract, Fuse)
    ├── ExtractService               Descend / Bank loot, haul persistence
    └── FunnelTelemetry              onboarding funnel: server-observed steps + client-only steps

StarterPlayer.StarterPlayerScripts
├── ClientBootstrap.client        ✅ starts the controllers and wires their signals together
└── Controllers                   ✅ Folder
    ├── LaneCamera                ✅ Scriptable 62°/32° camera, fit solve, intro ease, screen <-> lane
    ├── CombatController          ✅ touch move strip + floating aim stick (release fires), mouse,
    │                                keys, gamepad; rail movement + RailInput; aim guide; FireProjectile
    ├── LaneRenderer              ✅ targets (SurfaceGui HP), pulse steps, telegraphs, pooled shots
    │                                dead-reckoned from server times, own shots predicted by sequence
    ├── HudController             ✅ HP pips, room, XP bar, haul, pause, modifier badges, banners
    ├── UpgradeUIController       ✅ 3-card pick: rarity styling, chips, input lock, 1/2/3 keys, reroll
    ├── HitFeedback                  hit-stop, wall flash, rising ping, xN pops, gem vacuum
    ├── ContextButton                the single context verb button
    └── ExtractFlow                  Descend / Bank loot, haul tally, goal card, lift ride
```

## The combat loop

1. **Aim.** `CombatController` turns a right-thumb drag (or the mouse, or the right stick) into a
   lane-space direction, clamped by `LaneGeometry.clampAim`. The guide is
   `Ricochet.trace` from the muzzle against the lane walls and the targets the client can see
   (`LaneRenderer.obstacles`): solid to the first contact, dashed to the second, a ring at the
   first contact.
2. **Fire.** Releasing sends `FireProjectile { originX, direction, sequence }` and fires
   `CombatController.Fired`, which `LaneRenderer.predictShot` draws at once.
3. **Simulate.** `CombatService` checks the cooldown, the per-player shot cap and the origin
   (a client `originX` counts only within `Rail.fireOriginTolerance` of the server's rail
   position), then steps every shot at 60 Hz on Heartbeat with `Ricochet.step`. Walls reflect;
   target contacts go through a responder that deals damage and returns Reflect, Pierce or Stop.
4. **Report.** Each frame's spawns, bounces, hits and ends go out batched
   (`ShotsSpawned`, `ShotsBounced`, `DamageReport`, `ShotsEnded`). Clients move each shot in a
   straight line from its last reported point and server time, so no collision runs on a client.
5. **Level up.** Breaks feed `RunDirector` (gems, XP) through `CombatService.TargetBroken`. A full
   XP bar makes `UpgradeService` send `UpgradeOffered`; the run freezes (time scale 0) while the
   pick is open. `UpgradeUIController` shows the cards and sends `SelectUpgrade`; picking a card
   that has a recipe with a held card fuses them on the spot (`LoadoutChanged.fusion`).

## Remotes

Declared in `ReplicatedStorage.Network`, created in `ReplicatedStorage.NetworkRemotes` at runtime.

### Client → server

| Remote | Class | Payload | Rate (per s / burst) | Server owner |
|---|---|---|---|---|
| `FireProjectile` | RemoteEvent | `originX`, `direction: Vector2` (normalised by the validator), `sequence` | 9 / 4 | CombatService |
| `RailInput` | UnreliableRemoteEvent | `x` (inside rail bounds), `sequence` | 30 / 10 | CombatService |
| `SelectUpgrade` | RemoteEvent | `offerId`, `modifierId` (base cards only) | 4 / 4 | UpgradeService |
| `RerollUpgrade` | RemoteEvent | `offerId` | 2 / 2 | UpgradeService |
| `ContextAction` | RemoteEvent | `verb: "Revive" \| "Fuse" \| "Extract"` | 4 / 4 | (planned) |
| `ExtractDecision` | RemoteEvent | `choice: "Descend" \| "BankLoot"` | 2 / 2 | (planned) |
| `SetPaused` | RemoteEvent | `paused` (solo only) | 2 / 3 | RunDirector |
| `ReportFunnelStep` | RemoteEvent | `step: "first_goal_seen" \| "tally_skip"` | 1 / 3 | (planned) |
| `FetchRunSnapshot` | RemoteFunction | none -> `RunSnapshot?` | 1 / 3 | RunDirector |

`FetchRunSnapshot` is the only RemoteFunction, and it only goes client → server. The server never
invokes a client.

### Server → client

| Remote | Payload | Sent by |
|---|---|---|
| `RunStateChanged` | `RunState`: run id, phase, depth, room i/n, time scale, pause, lane origin | RunDirector |
| `ShotsSpawned` | batched `ShotSnapshot`s: point, direction, speed, radius, tint, server time, `sequence` | CombatService |
| `ShotsBounced` | batched new point, direction, speed and server time per bouncing shot | CombatService |
| `ShotsEnded` | batched shot ids + end points | CombatService |
| `DamageReport` | every hit of one sim step: target, amount, HP after, source, point | CombatService |
| `TargetsSpawned` | `TargetSnapshot`s on the grid (column, row, width, HP) | RunDirector |
| `TargetsAdvanced` | pulse number, moved targets, breached target ids | RunDirector |
| `AttackTelegraph` | column, width, windup, start time | RunDirector |
| `HealthChanged` | user, pips, max, downed | RunDirector |
| `HaulChanged` | haul, delta, source target | RunDirector |
| `XpChanged` | fraction to next pick, level | UpgradeService |
| `UpgradeOffered` | offer id, 3 choices (recommended, new, fuses into), rerolls, timeout, input lock | UpgradeService |
| `UpgradeResolved` | offer id, card, auto-picked | UpgradeService |
| `LoadoutChanged` | user, modifier stacks, fusion-ready flags, fusion event | UpgradeService |
| `ContextVerbChanged` | the verb to show, or nil to hide | (planned) |
| `ExtractOffered` | depth, haul, bank bonus, goal preview | (planned) |
| `RunEnded` | outcome, banked/lost haul, best combo, fusions, discoveries, XP | RunDirector |

`DamageReport` goes server → client only. A client never reports damage.

## Simulation (`Source/Sim`)

- **Plain numbers, no `Vector2`.** `Vector2` stores 32-bit floats, so a simulation that went
  through it would not match between machines. The sim uses Luau doubles throughout; vectors
  appear only where a result leaves it (payloads, world mapping).
- **One cast for the server and the preview.** `Ricochet.step` (server simulation) and
  `Ricochet.trace` (client aim preview) share the same ray casts and reflection, and a test checks
  they produce the same contact points.
- **Targets are rounded boxes.** A shot hits a target's box grown by the shot radius, with circular
  corners, so a corner hit bounces along the true normal instead of off a flat face.
- **Rules stay outside.** When a shot touches a target, a responder chosen by the caller returns
  `Reflect`, `Pierce` or `Stop`. Ricochet only moves circles and reports contacts; damage, burn,
  arcs and shards belong to the server services.
- **Bounded work.** At most `Ricochet.maxBouncesPerStep` contacts resolve per step, and a shot
  dies on its bounce budget, below `minSpeed`, at its lifetime, or past the rail edge.
- **Stacking** (`ShotStats`): size, fire rate and extra bounces stack. On-hit effects (split,
  burn, chill, arc, pierce) take one card per kind, and a fused card beats its base card. Fire
  cooldown never goes below `Shot.minCooldownSeconds`.

## Coordinates

Lane space is 2D. `x` runs across the lane (0 is the centre, ±`Lane.halfWidth`). `y` runs up the
lane from the rail (`y = 0`) to the back wall (`y = Lane.length`). The target grid has 9 columns
of 3-stud cells, and row 1 is against the back wall. Each pit maps lane space to the world through
its own origin CFrame (`Sim.LaneGeometry`), so config never depends on where a pit is built.

## Decisions to revisit

- **Ember is Common**, although section 04's card mock-up shows it as Rare. The FTUE needs a
  first pick of three commons that includes Ember, so the FTUE requirement wins.
- **Fusion happens on pick** (`GameConfig.Fusion.fuseOnPick`): picking a card that has a recipe
  with a card already held fuses the two at once. The HUD's gold "fusion ready" badge marks a held
  card that one more pick would fuse. The context button's *Fuse* verb from the mock-up is not
  used yet.
- **The aim guide ray-casts analytically** (`Ricochet.trace`) instead of with
  `Workspace:Raycast` against the wall parts, so the guide uses exactly the math the server
  simulates and ignores unrelated geometry.
- **Solo only for now.** Every player gets a lane of their own; parties, co-op timers, the FTUE,
  extraction and saving the haul are not built yet.
- The 4 cards beyond the proposal's Splitshot / Ember / Bigshot / Echo (Quickdraw, Frostbite,
  Spark, Drill) and all 8 fused variants except Inferno are new designs. Numbers marked "tuning"
  in `GameConfig` are first-pass.
