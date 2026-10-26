--!strict
-- Builders for specs: a run on a copy of the real config, which a spec may
-- change without affecting others. The world is generated like the server's,
-- from the seed; a spec that needs a known layout reads run.world.

local Config = require("../src/shared/Config")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

local Fixtures = {}

local function deepCopy<T>(value: T): T
	if type(value) ~= "table" then
		return value
	end
	local copy = {}
	for key, inner in value :: any do
		copy[key] = deepCopy(inner)
	end
	return copy :: any
end

function Fixtures.config(): Types.Config
	return deepCopy(Config)
end

-- A run with `playerCount` Elementalists in their start rooms, ids 1..n, and
-- no enemies: a spec places the ones it needs, or calls Camps.populate.
function Fixtures.run(playerCount: number?, config: Types.Config?, seed: number?): Types.Run
	local count = playerCount or 1
	local run = State.newRun(config or Fixtures.config(), seed or 1, count)
	for id = 1, count do
		State.newPlayer(run, id)
	end
	return run
end

-- The room a player stands in.
function Fixtures.roomOf(run: Types.Run, player: Types.Player): Types.Room
	for _, room in run.world.rooms do
		if
			math.abs(player.x - room.x) <= room.halfWidth
			and math.abs(player.z - room.z) <= room.halfDepth
		then
			return room
		end
	end
	error("player " .. player.id .. " stands in no room")
end

-- Places an enemy of `archetype` at (x, z), at home there, and returns it.
function Fixtures.enemy(run: Types.Run, archetype: string, x: number, z: number): Types.Enemy
	return State.newEnemy(run, archetype, 1, x, z)
end

-- Moves a player to (x, z) and refreshes where they stand.
function Fixtures.place(run: Types.Run, player: Types.Player, x: number, z: number)
	player.x, player.z = x, z
	local room = nil
	for _, candidate in run.world.rooms do
		if
			math.abs(x - candidate.x) <= candidate.halfWidth
			and math.abs(z - candidate.z) <= candidate.halfDepth
		then
			room = candidate.id
		end
	end
	player.roomId = room
end

return Fixtures
