# Design research: what makes a game like this feel complete

Research done for 1.3.0 (September 2026). It compares Ricochet Depths against the games it is
closest to, and against published Roblox retention data, then lists what changed as a result and
what is still missing.

## What the references do

**Ball x Pit** (ricochet + roguelite, the closest mechanical cousin). Reviewers single out three
things: every ball type has its own element (fire, ice, poison, lightning) so the screen fills with
different effects; balls can be **fused or evolved** into stronger versions, which gives a build a
goal to grow toward; and a **meta layer** (a village that unlocks new heroes, each with a different
starting kit) means every run adds something permanent. Later updates added more heroes and an
endless mode.

**Hades.** The **Pact of Punishment** turns difficulty into a menu of small, stackable conditions,
each adding "Heat", with bigger rewards for higher Heat. It is credited with most of the game's
long-tail replayability, because players choose their own challenge.

**Brotato / Vampire Survivors.** Build variety comes from **characters that change how you play**,
not only how big your numbers are, and from upgrades that interact (focusing a build beats
spreading it). "Does this unlock change player behaviour? If not, it is filler."

**Risk of Rain 2.** A **logbook** of every item and monster found, plus **challenges** that unlock
things, give completionists a checklist that outlasts the core loop.

**Game feel.** Distinct feedback per effect (colour, size, sound pitch), bigger hits for bigger
moments, and screen shake that scales with the event.

**Roblox retention data.** A good D1 is 20%+, great is 30%+. "D1 is the first session, D7 is
progression, D30 is social." Players with friends in-game retain far better than solo players.
Clear medium-term goals ("reach level 50") and prominently shown long rewards help the first week.

## Gap analysis against 1.2.0

| Reference pattern | 1.2.0 | Gap |
|---|---|---|
| Elemental effects that look and play differently | 15 cards, all stat changes | No on-hit or on-kill behaviour at all |
| Evolutions as build goals | 2 fusions (Fusillade, Caroms) | Few, and they could be missed by a bad roll |
| Characters / starting kits | One loadout for everyone | Nothing to unlock that changes playstyle |
| Player-chosen difficulty for bigger rewards | None | Nothing to do after the first extraction but repeat it |
| Enemy variety within a run | 8 archetypes, fixed per room | No per-run variation in enemy quality |
| Co-op interdependence (the D30 "social" lever) | Downed players wait for the next room | Nothing a teammate can do for you |
| Collection / logbook | Lifetime stats only | No codex, no long achievements |
| Medium-term goals | Levels, daily quests | No multi-week goals |

## What 1.3.0 adds

- **Shot effects: 10 new cards and 4 new evolutions.** Keen Edge (crits), Trick Shot (a shot that
  has ricocheted twice always crits: a reward for the game's core skill), Ignite (burn),
  Chain Arc, Volatile (kill explosions that chain through a cluster), Frostbite (slow), Siphon
  (heal on kill), Hunter (bonus against elites, champions and the boss), Second Wind (survive one
  fatal blow), Fleet Foot. Evolutions: Storm Conduit, Wildfire, Absolute Zero, Deadeye. An
  evolution you qualify for is **always** in your next offer. Arcs, explosions and burns ignore
  shields, so an elemental build is a real answer to Bulwarks and the Warden.
- **Rigs: six starting loadouts** unlocked at levels 1, 3, 5, 8, 12 and 16: Striker, Scatter,
  Carom, Juggernaut, Arcanist and Gambler. Each changes how you play (two shots at once, more
  bounces, a tank, elements from room 1, a crit gambler).
- **The Depth Pact:** seven conditions, Heat 0–16, +10% coins and experience per Heat. It opens after
  the first extraction. A group runs at the lowest rank anyone chose.
- **Champion enemies:** Armored, Swift, Volatile (bursts into orbs on death) and Mending,
  with a glow and a name tag. Triple coins and bonus experience. They appear in the Foundry and
  the Abyss, and in the Ruins as well under the Pact.
- **Co-op revives:** stand next to a downed teammate for 3.5 seconds to bring them back at 40%
  health, faster with more helpers. Downed players crawl toward help. A Revives stat and an
  achievement reward it.
- **The Journal:** 13 achievements that pay coins and experience, and a Codex of every card taken
  and every enemy defeated, with undiscovered entries hidden.
- **Feel:** colour-coded bursts, crit popups with "!", element-coloured damage numbers, bigger
  explosion bursts, pitch-shifted sounds, and a "CHAMPION SLAIN" callout.

## 2.0: the redesign of the fighting rooms

After 1.3.0 the owner's verdict was that the rooms "just lack something". The numbers agreed:
shots were free, enemies died in one or two hits, every room was one wave of the same job, and
the player had one verb. 2.0 took every recommendation that followed:

| Idea | Delivered as |
|---|---|
| Make every shot count | Orbs: 3, dropped where they stop, picked up or rolled home; trick-shot refunds |
| Bounces power up every shot | +50% damage and +8% speed per bounce, growing and heating the shot |
| A combo meter | Tiers x1.5 to x4 on coins and kill experience, called out, halved by a hit |
| A dash | 15 studs, 0.35s invulnerable, with Blink Strike, Quick Step, Recall and Phantom |
| Waves and swarms | 2–3 waves per room announced on the floor; Mite packs |
| XP gems mid-room | The Surge meter and its non-blocking perk strip (a meter rather than pickups, so the floor stays readable with orbs and coins on it) |
| Rooms with different jobs | Crystal Hunt, Hold the Beacon, Treasure Runners, the Trick Shot Gallery |
| Things that react to shots | Barrels that chain, boost pads, portals, loot crates |
| Enemies that react to ricochets | Mirror, Sponge, Magnet, Splitter King, and health bars |
| Choose the next door | Two doors after every room, with six kinds of promise, voted on as a group |
| A mini-boss per zone | The Colossus (Ruins) and the Forge Press (Foundry); the Warden Vault remains the Abyss's |
| Optional challenges | Trials: Trick shots only, Untouchable, Swift, Frenzy |
| More impact | Shatter shards, the room-clear flash and stamp, camera kicks, pulsing cues |

Not delivered, and why: **slow motion on the last kill** (the server owns time; a client-only
slow-down would desync what players see from where things are), **music tied to the combo**
(there is no music to layer yet), **an Abyss twin mini-boss** (the Warden Vault already fills
the slot), and **a shop door** (the Armoury and Surge Well doors cover "spend something here").

## Still missing (ranked by expected impact, as of 2.0)

1. **Music.** The game has no music. A lobby loop and a combat loop with a layer per combo tier
   would be the cheapest large gain in atmosphere. Needs original uploaded audio.
2. **Endless mode.** After the Throne there is only the Pact. An endless descent with a depth
   leaderboard would give the best players a goal with no ceiling.
3. **Daily seeded run.** The same seed, doors and Pact for everyone that day, with its own board.
4. **Pact and combo leaderboards.** Highest Heat and best combo on the lobby wall (new boards
   need lobby geometry).
5. **Onboarding for Rigs, the Pact and revives**, matching the 2.0 hints.

All of it still needs the Studio and live-server validation in `RELEASE_CHECKLIST.md`.

## Sources

- [Ball x Pit (Wikipedia)](https://en.wikipedia.org/wiki/Ball_x_Pit)
- [Ball x Pit review, ScreenHub](https://www.screenhub.com.au/news/reviews/ball-x-pit-review-ball-bouncing-roguelite-is-hard-to-put-down-2682765/)
- [Ball x Pit review, Use a Potion](https://www.useapotion.com/2025/11/ball-x-pit-review-bouncing-into-roguelite-perfection/)
- [Hades Pact of Punishment, RPG Site](https://www.rpgsite.net/feature/10287-hades-pact-of-punishment-heat-modifiers-and-how-to-maximize-your-rewards)
- [Pact of Punishment, Hades Wiki](https://hades.fandom.com/wiki/Pact_of_Punishment)
- [5 Essential Tips to Make Your Roguelite Game Work, Entalto Studios](https://entaltostudios.com/5-essential-tips-to-make-your-roguelite-game-work/)
- [How to Design a Roguelite Meta-Progression, Bugnet](https://bugnet.io/blog/how-to-design-a-roguelite-meta-progression)
- [Brotato guide, Rogueliker](https://rogueliker.com/brotato-guide/)
- [Risk of Rain 2 Challenges wiki](https://riskofrain2.fandom.com/wiki/Challenges)
- [2026 Roblox Benchmark Report, GameAnalytics](https://www.gameanalytics.com/reports/2026-roblox-report)
- [Roblox Retention Rate Benchmarks by Genre (2026), BLOXG](https://bloxg.com/statistics/roblox-retention-benchmarks)
- [First Week Retention: Optimizing Day-1 Through Day-7, ROLearn](https://rolearn.dev/guidance/first-week-retention-optimization/)
- [Retention, Roblox Creator Hub](https://create.roblox.com/docs/production/analytics/retention)
- [Game feel on the web: squash, shake, and the art of juice](https://valdemird.com/blog/game-feel-on-the-web/)
