# Ricochet Depths — Progress

Original IP. Nothing in this project copies names, art, layouts, wording, enemies, cards or
presentation from any existing game.

## Current milestone

**Headless hardening complete. Blocked on manual Studio validation.**

Milestones 1–11 are implemented and the automated gate is green. Nothing has been run inside
Roblox Studio, and nothing in this repository should be read as engine-validated. The work since
the last entry pushed the headless ceiling as high as it will go — 225 tests, box-accurate
collision, property-based fuzzing, and a dry-run simulator — specifically so that the first
Studio session is execution rather than discovery. Run `docs/STUDIO_VALIDATION_CHECKLIST.md`
top to bottom when Studio is available.

### Where the stub is more forgiving than the engine

These are the places a headless pass **cannot** fail but the real engine might. They are the
highest-value targets for the first Studio session, in rough order of risk. None is a known
defect; each is an untested assumption.

| # | Assumption the stub makes | What the engine does instead | Watch for |
|---|---|---|---|
| 1 | `task.wait` returns immediately, so `PlayerDataService` retries cost nothing. | Real backoff yields up to ~7.5s per profile. `BindToClose` calls `SaveAll` **synchronously**, so four struggling profiles could approach Roblox's ~30s shutdown budget. | Data loss on a server shutdown while the datastore is slow. Studio step V6b. |
| 2 | No yielding means no interleaving, so a load can never overlap a leave or a rejoin. | A player can leave, or rejoin, while their `Load` is still yielding. The session is detached mid-flight and the completed load writes to a table no longer in `_sessions`. | A fast rejoin producing a stale or missing profile. |
| 3 | `WorldAdapter.Teleport` always finds a `HumanoidRootPart`. | A player mid-respawn has no character. `Teleport` returns false and **`_beginRoom` ignores it**, leaving that player at the previous room's coordinates after the geometry is destroyed. | A player falling out of the world at a room transition. |
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
| UI | Nothing. Views are constructed but never rendered | All of it: layout, scaling, touch, readability |
| Input | Nothing | All of it: drag-to-aim on mouse and touch |
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
- Versioned profile schema (v3) with safe defaults and ordered forward migrations.
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
  limited per event, and identities reduced to an opaque per-session index.

## Known limitations

| # | Limitation | Impact |
|---|---|---|
| 1 | **Nothing has been run in Roblox Studio.** Every claim of correctness rests on static checks and the headless harness, which stubs the engine. Physics feel, replication, character handling and UI layout are all unverified against the real engine. | Blocker for playtest. |
| 2 | Co-op is verified only headlessly. 2–4 real clients have never connected. | Blocker for playtest. |
| 3 | Balance numbers are first-pass guesses. The 6–8 minute run target has never been measured. | Tune from playtest data. |
| 4 | No audio; `FeatureFlags.Audio` is off and no sound assets are wired. | Post-playtest. |
| 5 | Enemies clamp to arena bounds but do not path around pillars. | Revisit if playtests flag it. |
| 6 | Telemetry only prints to the Studio output; no external transport is wired. | Needs a destination chosen. |
| 7 | Effects are placeholder parts, not particles. | Post-playtest polish. |
| 8 | `MatchService` and its four installed halves use a mixin pattern; a method name collision between them would silently overwrite. Names are currently distinct. | Acceptable; noted for future edits. |
| 9 | A late joiner is credited with `roomsCleared = index - 1`, so joining at the elite room still pays for the rooms the team cleared without them. Possible farming vector. | Design decision to confirm; untouched because it is a balance call. |
| 10 | Any participant can dismiss the results screen for the whole team. | Design decision to confirm; currently documented as intentional. |
| 11 | Duplicate small idioms across modules: flattening a Vector3 to XZ (five places), point-in-box tests (`EnemyService.FindEnclosingMover`, `RoomService.GetSpawnPoint`), and list removal. | Flagged only; consolidating would move code between modules, which needs approval. |

## Manual Studio validation still required

Nothing in this project has been run inside Roblox Studio yet — every result below is from
`luau-compile`, `luau-analyze`, `rojo build` and the headless test harness. The following must be
confirmed by hand; see `docs/TEST_PLAN.md` for the steps.

- [ ] MS-1 Rojo connects and syncs with no red errors.
- [ ] MS-2 Player spawns in the lobby; the pedestal prompt appears and starts a run.
- [ ] MS-3 Drag-aim fires; the projectile travels flat and ricochets visibly.
- [ ] MS-4 Enemies take damage, die, and the room-clear banner appears.
- [ ] MS-5 Three upgrade cards appear; clicking one applies it and the HUD updates.
- [ ] MS-6 Auto-pick fires after 10s of inactivity.
- [ ] MS-7 All four rooms complete and the results screen shows correct totals.
- [ ] MS-8 Return to lobby resets everything; a second run behaves identically.
- [ ] MS-9 `Workspace/ProjectilePool` holds exactly 150 parts at all times.
- [ ] MS-10 `Arena/EnemyPool` holds exactly 36 parts at all times.
- [ ] MS-11 Bulwark blocks head-on shots and dies to a flanking ricochet.
- [ ] MS-12 Touch aiming works under device emulation (iPhone and iPad targets).
- [ ] MS-13 2, 3 and 4 simulated clients complete a run together.

## Changelog

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
