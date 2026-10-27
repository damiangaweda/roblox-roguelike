# A map is a round, bounded ground where the horde spawns around the players

**Status:** proposed; once accepted it supersedes [ADR-0012](0012-open-map-of-points-in-a-shared-world.md) and [ADR-0008](0008-generated-room-graph.md), and deprecates [ADR-0011](0011-rooms-on-a-grid-with-straight-corridors.md).

A run takes place on one map: a flat, round piece of ground in that map's own setting (a forest, a desert, a glacier), closed by an invisible wall, with obstacles scattered on it by rules anew for every run. Enemies do not live anywhere on it: the horde spawns on a ring just outside the camera around the players and walks at them, the number alive rising with run time, the kinds sliding up the map's roster, elites appearing more often and a boss arriving on a clock. A map differs from another by its setting, its roster, its bosses and the power it asks for, not by its rules. We chose this over the open map of ADR-0012 because the generated terrain, points, paths and camps were the part that looked weakest and cost the most, and a survivors-like needs none of them: the pressure comes from the horde and the clock, not from choosing camps.

## Considered options

- **The open map of points** (ADR-0012, stage 2b): built and played; judged too weak to look at and too costly to make good.
- **An empty arena without obstacles**, exactly as in Azeroth Survivors: simplest, but kiting has no shape.
- **Hand-made arenas, one fixed layout per map**: more polish per map, the same layout every run.

## Consequences

The generator shrinks to scattering obstacles at a minimum spacing with clear ground around the start and the extraction chest. Obstacles block the movement of players and enemies and nothing else, so no skill is ever wasted on a prop and the rules need only circle checks. Spawning is relative to the players, so the core needs no camps, patrols, leashes or detection, and enemies that stray too far are moved back into the ring. The horde's size is bounded by [ADR-0004](0004-lightweight-enemies.md)'s budget, shared by the whole party.
