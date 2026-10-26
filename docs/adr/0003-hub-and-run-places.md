# A hub place and a run place in one universe

The game is two places in one universe: a hub, where players manage their stash and loadout and form alliances, and a run place, where each run gets its own reserved server with its map tier and up to 12 players, reached by teleport. We chose this over one place because a run server must hold exactly the players and the map tier of that run, while the hub holds many players at once.

## Consequences

Everything that crosses the teleport (alliance, loadout, map tier) travels as teleport data checked by the run server against the player's saved profile, never trusted from the client. Until the hub exists (stage 3), the run place starts runs on its own.
