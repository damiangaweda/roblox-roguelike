# The server holds player movement to a walking budget

Roblox lets each client simulate its own character, so a modified client can report any position. Rather than simulate players on the server, the run accepts a reported position only as far as a movement budget allows: it refills at walking speed times a tolerance and banks a short burst for late updates, and the server moves a character that drifts too far back to the run's position. We chose this over server-side character simulation because it keeps Roblox's responsive client movement for honest players and costs one check per player per step.

## Considered options

- **Trust client movement in stage 1**: nothing to gain without PvP or saving, but stage 2 and 3 could not live with it, and the user chose to fix it now.
- **Server-simulated characters**: no trust at all, but input lag on every move and far more work.

## Consequences

Anything that moves a player faster than walking (a dash, a knockback, a teleport skill) must raise the budget in the core, or the server will pull the player back.
