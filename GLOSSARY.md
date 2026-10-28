# Roblox roguelike

A co-op survivors-like roguelite in which a party fights a growing horde on a round map, builds a different character from level-up cards every run, and decides when to leave with what it found.

## Language

### Run

**Run**:
One session of play on one map, from the moment a party enters until each player extracts or dies: fifteen minutes and the final boss.
_Avoid_: Match, round, game, podejście (in code)

**Party**:
The one to four players who enter a run together, share experience, revive one another and can never harm each other.
_Avoid_: Alliance, team, squad, group

**Extraction**:
Leaving a run alive through the portal, or by killing the final boss; only an extracted player keeps the haul.
_Avoid_: Evacuation, escape, win

**Extraction chest**:
The one chest hidden at a random place on the map that holds the extraction spell.
_Avoid_: Loot chest, crate, airdrop

**Extraction spell**:
What the extraction chest gives: cast whenever its holder chooses, interrupted by a hit, it opens the portal, and it can be cast again once the portal closes.
_Avoid_: Scroll, key, token

**Portal**:
The way out the extraction spell opens, standing for a while for the whole party.
_Avoid_: Extraction zone, exit, gate

**Haul**:
The items and utility skills a player has picked up during the current run, kept only by extracting.
_Avoid_: Bag, loot, inventory

### World

**Map**:
A round, bounded ground in its own setting, with its own roster, bosses, final boss and minimum power, on which a run takes place.
_Avoid_: Zone, arena, level, battleground, world (the game's setting as a whole)

**Obstacle**:
A prop scattered on the map anew for every run, which blocks players and enemies and nothing else.
_Avoid_: Cover, prop, wall

### Enemies

**Enemy**:
A hostile creature of the run; data on the server, drawn by the client.
_Avoid_: Mob, monster, creature, NPC

**Horde**:
The mass of grunts that spawns around the players and grows with run time.
_Avoid_: Wave, mobs, swarm

**Roster**:
The kinds of grunt a map's horde is drawn from, ordered from weakest to strongest.
_Avoid_: Spawn table, enemy list

**Archetype**:
A kind of enemy with its own role, attack and telegraph: grunt, brute, spitter, exploder, shieldbearer, shaman.
_Avoid_: Type, species, class (reserved for players)

**Elite**:
A rare, stronger enemy of one of the archetypes other than the grunt, appearing in the horde more often as the run goes on.
_Avoid_: Champion, miniboss, rare

**Boss**:
A strong enemy that arrives on the run's clock, with telegraphed attacks of its own.
_Avoid_: Camp leader, world boss, miniboss

**Final boss**:
A map's own boss that ends a run: killing it extracts everyone still alive, and if it lives too long the map closes and everyone left dies.
_Avoid_: Last boss, raid boss

**Telegraph**:
The visible wind-up before an enemy's attack, which gives the player time to move away.
_Avoid_: Wind-up, warning, cast

**Threat**:
How strongly an enemy wants one player, raised by that player's damage and sharply by a taunt; an enemy chases the player with the most.
_Avoid_: Aggro, hate, focus

### Build

**Hero**:
The character a player controls in a run.
_Avoid_: Avatar, character, champion

**Class**:
A character type a player picks before a run, with its own pool of skills, starting skill, health and speed: Mage, Warrior, Archer.
_Avoid_: Character, role, specialisation

**Skill**:
A combat move of a class that casts itself on its own cooldown at what its targeting picks, gained and ranked from cards during a run and gone when it ends.
_Avoid_: Ability, spell, power, active skill

**Skill pool**:
The skills a class's cards can offer.
_Avoid_: Deck, spellbook

**Targeting**:
How a skill chooses where it lands: the nearest enemies, the toughest, the densest cluster, a chain, the ground around the hero, and the like.
_Avoid_: Aim, lock-on

**Utility skill**:
A move a player fires by hand on a cooldown, such as a sprint, a barrier or a heal; up to three are worn, any of them by any class, and they persist between runs in the stash.
_Avoid_: Active skill, ultimate, spell

**Passive**:
An upgrade taken from a card that raises one of the hero's stats until the run ends.
_Avoid_: Perk, talent, buff

**Rank**:
How far a skill or a passive has been upgraded in the current run.
_Avoid_: Level (reserved for the hero), tier, star

**Card**:
One of the three choices a level-up offers: a new skill, a skill's next rank, a new passive or a passive's next rank.
_Avoid_: Perk, upgrade, offer

**Offer**:
The three cards a level-up deals, from which the player takes one; a solo run stands still until they do.
_Avoid_: Hand, draw, choice

**Crystal**:
What a killed enemy drops and a player within pickup range draws in, carrying experience.
_Avoid_: Gem, orb, shard, XP

**Level**:
The hero's level within the current run, raised by experience from crystals and shared by the party.
_Avoid_: Rank, class level

**Tag**:
An element or property a skill carries, such as fire, ice, bleed or stun, which synergies key on.
_Avoid_: Element, type, category

**Status**:
A temporary condition a hit puts on an enemy, such as slowed, rooted, stunned, burning or bleeding.
_Avoid_: Debuff, effect, condition

**Synergy**:
A bonus that triggers when skills with matching tags meet on one enemy, from one player's build or from members of one party.
_Avoid_: Combo, interaction

**Shatter**:
The synergy in which fire damage to a chilled enemy is multiplied.
_Avoid_: Combo, crit, freeze-burn

**Build**:
The skills and passives a player gathered during a run, together with the loadout they brought into it.
_Avoid_: Kit

**Taunt**:
A skill that raises an enemy's threat towards its caster sharply.
_Avoid_: Provoke, aggro pull

**Downed**:
The state of a player at zero health in a party, during which another member can revive them before they die.
_Avoid_: Knocked, dying

**Revive**:
Raising a downed player back into the run by holding the interact button beside them.
_Avoid_: Resurrect, respawn

### Progress

**Item**:
A piece of equipment worn in one of six slots that raises the hero's stats; a legendary one also changes a skill.
_Avoid_: Gear piece, equipment, relic

**Loadout**:
The class, items and utility skills a player brings into a run; never lost.
_Avoid_: Kit, equipment set

**Stash**:
A player's persistent storage of items and utility skills between runs.
_Avoid_: Inventory, vault, bank

**Gold**:
The currency a run earns and a player keeps even in death, spent in the hub.
_Avoid_: Coins, money, credits, seals

**Class level**:
A class's persistent level, raised by the experience of runs played with it, which unlocks skills in its pool and utility slots.
_Avoid_: Mastery, level (reserved for the run)

**Account level**:
A player's persistent level across every class, which gives small stats and unlocks classes.
_Avoid_: Player level, prestige

**Power**:
A number rating how strong a player enters a run, from their account level, items and utility skills.
_Avoid_: Gear score, item level

**Minimum power**:
The power every party member must reach to enter a map.
_Avoid_: Power limit, gear check, tier

### Places

**Hub**:
The place where players manage their stash and loadout, spend gold and form a party between runs.
_Avoid_: Lobby, town, menu
