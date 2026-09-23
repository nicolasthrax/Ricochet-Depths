# Closed Playtest Release Checklist

Gate for putting a build in front of invited testers. Nothing here is a formality: an unchecked
box that is not explicitly waived blocks the playtest.

**Build:** `0.5.0-dev` · **Status:** not releasable — no Studio validation has been performed.
The ordered procedure for section 2 is `docs/STUDIO_VALIDATION_CHECKLIST.md`.

## 1. Build status

| Check | State | Notes |
|---|---|---|
| `luau-compile` on all sources | PASS | 47 modules + 8 test files |
| `luau-analyze` lint | PASS | zero findings in `src/` |
| `rojo build` | PASS | Rojo 7.5.1 |
| Headless test suite | PASS | 225 tests, 0 failures |
| Property-based fuzz suite | PASS | randomised config and event sequences, all seeded |
| Soak: 25 consecutive runs | PASS | instance count flat from run 3 onward |
| Soak: ~3600 frames of continuous fire | PASS | pool constant at 150 throughout |
| No secrets, keys, cookies or private IDs in the repo | PASS | `DebugConfig.AllowedUserIds` ships empty by design |
| Version string surfaced in-game | PASS | Options panel, from `RunConfig.Version` |

## 2. Studio validation — **NOT STARTED**

Every box below is unchecked. The project has never been opened in Studio. Until these pass,
nothing in this document should be read as "it works".

- [ ] Rojo connects and syncs with no errors
- [ ] Player spawns in the lobby; the pedestal prompt appears and starts a run
- [ ] Drag-to-aim fires; the shot travels flat and ricochets visibly
- [ ] Enemies take damage and die; room-clear fires
- [ ] Card picker shows three cards; a pick applies and the HUD updates
- [ ] Auto-pick resolves an ignored offer
- [ ] All four rooms complete; results totals are correct
- [ ] Return to lobby resets cleanly; a second run behaves identically
- [ ] `Workspace/ProjectilePool` holds exactly 150 parts throughout
- [ ] `Arena/EnemyPool` holds exactly 36 parts throughout
- [ ] Bulwark blocks head-on shots and dies to a flank ricochet
- [ ] Warden Vault escorts respawn while the core lives
- [ ] No errors or warnings in the Output window across a full run

## 3. Multiplayer validation — **NOT STARTED**

- [ ] 2 clients: full run to extraction
- [ ] 3 clients: full run to extraction
- [ ] 4 clients: full run to extraction
- [ ] Each player receives and resolves their own upgrade offer
- [ ] One player leaving mid-run does not disturb the others
- [ ] The last player leaving ends the run and returns the server to lobby state
- [ ] A late joiner is admitted at the next room boundary
- [ ] One player going down does not end the run; all going down does

## 4. Datastore validation — **NOT STARTED**

Requires a separate test experience with **Enable Studio Access to API Services** turned on.
Development builds write to the `dev_v1` scope and can never touch live data.

- [ ] Salvage persists across leave and rejoin
- [ ] `BindToClose` flushes on server shutdown
- [ ] A repeated completion for the same run key pays nothing
- [ ] With API services disabled, the session goes read-only, the run still completes, and no
      reward is granted or duplicated
- [ ] A v2 profile migrates to v3 without losing currency or ledger entries

## 5. Mobile validation — **NOT STARTED**

- [ ] iPhone emulation: HUD readable, nothing clipped
- [ ] iPad emulation: three cards fit on one row
- [ ] Touch drag aiming matches mouse behaviour
- [ ] Every button meets the 48px minimum target
- [ ] Options panel is usable on the narrowest supported width

## 6. Known issues at this build

| # | Issue | Severity | Plan |
|---|---|---|---|
| 1 | No Studio validation at all. | **Blocker** | Sections 2–5 before any tester sees this. |
| 2 | No audio; `FeatureFlags.Audio` is off. | Medium | Post-playtest. |
| 3 | Enemies do not path around pillars. | Low | Revisit only if playtests flag it. |
| 4 | Telemetry only prints to the Studio output; no transport. | Medium | Wire once an analytics destination is chosen. |
| 5 | Effects are placeholder parts; no particles. | Low | Post-playtest polish. |
| 6 | Balance numbers are first-pass guesses, never played. | High | Tune from playtest data. |
| 7 | Run length target of 6–8 minutes is unverified against real play. The dry-run simulator puts the floor well below it, but that is a bot estimate. | High | Measure in the first playtest. |
| 8 | 85% of simulated runs end in room 3. May be an artifact of a bot that cannot bank shots. | Medium | Watch in the first playtest before changing anything. |
| 9 | Persistence data-loss races: a reward granted mid-save can vanish; a cross-server rejoin can erase a payout that the ledger then refuses to re-grant. | **High** | Proposal in `docs/PERSISTENCE_SHUTDOWN_PLAN.md`, pending review. Should be resolved before any playtest where salvage matters. |

## 7. Rollback

Every milestone is a separate commit on `claude/vigilant-keller-xt8dly`, and each one leaves the
suite green, so reverting to any earlier commit yields a working build.

- **A feature misbehaves in a playtest:** turn its flag off in `FeatureFlags.luau` and republish.
  Flags are checked at bootstrap, so a disabled feature registers no remote handler and writes no
  data.
- **Persistence misbehaves:** set `FeatureFlags.Persistence = false`. Every session becomes
  read-only, runs still complete, and no profile is written — no partial or corrupt saves.
- **A schema change goes wrong:** do not roll the schema version back. Add a forward migration
  instead; `PlayerDataService.Normalise` only ever moves a profile forward, so a downgrade would
  strand newer profiles.
- **The build is bad:** revert to the previous milestone commit and republish. No datastore
  migration is needed, because migrations are additive and older code ignores unknown fields.

## 8. Manual steps required in Roblox Studio / Creator Hub

These cannot be done from this repository and need a human with account access.

1. **Create the experience.** Creator Hub → Create → Experience. Build the place with
   `rojo build -o RicochetDepths.rbxlx`, open it in Studio, and publish to that place.
2. **Create a separate test experience.** Publish the same place a second time under a test
   experience. Keep playtesting off the live place entirely.
3. **Enable API services on the test experience.** Studio → Game Settings → Security → *Enable
   Studio Access to API Services*. Without this, datastore calls fail and every session is
   read-only, which is the correct fallback but blocks section 4.
4. **Set experience permissions.** Creator Hub → Experience → Permissions → Private, then invite
   testers individually. Do not make it public for a closed playtest.
5. **Set the icon and thumbnails.** Creator Hub → Experience → Icon and Thumbnails. Placeholder
   art is fine for a closed test; it must be original.
6. **Set the maximum players to 4.** Game Settings → Players → Max Players. The run loop assumes
   1–4 and has not been exercised beyond that.
7. **Enable the platforms you intend to test.** Game Settings → Places → Devices. Mobile must be
   on for the touch checks in section 5.
8. **Populate `DebugConfig.AllowedUserIds`** in the test build only, with the user ids that
   should see the F3 overlay. Never commit real ids; the file ships with an empty list.
9. **Check analytics after the first session.** Creator Hub → Analytics. Confirm sessions and
   playtime are recording before drawing conclusions from telemetry.
10. **Choose a telemetry destination** if you want events off-server. Nothing is wired yet;
    `TelemetryService` takes a sink function, so this is a one-line change once a destination
    exists.
11. **Do not configure monetization.** No game passes or developer products should be created.
    `FeatureFlags.Monetization` is off and no monetization code exists.
