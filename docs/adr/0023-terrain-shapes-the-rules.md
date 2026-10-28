# Terrain shapes the rules: cliffs and deep water block, shallows slow

**Status:** proposed on 2026-10-28; once accepted it amends [ADR-0014](0014-round-map-with-a-horde-around-the-party.md)'s flat ground.

The map was flat because the rules live on the XZ plane (ADR-0002, ADR-0014). The user wants terrain the fight can use: hills not every side of which can be climbed, water that slows, and deep water that cannot be crossed. We keep the rules on the plane and give the terrain a description the rules can read: a plateau is a ring of cliff obstacles with ramp gaps, a stream is a chain of deep-channel obstacles with fords, and shallow water is a slow zone; the core generates this description from the seed and the adapter sculpts the Roblox terrain from the same description. We chose this over height in the rules (a bonus for high ground, slopes that cost movement) because circles and zones keep the rules cheap and testable, and the shape of the ground already gives positions, chokepoints and detours without a third dimension.

## Considered options

- **Height in the rules:** every move and hit would need a height; the adapter's physics and the core's rules would disagree on slopes.
- **Terrain as look only:** nothing to use in a fight; the user asked for the opposite.

## Consequences

Enemies need a way to a ramp or a ford when a cliff or the channel stands between them and their target: the core keeps a flow field per alive player over a grid of the map (one flood every few steps), and enemies walk down its gradient, with the local steering kept for bodies; the user chose full pathfinding over hand-placed crossing points. The adapter must read the ground's height everywhere it places something.
