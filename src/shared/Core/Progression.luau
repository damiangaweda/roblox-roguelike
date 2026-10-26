--!strict
-- Experience and levels.

local Perks = require("./Perks")
local Types = require("./Types")

local Progression = {}

-- Experience needed to go from `level` to the next one.
function Progression.xpToNext(config: Types.Config, level: number): number
	local progression = config.progression
	return math.floor(progression.xpToSecondLevel * progression.xpGrowth ^ (level - 1) + 0.5)
end

-- Adds experience, levelling up (and offering perks) as many times as it covers.
function Progression.grantXp(run: Types.Run, player: Types.Player, amount: number)
	player.xp += amount
	while player.xp >= Progression.xpToNext(run.config, player.level) do
		player.xp -= Progression.xpToNext(run.config, player.level)
		player.level += 1
		table.insert(run.events, { kind = "levelUp", player = player.id, level = player.level })
		Perks.offer(run, player)
	end
end

return Progression
