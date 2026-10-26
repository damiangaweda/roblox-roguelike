--!strict
-- Perk offers at level-up and taking a perk.

local Types = require("./Types")

local Perks = {}

-- Queues an offer of up to `offerSize` distinct perks the player can still take.
function Perks.offer(run: Types.Run, player: Types.Player)
	error("not implemented")
end

-- Takes perk number `index` of the player's oldest offer. Returns false when
-- there is no such offer or the player cannot choose now.
function Perks.choose(run: Types.Run, playerId: number, index: number): boolean
	error("not implemented")
end

return Perks
