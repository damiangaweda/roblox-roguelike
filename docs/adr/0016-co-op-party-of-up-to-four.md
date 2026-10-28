# A run is played by one party of up to four, or solo, and players never harm each other

**Status:** accepted on 2026-10-27; once accepted it supersedes [ADR-0003](0003-hub-and-run-places.md), whose two places it keeps.

A run holds one party of one to four players who entered together; they share experience, revive one another and cannot harm each other, and there are no alliances, betrayal or fighting between players. The game is still two places in one universe: a hub, where players manage their stash and loadout and form a party, and a run place, where each run gets its own reserved server for its party and map, reached by teleport. We chose co-op over twelve players with alliances and betrayal because a survivors-like lives on a dense horde per player, which a server can give four players and not twelve, and because the user chose a game played with friends over one played against strangers.

## Considered options

- **Twelve players with alliances and betrayal** (the plan before this ADR): the horde thins to about twenty enemies a player, and PvP brings back every fairness question the pivot removed.
- **Six to eight players**: room for two parties in one run, with the same thinning and the same PvP questions.

## Consequences

Stage 3 of the old plan (alliances and betrayal) is dropped, and with it the reason for [ADR-0006](0006-map-tiers-with-power-limit.md)'s upper power limit ([ADR-0018](0018-maps-ask-for-a-minimum-power.md)). Everything that crosses the teleport (party, loadout, map) travels as teleport data checked by the run server against each player's saved profile, never trusted from the client. Until the hub exists, the run place starts runs on its own. Loot is personal: each player sees and picks up their own drops.
