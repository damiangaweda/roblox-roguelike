# Only what a run found is at risk; what a player brings in and earns is kept

**Status:** accepted on 2026-10-27; once accepted it supersedes [ADR-0005](0005-gear-at-risk-skills-safe.md).

A player who dies in a run loses the haul, every item and utility skill they picked up during that run; the items and utility skills they brought in are never lost, and the gold and experience the run earned are kept either way. Extracting moves the haul into the stash. We chose this over ADR-0005's gear at risk because, with no betrayal and no other players to take a dead player's bag, losing worn gear would only punish, while losing the haul keeps every extraction a decision and every run leaves some progress.

## Considered options

- **Everything unbound at risk, with seals to bind** (ADR-0005): made for betrayal and looting other players, which co-op removes.
- **Utility skills never lost, as skills were in ADR-0005**: gentler, but a utility skill found deep in a run would be worth nothing at stake.
- **Part of the run's gold lost on death**: harsher, with no clear gain over losing the haul.

## Consequences

Seals and bound items have no purpose and leave the plan. Items and utility skills need no sink at death, so their growth is held by the power a map asks for ([ADR-0018](0018-maps-ask-for-a-minimum-power.md)) and by gold spent on upgrades. The profile (stage 5) stores the stash, gold, the account level and each class level, with a format version from day one (rule 2).
