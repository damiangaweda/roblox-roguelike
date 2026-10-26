# Game rules in a pure core, the engine behind an adapter

Damage, ability offers, synergies, loot, death and extraction are decided by pure Luau modules that never touch the Roblox API; a thin server adapter feeds them input (players, remotes, time, randomness) and applies their results to the world. We chose this so the rules are tested offline in `make ci` ([ADR-0001](0001-rojo-toolchain-and-offline-gate.md)) and so the server's authority over outcomes lives in one place that the client cannot reach.

## Consequences

Randomness and time are passed into the core rather than read from the engine, so a test can replay a run deterministically. Code that needs the engine (physics, rendering, DataStores) belongs to the adapter and is kept free of game rules.
