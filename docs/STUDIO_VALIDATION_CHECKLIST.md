# First Studio Session — Validation Checklist

Everything in this project has been verified headlessly against a stubbed engine. This document
turns the first Studio session into execution rather than discovery: ordered steps, the exact
thing to click, the exact output to expect, and what a failure most likely means.

Work top to bottom. A failed step usually invalidates the ones after it, so stop and record it
rather than pressing on.

**Time needed:** about 40 minutes for V0–V6.

---

## V0 — Prerequisites and sync

| # | Do this | Expect |
|---|---|---|
| 0.1 | Install the Rojo CLI (`rojo --version` ≥ 7.0) and the Rojo Studio plugin. | Version prints. |
| 0.2 | In the repo root, run `rojo serve`. | `Rojo server listening on port 34872`. |
| 0.3 | Open a new empty Baseplate place in Studio. Delete the default Baseplate part. | Empty workspace. |
| 0.4 | Plugins tab → Rojo → **Connect**. | Panel reads **Connected**. No red toast. |
| 0.5 | In Explorer, expand ReplicatedStorage, ServerScriptService and StarterPlayer. | ReplicatedStorage holds 14 ModuleScripts. ServerScriptService holds `Main` (Script) and a `Modules` folder of 27 ModuleScripts. StarterPlayerScripts holds `AimController` and `ClientMain` (LocalScripts) plus the view ModuleScripts. |

**Pass:** connected, tree matches, no output errors.
**On failure:** a missing folder almost always means `default.project.json` was edited or a file
has the wrong extension. `.server.luau` → Script, `.client.luau` → LocalScript, `.luau` → ModuleScript.

---

## V1 — Lobby load

| # | Do this | Expect |
|---|---|---|
| 1.1 | Press **F5** (Play). Not F8 — several steps need a real server. | Character spawns. |
| 1.2 | Look at the Output window. | `[data] scope=dev_v1 schema=v4`. Possibly a `[data] profile load failed … read-only` warning — that is expected without API services and is checked properly in V6. **No red errors.** |
| 1.3 | Look around. | A dark 80×80 lobby floor, a cyan spawn pad, and a glowing cyan pedestal a few studs away. |
| 1.4 | Check the HUD. | Bottom-left health panel reading `100 / 100`. Top-centre panel reading `Ricochet Depths` with `Use the pedestal to begin a descent` beneath it. Bottom-right `Options` button. |
| 1.5 | Wait a moment without moving. | A hint appears near the bottom: *"Walk to the glowing pedestal and hold to begin a descent."* It fades after about 6 seconds. |
| 1.6 | In Explorer during play, expand Workspace. | `Arena` (containing `Enemies` and `EnemyPool`), `Lobby`, `ProjectilePool`. **No `Room` folder yet** — rooms are only built during a run. |
| 1.7 | Click the **Options** button. | Panel opens with Reduced flash / Effect intensity / Screen shake, and a `Build 0.4.0-dev` line. Click each control once; the label cycles. |

**Pass:** lobby renders, HUD populated, no red output.
**On failure:** if the lobby is missing entirely, `GameBootstrap.Start()` threw — the first red
error in Output names the module. If the HUD is missing but the lobby is there, the failure is
client-side in `ClientMain`.

---

## V2 — Single-player run into room 2

| # | Do this | Expect |
|---|---|---|
| 2.1 | Walk to the pedestal. | A prompt appears reading **Begin Descent / Ricochet Depths**. |
| 2.2 | Hold the prompt key (E on desktop) for about a third of a second. | Banner reads `Descending...`. Output shows `[telemetry …] RunStart {Players=1 RunId=1}`. |
| 2.3 | Wait 3 seconds. | You are teleported into a large walled room with three pillars, and the camera switches to a fixed high-angle view that follows you (mouse wheel zooms). The floor is dark with a faint grid; every wall and pillar has a glowing cap and base strip. HUD reads `Room 1 / 4 - Collapsed Atrium` and `6 targets left`. Output shows `RoomStart {Room=1 RoomId=Atrium …}`. |
| 2.4 | Confirm you are **not** stuck inside a pillar. | You can walk freely in all four directions. *(Two layouts had cover on the spawn point; this was fixed headlessly and V2.4 is the engine-side confirmation.)* |
| 2.5 | Press and drag the mouse **away** from a target, then release. | A cyan line pivots at the press point while dragging, and a neon aim line starts just ahead of your character (not through the torso) with a faint floor shadow, a drop line and a diamond reticle on the floor at its tip. A power bar fills at the bottom, and on release a glowing ball leaves from the start of the aim line, travelling flat. |
| 2.6 | Watch the ball reach a wall. | It reflects off the wall at a mirrored angle and a small white burst appears at the contact point. |
| 2.7 | Hit a pink Drifter. | It vanishes immediately. The `targets left` count drops by one. |
| 2.8 | Drag less than about 15 pixels and release. | Nothing fires. This is the deadzone, not a bug. |
| 2.9 | Fire twice in quick succession. | The second drag shows a **grey** aim line instead of cyan, and releasing does nothing. That is the cooldown, shown client-side. |
| 2.10 | Clear all 6 Drifters. | Banner reads `Choose an upgrade`, and three cards appear with a countdown reading `Auto-picks in 10s`. |
| 2.11 | Click one card. | The picker closes. The card's title appears in the top-right `Upgrades` list. Output shows `CardChosen {CardId=… }`. |
| 2.12 | Wait through the transition. | Banner `Moving deeper...`, then you are teleported into room 2. HUD reads `Room 2 / 4 - Shattered Gallery`. |

**Pass:** through 2.12 with no red errors.
**On failure at 2.5:** if no line appears, the client is not in combat state — check that
`RunStateChanged` reached the client. If the line appears but nothing fires, the server rejected
the request; look for a silent return in `MatchCombat.HandleFire`.
**On failure at 2.6:** if the ball passes through walls or leaves the room, that contradicts the
headless containment tests and is the single most important thing to report — capture a clip.

---

## V3 — Pool leak check

Do this **during** the run started in V2, while enemies are alive.

| # | Do this | Expect |
|---|---|---|
| 3.1 | Press **F3**. | A developer overlay appears top-left with fps, state, room, enemies, projectile counts, players, effects, telemetry and data counters. |
| 3.2 | Fire continuously for 30 seconds, watching the overlay. | `projectile` active + free always sums to **150**. Active never exceeds 150. |
| 3.3 | In Explorer, select `Workspace.ProjectilePool` and read the child count. | Exactly **150**, at every moment, including mid-barrage. |
| 3.4 | Select `Workspace.Arena.EnemyPool`. | Exactly **36**, at every moment. |
| 3.5 | Switch the command bar context to **Server** and run:<br>`local g = _G.RicochetDepths print(g.projectiles:GetActiveCount(), g.projectiles:GetFreeCount(), g.enemies:GetActiveCount())` | Three numbers. The first two sum to 150. The third matches the HUD's `targets left`. |
| 3.6 | Repeat 3.5 a few times over a minute of play. | The sum stays 150. It must never drift. |

**Pass:** both pools hold their exact configured size throughout.
**On failure:** a growing child count means something calls `Instance.new` at runtime — the pools
are the only places parts should be created. A shrinking free count that never recovers means
projectiles are not being released; check the despawn path in `ProjectileService:Step`.

---

## V4 — Results screen and dismiss

This step exists specifically to confirm a bug that was found and fixed headlessly: the results
dismiss callback previously closed over a global rather than its local view, so the button would
have errored on click. Nothing but a real click proves the fix.

| # | Do this | Expect |
|---|---|---|
| 4.1 | Finish the run, by either route. Fastest: clear all four rooms. Fastest failure: stand still in room 2 and let the orange Chasers kill you. | A results panel appears. |
| 4.2 | Read the panel. | A title (`Extracted` in green, or `Lost in the Depths` in red), then rooms cleared, enemies defeated, best ricochet chain, shots fired, damage taken, time, salvage earned, and the upgrades you took. |
| 4.3 | Sanity-check two numbers against what you did. | Rooms cleared and enemies defeated match your run. Best ricochet chain is at least 1. |
| 4.4 | **Click `Return to Lobby`.** | The panel closes and you are returned to the lobby. **Watch the Output window closely.** |
| 4.5 | Confirm the Output. | **No error at all.** An error mentioning `attempt to index nil` at `ResultsView` would mean the closure fix regressed. |
| 4.6 | Check the HUD after returning. | Health back to `100 / 100`, the `Upgrades` list empty, top panel back to `Ricochet Depths`. |
| 4.7 | Start a second run immediately. | It behaves exactly like the first. Room 1, six Drifters, full health, no upgrades carried over. |

**Pass:** 4.4 produces no error and 4.7 runs clean.
**On failure at 4.5:** capture the full stack trace. That is the closure bug returning.

---

## V5 — Co-op and late join

| # | Do this | Expect |
|---|---|---|
| 5.1 | Stop play. Test tab → set **Clients** to 2 → **Start**. | Two client windows plus a server window. |
| 5.2 | In client 1, start a run from the pedestal. | **Both** clients enter the run. Both HUDs read `Room 1 / 4`. The overlay's `players` reads 2. |
| 5.3 | Fire from both clients at once. | Each aims and fires independently. Neither client's aim line responds to the other's drag. |
| 5.4 | Clear room 1. | **Both** clients show their own three-card picker. The two offers may differ. |
| 5.5 | Pick a card on client 1 only. Leave client 2 alone. | Client 1's picker closes. The run does **not** advance. Client 2's countdown keeps running. |
| 5.6 | Let client 2's timer expire. | Client 2 shows `Upgrade auto-selected`, and only then does the run advance to room 2. |
| 5.7 | Check each client's top-right `Upgrades` list. | Each shows only its own card. |
| 5.8 | Stop. Set **Clients** to 3 and Start. Have client 1 begin a run, and **do not** start client 3 until the run is under way. | Clients 1 and 2 are in the run. |
| 5.9 | While room 1 is still in progress, look at client 3's HUD. | Client 3 is **not** in the run and is **not** teleported into the room. This is the late-join rule working. |
| 5.10 | Clear room 1 and let the run advance to room 2. | Client 3 is now teleported in, with full health and an empty `Upgrades` list. The overlay's `players` increases. |
| 5.11 | Close one client window mid-run. | The remaining clients continue with no errors in the server Output. |
| 5.12 | Repeat 5.1 with **4** clients and complete one full run. | Completes cleanly. All four receive a results screen. |

**Pass:** 5.6, 5.9 and 5.10 are the load-bearing ones. Record them individually.
**On failure at 5.5/5.6:** if the run advances while a player still has an open picker, the
round-completion check is wrong. If it never advances, the auto-pick timer is not firing.

---

## V6 — Persistence and the read-only fallback

Two sub-cases. Run them in this order.

### V6a — API services **off** (the failure path)

This is the default for a fresh place, so do it first.

| # | Do this | Expect |
|---|---|---|
| 6a.1 | Game Settings → Security → confirm **Enable Studio Access to API Services** is **off**. | Off. |
| 6a.2 | Play, and read the Output as you join. | A **warning** (yellow, not red): `[data] profile load failed for <name>, session is read-only: load failed after 5 attempts: …` |
| 6a.3 | Play a full run to the results screen. | The run completes normally. Nothing is blocked. |
| 6a.4 | Read the salvage line on the results panel. | `Salvage earned: 0`. Zero is correct here: an unloadable profile must never be credited. |
| 6a.5 | Check the Output for red errors. | None. The failure must be a controlled warning, never a crash. |

**Pass:** the game is fully playable, the warning appears, and the payout is 0.
**On failure:** a red error here means the read-only path is not being taken — the most likely
cause is something calling into `PlayerDataService` without checking `IsLoaded`.

### V6b — API services **on** (the success path)

| # | Do this | Expect |
|---|---|---|
| 6b.1 | Publish the place to a **separate test experience**, not a live one. | Published. |
| 6b.2 | Game Settings → Security → turn **Enable Studio Access to API Services** **on**. | On. |
| 6b.3 | Play and join. | `[data] scope=dev_v1 schema=v4` and **no** read-only warning. |
| 6b.4 | Complete a run and note the exact salvage figure on the results panel. | A number greater than 0. Write it down. |
| 6b.5 | Stop, then Play again and reach the lobby. | No read-only warning. |
| 6b.6 | Server command bar:<br>`local p = _G.RicochetDepths.persistence print(p:GetPublicProfile(game.Players:GetPlayers()[1]).Salvage)` | The figure from 6b.4, carried across the restart. |
| 6b.7 | Complete a second run. | Salvage increases by the second run's payout. Nothing is double-counted. |
| 6b.8 | Server command bar:<br>`local p = _G.RicochetDepths.persistence local s = p:GetStats() print(s.saves, s.saveFailures, s.retries)` | Saves greater than 0, failures 0. |

**Pass:** 6b.6 and 6b.7 both correct.
**On failure at 6b.6:** salvage reading 0 after a restart means the save is not landing — check
whether `Release` ran on leave, and whether the scope in 6b.3 matched.

---

## V7 — Content, juice, touch and the salvage shop (0.6.0-dev)

Everything below was built and tested headlessly only. Run it after V1–V6 pass.

| # | Do this | Expect |
|---|---|---|
| 7.1 | Start a run and look at room 1 from the tactical camera. | A two-tone checker floor under a faint grid, a glowing line just inside each wall, and **amber**-trimmed metal pieces: a 45° bevel in each corner and two diagonal reflectors south of the pillars. |
| 7.2 | Fire straight at one of the diagonal reflectors. | The shot turns 90° and carries on. Nothing gets stuck behind a corner bevel. |
| 7.3 | Hit a Chaser once, then shoot a Bulwark in the face. | A floating **1** rises over the Chaser; **BLOCKED** rises over the Bulwark. |
| 7.4 | Kill an enemy, then set Options → Screen shake to **Off** and kill another. | The camera kicks on the first kill and stays still on the second. |
| 7.5 | Reach the Fractured Crossing (room 2 in about half of runs since 0.7.0-dev). | HUD reads `5 targets left`: four Chasers and **one** Bulwark, which starts in the north-west area with open ground around it. |
| 7.6 | Audio. Sound ids ship as placeholders and `FeatureFlags.Audio` is off, so the game is silent. To check the hooks, put any sound id into `SoundConfig.Cues.WallBounce.SoundId`, set `FeatureFlags.Audio = true`, and bank a shot several times. | Each bounce plays, higher-pitched than the last, up to twice the base pitch. No Output warnings with the flag off. |
| 7.7 | In the lobby, stand on one of the four pads behind the pedestal. | The pad lights green, the HUD reads `Descending in 3...`, and the run starts on its own. Stepping off before zero cancels it. |
| 7.8 | Use the **Salvage Shop** kiosk prompt with no salvage and press Buy on anything. | The shop opens with your balance; buying says `Not enough salvage` and nothing changes. |
| 7.9 | Finish a run for salvage, buy **Reinforced Frame**, then start a run. | The balance drops by the price, and the run starts at `110 / 110` health. |
| 7.10 | Buy **Ember Trail** and fire. | Your shots leave an orange ribbon; teammates' shots do not. Tapping Unequip turns it off. |
| 7.11 | Device emulator (phone): drag on the **left** third of the screen, then on the **right** half, then tap the right half. | Left moves the character with the thumbstick and never aims. Right aims and fires on release. A tap fires nothing. |

**Pass:** 7.2, 7.5, 7.7 and 7.9 are the must-haves.
**On failure at 7.2:** a shot passing through a reflector or escaping the room means the engine
disagrees with the harness's rotated-box model; capture the heading and position.

## V8 — Playtest fixes, enemy models, zones, mechanics and the boss (0.7.0-dev)

Built and tested headlessly only. Run it after V7.

| # | Do this | Expect |
|---|---|---|
| 8.1 | In a run, hold the right mouse button and drag, then press Q and E, then scroll. | The view turns around your character and tilts between steep and shallow (never flat, never straight down). Q/E turn it. The wheel zooms. |
| 8.2 | After turning the camera, aim and fire at an enemy. | The aim line and the shot follow the rotated view; drag direction still matches shot direction on screen. |
| 8.3 | Drag to aim. | No blue line at the cursor. The world aim line, its floor shadow, the reticle and the power bar remain. |
| 8.4 | Stand on the room's spawn pad and move the camera around; aim across the floor. | The pad (a low plinth with a glowing ring) does **not** flicker, and neither does the floor under the aim line. |
| 8.5 | Look at the enemies. | Models, not boxes: Drifter eye with orbiting motes, Chaser with legs and fins, Bulwark with a visor, Warden core in spinning rings. A Bulwark or Warden flashes its whole model before lunging. |
| 8.6 | Play three runs. | Rooms differ between runs. The HUD reads `Room n / 7 - <zone>: <room>`; lighting shifts warmer in The Foundry and violet in The Abyss, and returns to normal in the lobby. |
| 8.7 | Foundry room with a laser gate (Cold Smelter, Stalled Conveyor or Forgeworks). | The beam dims, turns orange, then red. Standing in it while red costs health in ticks; shots pass through it at any time. |
| 8.8 | Foundry room with crates (Cold Smelter, Crucible or Forgeworks). Shoot one repeatedly. | It darkens at half health, then vanishes, and shots then pass where it was. |
| 8.9 | Abyss room with a sweeper (Hanging Spire or Starless Hollow). | The amber bumper swings back and forth; shots bounce off wherever it is. |
| 8.10 | Room with an amp pad (Rift, Spire, Warden Vault or Throne). Fire across the gold strip. | The shot turns gold and hits for one more. |
| 8.11 | Meet each new enemy. | Splitter breaks into two small Shards. Sentinel stays put, flashes, fires a slow red orb that stops on cover. Phaser flashes, goes see-through (shots pass it), and reappears near you. |
| 8.12 | Reach the Throne. | A boss bar reads `Warden Prime`. Its shield spins at first; below ~60% the bar says phase 2 and Shards and orb rings appear; below ~25% (phase 3) the shield is gone and rings come faster. Killing it extracts. |
| 8.13 | In the lobby. | Walls on every side (you cannot walk off), pillars and four lamps, a glowing ring round the pedestal, numbered ready pads, a canopy over the shop, and three zone banners on the north wall. |
| 8.14 | Look above and beyond the room walls. | Ruins: broken columns on the walls, rubble in the corners. Foundry: pipes, vents, hazard stripes. Abyss: floating crystals and glow lines. None of it blocks a shot. |

**Pass:** 8.1–8.4 (the playtest fixes), 8.6, 8.7 and 8.12 are the must-haves.

## V9 — Launch build: gates, solo portal, coins, regen, shops, cinematic (1.0.0)

Built and tested headlessly only. V9.10–9.11 need **Test → Clients and Servers → Local Server**
with 2–4 players; V9.12 needs a published test experience with real Robux ids.

| # | Do this | Expect |
|---|---|---|
| 9.1 | Walk round the lobby. | Readable signs on boards: SOLO DESCENT at the north, ARMORY and COSMETICS on the east kiosks, a board in each west gate, and the three zone names on the north wall. |
| 9.2 | Climb a lamp, pillar or canopy and try to jump out. | An invisible wall stops you everywhere; you cannot leave the hall. |
| 9.3 | Use the Solo Portal. | The camera falls down a glowing shaft with `DESCENDING · UPPER RUINS`, fades to black, then the room fades in under `Room 1 · <name>`. |
| 9.4 | Kill enemies. | Gold coins spin where they die and fly to you when you get close; the HUD shows `+N  Coins N`. Leftovers fly to you when the room clears. |
| 9.5 | Take a hit, then avoid damage for 5 seconds. | Health starts climbing slowly after about 4 seconds and stops at full. |
| 9.6 | Watch a Bulwark. | Its shield turns steadily on its own; shots into the open side land. |
| 9.7 | Look at the HUD in the lobby, then in a run. | Lobby: STORE button, no upgrades panel. Run: upgrades panel, no STORE button. |
| 9.8 | Finish or lose a run. | Results show `Coins earned`; the balance in the player list and the shop matches. |
| 9.9 | Use the Armory, then Cosmetics. | Each opens on its own tab; buying and equipping work; the Gold trail says VIP only. |
| 9.10 | Two players stand in Gate I; then one steps out. | The board shows `GATE I 2/8 · 15s` counting down; stepping out cancels it. Back in, it restarts and both descend together. One player alone never starts. |
| 9.11 | While that group plays, two more players use Gate II. | They start in a different arena; neither group sees the other's enemies, HUD or results. |
| 9.12 | (Published test place, real ids.) Buy a coin pack, then 2x Coins. | The pack credits once; the next run pays double; the Store shows the pass as Owned. |

**Pass:** 9.2, 9.3, 9.4, 9.10 and 9.11 are the must-haves.

---

## V10 — Polish build: menus, daily rewards, quests, codes, leaderboards, audio (1.2.0)

Built and tested headlessly only. 10.6 and 10.7 need a published test experience with API
services on (leaderboards and saved claims need a real DataStore).

| # | Do this | Expect |
|---|---|---|
| 10.1 | Join. | A full-screen title card: `RICOCHET DEPTHS`, a tagline and a gold PLAY button. PLAY fades it out. A toast says your daily reward is ready. |
| 10.2 | Look round the lobby. | `RICOCHET DEPTHS` over the north wall; three framed leaderboards on the south wall; fire braziers by the portal, gates and shops; crystals turning and bobbing over the well; motes rising from the well and dust drifting in the hall; a lit walkway from the spawn. You never see a spawn pad. |
| 10.3 | Press every button. | Every button clicks and presses in. **Listen:** shots zap, bounces ping (rising in pitch along a chain), kills shatter glass, shields clank, a room clear plays a fanfare. If any cue is silent, its built-in id is missing on your client; replace it in `SoundConfig`. |
| 10.4 | Options → Sound volume → Off, Low, Full. | Sound goes silent, quieter, full. |
| 10.5 | Open DAILY, CLAIM. | Day 1 tile turns CLAIMED; a toast shows `+50 coins`; the dot on DAILY clears; the balance rises. Reopen: `Next reward in …`. |
| 10.6 | Rejoin the same day (published place). | DAILY still says claimed. Nothing pays twice. |
| 10.7 | Open QUESTS; play runs until one completes; CLAIM it. | Three quests with bars. A toast at the end of the run names the finished quest; the dot shows on QUESTS; CLAIM pays once, then says DONE. |
| 10.8 | CODES → type `ricochet` → REDEEM, twice. | First: toast `Code redeemed! +150 coins`. Second: `You already redeemed that code.` A made-up code says it does not exist. |
| 10.9 | Tap the LEVEL badge. | Your profile card: level, XP bar and six lifetime stats. |
| 10.10 | Kill two enemies within two seconds; kill one off 3+ bounces. | `DOUBLE KILL` / `RICOCHET x3` pop up mid-screen with a sound. |
| 10.11 | Chat. | Your message is prefixed with `[Lv N]`; a VIP pass holder also gets a gold `[VIP]`. |
| 10.12 | Watch the leaderboards (published place, a few minutes after a run). | Your name appears with your level, kills and extractions. In Studio without API access they read `Leaderboards go live once the game is published`. |
| 10.13 | Watch a room in each zone. | Dust falls in the Ruins, embers in the Foundry, violet motes in the Abyss. |
| 10.14 | Tap INVITE. | The Roblox invite prompt opens (on a published place). |

**Pass:** 10.2, 10.3, 10.5 and 10.7 are the must-haves.

---

## Record your results

| Step | Pass / Fail | Notes |
|---|---|---|
| V0 sync | | |
| V1 lobby | | |
| V2 run to room 2 | | |
| V3 pool leak | | |
| V4 results dismiss | | |
| V5 co-op and late join | | |
| V6a read-only fallback | | |
| V6b persistence | | |
| V7 content, juice, touch, shop | | |
| V8 camera, flicker, models, zones, mechanics, boss | | |
| V9 gates, solo, coins, regen, shops, cinematic | | |

For any failure, capture: the step number, the full Output text including the stack trace, what
you saw instead, and a clip if it is visual. Those four things are enough to reproduce it
headlessly in most cases, which is where it can then be fixed and regression-tested.

## What this checklist deliberately does not cover

Left for a later session, so the first one stays focused:

- Mobile and tablet emulation (see MOBILE cases in `docs/TEST_PLAN.md`).
- Sustained performance and soak behaviour (PERF cases).
- The Warden Vault escort-respawn loop in detail.
- Shield-arc behaviour against the Bulwark from every angle.
- Balance. Nothing here asks whether the game is *good*, only whether it *works*.
