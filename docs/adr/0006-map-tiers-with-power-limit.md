# Map tiers with a power limit keep new players in the game

**Status:** accepted; superseded by [ADR-0018](0018-maps-ask-for-a-minimum-power.md) once that one is accepted.

Every item, skill and class has a power rating, and every map tier admits only loadouts whose total power stays under its power limit; higher tiers drop better items. Later classes have the same power budget as the first ones and differ by mechanics and comfort, not strength, so unlocking one early for Robux buys convenience, not victory. We chose this over matchmaking by power because 12-player runs on a young game would wait too long for a narrow match.

## Considered options

- **Matchmaking by power** on one map: thin player pools, long queues.
- **Horizontal progression only**: fair, but the user wants a felt sense of growing stronger.
- **Normalising stats in PvP**: hides progression exactly where players compare it.

## Consequences

The power limit is checked when a player enters a run; items found during a run may exceed it. Power ratings and limits are configuration (rule 3).
