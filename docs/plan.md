# Plan

The single source of truth for scope. Terms are defined in [`GLOSSARY.md`](../GLOSSARY.md), decisions in [`docs/adr/`](adr/).

## The game

A multiplayer action roguelite for PC and phone, for players aged 13 and up. Up to 12 players enter a run of 15 minutes on an open map generated for that run and shared by everyone in it: terrain with hand-made points on it, paths between them and cover in between ([ADR-0012](adr/0012-open-map-of-points-in-a-shared-world.md)). Enemies live in camps at the points and on patrol along the paths; a cleared camp returns after a while, stronger with run time. The player who explores chooses which camps to fight and which to walk past, and pays for walking past with a weaker build and an empty bag: experience and perks come only from kills, and potions, chests and keys only from kills and from what the points hold. Combat is aimed ([ADR-0009](adr/0009-aimed-combat.md)): a basic attack, three active skills and a dash per class, with perks that modify how skills behave. Players may form alliances of up to three, before or during a run; allies share synergies and cannot harm each other, and leaving an alliance is a betrayal everyone is told about. Extraction zones open one after another during the run at announced points, and the flood closes the map from its edges inward at the end; a player who extracts keeps what they carry, a player who dies drops every unbound item into a bag anyone can take ([ADR-0005](adr/0005-gear-at-risk-skills-safe.md)). Skills drop for the player's class and are never lost. Map tiers with a power limit keep new players in the game ([ADR-0006](adr/0006-map-tiers-with-power-limit.md)).

The public release happens when the user judges the game ready; it needs every main mechanic (stages 1–5). The shop comes after the release and sells skins, shortcuts to unlock classes, and seals.

## Stages

### Stage 1: the skeleton

**Status:** done ([PR #2](https://github.com/damiangaweda/roblox-roguelike/pull/2) merged).

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

**Status:** merged ([PR #3](https://github.com/damiangaweda/roblox-roguelike/pull/3), 2026-10-26). Criteria 1–3 met; criterion 4 met in a one-client playtest driven through the MCP except the brute's swing (it died before swinging) and everything only a screen shows (HUD, compass, touch layout); criterion 6 met for the server only (the one client rendered 15 FPS with Studio unfocused, the touch emulator was not run); criteria 5 and 7 open; rigs and animations ([ADR-0010](adr/0010-rigs-from-a-store-pack-first.md)) not built, enemies and players are still parts. Stage 2b picks up the open checks. The user's verdict on 2026-10-26: the world and the skills look weak, and walking past camps felt senseless; that verdict became [ADR-0012](adr/0012-open-map-of-points-in-a-shared-world.md) and stages 2b–2d below. The room graph this stage built is replaced by stage 2b; combat, enemies, perks and potions carry over.

**Goal:** a run that is satisfying to play alone: a world worth exploring, enemies that must be read and dodged, and a class whose kit and perks make every run a different build.

**Scope:**
- **The world** ([ADR-0008](adr/0008-generated-room-graph.md)): at run start the server generates a graph of rooms joined by corridors, the room count following the player count (configuration: rooms per player, with a minimum and a maximum), 2–3 exits per room and the occasional loop. Every room is one of the hand-made greybox templates (about 8 at first: hall, courtyard, cellar, grove, ruin…), which share one look and mark where a camp, a chest and cover can go. Start rooms are leaves of the graph, far apart; a run with fewer players uses fewer of them. Difficulty is a room's distance from the nearest start room: level 1 next to the starts, level 3 deepest; camps, patrols and loot follow the level. A closer top-down camera, so a room fills the screen.
- **Enemies:** the 7 archetypes, each with a telegraph before its attack: grunt (runs and bites), brute (slow, a hammer swing with knockback), spitter (keeps its distance, spits a projectile), exploder (runs, flashes, bursts), shieldbearer (blocks from the front, must be flanked), shaman (heals and buffs its camp), camp leader (a mini-boss of a level 2–3 camp with two attacks, which leaves a chest and a key in stage 2e). Most enemies sit in camps and react when a player enters their detection range, halved for a player in cover; they chase to the end of a leash and walk back. Patrols walk the corridors and grow in number and strength with run time; wanderers roam alone. A camp scales to the players near it (more enemies and health when more players arrive). Enemies are still lightweight ([ADR-0004](adr/0004-lightweight-enemies.md)): data on the server, rigs animated on the client.
- **Time:** extraction zones are open for the whole run, 2–3 per graph (configuration: one per four players, clamped), placed deep in the graph and shown on the HUD from the start; at minute 15 the horde floods the map and everyone left dies.
- **Combat** ([ADR-0009](adr/0009-aimed-combat.md)): the character faces the aim; on PC the cursor, on touch and gamepad the right stick, with a small auto-aim cone there so no platform is worse off. The basic attack fires while its input is held; moving backwards while firing is slower. Three active skills on cooldowns and a dash (a burst of about 10 studs with two charges, which passes through enemies and has no invulnerability). Hits flash, knock back and show damage numbers; skills have a short hit-stop and large ones shake the camera. Telegraphs are a ground marker and a flash. The movement budget of [ADR-0007](adr/0007-movement-budget.md) is raised by the dash and by any skill that moves the player.
- **The first class, the Elementalist:** Arcane Bolt (basic attack, a burst that pierces one enemy); Fireball (an aimed projectile that bursts and burns); Frost Nova (a ring around the player that chills and knocks back); Chain Lightning (jumps between the four nearest enemies); Blink (the dash). Tags fire, ice and lightning, with three synergies inside one build: shatter (fire on a chilled enemy deals double), conduct (lightning on a burning enemy spreads the burn), brittle (lightning on a chilled enemy lowers its defence).
- **Perks** are modifiers independent of any one skill: each changes a property that skills can have (projectiles split in three, areas grow, statuses last longer, cooldowns shorten, health rises). About 20 perks; a level-up offers three. Experience comes straight from kills, and enemies can be skipped.
- **Health:** no regeneration. Potions, up to three carried, drop from camp leaders (and from chests in stage 2e); drinking takes one second and damage interrupts it.
- **Rigs and animations** ([ADR-0010](adr/0010-rigs-from-a-store-pack-first.md)): the 7 archetypes from one rigged store pack, the Elementalist on an Auto Setup R15 rig; idle, run, attack, hit and death played by the client from a state the server sends.
- Downed, revive and extraction as in stage 1 (hold the interact button; a hit or letting go resets).

**Acceptance criteria:**
1. Core tests cover the generator (a graph with every room reachable, start rooms on leaves at the configured minimum distance apart, the room count following the player count, repeatable for a seed), room levels by distance, camp detection with cover, leash and return, patrol growth with time, camp scaling with nearby players, every archetype's telegraph timing and attack, the aim cone, the dash and its charges, the three synergies, perk modifiers applied to the skills that carry the property, potions, and the zones being open from the start.
2. Every number in the scope is configuration; a room template is data, not code.
3. The client sends only intents: aim direction, basic attack held or released, each active skill, dash, drink, interact, choose a perk; the server decides every outcome.
4. In a Studio playtest with one client: the player walks from a start room through a corridor, meets a camp that reacts at its detection range and gives up at its leash, kills a camp leader and picks up its potion, dodges a brute's swing and a spitter's projectile with the dash, levels up, picks a perk that visibly changes a skill, triggers each of the three synergies, drinks a potion, reaches a zone and extracts; a second run generates a different graph.
5. In a Studio test with two clients: one revives the other; a camp grows when the second player arrives.
6. In a Studio test with a server and four clients, in a room with a level 3 camp and a patrol, the server holds at least 50 Hz and each client at least 50 FPS with Studio focused; with the touch emulator the right-stick aim, the attack button and the skill buttons work.
7. The user plays a run and judges whether combat is satisfying; the stage is done only when they say so.

### Stage 2b: the open map

**Status:** proposed; grilled on 2026-10-26, awaiting the user's acceptance of this text and [ADR-0012](adr/0012-open-map-of-points-in-a-shared-world.md).

**Goal:** one open map per run that twelve players can share without rules about who owns a point: terrain, points, paths and cover generated from hand-made pieces, camps that return, and difficulty that grows away from the entries.

**Scope:**
- **The map** ([ADR-0012](adr/0012-open-map-of-points-in-a-shared-world.md)): at run start the server generates a square map whose side grows with the player count (configuration: studs per player, with a minimum and a maximum). The ground is Roblox terrain with gentle hills and water, generated from a seed; water cannot be walked, hills always can. Points are placed on it at a minimum spacing (configuration), each one of the hand-made point templates (the stage 2a templates without their outer walls: hall, courtyard, cellar, grove, ruin, crossing, gallery, pit), which mark where a camp, a chest, a clue and cover go and which props block movement and shots. Paths join every point to the map (a spanning tree plus the occasional extra link), drawn on the ground; cover is scattered between points. Entries are points at the map's edge with no camp (the clearing template), far apart, their count following the player count (configuration: players per entry, with a maximum), placed anew for every run; a group starting at one entry is stage 3's.
- **Difficulty:** a point's level is its distance along the paths from the nearest entry, as a room's was along corridors: level 1 next to the entries, the highest level at the points whose nearest entry is farthest; camps, patrols and loot follow the level, and the camps of the highest level carry the leaders, as the configuration of camps by level says today.
- **Camps return:** a cleared camp comes back after a delay (configuration: minutes) at the strength the configuration gives patrols for that run time; only the camp returns, nothing else the point held.
- **Patrols** walk the paths between points as they walked the corridors, and spawn no closer to a player than a configured distance in studs; wanderers roam the open ground.
- **Visibility:** everything in camera range is drawn; cover hides a player from enemies at half detection range as before.
- **Rules carried over without change:** detection, leash and walk-back, camp scaling with nearby players, aimed combat, the Elementalist, perks, potions, downed and revive. Shots and bursts fly over water; only props stop them.
- **Zones and the flood until stage 2d:** two or three zones at far points, open for the whole run, each guarded by its point's camp (the user's decision on 2026-10-26: a camp guards the zone, and once it is cleared the zone is open to whoever arrives until the camp returns), and the flood at minute 15 as in stage 2a; stage 2d replaces the fixed zones and the flood.
- **Generation on the server** is split over several frames so the server never stalls for more than a frame; the run starts when the map is built.

**Acceptance criteria:**
1. Core tests cover the generator: points at the configured spacing and every point reachable on foot from every entry, entries on the edge at the configured minimum distance apart and without a camp, the map's side following the player count, repeatable for a seed; point levels by path distance, the highest level at the points whose nearest entry is farthest; camps returning after the configured delay at the configured run-time strength; patrols routing along paths; movement stopped by props and water, shots and bursts by props only.
2. Every number in the scope is configuration; a point template is data, not code.
3. The client sends only the stage 2a intents; the server decides every outcome, including where the terrain can be walked.
4. In a Studio playtest with one client: the player walks from an entry over the terrain to a point, meets its camp, clears it, sees it return after the configured minutes, meets a patrol on a path, walks past a camp without being forced to fight, clears a zone's camp and extracts there; a second run generates a different map with different entries.
5. In a Studio test with two clients: one revives the other, and a camp grows when the second player arrives (stage 2a's open criterion 5).
6. In a Studio test with a server and four clients on a map sized for twelve players, the server holds at least 50 Hz, each client at least 50 FPS with Studio focused, and generating the map takes under the configured seconds (proposal: five) without a visible stall; with the touch emulator the right-stick aim, the attack button and the skill buttons work (stage 2a's open half of criterion 6).
7. The user plays a run and judges whether the map is worth exploring; the stage is done only when they say so.

### Stage 2c: effects and readability

**Status:** proposed; grilled on 2026-10-26, awaiting the user's acceptance.

**Goal:** a run that looks like a game made in 2026 rather than a greybox: every skill, telegraph and hit reads at a glance and feels like what it is.

**Scope:**
- **Skill effects** built in code from Roblox particles, beams, trails and lights, no store packs: Arcane Bolt a bright bolt with a trail and an impact flash; Fireball a burning sphere with a smoke trail, an explosion and scorched ground; Frost Nova an expanding ring of ice shards and mist that leaves frost on the ground; Chain Lightning a jagged, forking bolt with a flash at every enemy it jumps to; Blink a streak and a shimmer at both ends.
- **Enemy effects:** every telegraph as a shape on the ground and on the enemy (the brute's hammer arc, the exploder's swelling flash, the spitter's spit, the shaman's heal and buff), hits as a flash, blood or sparks and a damage number, deaths as a dissolve.
- **The world:** lighting with a time of day and shadows, materials and colour for the terrain, the paths, the points and the cover, water that looks like water, the baseplate and the default spawn gone.
- **Feedback:** hit-stop, camera shake, screen flash on being hurt and a clearer low-health state, tuned so they help reading the fight.
- **Budget:** every effect is pooled; the frame budget of stage 2b criterion 6 still holds with twenty enemies on screen.

**Acceptance criteria:**
1. Every effect is driven by the events the server already sends; the client adds no gameplay of its own and the core does not change.
2. In a Studio playtest with one client, each skill, each telegraph and each synergy is recognisable from a screen capture without the HUD.
3. The server and four clients hold stage 2b's frame budget with twenty enemies and every skill firing.
4. The user watches a run and judges whether the effects are up to standard; the stage is done only when they say so.

### Stage 2d: the run arc

**Status:** proposed; grilled on 2026-10-26, awaiting the user's acceptance.

**Goal:** no two runs with the same plan: zones that open as the run goes, a flood that closes the map, clues that lead to the leaders, events that pull players together, and a map screen to read it all.

**Scope:**
- **Zones** ([ADR-0012](adr/0012-open-map-of-points-in-a-shared-world.md)): no zone is open at the start; the first opens at a configured minute, then one every configured interval, each at a random point at least a configured distance from every other zone and never at a point whose camp leader is alive. Every zone is announced to every player and marked on the map screen and the compass; a zone stays open, with no limit on who uses it, until the flood covers it.
- **The flood** from a configured minute advances from the map's edges to its centre over configured minutes; a player inside it loses a configured amount of health every second; a zone inside it closes; when it reaches the centre the run ends and everyone still in it dies.
- **Clues:** every leader camp has a configured number of clues at random points; reading one takes a configured time and a hit interrupts it; each clue read narrows, for every player in the run, the area of the map screen where that leader is, and the last one marks its point.
- **Run events**, each on a configured clock and announced to everyone with a marker: a chest drop (a chest at a random point, guarded by a patrol), a wandering boss (one strong enemy walking the paths, which leaves what a leader leaves), an incursion wave (a configured stretch during which patrols grow by a configured factor).
- **Chests** come forward from stage 2e for the chest drop: a chest takes a configured time to open, a hit interrupts it, and it holds a perk choice or potions.
- **The map screen**, opened with a keyboard key or a HUD button: the map's layout and points known from the start, a point's contents never shown before a visit, own position, allies (once stage 3 has alliances), open zones, clue areas, the flood's edge; other players and enemies never. The HUD's compass points at the nearest open zone.

**Acceptance criteria:**
1. Core tests cover zones opening on the configured clock at the configured distances and never at a living leader's point, the flood's advance, its damage and its closing of zones, the run ending when the flood meets, clues narrowing an area and the last marking the point, each run event on its clock, the chest opening and its interruption, and all of it repeatable for a seed.
2. Every number in the scope is configuration.
3. In a Studio playtest with one client: the player reads a leader's clues and finds it, sees a zone announced and extracts in it, in another run is caught by the flood and loses health, sees a chest drop and an incursion wave announced, and reads all of it on the map screen; the map screen never shows an enemy or another player.
4. The user plays a run and judges whether the run has an arc; the stage is done only when they say so.

### Stage 2e: classes and points

**Status:** outline; grilled for acceptance criteria before it starts.

The Archer (Arrow; Multishot, a fan of five; Trap, which roots and bleeds; Arrow Rain, an aimed area over three seconds; Roll) with tags poison, bleed and wind, and the Warrior (Swing, a 120° cone that hits many and knocks back; Charge, 15 studs with a stun; Shield, a two-second block from the front; Shockwave, a ring that topples; Side-step) with tags stun, bleed and earth; two synergies inside each class, and tags that meet across classes. Points gain content: chests at points (the chest of stage 2d, placed by the generator), keys from camp leaders (what a key opens, now that the map has no doors, is decided when this stage is grilled), altars with a trade (health for a perk, a potion for experience), and as much variety of point templates as the user asks for. Cover hides a player from enemies at half range; shooting from cover reveals the player for three seconds.

### Stage 3: alliances and betrayal

**Status:** outline; grilled for acceptance criteria before it starts.

A run starts after a short countdown with whoever is waiting, and a group that joined together starts at one entry. Players damage each other outside an alliance. Alliances of up to 3 form during a run by invitation and acceptance; allies cannot harm each other and share synergies. Leaving an alliance tells every player, and former allies can hurt each other after a 3 s grace period. From now on only allies revive. A solo player gets a bonus to experience and sees patrols from further away; a group splits experience and loot. Cover hides a player from other players until they are close.

### Stage 4: the hub, saving and items

**Status:** outline; grilled for acceptance criteria before it starts.

The hub and run places of [ADR-0003](adr/0003-hub-and-run-places.md), with alliances formed before a run in the hub and teleport data checked by the run server. A player profile with a format version from day one and numbered migrations. The stash; items with power in 6 slots; items dropping from camp leaders and chests; unbound items falling into a bag on death; seals dropping rarely and binding a limited number of slots.

### Stage 5: skills as loot, map tiers and telemetry

**Status:** outline; grilled for acceptance criteria before it starts.

Skills as loot, dropping for the picker's class, going straight to the stash and worn in skill slots; power for classes, items and skills; two map tiers with a power limit checked on entry. Telemetry without personal data: joining, first level-up, run start and end, extraction or death, betrayal, second run, a friend joining.

### After the public release

Each item below is grilled into a stage when its turn comes: the shop (skins, shortcuts to unlock classes, seals); trading of skills and items; seasonal ranks earned mainly by extractions; later classes with the same power and added comfort (rerolling and excluding perks); more classes, templates and tiers.

## Open questions

- Library or own code for saving the profile (ProfileStore or a wrapper over DataStores): stage 4.
- When `make test-cloud` arrives (ADR-0001 ties it to the adapter growing; stage 4 adds DataStores and teleports).
- The power numbers of items, skills and classes, and the power limits of the two tiers: stage 5.
- Whether the auto-aim cone on touch and gamepad is fair against the cursor in PvP: watch from stage 3, tune the cone.
- How generated terrain keeps every point reachable on foot and how the core answers "can this be walked" cheaply enough for two hundred enemies a step: decided in stage 2b.
- Whether generated terrain can look good enough, or a few hand-made maps with random contents should replace it: judged after stage 2c.
- Whether buying seals is fair enough, since bought safety is an economic edge: decided with the shop.
- How trading guards against scams and duplication: decided with trading.

## Simplification register

Simplifications are allowed only when listed here, with the stage that removes them.

| Simplification | Removed by |
|---|---|
| Greybox environment: point templates from plain shapes | Stage 2c for lighting, materials and effects; the rest after stage 5, before the release |
| Zones fixed at far points and open the whole run, the flood all at once at minute 15 | Stage 2d |
| Enemies from one store pack, players on default R15 rigs | The art stage, with generated creatures (ADR-0010) |
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
- Fully procedural point shapes instead of templates.
- Hand-made maps with random contents, if generated terrain disappoints (ADR-0012).
- Fog of war on the map screen; a minimap in the HUD's corner.
- Zones that are hidden until found, or that close after one use.
- Line of sight: walls and large cover blocking what a player sees.
- Clues private to the reader and their allies.
