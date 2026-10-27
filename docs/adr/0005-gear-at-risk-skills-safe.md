# Items are at risk in a run, skills are never lost

**Status:** accepted; superseded by [ADR-0017](0017-only-the-haul-is-at-risk.md) once that one is accepted.

A player who dies in a run drops every unbound item they carry, worn or found, into a bag anyone can pick up; only items bound with a seal survive, and binding is limited to a number of slots. Skills are the opposite: a skill drops only for the picker's class, goes to the stash the moment it is picked up and is never lost. We chose an extraction economy so that trust and betrayal have real stakes, and safe skills so that every run still leaves lasting progress.

## Considered options

- **Items only for the run**: fair, but nothing worth extracting or stealing.
- **Only items found in this run at risk**: gentler, but a veteran's worn items would never leave the economy.
- **Permanent items never lost** (as in Obsidian Knight): progression without stakes, and power that only grows.

## Consequences

Items need a sink (death) and a protection (seals); seals can be bought, which buys safety, not power. Skills have no sink, so their power counts toward the power limit ([ADR-0006](0006-map-tiers-with-power-limit.md)).
