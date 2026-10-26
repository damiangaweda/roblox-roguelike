--!strict
-- Damage to enemies: the basic attack, the skill, burning and the synergy.

local Types = require("./Types")

local Combat = {}

-- Fires the basic attack of every alive player whose attack is ready.
function Combat.basicAttacks(run: Types.Run)
	error("not implemented")
end

-- Fires a player's skill at `aim`, or at the nearest enemy in range when
-- `aim` is nil. Returns false when the player cannot use it now.
function Combat.useSkill(run: Types.Run, playerId: number, aim: { x: number, z: number }?): boolean
	error("not implemented")
end

-- Applies burning damage for `dt` seconds.
function Combat.burn(run: Types.Run, dt: number)
	error("not implemented")
end

return Combat
