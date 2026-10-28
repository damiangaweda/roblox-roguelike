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

**Status:** accepted on 2026-10-27 together with ADR-0013 to ADR-0018; criteria 1–5 met and merged on 2026-10-28 (PR #9); criterion 6 continues in stage 3b. Decided on 2026-10-28 after the first playtest: bosses keep two attacks and the final boss three; the horde's cap is 220 ([ADR-0019](adr/0019-horde-cap-of-220.md)); the roster's ramp stays until more runs are played; a barrier already up keeps whatever is larger, and a shield skill fires only with an enemy in a configured range; bosses are never knocked back or stunned; the chest's position travels in the world view from the start and only the compass hides it.

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
- **Extraction** ([ADR-0015](adr/0015-extraction-by-a-found-spell.md)): one chest at a random place on the map, unmarked until a configured minute (proposal: 5) when the compass starts to point at it; opening it takes a moment that a hit does not interrupt (decided on 2026-10-28 after the horde made it unopenable; only stepping away does), and gives the extraction spell; casting takes a configured time (proposal: 5 s) and a hit interrupts it; the portal stands for a configured time (proposal: 20 s) and the spell can be cast again once it closes.
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

### Stage 3b: the run's feel

**Status:** accepted on 2026-10-28 together with ADR-0019 and ADR-0020; built on `feat/run-feel` (PR #10), criteria 1–3 met, 4–5 verified through the Studio MCP except the touch emulator, criterion 6 waits for the user's run.

**Goal:** the solo run of stage 3, played by the user, is fun and looks intended: a dodge, a reason to cross the map, a forest that looks made, skills with faces and a HUD that stays visible. Everything else of stage 3 stays as it is.

**Scope:**
- **Dash:** every class dashes with one button (space, a touch button, a gamepad button): a configured distance (proposal: 14 studs) in the direction of movement, or the facing when standing, over a configured time (proposal: 0.25 s), through enemies, stopped by obstacles and the wall. The hero is untouchable for the dash: no contact, attack, projectile or area hurts them. Two charges, each back after a configured cooldown (proposal: 3 s). The client sends the intent with the direction; the server moves the hero and the client plays the move at once, as it does a knockback. The sprint utility stays.
- **Buttons:** utility skills on Q, E and R (and the gamepad's face buttons); cards by click or tap, or 1, 2, 3 only while an offer is up; every interaction in the world on one key, F (and one gamepad button): the chest and a shrine are held, the portal and the spell are pressed. Touch keeps its thumbstick, the three utility buttons and gains a dash button and an interact button.
- **Shrines** ([ADR-0020](adr/0020-shrines-reward-crossing-the-map.md)): a configured number (proposal: 8) of shrines scattered with the obstacles, at a minimum distance from the start, the chest and one another, each of one of four kinds drawn at random (proposal: two of each), told apart from afar by a beam of light in its kind's colour and named up close. Activating one takes a configured hold (proposal: 1.5 s) that a hit interrupts. A **boon** gives one stat bonus from a configured pool (proposal: damage, speed, max health, haste, pickup range) until the run ends, once. A **pact** gives a bigger bonus at a cost from a configured pool (proposal: damage up for max health down, haste up for speed down, area up for armour down), once. A **trial** spawns a ring of the window's grunts and one elite around the shrine; when the last of them dies the shrine deals a **great offer**: three cards of the usual draw, each worth two ranks (a new skill arrives at rank 2), with the run paused as at a level-up; once. A **spring** heals the hero fully and resets the utility skills' and the dash's cooldowns, and is back after a configured time (proposal: 3 min).
- **The forest's look:** every map object is a low-poly mesh generated with the Studio MCP and published under the owner's account, its asset ids in configuration (decided on 2026-10-28; parts remain only as a fallback while a mesh fails to load): the shrines, the chest, the portal and the obstacles: three pines and two broad trees, a fallen log, a stump, two boulders, a ruined chapel, a watchtower, a hut, a well, a stone circle and fence pieces. Buildings are bigger obstacles that take several circles in the rules. The map is composed, not scattered (decided on 2026-10-28): a configured number of places (a chapel yard, a woodcutter's camp, a stone glade, a tower knoll, a pond shore, a boulder field), each a kit of props on a clearing, kept apart from the start and one another; groves of trees dense at their core and thin at their edge, pines in the north and oaks in the south with a gradual blend; a path of open ground from the start to every place; sparse leftovers denser near the groves; every prop with a little scale variation and lean. The chest and the shrines keep their random places. The tree line and the wall stay.
- **Skill faces:** every skill, passive and utility skill has an icon (an image asset, its id in configuration) shown on its card, its tile and the pick screen; a card shows the icon large with the name under it. Icons come from a CC BY icon set, rasterised in the class's colours, with the attribution in `CREDITS.md` and the game's description.
- **HUD:** experience across the top of the screen with the level; health and the barrier at the bottom centre above the skill tiles, with the dash charges and the utility keys shown; kills and passives at the right edge; the chat untouched.

**Acceptance criteria:**
1. Core tests cover the dash's distance, time, charges, cooldown, untouchability (contact, attack, projectile and area miss a dashing hero), its stop at an obstacle and the wall; the shrines' scatter (count, kinds, spacing, clear ground), the hold and its interruption, each kind's effect, the trial's ring and its reward, the spring's recharge, all repeatable for a seed.
2. Every number in the scope is configuration; the shrine kinds, the boon and pact pools, the mesh set and the icon ids are data.
3. The client sends only intents: dash with a direction, interact held or pressed; the server decides every move, hit and reward.
4. In a Studio playtest driven through the Studio MCP: the dash crosses a group of enemies without damage, each shrine kind is activated and its effect shows, the trial's ring is fought and its great offer taken, the forest shows every prop of the set, every card and tile shows its icon, the HUD stays readable with the chat open, and the touch emulator's buttons dash and interact.
5. With the horde at its cap the server holds at least 50 Hz and the client at least 50 FPS with Studio focused, on mains power.
6. The user plays a run and judges whether it is fun and looks intended; the stage is done only when they say so.

### Stage 3c: lairs

**Status:** accepted on 2026-10-28 together with ADR-0021 after the playtests of stages 3 and 3b; in progress on `feat/lairs`.

**Goal:** the run has a goal on the map: five lairs, each with a boss tied to it, that feed the horde until their boss dies; the final boss comes only when every lair is silent, and the clock punishes those who dawdle.

**Scope:**
- **Lairs** ([ADR-0021](adr/0021-lairs-feed-the-horde-and-hold-the-bosses.md)): the map's bosses live in lairs, one lair kind per boss (proposal: Thornback's bramble nest, Mossmaw's bog, the Hollow Shade's barrow, the Bramble Matron's hollow, the Ironbark Warden's elder grove, the Ashen Stag's burnt glade), of which a configured number (proposal: 5 of 6) is drawn for a run and placed as places of the map's composition, apart from the start, the chest and one another. A lair is a kit of meshes with a landmark seen from afar (proposal: a column of light or smoke in the lair's colour) that goes out when the lair is silenced. "Camp" is a metaphor: variety is the point, every lair is its own kind of den.
- **Emission:** every living lair releases a batch of grunts of its own kinds (a configured subset of the roster, 2–3 kinds per lair) at its own interval (configuration per lair kind, proposal: 8–14 s) from its own random offset, so the lairs never release together and the player gets time to rest between arrivals; the batch grows with run time (proposal: 3 to 14) and the grunts' health and damage grow as now. Grunts walk straight at the nearest player through the whole map, so the pressure is highest near living lairs and lowest far from them: the breather comes from distance, not from a timer. The alive cap of [ADR-0019](adr/0019-horde-cap-of-220.md) stays; a grunt farther than a configured distance from every player despawns and its count returns to its lair's next batch. The spawn ring around the players, the kind window, the boss clock and the closing rings of stage 3 go; the trial shrine keeps its ring.
- **The boss and its guard:** a lair's boss and guard sleep in sight in the lair until a player enters the lair's radius (proposal: 45 studs) or anything damages the boss (a skill fired from outside wakes it too), then wake together (proposal: 2–3 elites of the lair's kinds); the boss and the guard are tied to the lair: they fight inside its radius and never leave it. The boss grows with run time (proposal: +10% health and damage per minute), so an early kill is cheaper. The boss and the guard chase only heroes within a configured reach (proposal: twice the radius); with no hero in reach they walk back to the lair's centre. The lair sleeps again once no hero has been in reach and nothing has hit it for a configured grace (proposal: 4 s); the boss regains a share of its missing health (proposal: half). A lair's grunts unlock weakest first with run time, so the early batches are its weakest kind.
- **Silencing a lair:** the boss's death stops the lair's emission for good, deals a great offer to its killer (the party in stage 4), drops food, removes the surviving guard and leaves the lair safe ground; the landmark goes out. A chance of an item drop joins here when items exist (stage 5).
- **The final boss:** comes the moment the last lair falls, at that lair, with a spectacle (proposal: the sky darkens, the ground splits in a ring of light, a roar, the boss rises over a few seconds during which nothing spawns); it keeps its attacks and second phase; killing it extracts everyone alive.
- **Doom:** from the run's end time (15:00) wraiths spawn around every player every few seconds: fast, with enormous health and damage, immune to control and knockback (damage over time still lands), worth no experience; doom replaces the map's closing of ADR-0015. The final boss no longer comes. Only the portal (the extraction spell) is a way out; a player without it dies within about a minute.
- **HUD:** the lairs silenced over the total ("Lairs 2/5") beside the clock; from a configured minute before the end (proposal: 14:00) a red countdown to doom; a "Doom" banner from the end time.
- **Unchanged:** the chest, the spell, the portal, the compass, the shrines, cards, classes, skills and the dash.

**Acceptance criteria:**
1. Core tests cover the lair draw (count, distinct kinds, placement rules, seed repeatability), the emission (interval, batch growth, kinds per lair, the cap, despawn and return of strays, silence after the boss dies), the sleeping boss (wake on entry, leash of boss and guard, growth with time, sleep and recovery on leaving), silencing (the great offer, the food, the landmark state in the view), the final boss on the last lair's fall with its spawn delay, doom (wraith spawns, no experience, the portal still working, no final boss after the end time), all repeatable for a seed.
2. Every number is configuration; lairs, their kinds, guards and wraiths are data.
3. The client sends only the intents of stages 3 and 3b.
4. In a Studio playtest through the Studio MCP: each lair kind is seen with its landmark, a lair is silenced and its landmark goes out, the final boss rises at the last lair with its spectacle, doom kills a hero without the spell and a hero with it extracts; the server holds 50 Hz at the cap with grunts walking across the map.
5. The user plays a run and judges whether it is fun and looks intended; the stage is done only when they say so.

### Stage 3d: enemy meshes and terrain

**Status:** grilled and accepted on 2026-10-28 for the terrain (ADR-0023); the enemy meshes went through the Meshy trial and the user chose rigged Meshy models for every kind ([ADR-0024](adr/0024-enemies-are-rigged-meshy-models-with-clips.md), accepted on 2026-10-28), built on `feat/terrain` over the procedural motion of `feat/enemy-meshes`: all 25 kinds draw as skinned rigs with walk, run and attack clips, seen in Studio (grunts running, sleeping bosses holding a pose, the boss's and elites' attack clip on the telegraph, server 60 Hz); the terrain is PR #13 (stacked on #12 and #11): criteria 1–2 met, the Studio playtest done for the stream, a plateau and a cliff, the user's run pending.

**Goal:** enemies that look made, and a map whose shape matters in the fight.

**Scope:**
- **Enemy rigs** ([ADR-0024](adr/0024-enemies-are-rigged-meshy-models-with-clips.md), accepted, superseding ADR-0022): every enemy kind is a stylized Meshy model with a skeleton and three clips (walk, run, attack), imported into Studio and checked in as `.rbxm` templates under `src/shared/Assets/Enemies`, its mesh ids and scale in configuration; the client clones the template, scales it with `ScaleTo`, plays walk or run by the enemy's pace, the attack on the telegraph (bosses, elites) or on a bite (grunts), and holds the first walk frame when still or asleep. What has no clip stays procedural as ADR-0022 described: the hit pop, the telegraph swell, the charge tilt, the wraith's hover, the sleep pose, the death's fall and fade. The old text follows for the record: every enemy kind (twelve grunts, five elites, six bosses, the final boss, the wraith) was a low-poly mesh generated with the Studio MCP and published under the owner's account, its asset ids in configuration, drawn by the client in place of the part silhouettes at the kind's scale; no skeleton or animation: motion is a bob and a lean toward the walk, an attack is a lunge, a telegraph a rising glow, a death a fall and a fade. Statuses and the boss aura keep their rings and lights at the feet; a tint for burning, chilled and the like is a translucent shell around the mesh rather than a colour on it (a textured mesh ignores its colour). Parts remain only as a fallback while a mesh fails to load.
- **Pathfinding** (decided on 2026-10-28): enemies find their way around cliffs and the channel with a flow field: the core keeps a grid over the map (cell size in configuration) marking cells blocked by obstacles, cliffs and the channel, and for each alive player floods it from the player's cell every configured number of steps; an enemy walks down the gradient of its target's field, with the local steering kept for bodies and small gaps. Deterministic, one flood per player, no per-enemy search.
- **Terrain** ([ADR-0023](adr/0023-terrain-shapes-the-rules.md); grilled on 2026-10-28): the core's generator lays out the terrain from the seed and the adapter sculpts it, so the rules and the look come from one description. Four to six **plateaus** (radius 25–45, 6–8 studs high, flat tops) ringed by cliffs that are obstacles in the rules, with one or two ramps as gaps (the first facing the start, the others well apart; every gap wide enough for the widest enemy), so a plateau is a position reached only by its ramps, for enemies too. One **stream** winding edge to edge, avoiding the start, the chest, the places and the lairs: a deep channel that is an obstacle, shallow banks on both sides that are a slow zone (proposal: 35% slower, heroes and enemies alike), and three **fords** where the whole width is shallow. **Ponds** deep in the middle, shallow at the rim. One or two lairs a run stand on a plateau (entered by its ramps), the others and every place on the plain; the stream never cuts a place's or a lair's clearing. The rest of the ground gently rolling (up to 3 studs) with no rule. Everything flattened under the start, the chest, the places, the lairs and the paths; the adapter reads the ground's height for every enemy, crystal, prop and effect; the camera rides a little higher over rises.

**Acceptance criteria (proposed):**
1. Core tests cover the terrain's layout (plateaus with cliffs and ramps, the stream with its channel, banks and fords, the ponds; seed repeatability), cliffs and the channel blocking heroes and enemies, ramps and fords passable, the slow zones slowing both, enemies routing to a ramp or a ford when a cliff or the channel lies between them and their target.
2. Every number is configuration; the meshes and the terrain's shape parameters are data.
3. In a Studio playtest: every enemy kind drawn as its mesh at a readable size, statuses and telegraphs still readable, the horde at its cap holding 50 Hz on the server and 50 FPS on the client; hills and the stream seen, a ford crossed, the stream blocking elsewhere, enemies and crystals on the ground everywhere.
4. The user plays a run and judges whether it is fun and looks intended.

### Stage 4: co-op

**Status:** outline with the lead's proposed answers (2026-10-28); grilled for acceptance criteria before it starts.

**Goal:** up to four players share one run on the lairs map and the game stays fair, readable and fast for all of them.

**Scope (proposed):**
- **The party** ([ADR-0016](adr/0016-co-op-party-of-up-to-four.md)): until the hub exists, everyone in the run place when a run starts is the party (up to four; later joiners wait for the next run); the pick screen shows who is in and the run starts when everyone picked or after a configured countdown.
- **Experience and cards:** a crystal anyone picks up gives experience to everyone; each player gets their own offer at each level-up, but the run never pauses: an offer stays open while the player keeps playing, with a configured time (proposal: 20 s) after which the first card is taken for them; the HUD shows the offer small until opened. The great offer of a lair goes to the whole party.
- **Downed and revive:** at zero health a party member is downed (proposal: 25 s to bleed out, crawling slowly, not targeted); another member holds F beside them (proposal: 3 s, interrupted by a hit) to revive at a share of health (proposal: 40%); a downed member who bleeds out is dead and spectates. Alone (the last one standing) the hero dies as in solo.
- **Threat:** an enemy chases the player with the most threat towards it; damage dealt raises threat (proposal: by the damage), a taunt raises it sharply (proposal: +500 and a 6 s hold); threat decays (proposal: 10%/s); without threat the nearest player. The Warrior's war roar taunts. Lair bosses and guards use threat within their reach.
- **The horde in a party:** every lair's batch scales with the party (proposal: ×1 solo, ×1.6 duo, ×2.1 trio, ×2.5 quad) and the alive cap is one shared budget measured with four clients (open question of ADR-0019); strays despawn far from every member; wraiths spawn around every member.
- **Synergies across members:** a status one member put on an enemy counts for another member's synergy.
- **Extraction and doom:** the portal admits every member while it stands; killing the final boss extracts everyone alive; a downed member at extraction counts as extracted if revived in time.
- **Performance:** the server holds 50 Hz with four clients at the cap; the client holds 50 FPS with four heroes on screen.

**Acceptance criteria (proposed):**
1. Core tests cover the party roster, shared experience with per-player offers and the offer timeout, downed/revive/bleed-out, threat (raise, taunt, decay, target choice), batch scaling by party size, cross-member synergies, the portal for several members, the final boss extracting all, doom with several members, all repeatable for a seed.
2. Every number is configuration.
3. The client sends only the intents of stages 3–3d plus revive (the F hold beside a downed member).
4. A Studio playtest with two clients (the Studio test server): both pick, share experience, choose cards without a pause, one is downed and revived, a taunt pulls a boss, both extract; with four clients the server holds 50 Hz at the cap.
5. The user plays with at least one other person and judges whether it is fun and fair.

### Stage 5: the hub, the profile and loot

**Status:** outline; grilled for acceptance criteria before it starts.

The hub and run places of [ADR-0016](adr/0016-co-op-party-of-up-to-four.md), with the party formed in the hub and teleport data checked by the run server. A player profile with a format version from day one and numbered migrations: the stash, gold, the account level and each class level. Loot is personal: any enemy may drop an item, a utility skill or gold, and a tougher enemy drops more often and better. Items in six slots raise the hero's stats, and legendary items also change a skill. Utility skills drop from the same loot table, rarer, and can be equipped to any class. Death loses the haul and keeps the gold and experience ([ADR-0017](adr/0017-only-the-haul-is-at-risk.md)). A class level unlocks more skills in the class's pool and the second and third utility slot; the account level gives small stats and unlocks classes. Gold buys basic cosmetics, upgrades to items and utility skills, and items in the hub. One class is free; the others come with the account level or the shop.

### Stage 6: maps and the shop

**Status:** outline; grilled for acceptance criteria before it starts.

More maps, ordered from easiest to hardest, each with its own setting, roster, bosses and final boss and a minimum power every party member must reach ([ADR-0018](adr/0018-maps-ask-for-a-minimum-power.md)); harder maps drop better loot. The shop for Robux: skins and shortcuts to unlock classes. Telemetry without personal data: joining, first level-up, run start and end, extraction or death, second run, a friend joining.

### After the public release

Each item below is grilled into a stage when its turn comes: trading of items and utility skills; seasonal ranks; more classes with the same power budget; more maps.

## Open questions

- Stage 3d's enemy animation: the user wants a trial of Meshy rigging (humanoids and quadrupeds, a Roblox bridge; Tripo rigs humanoids only) on one quadruped and one humanoid before accepting ADR-0022's procedural motion; the trial was run on 2026-10-28 (cutthroat and grey wolf rigged with walk and run, the cutthroat with attack and death; 76 credits): rigs and clips work in Studio, but the models read more realistic than the Roblox-generated props; a stylized Thornback (chunky, flat colours; 30 credits) matched the forest's style. The user chose Meshy for every kind (meshy-6-lite, stylized prompts, rigs with walk, run and attack). Done on 2026-10-28: all 25 kinds generated and textured, all 25 rigged with walk, run and attack clips after the user asked for animation on every kind (the forest spider became a boar-shaped 'web lurker' with green eyes and web markings, the Bramble Matron a bear-like vine beast with a spider face, the dire wolf lost its mane: Meshy's auto-rig takes only bipeds and quadrupeds, and anything with spider legs or a mane fails pose estimation), about 740 credits spent, the FBX files in `build/meshy/<kind>/` (gitignored, with `ledger.json` of task ids). [ADR-0024](adr/0024-enemies-are-rigged-meshy-models-with-clips.md) (accepted on 2026-10-28) supersedes ADR-0022 with rigged models and clips, imported by hand from one flat folder and rebuilt into `.rbxm` by a Lune script; wired into `Config.enemyMeshes` and EnemyView on PR #13.
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
- A utility skill that draws crystals in from farther away (the user's idea once the pickup range shrank to 4 studs on 2026-10-28).
- A PvP mode, as a separate mode, if co-op proves itself.
