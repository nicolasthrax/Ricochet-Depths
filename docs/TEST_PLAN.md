# Ricochet Depths — Test Plan

Two layers: an automated headless suite that runs on every change, and manual Studio passes for
anything that needs a real engine, a real character or a real second client.

## Running the automated suite

```bash
./scripts/check.sh          # syntax + lint + rojo build + headless tests
python3 tests/run.py        # tests only
python3 tests/run.py tests/match.test.luau   # one file
```

Tool paths are overridable: `LUAU_BIN`, `LUAU_COMPILE_BIN`, `LUAU_ANALYZE_BIN`, `ROJO_BIN`.

The harness bundles the real production modules against a Roblox API stub
(`tests/harness/RobloxStub.luau`). Roblox-style `require(Instance)` calls are rewritten to a flat
module loader and `os.clock` is redirected to a virtual clock, so time-dependent behaviour is
deterministic. Game source is never modified for tests.

## Automated coverage

| Area | File | What it proves |
|---|---|---|
| Pool integrity | `projectile.test.luau` | 150 parts built once; `Acquire` never allocates; a dry pool returns nil; released parts are parked anchored and invisible. |
| Ricochet physics | `projectile.test.luau` | Bounce budget and lifetime both despawn; 120 randomised headings stay inside the room with zero overshoot past the surface skin; projectiles hold their travel plane. |
| Wall-adjacent spawns | `projectile.test.luau` | A shot fired into a wall from 1 stud away never spawns past it; open-space shots still use the full muzzle offset. |
| Fire validation | `projectile.test.luau` | Rate limiting; rejection of non-Vector3, NaN, infinite, vertical-only and zero directions, non-numeric and NaN power, and players with no live character. |
| Impact batching | `effects.test.luau` | Many contacts collapse into one remote; per-batch cap holds and overflow is counted; nothing is sent on an idle interval; capacity frees after a flush. |
| Enemy lifecycle | `enemy.test.luau` | Spawn on plane, unknown archetype rejected, active cap enforced, kill credited exactly once, recycled parts do not re-award kills. |
| Shield arc | `enemy.test.luau` | Head-on and inside-arc shots blocked; flank and rear shots land; unknown direction does not make an enemy invulnerable. |
| Enemy behaviour | `enemy.test.luau` | Chaser honours its standoff distance; sentry stays leashed; bounds clamping holds over 900 frames; contact damage respects its cooldown; lunge telegraphs before committing. |
| Enemy cleanup | `enemy.test.luau` | `Clear` empties the registry and returns every part; 40 spawn/clear cycles leave the pool at exactly its configured size. |
| Upgrade data | `upgrade.test.luau` | ≥9 cards over ≥4 categories; every effect targets a real stat with a valid op; exactly one unlimited-stack fallback. |
| Offer generation | `upgrade.test.luau` | Exactly three distinct cards; maxed cards never offered; fusion and stat gates hold; an offer still appears with the pool nearly exhausted; reproducible per seed. |
| Selection validation | `upgrade.test.luau` | Duplicate, stale, malformed and not-offered selections all rejected with a reason and no state change; auto-pick on timeout; offers dropped when a player leaves. |
| Stat stacking | `upgrade.test.luau` | Add stacks linearly, Multiply compounds, stack caps hold, max-health cards heal the difference, malformed cards rejected. |
| Run loop | `match.test.luau` | Full four-room run to extraction with correct summary; three back-to-back runs with fully reset state; second start refused; defeat when all players are down. |
| Soft-lock guards | `match.test.luau` | A room whose enemies vanish still clears; a room past its time limit is force-cleared; an unanswered upgrade auto-resolves; the run ends when the last participant leaves. |
| Reward integrity | `match.test.luau` | A run pays a player once however many completion events fire; multiplier scaling and the per-run cap; a defeat pays less than an extraction. |
| Fire gating | `match.test.luau` | Fire is only accepted during combat; upgrade choices are rejected outside the choice state. |

## Manual Studio test cases

### Setup
1. `rojo serve` in the repo root.
2. Studio → Plugins → Rojo → Connect. Expect "Connected", no red toast.
3. **F5** (Play, server + client). Play Solo alone is not sufficient for anything marked CO-OP.

### SP — single player

| ID | Steps | Expected |
|---|---|---|
| SP-1 | Enter play | Spawn on the lobby pad. HUD shows "Ricochet Depths" and the pedestal hint. |
| SP-2 | Walk to the pedestal, hold the prompt | "Descending…" banner, then room 1 loads and the HUD reads `Room 1 / 4`. |
| SP-3 | Drag from the character and release | A neon ball leaves the body, travels flat, and bounces off a wall with a white burst. |
| SP-4 | Drag a very short distance | Nothing fires (deadzone). |
| SP-5 | Fire at a wall while pressed against it | The shot bounces immediately; it never passes through. |
| SP-6 | Hit a Drifter | It disappears at once and the target count drops. |
| SP-7 | Clear the room | Card picker appears with three cards and a countdown. |
| SP-8 | Click a card | Picker closes, the HUD upgrade list gains the card, room 2 loads after the transition. |
| SP-9 | Let the timer run out | "Upgrade auto-selected" flashes and the run continues. |
| SP-10 | Reach room 4 | Warden Core spawns with escorts; escorts return while the core lives. |
| SP-11 | Shoot a Bulwark head-on | No damage. Bank a shot into its flank or back — it takes damage. |
| SP-12 | Finish room 4 | Results screen: outcome Extracted, four rooms, non-zero best chain, salvage earned. |
| SP-13 | Press Return to Lobby | Back in the lobby, HUD reset, upgrades cleared, a second run starts cleanly. |
| SP-14 | Die to Chasers | Results screen: outcome "Lost in the Depths", reduced salvage. |

### PHYS — projectile physics

| ID | Steps | Expected |
|---|---|---|
| PHYS-1 | Fire into a corner at 45° | The shot reflects and stays inside the room. |
| PHYS-2 | Spam fire for 30s | `Workspace/ProjectilePool` holds exactly 150 parts throughout. |
| PHYS-3 | Command bar: `print(_G.RicochetDepths.projectiles:GetActiveCount(), _G.RicochetDepths.projectiles:GetFreeCount())` | The two always sum to 150. |
| PHYS-4 | Watch a shot for its full life | It stays at y≈3 with no visible sag or climb. |
| PHYS-5 | Take `SplitShot`, then fire | Multiple projectiles leave in a fan. |

### ENEMY — lifecycle

| ID | Steps | Expected |
|---|---|---|
| ENEMY-1 | Inspect `Arena/EnemyPool` between rooms | Exactly 36 parts, all invisible and parked. |
| ENEMY-2 | Stand still near a Chaser | Damage lands about once a second, not every frame. |
| ENEMY-3 | Watch a Bulwark | It stops and flashes yellow before each lunge. |
| ENEMY-4 | Return to lobby mid-run by leaving | No enemy parts remain visible in the arena. |

### CO-OP — 2 to 4 clients

Studio → Test tab → set **Players** to 2, 3 or 4 → **Start**.

| ID | Steps | Expected |
|---|---|---|
| COOP-1 | One player starts a run | All connected players are pulled into the same run. |
| COOP-2 | Both players fire | Each aims and fires independently; neither can fire for the other. |
| COOP-3 | Clear a room | Every player receives their own three-card offer. |
| COOP-4 | One player picks, the other waits | The run advances only after both resolve (pick or auto-pick). |
| COOP-5 | One player dies | The other continues; the downed player returns at the start of the next room. |
| COOP-6 | All players die | Run ends in defeat for everyone. |
| COOP-7 | A player leaves mid-run | The run continues for the rest; no errors in the output. |
| COOP-8 | The last player leaves | The run ends and the server returns to lobby state. |
| COOP-9 | A player joins mid-run | They are admitted at the next room boundary, not mid-fight. |

### SAVE — persistence (Milestone 8, not yet implemented)

| ID | Steps | Expected |
|---|---|---|
| SAVE-1 | Finish a run, leave, rejoin | Salvage total persists. |
| SAVE-2 | Finish a run, force-close the server | Salvage is saved by the close handler. |
| SAVE-3 | Finish a run twice with the same run id | The second grant pays nothing. |
| SAVE-4 | Run with API services disabled | A controlled error state; no reward duplication, no data loss. |

### MOBILE — touch and scaling

| ID | Steps | Expected |
|---|---|---|
| MOB-1 | Device emulation → iPhone | HUD readable, nothing clipped, no horizontal scroll. |
| MOB-2 | Drag with touch emulation | Aiming behaves exactly as with a mouse. |
| MOB-3 | Tap an upgrade card on a phone target | The card is comfortably tappable (≥48px). |
| MOB-4 | Device emulation → iPad | Three cards fit on one row. |

### PERF — sustained load

| ID | Steps | Expected |
|---|---|---|
| PERF-1 | Fire continuously for 2 minutes | No growth in instance counts; frame rate stable. |
| PERF-2 | Complete 5 runs back to back | Pools return to their configured sizes after each. |
| PERF-3 | Watch the microprofiler during the elite fight | No per-frame allocation spikes from projectiles or effects. |
