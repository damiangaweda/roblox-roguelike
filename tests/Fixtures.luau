--!strict
-- Builders for specs: a run on a copy of the real config, which a spec may
-- change without affecting others. The arena is generated like the server's,
-- from the seed; a spec that wants open ground calls Fixtures.clearObstacles.

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

-- A run with `playerCount` heroes of `class` (Mage by default) at the start,
-- ids 1..n, and no enemies: a spec spawns the ones it needs.
function Fixtures.run(
	playerCount: number?,
	config: Types.Config?,
	seed: number?,
	class: string?
): Types.Run
	local count = playerCount or 1
	local run = State.newRun(config or Fixtures.config(), seed or 1)
	for id = 1, count do
		State.newPlayer(run, id, class or "mage")
	end
	return run
end

-- Open ground: no obstacles stand in the way of a spec's positions.
function Fixtures.clearObstacles(run: Types.Run)
	run.arena.obstacles = {}
end

-- An enemy of `kind` at (x, z) without the horde's growth.
function Fixtures.enemy(run: Types.Run, kind: string, x: number, z: number): Types.Enemy
	return State.newEnemy(run, kind, x, z, 1, 1)
end

-- A shrine of `kind` at (x, z), its gift drawn as at generation. The run's
-- generated shrines stay; a spec that wants only its own clears run.shrines.
function Fixtures.shrine(run: Types.Run, kind: Types.ShrineKind, x: number, z: number): Types.Shrine
	local shrine = State.newShrine(run, { kind = kind, x = x, z = z })
	table.insert(run.shrines, shrine)
	return shrine
end

function Fixtures.place(run: Types.Run, id: number, x: number, z: number)
	local player = run.players[id]
	player.x = x
	player.z = z
end

-- Counts the events of `kind` in `events`.
function Fixtures.count(events: { any }, kind: string): number
	local total = 0
	for _, event in events do
		if event.kind == kind then
			total += 1
		end
	end
	return total
end

return Fixtures
