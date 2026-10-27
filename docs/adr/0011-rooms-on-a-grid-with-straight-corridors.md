# Rooms sit on a grid and corridors run straight between them

**Status:** proposed; deprecated by [ADR-0012](0012-open-map-of-points-in-a-shared-world.md) once that one is accepted. The grid and corridors it describes shipped in stage 2a and are replaced by the open map.

The generator of [ADR-0008](0008-generated-room-graph.md) places one room per cell of a square grid (the pitch is configuration) and joins adjacent cells with straight, axis-aligned corridors, so the centres of two joined rooms and their corridor lie on one line. We chose this over free placement because it makes every geometric question the rules ask cheap and exact: a room is a convex rectangle, a corridor a straight band, a point is in at most one of them, the nearest walkable point and the first wall on a path are a few rectangle checks, and the way from one room to the next is "walk to the corridor mouth, then straight through". Enemies, projectiles and the movement budget all rely on these answers every step for up to two hundred enemies.

## Consequences

A template's half extents must leave room for a corridor inside the cell, and a room has at most four neighbours, one per side, so the configured exit limit is at most four. Two rooms in neighbouring cells with no corridor between them can stand a wall apart; the rules treat that wall like any other (detection needs the same room or corridor, shots and bursts stop at walls). Fully procedural room shapes stay parked.
