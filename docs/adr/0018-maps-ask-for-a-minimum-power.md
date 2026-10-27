# Maps ask for a minimum power from every player who enters

**Status:** proposed; once accepted it supersedes [ADR-0006](0006-map-tiers-with-power-limit.md).

Maps are ordered from easiest to hardest, and each asks for a minimum power: a party enters only if every member's power (account level, worn items and utility skills) reaches it; harder maps hold stronger enemies and drop better loot. Later classes have the same power budget as the first ones and differ by mechanics, not strength, so unlocking one for Robux buys convenience, not victory. We chose a minimum over ADR-0006's maximum because the maximum protected new players from veterans in PvP, which co-op removes ([ADR-0016](0016-co-op-party-of-up-to-four.md)), while a minimum tells a player when they are ready and keeps a weak player from being carried through a map that would only kill them.

## Considered options

- **A power limit from above** (ADR-0006): fair in PvP, purposeless in co-op.
- **Only the party leader checked**: friends with different progress could always play together, at the cost of carried players dying in maps far beyond them.
- **Maps unlocked by extracting from the previous one**: a clear goal, but nothing ties the map to the player's strength.

## Consequences

Power ratings, the account level's share and every map's minimum are configuration (rule 3). The check runs on the run server against the saved profiles, never against what a client reports.
