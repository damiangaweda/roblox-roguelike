# Plan

The single source of truth for scope. Terms are defined in [`GLOSSARY.md`](../GLOSSARY.md), decisions in [`docs/adr/`](adr/).

## The game

A multiplayer action roguelite for PC and phone, for players aged 13 and up. Up to 12 players enter a run of 15 minutes in a world generated for that run: a graph of rooms joined by corridors, built from hand-made templates ([ADR-0008](adr/0008-generated-room-graph.md)). Enemies live in camps and on patrol; the player who explores chooses which camps to fight, which to sneak past, and which chests, keys and altars are worth the risk. Combat is aimed ([ADR-0009](adr/0009-aimed-combat.md)): a basic attack, three active skills and a dash per class, with perks that modify how skills behave. Players may form alliances of up to three, before or during a run; allies share synergies and cannot harm each other, and leaving an alliance is a betrayal everyone is told about. Two or three extraction zones are open for the whole run, deep in the graph; a player who extracts keeps what they carry, a player who dies drops every unbound item into a bag anyone can take ([ADR-0005](adr/0005-gear-at-risk-skills-safe.md)). Skills drop for the player's class and are never lost. Map tiers with a power limit keep new players in the game ([ADR-0006](adr/0006-map-tiers-with-power-limit.md)).

The public release happens when the user judges the game ready; it needs every main mechanic (stages 1–5). The shop comes after the release and sells skins, shortcuts to unlock classes, and seals.

## Stages

### Stage 1: the skeleton

**Status:** in review ([PR #2](https://github.com/damiangaweda/roblox-roguelike/pull/2)).

**Goal:** the technical foundation every later stage builds on, proven on a throwaway combat loop: the toolchain and the offline gate, the pure rules core, validated remotes, lightweight enemies at the target count, and verification through the Studio MCP.

**Scope:**
- The toolchain of [ADR-0001](adr/0001-rojo-toolchain-and-offline-gate.md) and the pure core of [ADR-0002](adr/0002-pure-rules-core.md): `make ci` runs commit check, format check, lint, strict type check, core purity and core tests, offline, and builds the place.
- One run place with a greybox arena and a fixed top-down camera; a run per server, a new one after the summary.
- A throwaway combat loop, replaced by stage 2a: an auto-targeting basic attack, one active skill, two enemy kinds spawning around the players up to 150 alive ([ADR-0004](adr/0004-lightweight-enemies.md)), experience and perk offers, downed, revive and death, extraction zones opening at minute 10, the flood at minute 15, and a summary.
- The wire protocol: every remote parsed in one place, intents rate-limited, private events sent only to their player, player movement held to a walking budget ([ADR-0007](adr/0007-movement-budget.md)).

**Acceptance criteria:**
1. On a clean clone, after `make setup` and `make hooks`, `make ci` passes without network access and runs every check listed in the scope.
2. Core tests cover damage, perk offers (distinct, repeatable for a seed, never past a perk's stacks), the synergy firing only when its tags meet, downed, revive and death timings, the extraction channel and its interruption, the zones and the flood, and the movement budget.
3. Core modules reference no Roblox API and read no time or randomness of their own, and `make purity` fails if one does.
4. Every gameplay number is read from `src/shared/Config.luau`.
5. The client sends only intents (fire the active skill at a point or at the nearest enemy, choose a perk, press or release the interact button); the server checks cooldown, range, position and state and decides damage, experience, perks, revives and extraction.
6. In a Studio playtest driven through the Studio MCP with one client: the player auto-attacks, levels up and picks perks, fires the active skill, sees the synergy, is downed and dies, extracts in a zone, sees the summary and the next run starts.
7. With 150 living enemies the server holds at least 50 Hz, and the client's render-step scripts take under 1 ms per frame.

Checks that stage 1 leaves to stage 2a, where the loop they would test is replaced: a second player reviving the first, four clients at 50 FPS with Studio focused, and the touch controls.

### Stage 2a: world and combat

**Status:** planned; grilled on 2026-10-26.

**Goal:** a run that is satisfying to play alone: a world worth exploring, enemies that must be read and dodged, and a class whose kit and perks make every run a different build.

**Scope:**
- **The world** ([ADR-0008](adr/0008-generated-room-graph.md)): at run start the server generates a graph of rooms joined by corridors, the room count following the player count (configuration: rooms per player, with a minimum and a maximum), 2–3 exits per room and the occasional loop. Every room is one of the hand-made greybox templates (about 8 at first: hall, courtyard, cellar, grove, ruin…), which share one look and mark where a camp, a chest and cover can go. Start rooms are leaves of the graph, far apart; a run with fewer players uses fewer of them. Difficulty is a room's distance from the nearest start room: level 1 next to the starts, level 3 deepest; camps, patrols and loot follow the level. A closer top-down camera, so a room fills the screen.
- **Enemies:** the 7 archetypes, each with a telegraph before its attack: grunt (runs and bites), brute (slow, a hammer swing with knockback), spitter (keeps its distance, spits a projectile), exploder (runs, flashes, bursts), shieldbearer (blocks from the front, must be flanked), shaman (heals and buffs its camp), camp leader (a mini-boss of a level 2–3 camp with two attacks, which leaves a chest and a key). Most enemies sit in camps and react when a player enters their detection range, halved for a player in cover; they chase to the end of a leash and walk back. Patrols walk the corridors and grow in number and strength with run time; wanderers roam alone. A camp scales to the players near it (more enemies and health when more players arrive). Enemies are still lightweight ([ADR-0004](adr/0004-lightweight-enemies.md)): data on the server, rigs animated on the client.
- **Time:** extraction zones are open for the whole run, 2–3 per graph (configuration: one per four players, clamped), placed deep in the graph and shown on the HUD from the start; at minute 15 the horde floods the map and everyone left dies.
- **Combat** ([ADR-0009](adr/0009-aimed-combat.md)): the character faces the aim; on PC the cursor, on touch and gamepad the right stick, with a small auto-aim cone there so no platform is worse off. The basic attack fires while its input is held; moving backwards while firing is slower. Three active skills on cooldowns and a dash (a burst of about 10 studs with two charges, which passes through enemies and has no invulnerability). Hits flash, knock back and show damage numbers; skills have a short hit-stop and large ones shake the camera. Telegraphs are a ground marker and a flash. The movement budget of [ADR-0007](adr/0007-movement-budget.md) is raised by the dash and by any skill that moves the player.
- **The first class, the Elementalist:** Arcane Bolt (basic attack, a burst that pierces one enemy); Fireball (an aimed projectile that bursts and burns); Frost Nova (a ring around the player that chills and knocks back); Chain Lightning (jumps between the four nearest enemies); Blink (the dash). Tags fire, ice and lightning, with three synergies inside one build: shatter (fire on a chilled enemy deals double), conduct (lightning on a burning enemy spreads the burn), brittle (lightning on a chilled enemy lowers its defence).
- **Perks** are modifiers independent of any one skill: each changes a property that skills can have (projectiles split in three, areas grow, statuses last longer, cooldowns shorten, health rises). About 20 perks; a level-up offers three. Experience comes straight from kills, and enemies can be skipped.
- **Health:** no regeneration. Potions, up to three carried, drop from camp leaders (and from chests in stage 2b); drinking takes one second and damage interrupts it.
- **Rigs and animations** for the Elementalist and the 7 archetypes: run, idle, attack, hit, death. Source: open question below.
- Downed, revive and extraction as in stage 1 (hold the interact button; a hit or letting go resets).

**Acceptance criteria:**
1. Core tests cover the generator (a graph with every room reachable, start rooms on leaves at the configured minimum distance apart, the room count following the player count, repeatable for a seed), room levels by distance, camp detection with cover, leash and return, patrol growth with time, camp scaling with nearby players, every archetype's telegraph timing and attack, the aim cone, the dash and its charges, the three synergies, perk modifiers applied to the skills that carry the property, potions, and the zones being open from the start.
2. Every number in the scope is configuration; a room template is data, not code.
3. The client sends only intents: aim direction, basic attack held or released, each active skill, dash, drink, interact, choose a perk; the server decides every outcome.
4. In a Studio playtest with one client: the player walks from a start room through a corridor, meets a camp that reacts at its detection range and gives up at its leash, kills a camp leader and picks up its potion, dodges a brute's swing and a spitter's projectile with the dash, levels up, picks a perk that visibly changes a skill, triggers each of the three synergies, drinks a potion, reaches a zone and extracts; a second run generates a different graph.
5. In a Studio test with two clients: one revives the other; a camp grows when the second player arrives.
6. In a Studio test with a server and four clients, in a room with a level 3 camp and a patrol, the server holds at least 50 Hz and each client at least 50 FPS with Studio focused; with the touch emulator the right-stick aim, the attack button and the skill buttons work.
7. The user plays a run and judges whether combat is satisfying; the stage is done only when they say so.

### Stage 2b: classes and rooms

**Status:** outline; grilled for acceptance criteria before it starts.

The Archer (Arrow; Multishot, a fan of five; Trap, which roots and bleeds; Arrow Rain, an aimed area over three seconds; Roll) with tags poison, bleed and wind, and the Warrior (Swing, a 120° cone that hits many and knocks back; Charge, 15 studs with a stun; Shield, a two-second block from the front; Shockwave, a ring that topples; Side-step) with tags stun, bleed and earth; two synergies inside each class, and tags that meet across classes. Rooms gain content: chests (two seconds to open, interruptible; a perk choice or a potion), keys from camp leaders and locked doors to the best rooms or shortcuts to a zone, altars with a trade (health for a perk, a potion for experience), and as much variety of templates as the user asks for. Cover hides a player from enemies at half range; shooting from cover reveals the player for three seconds.

### Stage 3: alliances and betrayal

**Status:** outline; grilled for acceptance criteria before it starts.

A run starts after a short countdown with whoever is waiting, and a group that joined together starts in one room. Players damage each other outside an alliance. Alliances of up to 3 form during a run by invitation and acceptance; allies cannot harm each other and share synergies. Leaving an alliance tells every player, and former allies can hurt each other after a 3 s grace period. From now on only allies revive. A solo player gets a bonus to experience and sees patrols from further away; a group splits experience and loot. Cover hides a player from other players until they are close.

### Stage 4: the hub, saving and items

**Status:** outline; grilled for acceptance criteria before it starts.

The hub and run places of [ADR-0003](adr/0003-hub-and-run-places.md), with alliances formed before a run in the hub and teleport data checked by the run server. A player profile with a format version from day one and numbered migrations. The stash; items with power in 6 slots; items dropping from camp leaders and chests; unbound items falling into a bag on death; seals dropping rarely and binding a limited number of slots.

### Stage 5: skills as loot, map tiers and telemetry

**Status:** outline; grilled for acceptance criteria before it starts.

Skills as loot, dropping for the picker's class, going straight to the stash and worn in skill slots; power for classes, items and skills; two map tiers with a power limit checked on entry. Telemetry without personal data: joining, first level-up, run start and end, extraction or death, betrayal, second run, a friend joining.

### After the public release

Each item below is grilled into a stage when its turn comes: the shop (skins, shortcuts to unlock classes, seals); trading of skills and items; seasonal ranks earned mainly by extractions; later classes with the same power and added comfort (rerolling and excluding perks); more classes, templates and tiers.

## Open questions

- **Rigs and animations for stage 2a**: Roblox's own AI tools, external AI pipelines, Creator Store packs or Rig Builder; decided from the research in progress, before stage 2a starts.
- Library or own code for saving the profile (ProfileStore or a wrapper over DataStores): stage 4.
- When `make test-cloud` arrives (ADR-0001 ties it to the adapter growing; stage 4 adds DataStores and teleports).
- The power numbers of items, skills and classes, and the power limits of the two tiers: stage 5.
- Whether the auto-aim cone on touch and gamepad is fair against the cursor in PvP: watch from stage 3, tune the cone.
- Whether buying seals is fair enough, since bought safety is an economic edge: decided with the shop.
- How trading guards against scams and duplication: decided with trading.

## Simplification register

Simplifications are allowed only when listed here, with the stage that removes them.

| Simplification | Removed by |
|---|---|
| Greybox environment: room templates from plain shapes | After stage 5, before the release |
| The engine adapter is verified in Studio (by an agent through the Studio MCP, or by hand), not by automated tests in the gate | When `make test-cloud` lands (open question) |
| No persistence: nothing survives a run | Stage 4 |
| The run place starts runs on its own, without a hub | Stage 4 |
| Every player is a friend: no PvP, anyone revives anyone, any player's chill shatters | Stage 3 |
| Stage 1's throwaway loop: enemies spawn around the players, the basic attack auto-targets | Stage 2a |

## Parking

Ideas outside the current stage.

- Consoles and gamepad as a supported platform (the aim scheme already allows for a right stick).
- Items as in-run modifiers (relics) next to persistent items.
- Bosses beyond camp leaders.
- Seasonal events.
- Flying enemies that ignore walls (needs a third dimension in the core).
- Fully procedural room shapes instead of templates.
