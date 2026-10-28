# Lairs feed the horde and hold the bosses

**Status:** proposed on 2026-10-28; once accepted it supersedes the spawn ring, the kind window and the closing rings of [ADR-0014](0014-round-map-with-a-horde-around-the-party.md) and the boss clock of [ADR-0015](0015-extraction-by-a-found-spell.md); the round map, the obstacles, the chest, the spell, the portal and the map's closing stay as decided.

After playing stage 3b the user found that the horde spawning around the hero gives no reason to go anywhere and no breather to collect crystals or open the chest. The horde now comes from lairs: a few places on the map, one per boss, each releasing a batch of its own grunts at a fixed interval that walk at the players across the whole map. A lair's boss sleeps there with its guard until a player enters, fights only inside the lair and grows with run time; its death silences the lair for good. The final boss comes only when every lair is silent, and from the run's end time the map is overrun by wraiths that only the portal escapes. We chose lairs over waves on a timer because distance makes a better rhythm than a clock: near a living lair it is hot, far from every lair it is calm, and the player chooses when to go in; and over bosses on a clock because a boss that is a place is a goal the map shows, not an interruption.

## Considered options

- **The horde around the players with bosses on a clock** (ADR-0014, ADR-0015): built and played; pressure everywhere and nowhere to go.
- **Waves on a timer with lulls:** a breather by decree; it reads as artificial and ignores where the player stands.
- **Bosses that leave their lair to hunt:** more drama, but no safe ground and no way to choose a fight.

## Consequences

The run's goal is on the map and visible from afar. Grunts cross the map, so strays despawn instead of being moved back, and the alive cap of ADR-0019 is shared by the lairs. A run can end four ways: death, the portal, the final boss, or doom. Stage 4's party shares the lairs' rewards.
