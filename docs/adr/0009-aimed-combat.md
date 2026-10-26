# Combat is aimed, with one scheme across platforms

The character faces the player's aim: the cursor on PC, the right stick on touch and gamepad, where a small auto-aim cone makes up for the stick's imprecision. The basic attack fires while its input is held, active skills and the dash are aimed the same way, and nothing targets an enemy for the player. We chose this over an auto-targeting basic attack because aiming is where the satisfaction and the skill of an action RPG live, and over a PC-only cursor scheme because PvP between platforms must stay fair.

## Considered options

- **Auto-target the nearest enemy** (stage 1): fair across platforms, but the player only positions and nothing feels like a weapon.
- **Click to attack**, as in Diablo 2: more control and more finger work; tiring on a phone.
- **Cursor on PC, auto-aim on phones**: a PC advantage in every PvP fight.

## Consequences

Every skill is designed around an aim direction, so a skill that needs a target (a chain, a trap) picks it from the aim. The width of the cone is configuration and the subject of a fairness check once PvP exists. Input is sent as an aim direction plus held or released buttons, which the server validates like every other intent.
