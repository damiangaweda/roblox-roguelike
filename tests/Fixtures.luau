--!strict
-- Builders for specs: a run on a copy of the real config, which a spec may
-- change without affecting others.

local Config = require("../src/shared/Config")
local Run = require("../src/shared/Core/Run")
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

-- A run with `playerCount` players standing at the origin, ids 1..n.
function Fixtures.run(playerCount: number?, config: Types.Config?, seed: number?): Types.Run
	local run = Run.new(config or Fixtures.config(), seed or 1)
	for id = 1, playerCount or 1 do
		Run.addPlayer(run, id, 0, 0)
	end
	return run
end

-- Places an enemy of `kind` at (x, z) and returns it.
function Fixtures.enemy(run: Types.Run, kind: string, x: number, z: number): Types.Enemy
	local enemy: Types.Enemy = {
		id = run.nextEnemyId,
		kind = kind,
		x = x,
		z = z,
		health = run.config.horde.kinds[kind].health,
		chilledUntil = 0,
		burningUntil = 0,
		burnSource = nil,
	}
	run.nextEnemyId += 1
	table.insert(run.enemies, enemy)
	return enemy
end

return Fixtures
