# The world is a graph of rooms generated for each run

**Status:** accepted; superseded by [ADR-0014](0014-round-map-with-a-horde-around-the-party.md) once that one is accepted (ADR-0012, which was to supersede it, is itself superseded).

Every run gets its own world: a graph of rooms joined by corridors, generated on the server from a seed, where each room is one of a set of hand-made templates and the room count follows the player count. Enemies live in camps inside rooms and on patrol in corridors, and a room's difficulty is its distance from the nearest start room. We chose this over a horde that spawns around the players because the user found that loop senseless: nothing asked the player to move, read the map or choose a fight. We chose templates over fully procedural rooms so that every room is a space combat was designed for.

## Considered options

- **A horde spawning around the players** (stage 1): no exploration, every run the same.
- **One fixed map with random contents**: cheap, but the map is learnt in a few runs.
- **Open tiles with no corridors**: more horde-friendly, less roguelike; the user wants rooms.
- **Fully procedural room shapes**: variety without control over the fights inside; parked.

## Consequences

Enemy spawning, detection, leash and patrol rules live in the pure core and are tested there; a template is data the core reads, so the environment and the rules evolve apart. Extraction zones, start rooms and camps are placed by the generator, so their fairness is a property of the generator's tests. The room count scales with players, so a run started by two players is a small world.
