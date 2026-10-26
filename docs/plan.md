# Plan

The single source of truth for scope. Terms are defined in [`GLOSSARY.md`](../GLOSSARY.md), decisions in [`docs/adr/`](adr/).

## The game

A multiplayer roguelite for PC and phone, for players aged 13 and up. Up to 12 players enter a run of 12–15 minutes on a top-down map, fight the horde with an automatic basic attack and skills fired by hand, and pick a perk at every level-up. Players may form alliances of up to three, before or during a run; allies share synergies and cannot harm each other, and leaving an alliance is a betrayal everyone is told about. A player who extracts keeps what they carry; a player who dies drops every unbound item into a bag anyone can take ([ADR-0005](adr/0005-gear-at-risk-skills-safe.md)). Skills drop for the player's class and are never lost. Map tiers with a power limit keep new players in the game ([ADR-0006](adr/0006-map-tiers-with-power-limit.md)).

The public release happens when the user judges the game ready; it needs every main mechanic (stages 1–4). The shop comes after the release and sells skins, shortcuts to unlock classes, and seals.

## Stages

### Stage 1: the core loop

**Status:** planned.

**Goal:** prove that fighting the horde is fun and that 150 enemies run on a server and a phone, before anything persistent exists.

**Scope:**
- The toolchain of [ADR-0001](adr/0001-rojo-toolchain-and-offline-gate.md) and the pure core of [ADR-0002](adr/0002-pure-rules-core.md): `make ci` runs commit check, format check, lint, strict type check and core tests, offline. A spike decides whether Jest Roblox runs under Lune or a small runner of our own is written; the choice goes in the commit body.
- One run place, a greybox arena, a fixed top-down camera.
- One ranged class: a basic attack that fires automatically at the nearest enemy in range, and one active area skill on a cooldown, aimed with the mouse on PC and at the nearest enemy on touch.
- The horde as lightweight enemies ([ADR-0004](adr/0004-lightweight-enemies.md)), two enemy types, spawning faster as the run goes on, up to 150 alive.
- Experience from kills; each level-up offers 3 random perks out of about 6, carrying two tags (fire, ice), with one synergy between them.
- Downed for 15 s; any player can revive by holding the interact button next to the downed player for 3 s; a hit on the reviver or letting go starts it over.
- From minute 10, 2 extraction zones open at random among fixed points; extracting takes holding the interact button for 5 s in a zone, and damage or letting go interrupts it. At minute 15 the horde floods the map and everyone left dies.
- A short summary at the end of a run (extracted or died, time, level), then a new run on the same server.

**Acceptance criteria:**
1. On a clean clone, after installing the pinned tools and packages and `make hooks`, `make ci` passes without network access and runs every check listed in the scope.
2. Core tests cover damage; perk offers (three distinct perks, repeatable for a given seed); the synergy firing only when its tags meet; downed, revive and death timings; the extraction channel and its interruption; zones opening at minute 10 and the flood at minute 15.
3. Core modules reference no Roblox API, and a check in `make ci` fails if one does.
4. Every number named in the scope (timers, counts, spawn rates, damage, cooldowns) is read from one configuration module.
5. The client sends only intents (fire the active skill at a point or at the nearest enemy, choose a perk, press or release the interact button); the server checks cooldown, range, position and state and decides damage, experience, perks, revives and extraction. Player movement is held to what walking can reach ([ADR-0007](adr/0007-movement-budget.md)).
6. In a Studio test with 2 players, each can: move, auto-attack, fire the skill (mouse on PC; auto-target in the device emulator on a phone), level up and pick a perk, see the synergy deal its bonus, be downed and revived, die, extract, see the summary and start the next run.
7. In a Studio test with a server and 4 clients on the user's Mac, with 150 living enemies, the server holds at least 50 Hz and each client at least 50 FPS; the phone device emulator is checked by hand.

### Stage 2: alliances and betrayal

**Status:** outline; grilled for acceptance criteria before it starts.

Up to 12 players per run, and a run starts after a short countdown with whoever is waiting, with the horde scaled to the player count. Players damage each other outside an alliance. Alliances of up to 3 form during a run by invitation and acceptance; allies cannot harm each other and share synergies. Leaving an alliance tells every player, and former allies can hurt each other after a 3 s grace period. From now on only allies revive.

### Stage 3: the hub, saving and items

**Status:** outline; grilled for acceptance criteria before it starts.

The hub and run places of [ADR-0003](adr/0003-hub-and-run-places.md), with alliances formed before a run in the hub and teleport data checked by the run server. A player profile with a format version from day one and numbered migrations. The stash; items with power in 6 slots; items dropping from the horde; unbound items falling into a bag on death; seals dropping rarely and binding a limited number of slots.

### Stage 4: classes, skills, map tiers and telemetry

**Status:** outline; grilled for acceptance criteria before it starts.

A second class; skills as loot, dropping for the picker's class, going straight to the stash and worn in skill slots; power for classes, items and skills; one map in 2 tiers with a power limit checked on entry. Release content: 2 classes with about 6 skills each, about 20 perks, 3 tags, 3 enemy types and 1 elite. Telemetry without personal data: joining, first level-up, run start and end, extraction or death, betrayal, second run, a friend joining.

### After the public release

Each item below is grilled into a stage when its turn comes: the shop (skins, shortcuts to unlock classes, seals); trading of skills and items; seasonal ranks earned mainly by extractions; later classes with the same power and added comfort (rerolling and excluding perks); more classes and maps.

## Open questions

- Library or own code for saving the profile (ProfileStore or a wrapper over DataStores): stage 3.
- When `make test-cloud` arrives (ADR-0001 ties it to the adapter growing; stage 3 adds DataStores and teleports).
- The power numbers of items, skills and classes, and the power limits of the two tiers: stage 4.
- Mouse aim on PC against auto-aim on phones in PvP: watch fairness from stage 2, change if phones lose.
- Whether buying seals is fair enough, since bought safety is an economic edge: decided with the shop.
- How trading guards against scams and duplication: decided with trading.

## Simplification register

Simplifications are allowed only when listed here, with the stage that removes them.

| Simplification | Removed by |
|---|---|
| Greybox art: plain shapes, no models or animations of our own | After stage 4, before the release |
| The engine adapter is verified in Studio (by an agent through the Studio MCP, or by hand), not by automated tests in the gate | When `make test-cloud` lands (open question) |
| No persistence: nothing survives a run | Stage 3 |
| The run place starts runs on its own, without a hub | Stage 3 |
| Every player is a friend: no PvP, anyone revives anyone | Stage 2 |

## Parking

Ideas outside the current stage.

- Consoles and gamepad.
- Items as in-run modifiers (relics) next to persistent items.
- Bosses.
- Seasonal events.
