--!strict
-- Player health: damage, downed, revive and death.

local Types = require("./Types")

local Life = {}

-- Damages an alive player; at zero health the player is downed.
function Life.damage(run: Types.Run, player: Types.Player, amount: number)
	error("not implemented")
end

-- Advances revives and bleeding out of downed players by `dt`.
function Life.update(run: Types.Run, dt: number)
	error("not implemented")
end

return Life
