# Ricochet Depths — Progress

Original IP. Nothing in this project copies names, art, layouts, wording, enemies, cards or
presentation from any existing game.

## Current milestone

**Headless hardening complete. Blocked on manual Studio validation.**

Milestones 1–11 are implemented and the automated gate is green. Nothing has been run inside
Roblox Studio, and nothing in this repository should be read as engine-validated. The work since
the last entry pushed the headless ceiling as high as it will go — now 290 tests, box-accurate
collision, property-based fuzzing, and a dry-run simulator — specifically so that the first
Studio session is execution rather than discovery. Run `docs/STUDIO_VALIDATION_CHECKLIST.md`
top to bottom when Studio is available.

### Where the stub is more forgiving than the engine

These are the places a headless pass **cannot** fail but the real engine might. They are the
highest-value targets for the first Studio session, in rough order of risk. None is a known
defect; each is an untested assumption.

| # | Assumption the stub makes | What the engine does instead | Watch for |
|---|---|---|---|
| 1 | *Now modelled.* The harness scheduler makes `task.wait` really suspend, and the fake DataStore holds writes in flight, so retry cost and shutdown timing are tested headlessly. Shutdown saves now run in parallel under a 25s budget. | Real DataStore latency, throttling under load and the exact BindToClose behaviour are still assumptions. | Studio step V6b; a shutdown with a slow store. |
| 2 | *Now modelled.* Loads, saves, leaves and rejoins interleave under the scheduler, and every race in `docs/PERSISTENCE_SHUTDOWN_PLAN.md` (P1–P5) has a regression test and a fix. | Real request ordering, and two genuinely separate servers, are still simulated with two service instances sharing one fake store. | A real cross-server rejoin during playtest. |
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
  limited per event, and identities reduced to an opaque per-session index.

## Known limitations

| # | Limitation | Impact |
|---|---|---|
| 1 | **Nothing has been run in Roblox Studio.** Every claim of correctness rests on static checks and the headless harness, which stubs the engine. UI and input have no headless coverage at all. | Blocker for playtest. |
| 2 | Co-op is verified only headlessly. 2–4 real clients have never connected. | Blocker for playtest. |
| 3 | Balance numbers are first-pass guesses. The simulated floor suggests runs are well under the 6–8 minute target, but that is a bot estimate, not a measurement. | Tune from playtest data only. |
| 3a | The dry-run bots cannot plan bank shots, so they understate how fast a skilled player clears cover-heavy rooms and overstate how lethal room 3 is. | Inherent to the tool; stated wherever its numbers appear. |
| 4 | No audio; `FeatureFlags.Audio` is off and no sound assets are wired. | Post-playtest. |
| 5 | Enemies clamp to arena bounds but do not path around pillars. | Revisit if playtests flag it. |
| 6 | Telemetry only prints to the Studio output; no external transport is wired. | Needs a destination chosen. |
| 7 | Effects are placeholder parts, not particles. | Post-playtest polish. |
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

| Bot | Room 1 | Room 2 | Room 3 | Room 4 | Modelled run floor |
|---|---|---|---|---|---|
| Direct fire, exact aim | 49.0s | 15.4s | 11.7s | 6.2s | ~93s |
| Direct fire with aim error | 9.3s | 9.0s | 11.6s | 6.5s | ~47s |
| Probing (throws shots off-angle when blocked) | 7.9s | 7.9s | 11.7s | 8.2s | ~46s |

Medians. The run floor is the sum of per-room medians plus fixed pacing; full-run samples are too
scarce to quote because the bots keep dying.

Three hypotheses for playtest, **none acted on**:

1. **Room 3 is a difficulty wall.** About 85% of simulated runs end there. A human may play it
   better than a bot that only backs away, so this may be an artifact.
2. **Runs may be far shorter than the 420s target.** Even allowing for human aiming and full
   upgrade timers, the floor is well under target. Change nothing until real timings exist.
3. **Ricochets are load-bearing, as intended.** The probing bot clears rooms 1 and 2 roughly six
   times faster than the strictly-straight one.

With strictly direct fire, 23 rooms were force-cleared by the 150s room time limit, so the
soft-lock guard is doing real work.

## Changelog

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
