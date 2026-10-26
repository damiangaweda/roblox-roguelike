# Roblox roguelike

A multiplayer action roguelite in which players explore a world generated for each run, fight the enemies they choose to, gather a different build each time, and decide whom to trust.

## Language

### Run

**Run**:
One session of play, from the moment players enter the world until each of them extracts or dies, about 15 minutes long.
_Avoid_: Match, round, game, podejście (in code)

**Extraction**:
Leaving a run alive by holding the interact button in an extraction zone; only an extracted player keeps what they carried.
_Avoid_: Evacuation, escape, win

**Extraction zone**:
One of the few places in a run's world where a player can extract, open for the whole run.
_Avoid_: Exit, evac point, portal

**Flood**:
The horde overrunning the whole world at the end of a run, which kills everyone still in it.
_Avoid_: Timeout, storm, wipe

### World

**Room**:
One space of a run's world, built from a template, where camps, chests and cover sit.
_Avoid_: Zone, area, tile, cell

**Corridor**:
A passage joining two rooms, where patrols walk.
_Avoid_: Hallway, path, edge

**Room template**:
A hand-made layout a room is built from, with marked places for a camp, a chest and cover.
_Avoid_: Prefab, tile, blueprint

**Start room**:
A room at the edge of the world where players begin a run.
_Avoid_: Spawn, lobby room, base

**Room level**:
A room's difficulty, which grows with its distance from the nearest start room and sets its camp, patrols and loot.
_Avoid_: Tier (reserved for map tiers), depth, difficulty

**Cover**:
A place in a room, such as a bush, where a player is detected only from close by.
_Avoid_: Stealth, hiding spot, shadow

**Chest**:
A container in a room that takes a moment to open and holds a perk choice or a potion.
_Avoid_: Loot box, crate, reward

**Key**:
What a camp leader drops to open a locked door.
_Avoid_: Token, pass

**Altar**:
A place in a room that offers a trade, such as health for a perk.
_Avoid_: Shrine, statue

### Enemies

**Enemy**:
A hostile creature of the run; data on the server, drawn by the client.
_Avoid_: Mob, monster, creature, NPC

**Archetype**:
A kind of enemy with its own role, attack and telegraph: grunt, brute, spitter, exploder, shieldbearer, shaman, camp leader.
_Avoid_: Type, species, class (reserved for players)

**Camp**:
A group of enemies that holds a room and reacts to players entering its detection range.
_Avoid_: Spawn point, nest, encounter

**Camp leader**:
The mini-boss of a camp, which drops a key and a potion.
_Avoid_: Boss, elite, captain

**Patrol**:
A group of enemies walking the corridors, which grows in number and strength as the run goes on.
_Avoid_: Wave, roamers

**Wanderer**:
A lone enemy roaming the world without a camp.
_Avoid_: Stray, roamer

**Detection range**:
How close a player must come for an enemy to notice them; halved for a player in cover.
_Avoid_: Aggro radius, sight

**Leash**:
How far an enemy chases from its camp before it gives up and walks back.
_Avoid_: Tether, aggro range

**Telegraph**:
The visible wind-up before an enemy's attack, which gives the player time to dodge.
_Avoid_: Wind-up, warning, cast

**Horde**:
Enemies as a mass: the patrols of the late run and the flood.
_Avoid_: Mobs, wave (unless a wave is meant)

### Build

**Skill**:
A combat move of one class, either its basic attack or an active skill; skills drop as loot, stay in the stash and are never lost.
_Avoid_: Ability, spell, power

**Basic attack**:
The skill a player fires for as long as its input is held, aimed like every other skill.
_Avoid_: Auto-attack, primary, left click

**Active skill**:
A skill a player fires by hand, on a cooldown; a class has three.
_Avoid_: Ability, special, ultimate

**Dash**:
The short burst of movement every class has, with charges and a cooldown, which passes through enemies and grants no invulnerability.
_Avoid_: Dodge, roll (a class's dash may be called one), blink

**Aim**:
The direction the character faces and skills fire in: the cursor on PC, the right stick on touch and gamepad.
_Avoid_: Target, lock-on

**Perk**:
An upgrade picked at a level-up or from a chest during a run, which modifies a property skills can have and lasts until the run ends.
_Avoid_: Skill, upgrade, talent, modifier

**Tag**:
An element or property a skill carries (fire, ice, lightning, poison, bleed, wind, stun, earth), which synergies key on.
_Avoid_: Element, type, category

**Status**:
A temporary condition a tagged hit puts on an enemy, such as burning, chilled, bleeding or stunned.
_Avoid_: Debuff, effect, condition

**Synergy**:
A bonus that triggers when skills with matching tags meet, either in one player's build or between members of one alliance.
_Avoid_: Combo, interaction

**Shatter**:
The synergy in which fire damage to a chilled enemy is multiplied.
_Avoid_: Combo, crit, freeze-burn

**Build**:
The skills a player brought into a run together with the perks gathered during it.
_Avoid_: Kit

**Potion**:
A carried item that restores health when drunk, which takes a moment and damage interrupts; the only healing in a run.
_Avoid_: Heal, flask, consumable

**Downed**:
The state of a player at zero health, during which an ally can revive them before they die.
_Avoid_: Knocked, dying

**Revive**:
Raising a downed player back into the run by holding the interact button beside them.
_Avoid_: Resurrect, respawn

### Gear

**Item**:
A piece of equipment with a power rating, worn in a slot, which persists outside runs in the stash.
_Avoid_: Gear piece, equipment, relic

**Loadout**:
The class, items and skills a player brings into a run.
_Avoid_: Kit, equipment set

**Stash**:
A player's persistent storage of items and skills between runs.
_Avoid_: Inventory, vault, bank

**Bound item**:
An item a player keeps when they die in a run; binding takes a seal and is limited to a number of slots.
_Avoid_: Insured, soulbound, permanent item

**Bag**:
The container a dead player's unbound items fall into, which anyone can pick up.
_Avoid_: Corpse, loot box, drop

**Seal**:
The rare currency that binds an item, dropped occasionally or bought.
_Avoid_: Binding token, insurance

**Power**:
A number rating how strong an item, a skill or a class is.
_Avoid_: Gear score, item level

**Map tier**:
A difficulty level of map with its own power limit; higher tiers drop better items.
_Avoid_: Difficulty, zone, level

**Power limit**:
The highest total power of class, items and skills a player may bring into a map tier.
_Avoid_: Gear cap, power cap

### Players

**Hub**:
The place where players manage their stash and loadout and form alliances between runs.
_Avoid_: Lobby, town, menu

**Alliance**:
Up to three players who cannot harm each other and share synergies; formed before or during a run, and left only deliberately, with every other player told.
_Avoid_: Party, team, squad, group

**Betrayal**:
Leaving an alliance during a run, which ends shared synergies and makes former allies valid targets.
_Avoid_: Backstab, defect

**Class**:
A character type a player unlocks and picks before a run, with its own stats, basic attack, three active skills and dash: Elementalist, Archer, Warrior.
_Avoid_: Hero, character, role
