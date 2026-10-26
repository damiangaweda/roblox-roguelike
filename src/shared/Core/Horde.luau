--!strict
-- The horde: spawning, movement and contact with players.

local Types = require("./Types")

local Horde = {}

-- Spawns enemies for `dt` seconds of the run's spawn rate, up to the alive cap.
function Horde.spawn(run: Types.Run, dt: number)
	error("not implemented")
end

-- Moves every enemy toward the nearest alive player, keeping enemies apart.
function Horde.move(run: Types.Run, dt: number)
	error("not implemented")
end

-- Returns the contact damage each player takes during `dt`, by player id.
function Horde.contact(run: Types.Run, dt: number): { [number]: number }
	error("not implemented")
end

return Horde
