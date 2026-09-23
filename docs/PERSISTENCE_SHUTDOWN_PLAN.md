# Persistence: Shutdown and Session Lifecycle — Design Proposal

**Status: approved and being implemented one step at a time.** Live progress is tracked under
*Persistence plan progress* in `docs/PROGRESS.md`. Sections 1–2 describe the code as it was before
implementation began; sections 3–5 describe the design as approved.

Platform limits relied on here: `BindToClose` handlers get up to **30 seconds**. There is **no
per-key write cooldown** — the old six-second same-key limit was removed in June 2023 — so writes
compete only against the general request budget, which scales with player count. An earlier
draft of this document assumed the cooldown still applied; that has been corrected throughout.

---

## 1. How it works today

| Path | Where | Behaviour |
|---|---|---|
| Join | `GameBootstrap.luau:114` | `task.spawn` → `PlayerDataService:Load`. Session is registered **before** the load yields (`PlayerDataService.luau:90`). |
| Retry | `PlayerDataService.luau:53–70` | Up to 5 attempts, backoff 0.5 → 1 → 2 → 4s (`task.wait`), so ~7.5s of sleeping plus the cost of each `UpdateAsync` call. |
| Save | `PlayerDataService.luau:125–162` | Captures `session.profile` by reference, calls `UpdateAsync`, then on success **replaces** `session.profile` with the stored result and clears `dirty`. Currency, unlocks, flags and stats are last-write-wins; only the run ledger is unioned. |
| Leave | `GameBootstrap.luau:128–131` | `task.spawn` → `Release` = `Save` then `_sessions[player] = nil`. |
| Shutdown | `GameBootstrap.luau:140–141` | `BindToClose` → `SaveAll`, which saves every session **one after another** on the calling thread. |

The headless harness cannot see any of the problems below: its `task.wait` returns immediately
and `task.spawn` runs synchronously, so nothing ever interleaves.

## 2. Problems

Ordered by severity. P5 is the most serious and was not in the previous report.

**P1 — Shutdown can exceed its budget.** Roblox waits up to 30 seconds for `BindToClose` handlers.
`SaveAll` is sequential, so its worst case is the *sum* of every player's worst case. One
struggling profile can spend ~7.5s sleeping plus five `UpdateAsync` calls; four of them can
comfortably pass 30s. Saves after the cutoff are simply lost.

**P2 — Duplicate concurrent saves of the same key.** On shutdown Roblox also removes each player,
so `PlayerRemoving` fires `Release` in its own thread *while* `SaveAll` is iterating. Both call
`Save` on the same session at once — two `UpdateAsync` requests for one key. With no per-key
cooldown the second write is not delayed, so this is **less severe than first drafted**: the cost
is a wasted request from the budget. The part that still matters is that two in-flight saves on
one session are exactly the interleaving that triggers P3.

**P3 — A change made during an in-flight save is lost.** `Save` yields inside `UpdateAsync`. If
`GrantReward` or `ApplySettings` runs during that yield and after the transform has already read
the snapshot, the save completes by **overwriting** `session.profile` with the stored result — which
does not contain the new change — and then clears `dirty`. The change is gone from memory *and*
never marked for saving. For a reward this means salvage silently disappears.

**P4 — A load still yielding when the player leaves.** `Release` sees `loaded == false`, skips the
save and deletes the session. The load then completes against a detached session table. This is
benign today — no mutation can happen before a load completes, so nothing is lost — but it is only
safe by accident, and it becomes unsafe the moment anything writes to a session during loading.

**P5 — A cross-server rejoin can erase a payout permanently.** A player finishes a run on server A
and moves to server B before A's save lands. B loads the pre-payout profile. A's save then commits
the payout and records the run in the ledger. Later, B saves: `Currency` is last-write-wins, so
B's stale balance overwrites A's payout — **but the ledger union keeps A's run key marked as paid**.
The salvage is gone and the idempotency guard now guarantees it can never be re-granted. The same
shape applies to a fast rejoin on one server, since sessions are keyed by `Player` object and a
rejoin creates a new one for the same `UserId`.

## 3. Proposal A — Bounded shutdown (P1)

### Options

| | Sequential with early cutoff | Parallel with shared deadline |
|---|---|---|
| Total time | Sum of every save | Roughly the slowest single save |
| Fairness | Players late in iteration order are starved first | Every player gets the full window |
| Request load | One in flight at a time | Up to N in flight; N ≤ 4 here, well inside the per-minute budget |
| Complexity | Low | Moderate: needs a completion counter and deadline-aware retries |
| Duplicate writes | Still possible via `PlayerRemoving` | Still possible; solved by Proposal B either way |

### Recommendation: parallel with a shared deadline

1. `BindToClose` computes `deadline = now + ShutdownBudget`, proposed **25s** — five seconds of
   margin under Roblox's 30.
2. Each dirty, loaded session gets its own save thread. Clean and read-only sessions are skipped.
3. Retries become deadline-aware: before sleeping, a save gives up if
   `now + backoff + expectedCallCost > deadline`, rather than sleeping past the cutoff.
4. The handler waits on a completion counter, polling briefly, until every save finishes or the
   deadline passes, then logs each unfinished save as `ShutdownSaveFailed`.

### And make shutdown matter less: save on reward

The only data whose loss really hurts is a payout. Today it sits unsaved until the next autosave
(120s) or the player leaving. **Proposal: save immediately after `GrantReward`.** That costs one
extra `UpdateAsync` per player per run — about one write per player every six to eight minutes,
negligible against a budget that scales with player count — and turns most shutdown saves into
settings-only no-ops. With no per-key cooldown, that write cannot collide with the next save of the
same profile, so it adds no queueing either.
With this in place, P1 degrades from "players lose rewards" to "players may lose an options
change".

## 4. Proposal B — One save per session at a time (P2, P3)

1. **Coalesce.** A session holds at most one in-flight save. A second `Save` request while one is
   running does not start another; it marks the session `saveAgain` and waits for the in-flight
   save's result. When the in-flight save finishes, it runs once more if `saveAgain` is set.
   `Release` and `SaveAll` then share one write instead of racing two.
2. **Version, not a boolean.** Replace `dirty` with a monotonically increasing `version`, bumped by
   every mutation. A save records the version it started with and, on success, marks
   `savedVersion` to that value — never "clean". Anything that changed during the yield leaves
   `version > savedVersion`, so it is still pending.
3. **Stop replacing the profile.** On success, merge only what the store authoritatively owns (the
   unioned ledger) back into the live profile, rather than overwriting the whole table. Changes
   made during the yield survive in memory.

## 5. Proposal C — Session lifecycle (P4, P5)

### C1. Generation tokens for loads (P4)

Each `Load` stamps its session with a fresh token. After the load returns, it commits only if
`_sessions[key]` still holds *that* session; otherwise it discards its result. A detached load can
then never become saveable, and the safety of P4 stops being accidental.

### C2. Key sessions by `UserId`, not `Player` (part of P5)

A same-server rejoin then finds the existing session instead of creating a second one for the same
DataStore key. A load requested while one is already in flight for that `UserId` waits for it
rather than issuing a second `UpdateAsync`.

### C3. Make currency commutative (P5)

Two ways to stop a stale server overwriting a payout:

| | Session locking | Delta currency (recommended) |
|---|---|---|
| Idea | The profile records which server owns it; a second server waits or refuses until the lock is released or expires | A session keeps unsaved *grants*, not a balance; the save applies them to whatever the store currently holds |
| Solves P5 | Yes | Yes |
| Cost | Lock expiry and stolen-lock handling; a crashed server can hold a player hostage until expiry | Small: the transform does arithmetic instead of assignment |
| Schema change | New lock field | **None.** Pending grants live in memory only |

**Recommended: delta currency.** The session keeps `pendingGrants = { [runKey] = amount }`. The
`UpdateAsync` transform, for each pending grant, adds it to the stored balance **only if** that run
key is not already in the stored ledger, then records the key. Because the transform re-reads the
stored value on every attempt and never mutates session state, it stays correct if `UpdateAsync`
invokes it more than once. Two servers writing the same player now compose instead of clobbering,
and the ledger check keeps it idempotent. Pending grants are cleared only when a save that included
them succeeds.

Stats need the same treatment in a lighter form: counters as deltas, `Best*` fields merged with
`max`. Settings, flags and unlocks can stay last-write-wins — losing an options change to a race is
acceptable; losing currency is not.

## 6. Testing plan (headless)

None of this is testable with the current stub, which is precisely why these bugs exist unseen.
Before any implementation:

1. **Cooperative scheduler in the harness.** `task.spawn` creates a coroutine; `task.wait` yields
   to a scheduler that advances the virtual clock and resumes due threads in order. Existing tests
   must stay green under it.
2. **Realistic fake DataStore.** `UpdateAsync` yields for a configurable duration, invokes its
   transform possibly more than once, draws from a request budget that throttles when exhausted
   (no per-key cooldown), and can be told to fail or stall.
3. **New cases**, each written to fail against today's code first:
   - Four stalled profiles: shutdown returns before the deadline, and reports every unfinished save.
   - `Release` and `SaveAll` on the same session produce exactly one write.
   - A reward granted during an in-flight save is persisted.
   - A player leaving mid-load leaves no session and no write beyond the load itself.
   - Two services sharing one store simulate a cross-server rejoin: the final balance includes both
     payouts, and neither run is paid twice.
   - The transform invoked twice by `UpdateAsync` does not double-apply a grant.

## 7. Rollout

- No schema change for A, B, C1 or C2. C3 keeps the stored format too; only the save transform and
  in-memory bookkeeping change.
- `FeatureFlags.Persistence` remains the kill switch.
- Suggested order, smallest risk first: save-on-reward (A) → coalescing and versioning (B) → tokens
  and `UserId` keys (C1, C2) → delta currency (C3) → parallel shutdown (A). Save-on-reward alone
  removes most of P1's real-world impact.

## 8. Open questions for review

1. Delta currency (C3) or session locking? The recommendation is delta; locking is the better fit
   only if you expect to add tradeable or otherwise non-commutative state later.
2. Is a 25s shutdown deadline right, or do you want more margin?
3. When a shutdown save fails outright, is logging it enough for the playtest, or do you want a
   recovery path (for example, a pending-grant record written to a separate key)?
4. Should the harness scheduler (§6.1) land first, on its own, since it is test-only and would
   start exposing interleaving bugs anywhere else in the codebase too?

**Resolved:** *Is one extra `UpdateAsync` per player per run acceptable for save-on-reward?* Yes.
With the per-key cooldown gone, the only cost is one request against a budget that scales with
player count, and that request cannot queue behind other writes to the same profile. That makes
save-on-reward the clear first step. It is the cheapest change in this plan and removes most of
P1's real-world impact on its own.
