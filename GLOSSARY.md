# Roblox roguelike

A multiplayer action roguelite in which players explore a world generated for each run, fight the enemies they choose to, gather a different build each time, and decide whom to trust.

## Language

### Run

**Run**:
One session of play, from the moment players enter the map until each of them extracts or dies, about 15 minutes long.
_Avoid_: Match, round, game, podejście (in code)

**Extraction**:
Leaving a run alive by holding the interact button in an extraction zone; only an extracted player keeps what they carried.
_Avoid_: Evacuation, escape, win

**Extraction zone**:
A place where a player can extract; zones open one after another during a run at announced points and close when the flood reaches them.
_Avoid_: Exit, evac point, portal

**Flood**:
The horde overrunning the map from its edges inward at the end of a run, which hurts everyone it reaches, closes the zones it covers and kills everyone still in the run when it meets in the middle.
_Avoid_: Timeout, storm, wipe, ring, circle

**Run event**:
Something announced to every player at a moment of the run that draws them to one place: a chest drop, a wandering boss, an incursion wave.
_Avoid_: Random event, mission, quest

**Chest drop**:
A run event that places a guarded chest at an announced point.
_Avoid_: Airdrop, supply drop, care package

**Wandering boss**:
A run event: one strong enemy announced to everyone, walking the paths between points, which leaves what a camp leader leaves.
_Avoid_: World boss, raid boss, miniboss

**Incursion wave**:
A run event: an announced stretch of the run during which patrols grow.
_Avoid_: Horde wave, surge

### World

**Map**:
The open world of one run: generated terrain with points, paths and cover on it, shared by every player in the run.
_Avoid_: Level, dungeon, arena, world (the game's setting as a whole)

**Point**:
A hand-made place on the map, built from a template, where a camp, a chest, a clue or cover sits.
_Avoid_: Room, point of interest, POI, location, tile

**Path**:
A visible track between two points, which patrols walk.
_Avoid_: Corridor, road, edge

**Point template**:
A hand-made layout a point is built from, with marked places for a camp, a chest, a clue and cover.
_Avoid_: Prefab, tile, blueprint, room template

**Entry**:
A point at the edge of the map, without a camp, where players begin a run; placed anew for every run.
_Avoid_: Spawn, start room, lobby, base

**Point level**:
A point's difficulty, which grows with its distance along the paths from the nearest entry and sets its camp, patrols and loot.
_Avoid_: Tier (reserved for map tiers), depth, difficulty, room level

**Clue**:
A thing at a point that, once read, narrows for every player where a camp leader is; a leader's last clue marks its point.
_Avoid_: Hint, marker, objective

**Map screen**:
The screen on which a player reads the map during a run: its layout and what the run has announced, never what a point holds before a visit, nor other players or enemies.
_Avoid_: Minimap, overview, radar

**Cover**:
A place on the map, such as a bush, where a player is detected only from close by.
_Avoid_: Stealth, hiding spot, shadow

**Chest**:
A container at a point or from a chest drop that takes a moment to open and holds a perk choice or potions.
_Avoid_: Loot box, crate, reward

**Key**:
What a camp leader drops; what it opens is decided with stage 2e.
_Avoid_: Token, pass

**Altar**:
A place at a point that offers a trade, such as health for a perk.
_Avoid_: Shrine, statue

### Enemies

**Enemy**:
A hostile creature of the run; data on the server, drawn by the client.
_Avoid_: Mob, monster, creature, NPC

**Archetype**:
A kind of enemy with its own role, attack and telegraph: grunt, brute, spitter, exploder, shieldbearer, shaman, camp leader.
_Avoid_: Type, species, class (reserved for players)

**Camp**:
A group of enemies that holds a point and reacts to players entering its detection range; once cleared, it returns after a delay, stronger with run time.
_Avoid_: Spawn point, nest, encounter

**Camp return**:
A cleared camp coming back to its point after a delay, as strong as the run time makes it.
_Avoid_: Respawn, repopulation, reset

**Camp leader**:
The mini-boss of a camp, which drops a key and a potion.
_Avoid_: Boss, elite, captain

**Patrol**:
A group of enemies walking the paths, which grows in number and strength as the run goes on.
_Avoid_: Wave, roamers

**Wanderer**:
A lone enemy roaming the map without a camp.
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
