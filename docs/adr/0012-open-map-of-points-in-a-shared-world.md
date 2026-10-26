# The world is an open map of points shared by every player in the run

**Status:** proposed; once accepted it supersedes [ADR-0008](0008-generated-room-graph.md) and deprecates [ADR-0011](0011-rooms-on-a-grid-with-straight-corridors.md).

A run's world is one open map generated for that run: terrain with hills and water, hand-made points (a ruin, a crossing, a grove) placed on it at a minimum spacing, paths between them that patrols walk, and cover in between. Every player in the run shares that one map; a camp cleared by anyone is cleared for everyone and comes back after a delay, stronger with run time. Nothing forces a player to fight: a skipped camp is skipped, and the cost is a weaker character and an empty bag, since experience and perks come only from kills, and potions, chests and keys only from kills and from what the points hold. A point's level is its distance along the paths from the nearest entry, so the leaders sit at the points whose nearest entry is farthest. Extraction zones are not fixed: they open one after another during the run at announced points, a minimum distance apart, and the flood that closes the run advances from the edges inward, taking zones with it.

We chose this over the room graph of ADR-0008 because the user's playtest of stage 2a showed that rooms with corridors made camps optional in a way that felt senseless (walk past, lose nothing), and every fix for that (locking a room until its camp is dead) collided with twelve players sharing one world: who locks, who is locked out, what a latecomer finds. An open map shared the way Hunt: Showdown and Dark and Darker share theirs dissolves that: a cleared point is simply cleared, what was worth taking is in someone's bag, and the pressure comes from the clock, the returning camps and the other players.

## Considered options

- **A room graph with corridors** (ADR-0008, stage 2a): implemented and played; camps felt skippable and rooms felt like Hades without its door locks.
- **Tiles with doors that lock until the tile is cleared** (Hades, Gunfire Reborn): grilled at length and rejected; the lock is a per-room state that twelve players in one world cannot share without rules nobody found fun (a per-player entrance, latecomers waiting at a barrier, a tile cleared by someone else).
- **A dungeon copy per party**: pure co-op; it removes alliances formed during a run, betrayal and fighting between players, which the plan is built on.
- **An extraction token dropped by a leader** (Hunt's bounty): rejected; the user wants extraction unconditional and the reasons to fight to be the build and the loot.
- **Fixed, hand-made maps with random contents**: fewer surprises after a few runs; parked as a later option if generated terrain disappoints.
- **A vision radius or line of sight**: rejected for now; everything in camera range is visible, and only cover hides.

## Consequences

The generator of stage 2a (rooms, corridors, cells) is replaced; camps, patrols, detection, leash, aimed combat, perks and potions stay as they are, with "room" read as "point" and "corridor" as "path". Walkability becomes a property of the terrain the generator makes, so the movement budget and the enemies need a walkable-ground query instead of rectangle checks, and the generator's tests must prove every point reachable on foot. The map's size follows the player count, so a solo run is a small map. Camps returning and zones opening on a clock make the run's shape a configuration of minutes, all in one place.
