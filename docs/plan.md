# Plan

The single source of truth for scope. Terms are defined in [`GLOSSARY.md`](../GLOSSARY.md), decisions in [`docs/adr/`](adr/).

## The game

A co-op action roguelite in the survivors-like genre for PC and phone, for players aged 13 and up, modelled in its skills, level-up cards, enemies and maps on Azeroth Survivors (a fan-made WoW roguelike), with our own setting, names and art and everything else our own. A party of one to four players ([ADR-0016](adr/0016-co-op-party-of-up-to-four.md)) enters a run of fifteen minutes on a round map in its own setting, with obstacles scattered anew for every run ([ADR-0014](adr/0014-round-map-with-a-horde-around-the-party.md)). The horde spawns around the players and grows with run time; elites and bosses with telegraphed attacks come on a clock. Skills cast themselves ([ADR-0013](adr/0013-skills-cast-themselves.md)): each player starts with one skill of their class and, at every level-up, takes one of three cards (a new skill, a skill's next rank, a passive), so the build is whatever the run deals; besides moving, a player fires up to three utility skills by hand. The way out is an extraction spell found in a chest hidden on the map; the run ends with the map's final boss ([ADR-0015](adr/0015-extraction-by-a-found-spell.md)). A player who extracts keeps the haul, the items and utility skills found in the run; one who dies loses it, and the gold and experience earned are kept either way ([ADR-0017](adr/0017-only-the-haul-is-at-risk.md)). Between runs players spend gold, raise their account level and class levels, and equip items in six slots and utility skills; harder maps ask for a minimum power and drop better loot ([ADR-0018](adr/0018-maps-ask-for-a-minimum-power.md)).

The look is deliberately stylised: low-poly shapes, strong colours, clear silhouettes, and most of the impression carried by skill effects, light and particles built in code.

The public release happens when the user judges the game ready; it needs stages 3–6. The shop comes with stage 6 and sells skins and shortcuts to unlock classes, never power.

## Stages

### Stage 1: the skeleton

**Status:** done ([PR #2](https://github.com/damiangaweda/roblox-roguelike/pull/2) merged).

The toolchain and offline gate ([ADR-0001](adr/0001-rojo-toolchain-and-offline-gate.md)), the pure rules core ([ADR-0002](adr/0002-pure-rules-core.md)), validated and rate-limited remotes, the movement budget ([ADR-0007](adr/0007-movement-budget.md)), lightweight enemies at the target count ([ADR-0004](adr/0004-lightweight-enemies.md)) and verification through the Studio MCP, proven on a throwaway loop of an auto-targeting attack and a horde spawning around the players.

### Stages 2a–2d: aimed combat on an open map

**Status:** merged ([PR #3](https://github.com/damiangaweda/roblox-roguelike/pull/3), [#5](https://github.com/damiangaweda/roblox-roguelike/pull/5), [#6](https://github.com/damiangaweda/roblox-roguelike/pull/6), [#7](https://github.com/damiangaweda/roblox-roguelike/pull/7)); superseded on 2026-10-27.

Aimed combat with the Elementalist ([ADR-0009](adr/0009-aimed-combat.md)), seven archetypes with telegraphs, perks, potions, downed and revive, a room graph and then an open map of points with camps, patrols, clues, zones on a clock and a flood ([ADR-0012](adr/0012-open-map-of-points-in-a-shared-world.md)), and skill effects, lighting and feedback built in code. The user's verdict on 2026-10-27: the concept was beyond what the project can make look and play well. What carries over into stage 3: the core's geometry, randomness, projectiles, statuses, synergies, enemy simulation and archetype telegraphs, life and the run's clock; the adapter's effects, atmosphere, camera, HUD and network code. The open map, camps, patrols, clues, zones, the flood and the map screen are removed.

### Stage 3: the solo run

**Status:** accepted on 2026-10-27 together with ADR-0013 to ADR-0018; in progress on `feat/solo-run`.

**Goal:** one fifteen-minute run, played alone, that is fun and looks intended: three classes whose skills cast themselves, cards that build a different character every run, a horde with elites and bosses, a hidden way out and a final boss.

**Scope:**
- **The run place** starts a run on its own, as now: a pick screen for the class, then the map; a summary after death or extraction, and a new run after it.
- **The map** ([ADR-0014](adr/0014-round-map-with-a-horde-around-the-party.md)): one map, a forest, flat and round (radius in configuration, proposal 400 studs), closed by an invisible wall. Low-poly obstacles (rocks, trees, ruins) are scattered by the server from a seed at a minimum spacing, with clear ground around the start and the extraction chest; they block players and enemies and nothing else. A fixed top-down camera that follows the hero.
- **Skills** ([ADR-0013](adr/0013-skills-cast-themselves.md)): every skill fires on its own cooldown at what its targeting picks: the nearest enemies, the toughest, the densest cluster, everything in a radius, a cone towards the nearest, a chain between neighbours, random enemies near the hero, a pulse or orbit around the hero, a totem that fights on its own, or the hero itself (a shield or a heal, each with its condition). A skill with no target retries shortly without spending its cooldown. A skill ranks up to 8: each rank raises damage, shortens the cooldown, grows the radius and the duration, and ranks 3, 5 and 7 add a target. Hits may splash, apply a status (slow, root, stun, fear, weaken, drain, burn, bleed, poison) and stack damage over time up to a limit per enemy; bosses shrug off most control.
- **Classes:** the Mage, the Warrior and the Archer, each with a pool of 8–11 skills modelled on WoW-like fantasy classes under our own names, three tags and two synergies between them (the Mage keeps shatter); a class sets the starting skill, health and speed. Ten passives are shared by every class (damage, health, speed, regeneration, haste, area, pickup range, experience, armour, critical chance), each ranking up to 5.
- **Level-up:** enemies drop crystals that fly to the hero within the pickup range; experience follows a curve that grows in three bands. Each level-up offers three distinct cards from a weighted draw: a skill's next rank, a new skill while fewer than six are held, a passive's next rank, a new passive while fewer than six are held, and a full heal only when nothing else is left. A card's colour shows how much it gives (a rank that adds a target, a rank 8, a strong new skill) and changes nothing else. There is no reroll and no skip. The run pauses while a solo player chooses.
- **Utility skills:** three buttons, each with its cooldown: a sprint, a barrier that absorbs damage, a heal. Until the stash exists (stage 5) every class has these three.
- **The horde:** grunts that walk straight at the hero, push apart and hit on contact. The number alive rises with run time to a cap within [ADR-0004](adr/0004-lightweight-enemies.md)'s budget (proposal: from 14 to 220); they spawn on a ring just outside the camera, a window of three adjacent kinds slides up the map's roster over the run, health and damage grow with run time, a closing ring of enemies spawns around the hero halfway between bosses, and strays far behind are moved back into the ring.
- **Elites:** the five archetypes of stage 2a with their telegraphs (brute, spitter, exploder, shieldbearer, shaman), rarer and stronger than grunts, appearing more often as the run goes on.
- **Bosses:** one every configured interval (proposal: 2 min 15 s, six before the end), each with one or two telegraphed attacks to dodge; the final boss at minute 15 with three attacks and a second phase at half health ([ADR-0015](adr/0015-extraction-by-a-found-spell.md)). Killing the final boss extracts the hero; if it lives for the configured time (proposal: 3 min) the map closes and the hero dies.
- **Extraction** ([ADR-0015](adr/0015-extraction-by-a-found-spell.md)): one chest at a random place on the map, unmarked until a configured minute (proposal: 5) when the compass starts to point at it; opening it takes a moment, and gives the extraction spell; casting takes a configured time (proposal: 5 s) and a hit interrupts it; the portal stands for a configured time (proposal: 20 s) and the spell can be cast again once it closes.
- **Health:** no regeneration without the passive; a kill sometimes drops food that heals, a boss always does. At zero health a solo hero dies and the run ends.
- **The look:** low-poly with strong colours; every skill, status, telegraph and the portal has an effect built in code from particles, beams, trails and lights, pooled; hits flash and show damage numbers; enemies are drawn as in stage 2a until the store pack is republished ([ADR-0010](adr/0010-rigs-from-a-store-pack-first.md)).
- **Removed:** the open map and its generator, camps, patrols, clues, zones, the flood, the map screen, potions, perks, aim and the basic attack, and the core modules and tests that only they used.

**Acceptance criteria:**
1. Core tests cover every targeting kind, the retry without a target, rank scaling and the target thresholds, statuses, damage-over-time stacking and the boss's resistances, the two synergies of each class, the card draw (three distinct cards, the slot limits, the heal only when nothing else is left, repeatable for a seed), the experience curve and crystal pickup, the horde's alive target, spawn ring, kind window, scaling and closing ring, every elite's and boss's telegraph and attack, the boss clock and the final boss's time limit, the chest, the spell's cast and interruption and the portal's lifetime, obstacles blocking movement, and the obstacle scatter keeping its spacing and clear ground, all repeatable for a seed.
2. Every number in the scope is configuration; classes, skills, passives, the roster and the map are data, not code.
3. The client sends only intents: pick a class, choose a card, fire a utility skill, open the chest, cast the spell, enter the portal; the server decides every target, hit and outcome.
4. In a Studio playtest with one client, driven through the Studio MCP and once by the user, each class plays a run in which skills fire on their own, level-ups offer cards that change the build visibly, an elite of each archetype and a boss are fought, the chest is found, the spell is cast and interrupted and cast again, and the hero extracts; another run reaches the final boss; a second run scatters different obstacles.
5. With the horde at its cap the server holds at least 50 Hz and the client at least 50 FPS with Studio focused; with the touch emulator moving and the three utility buttons work.
6. The user plays a run and judges whether it is fun and looks intended; the stage is done only when they say so.

### Stage 4: co-op

**Status:** outline; grilled for acceptance criteria before it starts.

A party of up to four in one run ([ADR-0016](adr/0016-co-op-party-of-up-to-four.md)); until the hub exists, the players who join the run place together are the party. Experience is shared: whoever picks up a crystal, everyone gains it, and each player chooses their own card. Downed and revive return for the party; a player who dies is out of the run. The horde spawns around every player within one shared budget and scales with the party's size. Threat: an enemy chases the player who holds the most threat towards it, which damage raises, and otherwise the nearest; a Warrior skill taunts, raising threat sharply, and other players' damage can take it back. The extraction portal stands for the whole party. Synergies between party members' tags. The performance check with four clients.

### Stage 5: the hub, the profile and loot

**Status:** outline; grilled for acceptance criteria before it starts.

The hub and run places of [ADR-0016](adr/0016-co-op-party-of-up-to-four.md), with the party formed in the hub and teleport data checked by the run server. A player profile with a format version from day one and numbered migrations: the stash, gold, the account level and each class level. Loot is personal: any enemy may drop an item, a utility skill or gold, and a tougher enemy drops more often and better. Items in six slots raise the hero's stats, and legendary items also change a skill. Utility skills drop from the same loot table, rarer, and can be equipped to any class. Death loses the haul and keeps the gold and experience ([ADR-0017](adr/0017-only-the-haul-is-at-risk.md)). A class level unlocks more skills in the class's pool and the second and third utility slot; the account level gives small stats and unlocks classes. Gold buys basic cosmetics, upgrades to items and utility skills, and items in the hub. One class is free; the others come with the account level or the shop.

### Stage 6: maps and the shop

**Status:** outline; grilled for acceptance criteria before it starts.

More maps, ordered from easiest to hardest, each with its own setting, roster, bosses and final boss and a minimum power every party member must reach ([ADR-0018](adr/0018-maps-ask-for-a-minimum-power.md)); harder maps drop better loot. The shop for Robux: skins and shortcuts to unlock classes. Telemetry without personal data: joining, first level-up, run start and end, extraction or death, second run, a friend joining.

### After the public release

Each item below is grilled into a stage when its turn comes: trading of items and utility skills; seasonal ranks; more classes with the same power budget; more maps.

## Open questions

- How a party chooses cards when the run cannot pause for one player: stage 4.
- How many enemies the server holds at 50 Hz with four clients, and so the horde's cap per party: measured in stage 3, decided in stage 4.
- Library or own code for saving the profile (ProfileStore or a wrapper over DataStores): stage 5.
- When `make test-cloud` arrives (ADR-0001 ties it to the adapter growing; stage 5 adds DataStores and teleports).
- The power numbers of items, utility skills and the account level, and each map's minimum: stage 6.
- How trading guards against scams and duplication: decided with trading.

## Simplification register

Simplifications are allowed only when listed here, with the stage that removes them.

| Simplification | Removed by |
|---|---|
| One map | Stage 6 |
| Every class has the same three utility skills | Stage 5 (the stash) |
| Solo only: no party, no revive, no threat | Stage 4 |
| Enemies from one store pack, players on default R15 rigs | The art stage, with generated creatures (ADR-0010) |
| Until the store pack is republished under the owner's account: enemies drawn by the client as pooled parts with a silhouette per archetype, no animations | ADR-0010's pack, when the user republishes it |
| The engine adapter is verified in Studio (by an agent through the Studio MCP, or by hand), not by automated tests in the gate | When `make test-cloud` lands (open question) |
| No persistence: nothing survives a run | Stage 5 |
| The run place starts runs on its own, without a hub | Stage 5 |

## Parking

Ideas outside the current stage.

- Consoles and gamepad as a supported platform.
- A utility skill that rerolls or skips a card offer.
- Items as in-run modifiers (relics) next to persistent items.
- Seasonal events.
- Flying enemies that ignore obstacles.
- Hand-made maps with a fixed layout, if scattered obstacles disappoint.
- A PvP mode, as a separate mode, if co-op proves itself.
