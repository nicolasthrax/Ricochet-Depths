# Ricochet Depths — Progress

Original IP. Nothing in this project copies names, art, layouts, wording, enemies, cards or
presentation from any existing game.

## Current milestone

**Milestone 7 — Co-op foundation** (next). Milestones 1–6 are complete; see the changelog.

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

## Known limitations

| # | Limitation | Impact |
|---|---|---|
| 1 | No persistence yet — salvage is computed and shown but not saved. | Milestone 8. |
| 2 | Co-op is untested with more than one client. Membership, shared rooms and per-player offers are implemented; 2–4 client validation has not been run. | Milestone 7. |
| 3 | `MatchService.luau` is ~500 lines, over the ~150-line convention. | Split planned in Milestone 10. |
| 4 | No audio. `SoundService` hooks are not yet placed. | Milestone 9/11. |
| 5 | No developer overlay yet; `DebugConfig` exists but nothing consumes it. | Milestone 10. |
| 6 | Enemies do not avoid pillars — they clamp to arena bounds but can walk into cover. | Acceptable for the slice; revisit if playtests flag it. |
| 7 | Telemetry sink only prints in Studio. No external transport. | Milestone 11. |

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
