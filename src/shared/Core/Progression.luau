--!strict
-- Experience and levels.

local Types = require("./Types")

local Progression = {}

-- Experience needed to go from `level` to the next one.
function Progression.xpToNext(config: Types.Config, level: number): number
	error("not implemented")
end

-- Adds experience, levelling up (and offering perks) as many times as it covers.
function Progression.grantXp(run: Types.Run, player: Types.Player, amount: number)
	error("not implemented")
end

return Progression
