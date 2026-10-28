--!strict
-- Shrines (ADR-0020, GLOSSARY: shrine): the hold that activates one, what
-- each kind gives (a boon, a pact, a trial, a spring), the trial's ring and
-- its great offer, and the spring's recharge.

local Types = require("./Types")

local Shrines = {}

-- The shrine within the config's reach of the player, if any; the chest wins
-- over a shrine, so a hero at both opens the chest.
function Shrines.inReach(run: Types.Run, player: Types.Player): Types.Shrine?
	local _ = run
	local _ = player
	return nil
end

-- The interact button went down (`held`) or up. Holding beside an unused
-- (or recharged) shrine for config.shrines.holdSeconds activates it; a hit
-- resets the hold (Hero.damage clears shrineProgress).
function Shrines.setHolding(run: Types.Run, playerId: number, held: boolean)
	local _ = run
	local _ = playerId
	local _ = held
end

-- Advances every hold, finishes trials whose enemies are all dead and
-- recharges springs.
function Shrines.update(run: Types.Run, dt: number)
	local _ = run
	local _ = dt
end

return Shrines
