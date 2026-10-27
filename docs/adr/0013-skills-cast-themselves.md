# Skills cast themselves; the player moves, picks cards and fires utility skills

**Status:** proposed; once accepted it supersedes [ADR-0009](0009-aimed-combat.md).

Every skill a player gathers during a run fires on its own cooldown at a target its targeting picks (the nearest enemy, the toughest, the densest cluster, a chain, the ground around the hero), and nothing the player aims steers it. The player's decisions are where to move, which of three cards to take at each level-up, and when to fire up to three utility skills by hand (a sprint, a barrier, a heal), which are the only buttons besides moving. We chose this over the aimed combat of ADR-0009 because the user judged the aimed, open-map game beyond what this project can make look and feel good, and the survivors-like loop (modelled on Azeroth Survivors) puts the fun in systems and numbers: ranks with thresholds, distinct targeting, a growing horde. With no aim, no platform has an aiming advantage, so the cursor-against-stick fairness problem disappears with it.

## Considered options

- **Aimed combat** (ADR-0009, stages 2a–2d): implemented and played; the user found that it, the open map and their look needed more than an AI-built greybox could give.
- **Auto-cast with one aimed ultimate**: more skill expression, but it brings back the fairness check between cursor and stick.
- **Utility skills that also cast themselves**: no buttons at all, and no decision at the moment that matters (escape, shield, heal).

## Consequences

A skill is designed around a targeting kind instead of an aim direction, and the server picks every target, so the client sends no aim at all. Skills exist only inside a run: they come from level-up cards, rank up to a configured maximum and are gone when the run ends; what persists between runs is the utility skills ([ADR-0017](0017-only-the-haul-is-at-risk.md)). The movement budget of [ADR-0007](0007-movement-budget.md) stays, and a utility skill that moves the player raises it.
