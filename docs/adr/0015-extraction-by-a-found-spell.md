# The way out is a spell found in a chest, and the run ends with a final boss

**Status:** proposed.

A run lasts a configured time (fifteen minutes), with a boss on a clock along the way. One extraction chest lies at a random place on the map, unmarked until a configured minute when the compass starts to point at it. The player who opens it gets the extraction spell and casts it whenever they choose: casting takes a few seconds, a hit interrupts it, and it opens a portal that stands for a while for the whole party; once the portal closes the spell can be cast again. At the end of the run's time the map's final boss arrives; killing it extracts everyone still alive with the best loot of the run, and if it is not killed within a configured time the map closes and everyone who has not left dies. We chose this over extraction zones on a clock and a closing flood (ADR-0012) because finding the chest and choosing when to cast gives the run two moments of tension that a party can read and argue about, and the final boss gives a run an ending worth staying for.

## Considered options

- **Zones that open on a clock and a flood that closes the map** (ADR-0012, stage 2d): built; suited to a large open map, not to a round one with a horde.
- **A portal after every boss for a short time**: a clean rhythm, but leaving needs nothing to be found.
- **No end, difficulty rising forever**: pure push-your-luck, with no ending and no predictable session length on a phone.
- **Survive to the end, as in Azeroth Survivors**: an ending, but no early way out and nothing at stake in leaving.

## Consequences

The run's clock (the boss times, the compass hint, the final boss, its time limit) is configuration in one place. Extraction keeps the haul ([ADR-0017](0017-only-the-haul-is-at-risk.md)), so a player who stops coping can leave with what they found, and one who stays for the final boss risks it.
