# Go / no-go metrics

What decides whether Ricochet Depths scales, from the concept's "Go / no-go metrics" section
(steam-to-roblox.xlsx, Concept MVP sheet), and where each number comes from in this build.

The concept gives **no fixed numeric thresholds**. Its bar is Roblox's own: "Do not scale
acquisition until first-play bounce and D1 are at/above Roblox similar-experience benchmarks"
(source S28, Creator Hub > Acquisition). Those benchmarks are shown per experience in Creator Hub
analytics. So the rule is **compare against the benchmark band Creator Hub shows**, never a number
written down here in advance. `docs/DESIGN_RESEARCH.md` records the public rule of thumb (D1 20%+
good, 30%+ great) for orientation only.

## The gates, in order

| # | Gate (concept wording) | Metric | Where to read it | Instrumented by |
|---|---|---|---|---|
| 1 | Before ads | First-play bounce (<60 s) and D1 at/above the similar-experience benchmark | Creator Hub > Analytics > Acquisition / Retention | Roblox (automatic) |
| 2 | FTUE | Join → first input → first hit → first upgrade → first fusion → first run end → first base upgrade | Creator Hub > Analytics > Onboarding funnel | `FunnelService` (`LogOnboardingFunnelStepEvent`, steps 1-7) + `TelemetryService` "FunnelStep" |
| 3 | Retention (primary) | D1, D7, play days/user, intentional co-play days/user; diagnose by device and acquisition source | Creator Hub > Analytics > Retention / Engagement | Roblox (automatic); co-play is driven by gates, the party/friend bonus and base visits |
| 4 | Monetization | Payer conversion, ARPPU, revenue per user by product; one change at a time; regional pricing on | Creator Hub > Analytics > Monetization; Economy dashboard | Roblox (automatic) + `FunnelService:Economy` (`LogEconomyEvent`, every coin/token source and sink) |
| 5 | Content | If players exhaust modifiers or the base in under two weeks, add content before any season pass | Economy dashboard (sinks by SKU), funnel step 7, building levels | `LogEconomyEvent` sinks carry the building / cosmetic id as the SKU |

## How to read each one

**Bounce (<60 s).** The first descent is built to beat it: no title card, spawn facing the well,
a solo first descent starting as soon as the character exists, a banner, a clustered target pack
for a first hit inside 5-15 s, a first card inside ~30 s and a fusion before the first minute's
elite (`RunConfig.FirstDescent`). If bounce is above the benchmark, look at funnel steps 2-4.

**Funnel (FTUE).** Each step is logged once ever per account (`Flags.Funnel`), so the funnel reads
as unique players. The biggest drop between two adjacent steps is where to work:
- Join → FirstInput: the first descent did not start, or the player did not understand aiming
  (check `FirstDescent` telemetry; test touch and gamepad).
- FirstInput → FirstHit: the first targets are too far or hidden (FirstPit layout).
- FirstHit → FirstUpgrade: the first room takes too long to clear.
- FirstUpgrade → FirstFusion: the forced Split Shot pair is not being taken (check the card
  picker's RECOMMENDED tag and the auto-pick).
- FirstRunEnd → FirstBaseUpgrade: the results screen's "your haul builds X" and the base panel
  are not leading players home.

**D1 / D7 / play days.** Supported by the forgiving 7-day track (never resets), the daily
modifier and its once-a-day bonus, three daily quests, and the offline Salvage Yard claim
(8 h cap, more with the Storehouse and the Supporter Pack, never past 12 h).

**Co-play days.** Gates of 2-4 players, the party bonus (+5% coins per extra member, up to +15%,
+10% with a Roblox friend), co-op revives, and cheering friends' bases.

**Payer conversion / ARPPU.** Two passes and two products, no paid power
(`MonetizationConfig`). Change one price at a time with Creator Hub price optimization, and turn
regional pricing on (`docs/RELEASE_CHECKLIST.md`). The paid Revive and rewarded video stay off
(`FeatureFlags.PaidRevive`, `FeatureFlags.RewardedVideo`) until checked in Studio and live.

## Decision

- **Go (scale acquisition):** bounce and D1 at/above benchmark, and no funnel step losing more
  than its neighbours.
- **Fix first:** any gate below benchmark. Work on the step the funnel shows, one change at a
  time, and re-measure over at least a week of new players.
- **No season pass** until D7 is proven and four weeks of content exist (the concept's own rule).
