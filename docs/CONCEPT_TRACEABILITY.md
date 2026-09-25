# Concept → code traceability (3.0.0)

Every item of the original concept (`steam-to-roblox.xlsx`: Overview, Roblox Playbook and Concept
MVP sheets, current as of 22 Sep 2026) mapped to the module that implements it and the headless
test that covers it, or marked as **deferred** where the concept itself defers it, or as
**ops** where it is a process step rather than code.

Legend: **✓** built and covered headlessly · **◐** built, but the part that matters most can only
be judged in Studio or live (called out) · **Deferred** not built, by the concept's own rule ·
**Ops** a production or live-ops step, tracked in `docs/RELEASE_CHECKLIST.md`.

Test files are under `tests/`; modules under `src/`. Nothing on this branch has run in Roblox
Studio yet; "covered" always means covered by the headless suite against the engine stub.

## Overview sheet

| Concept item | Status | Where | Tests |
|---|---|---|---|
| Original 1–4 player run (not a clone) | ✓ | Solo portal + gates of 2–4 (`RunConfig.Lobby.GateCapacity = 4`, `LobbyBuilder`, `PartyRooms`, `ArenaDirector`) | `lobby.test`, `coop.test`, `zz_bootstrap.test` |
| 6–8 minute projectile-ricochet roguelite | ◐ | `RunConfig.RunShape`, `TargetRunSeconds = 420`; dry-run floor 389 s (PROGRESS 3.0.0) | `match.test`, `runplan.test`, `./scripts/dryrun.sh` (bots, not humans: playtest confirms) |
| Descend, fuse visible modifiers, extract resources | ✓ | `UpgradeConfig` (8 fusions), `MatchRoute` Bank loot, `RewardService` | `upgrade.test`, `runloop.test` ("Bank loot") |
| Social home base with modest offline rewards | ✓ | `BaseConfig`, `BaseService`, `BaseBuilder`, `BaseView` | `base.test`, `views.test` |
| Drag/aim → release → ricochet → enemies pop, touch-ready | ◐ | `AimController`, `AimMath`, `ProjectileService` | `aim.test`, `physics.test` (feel on a phone: Studio/device) |
| Runs feed base, collection book, offline tasks, daily modifiers, friend visits | ✓ | `BaseService`, Codex (`PlayerDataService.RecordRunEnd`, `JournalView`), `DailyModifierConfig`, `BaseService:Cheer`, `VisitBase` | `base.test`, `loadout.test` (Codex), `runloop.test` |
| Pooled projectile visuals, modular modifiers | ✓ | `ProjectilePool`, `PartPool`, `EffectBroadcaster`; data-driven cards | `projectile.test`, `effects.test`, `soak.test` |
| Sell identity, convenience, structured progression, not combat power or paid random rewards | ✓ | `MonetizationConfig` (no coins, no stats; Premium coin bonus removed), `ShopConfig` (cosmetics only) | `monetization.test` ("no-paid-power rule"), `shop.test` |
| Bright, non-gory, short runs, optional co-op (ages 9–17) | ◐ | Art direction; co-op is optional (solo portal) | Studio review |

## Roblox Playbook: retention patterns

| Pattern / implementation | Status | Where | Tests |
|---|---|---|---|
| Core loop before menus: spawn into a safe micro-encounter, first input by 5–10 s, first reward by 30–45 s | ✓ | No title screen; `GameBootstrap._wantsFirstDescent` starts the solo first descent on spawn; `RunConfig.FirstDescent` (FirstPit) | `zz_bootstrap.test` ("drops a brand-new player"), `runloop.test` ("first descent") |
| Short complete run + long meta (resources feed base, collection, mastery) | ✓ | Run payouts → `BaseService`; Codex; levels and rigs | `base.test`, `progression.test`, `loadout.test` (Codex, rigs) |
| Visible short/mid/long goals (next fusion now, building today, collection this month) | ✓ | RECOMMENDED card (`UpgradeService.Recommend`), `BaseConfig.NextBuild` on results, Journal | `runloop.test`, `views.test` ("tells what the haul builds") |
| One daily biome modifier | ✓ | `DailyModifierConfig` (7), `MatchService._applyPact/_refreshMeta`, hub `ModifierBoard`, HUD chip | `runloop.test` ("daily modifiers"), `views.test` |
| Three lightweight quests | ✓ | `MetaConfig.QuestsPerDay = 3`, `MetaService` | `meta.test` |
| Forgiving 7-day reward track | ✓ | `MetaService.ClaimDaily` (never resets), extras on days 5 and 7 | `meta.test` ("never resets the track") |
| Offline progress with cap: modest claim for 8–12 h; active play faster | ✓ | Salvage Yard, `BaseConfig.Offline` (8 h base, +Storehouse, +2 h pass, 12 h max) | `base.test` ("offline claims") |
| Friend join button | ✓ | INVITE in `MenuDock` (SocialService) | `loadout.test` (MenuDock) |
| Party bonus that does not punish solos | ✓ | `RewardConfig.Party`, `MatchService:_partyBonus`, `FriendCache` | `runloop.test` ("party bonus") |
| Rescue / combo actions | ✓ | Co-op revives (`MatchCombat._stepRevives`), combo meter | `loadout.test` ("co-op revives"), `redesign.test` |
| Visitable bases | ✓ | `BaseBuilder` plots, `VisitBase`, Cheer | `base.test`, `zz_bootstrap.test` |
| Update cadence (drops every 2–4 weeks, biome/season every 2–3 months) | Ops | Content is data-driven (rooms, cards, buildings, cosmetics, modifiers) | Live-ops plan |

## Roblox Playbook: Robux spending mechanics

| Mechanic / offer | Status | Where | Tests |
|---|---|---|---|
| Low-price pass 99–149 R$: extra loadout slot + permanent nameplate + base sign style | ✓ | `ExplorerPass` (129 R$, `PresetSlots` 1; `Explorer` nameplate, `Banner` sign in `ShopConfig`) | `monetization.test`, `shop.test` ("cosmetic kinds"), `economy.test` (presets) |
| Premium pass 299–399 R$: cosmetic bundle, extra presets, build storage, supporter badge | ✓ | `SupporterPack` (349 R$: Gold trail, Gilded theme, Cheer emote, +2 presets, +2 h, `ChatTag` "Supporter") | `monetization.test`, `shop.test`, `base.test` (cap hours) |
| Dev product: 29 R$ one-per-run revive | ◐ | `Revive` product → ReviveToken, `MatchService:UseReviveToken`, grace window; behind `FeatureFlags.PaidRevive = false` | `monetization.test`, `economy.test` ("revive tokens"); purchase flow needs a live check |
| Dev product: 49–79 R$ reroll bundle | ✓ | `RerollBundle` (59 R$, +5 Rerolls) | `monetization.test`, `runloop.test` ("reroll") |
| Event currency packs only if earnable | Deferred | No events or event currency at launch | — |
| Season pass (299–399 R$, 28 days) | **Deferred** | Concept: "Add only after a reliable 4-week content pipeline and D7 proof" | — |
| UGC / Limited item | **Deferred** | Concept: "Not MVP-first" | — |
| Private server 49–99 R$/month; base-showcase controls | ✓ / Ops | Owner features a base (`FeatureBase`, lobby `FeaturedBoard`, `GameBootstrap._ownsPrivateServer`); price set in Creator Hub | `economy.test` ("private servers") |
| Rewarded video: small fixed bonus at run end | ◐ | `RewardedAds` (pcall, fixed coins, daily cap), results button; `FeatureFlags.RewardedVideo = false` | `economy.test` ("rewarded video"); needs a live check (eligibility varies) |
| Guardrails: no mandatory damage, show contents exactly, regional pricing, never create artificial failure, cap prompts, no paid random rewards | ✓ / Ops | No stats sold; descriptions list contents; revive offered only when down, once a run; regional pricing in the checklist | `monetization.test` |

## Roblox Playbook: first 60 seconds

| Time | Concept | Status | Where | Tests |
|---|---|---|---|---|
| 0–5 s | Spawn facing the pit, pulsing aim line, avatar moving, no lobby wall; banner "Bounce shots. Break everything." | ✓ / ◐ | Spawn pad faces the well; first descent on spawn; `WorldAdapter.Teleport(..., lookAt)` faces the room; `AimIndicator:Pulse` until the first shot; banner Callout + onboarding hint | `lobby.test` (spawn facing), `runloop.test` ("arrival", banner), `views.test` ("aim hint"); feel in Studio |
| 5–15 s | Drag/hold to aim, release; first shot destroys a clustered target; one large contextual prompt; input adapts | ✓ / ◐ | FirstPit: six harmless Drifters in a tight pack near the spawn; onboarding "Aim" hint | `runloop.test` ("tight pack of harmless Drifters"); input on touch/gamepad in Studio |
| 15–30 s | XP fills fast; choose 1 of 3 cards with icon + 3-word label; big cards, rarity colours, no paragraphs; default timer in co-op | ✓ | `UpgradeConfig` faces (`Label`, `Icon`), `CardPickerView`, `ChoiceTimeout = 10` | `runloop.test` ("card faces"), `views.test` |
| 30–45 s | A duplicate enables an obvious fusion; show the power jump; "Try it now" | ✓ / ◐ | Forced Split Shot twice; `MatchService:_offerFusionNow` offers Fusillade alone ("FUSION! Try it now") | `runloop.test` ("duplicate brings Fusillade at once"); the icon-merge animation is a Studio polish item |
| 45–60 s | Mini-elite bursts into resources; 3 s base preview of what the haul builds; one CTA: Descend or Bank loot | ✓ | FirstElite (`CoinBurst`, `ExtractPoint` → Bank loot door); `BasePreview` (3 s); results DESCEND / BUILD AT BASE with `SetNextBuild` | `runloop.test`, `views.test` ("points the camera at the player's plot") |

## Roblox Playbook: UI without a tutorial

| Rule | Status | Where | Tests |
|---|---|---|---|
| World first, UI second | ◐ | Targets in front of the spawn; signs in the world (`Signage`) | Studio review |
| Progressive disclosure (aim → upgrade → fusion → extraction) | ✓ | `OnboardingView` hints appear as each becomes relevant (Aim, Upgrade, Doors, BankLoot, Base) | `views.test` ("onboarding hints") |
| Mobile-first hierarchy (large buttons, few choices, readable icons) | ◐ | `UiConfig.MinTouchTarget = 48`; three cards maximum; icons | Studio / device check |
| Consistent verbs; one colour per resource/rarity | ✓ | `UiConfig.Colors`, `UpgradeConfig.Rarities` | — |
| Recoverable mistakes: auto-pick a safe upgrade, free early respec, teleport stuck players | ✓ | `ResolveExpired` picks the recommended card; `MatchFlow:RespecCard`; `_rescueFallers` | `upgrade.test`, `runloop.test` ("respec"), `match.test` |
| Instrument every step: join → first input → first hit → first upgrade → first fusion → first run end → first base upgrade | ✓ | `FunnelService` (once ever, AnalyticsService + telemetry) | `funnel.test` |

## Concept MVP sheet: loop stack

| Layer | Concept | Status | Where | Tests |
|---|---|---|---|---|
| Moment (2–5 s) | Aim → ricochet → hit chain → resource burst; 3 projectile bases; pooled FX; aim preview | ✓ | Six rigs (`RigConfig`, more than 3 bases); `CoinDrops`; `AimIndicator` | `loadout.test`, `coins.test`, `aim.test` |
| Run (6–8 min) | Clear rooms → modifiers → fuse → elite → extract; 2 biomes, 3 elites, 1 boss, 15 modifiers, 6 fusions | ✓ | 3 zones; WardenVault elite + Colossus and Forge Press mini-bosses (+ the tutorial's Hoard Keeper); Warden Prime; 36 cards; 8 fusions | `integrity.test`, `boss.test`, `upgrade.test` |
| Session (15–30 min) | Spend haul → place/upgrade buildings → claim quest; 12 buildings, 3 daily quests, collection book | ✓ | `BaseConfig` (12), `MetaService` quests, Codex | `base.test`, `meta.test`, `loadout.test` (Codex) |
| Daily (1–2 visits) | New modifier → offline claim → friend bonus; 7 modifiers, 8-hour offline cap, friend join reward | ✓ | `DailyModifierConfig`, Salvage Yard (8 h base cap), party friend bonus (+10%) and cheers | `runloop.test`, `base.test` |
| Season (28 days) | Guild target + cosmetic track + content drop | **Deferred** | Concept: "Post-MVP only; do not promise at launch" (weekly guild target included) | — |

## Concept MVP sheet: MVP build plan (exit tests)

| Phase | Exit test | Status |
|---|---|---|
| Prototype | Fun in 30 s; stable on target device; first shot readable | ◐ Studio / device |
| Vertical slice | New-player funnel from join to first extraction works without explanation | ✓ headless (`zz_bootstrap.test` first descent, `runloop.test` Bank loot); ◐ real players |
| Meta + social | Players understand why to run again; party flow low friction | ✓ base, visits, party bonus, 10 s vote cap (`RunConfig.DoorVoteSeconds`); ◐ playtest |
| Content + economy | No economy dead ends; free path feels complete | ✓ every building, card and cosmetic earnable (`shop.test` "one way to earn it"); ◐ playtest |
| Polish + soft launch | Analytics funnels, thumbnails, A/B configs, regional price setup | ✓ funnels (`funnel.test`); Ops: thumbnails in `marketing/`, regional pricing in the checklist |
| Buffer | No critical errors; 30+ FPS on low-end target | Ops (Studio / device) |

## Concept MVP sheet: launch economy

| System | Free path | Paid layer | Status | Where / tests |
|---|---|---|---|---|
| Power | All projectiles, fusions and buildings earnable | None at launch | ✓ | `MonetizationConfig`, Premium coin bonus removed; `monetization.test` ("sells no coins, no coin multiplier and no stats") |
| Identity | Earnable trails, titles, base trophies | Cosmetic trails, base themes, emotes, supporter badge | ✓ | `ShopConfig` (coins / level / pass), Trophy Hall pillars (`BaseBuilder`), `ChatTag`; `shop.test`, `base.test` |
| Convenience | 2 loadouts; normal upgrade pace | Extra preset slots; optional reroll bundle | ✓ | `MetaConfig.Presets`, `LoadoutService` presets, `RerollBundle`; `economy.test` |
| Failure recovery | Team revive and one earnable revive token | 29 R$ one-per-run revive, only after testing | ✓ / ◐ | Co-op revives; day-5 ReviveToken; `PaidRevive = false`; `economy.test`, `meta.test` |
| Progression track | Free 28-day track once content exists | 299–399 R$ premium track | **Deferred** | Concept: "No season pass in MVP unless four weeks of content is ready" |

## Concept MVP sheet: risks and controls

| Risk | Control | Status | Where / tests |
|---|---|---|---|
| Projectile count hurts mobile performance | Server-authoritative outcomes, client cosmetic trails, pooling, cap visible projectiles, test low-end Android | ✓ / ◐ | `ProjectilePool` (150), `EffectBroadcaster`; `soak.test`; device test is Ops |
| Looks like a direct clone | Distinct theme, original geometry and fusion grammar | ✓ | Original content throughout (README) |
| Build choices overwhelm ages 9–17 | Three cards max; icon + short verb; recommended tag; free early respec; gradual unlocks | ✓ | `UpgradeConfig` faces and `UnlockLevel`, `UpgradeService.Recommend`, respec; `runloop.test` ("gradual unlocks", "respec") |
| Co-op waiting / friction | Drop-in between rooms, 10-second vote cap, auto-choice, short revive window, solo scaling | ✓ | Late join (`MatchMembership`), `DoorVoteSeconds = 10`, auto-pick, `RunConfig.Revive.GraceSeconds`, `RunConfig.PartyScaling`; `coop.test`, `runloop.test`, `economy.test` |
| Monetization harms trust | Odds only if random systems exist (none); no random Robux packs; cap prompts; cosmetics first | ✓ | No random rewards anywhere (fixed ad bonus); `monetization.test` |
| Offline rewards replace active play | Cap at 8 hours; one active run worth several claims | ✓ | 8 h base cap, 10–30 coins/h vs hundreds per run; `base.test` |

## Concept MVP sheet: go / no-go metrics

| Gate | Status | Where |
|---|---|---|
| Before ads: bounce and D1 at/above similar-experience benchmarks | ✓ instrumented (Roblox) | `docs/GO_NO_GO.md` |
| FTUE funnel (7 steps) | ✓ | `FunnelService`; `funnel.test` |
| Retention: D1, D7, play days, co-play days | ✓ instrumented (Roblox) | `docs/GO_NO_GO.md` |
| Monetization: payer conversion, ARPPU, revenue by product | ✓ | `FunnelService:Economy` (`LogEconomyEvent`); `funnel.test` |
| Content exhaustion under two weeks → add content before a season pass | Ops | `docs/GO_NO_GO.md` |

## Deliberately deferred (per the concept)

- **Season pass** (free and premium 28-day tracks): "Add only after a reliable 4-week content
  pipeline and D7 proof" / "No season pass in MVP unless four weeks of content is ready".
- **UGC limiteds**: "Not MVP-first: eligibility, publishing advances and stock limits add cost/risk".
- **Weekly guild target** (the Season layer): "Post-MVP only; do not promise at launch".
- **Event currency packs**: "only if earnable", and there are no events at launch.
