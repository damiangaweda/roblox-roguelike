# The horde's cap is 220 living enemies

**Status:** accepted on 2026-10-28; supersedes the "about 150" of [ADR-0004](0004-lightweight-enemies.md), whose simulation and drawing stay as decided.

The horde of stage 3 ([ADR-0014](0014-round-map-with-a-horde-around-the-party.md)) grows to a cap of 220 grunts and elites alive at once (the number is configuration; bosses do not count). ADR-0004 budgeted about 150 when enemies were drawn by Humanoid-free rigs on an open map; measured in Studio on 2026-10-28, the server holds 60 Hz and the client 60 FPS at 220 with the circle-only rules and pooled parts, and the user judged the fuller horde the part of the run that works. We chose 220 over keeping 150 because the horde's pressure is the run's whole difficulty, and over going higher because the obstacle scan and the snapshot grow with the count and the four-client budget is still unmeasured (open question of stage 4).

## Consequences

The cap per party, with four clients, is measured and decided in stage 4 and may land below 220 per player. The snapshot's enemy buffer and the obstacle scan are the first places to optimise if it does not hold.
