--!strict
-- Builders for specs: a run on a copy of the real config, which a spec may
-- change without affecting others. The arena is generated like the server's,
-- from the seed; a spec that wants open ground calls Fixtures.clearObstacles.

local Config = require("../src/shared/Config")
local Lairs = require("../src/shared/Core/Lairs")
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

-- Open ground: no obstacles stand in the way of a spec's positions, and no
-- shallow water slows them.
function Fixtures.clearObstacles(run: Types.Run)
	run.arena.obstacles = {}
	run.arena.terrain.slowZones = {}
end

-- A slow zone (shallow water) of `radius` at (x, z).
function Fixtures.slowZone(run: Types.Run, x: number, z: number, radius: number): Types.SlowZone
	local zone = { x = x, z = z, radius = radius }
	table.insert(run.arena.terrain.slowZones, zone)
	return zone
end

-- An obstacle circle of `kind` (a rock by default) at (x, z).
function Fixtures.obstacle(
	run: Types.Run,
	x: number,
	z: number,
	radius: number,
	kind: string?
): Types.Obstacle
	local id = #run.arena.obstacles + 1
	local obstacle: Types.Obstacle = {
		id = id,
		kind = kind or "rock",
		x = x,
		z = z,
		radius = radius,
		rotation = 0,
		group = id,
		anchor = true,
	}
	table.insert(run.arena.obstacles, obstacle)
	return obstacle
end

-- A cliff ring round (x, z) of `radius` from the terrain's cliff circles,
-- with one ramp-wide gap facing `gapAngle` (radians): the circles whose arc
-- from the gap's middle is under half the ramp plus a circle's radius are
-- left out, so the opening is about a ramp wide.
function Fixtures.cliffRing(run: Types.Run, x: number, z: number, radius: number, gapAngle: number)
	local terrain = run.config.terrain
	local count = math.ceil(2 * math.pi * radius / terrain.cliffStep)
	local opening = terrain.rampWidth / 2 + terrain.cliffRadius
	for index = 0, count - 1 do
		local angle = index * 2 * math.pi / count
		local apart = math.abs((angle - gapAngle + math.pi) % (2 * math.pi) - math.pi)
		if apart * radius >= opening then
			Fixtures.obstacle(
				run,
				x + math.cos(angle) * radius,
				z + math.sin(angle) * radius,
				terrain.cliffRadius,
				"cliff"
			)
		end
	end
end

-- An enemy of `kind` at (x, z) without the horde's growth.
function Fixtures.enemy(run: Types.Run, kind: string, x: number, z: number): Types.Enemy
	return State.newEnemy(run, kind, x, z, 1, 1)
end

-- A shrine of `kind` at (x, z), its boon or pact drawn as at generation. The run's
-- generated shrines stay; a spec that wants only its own clears run.shrines.
function Fixtures.shrine(run: Types.Run, kind: Types.ShrineKind, x: number, z: number): Types.Shrine
	local shrine = State.newShrine(run, { kind = kind, x = x, z = z })
	table.insert(run.shrines, shrine)
	return shrine
end

-- A lair of `kind` at (x, z), asleep, its first batch due at `nextBatchAt`
-- (never by default); its boss and guard come at the next Lairs.update. The
-- run's generated lairs stay; a spec that wants only its own calls
-- Fixtures.clearLairs first.
function Fixtures.lair(
	run: Types.Run,
	kind: string,
	x: number,
	z: number,
	nextBatchAt: number?
): Types.Lair
	local lair = State.newLair(run, { kind = kind, x = x, z = z, rotation = 0 })
	lair.nextBatchAt = nextBatchAt or math.huge
	table.insert(run.lairs, lair)
	return lair
end

-- No lairs: nothing is released and no boss sleeps on the map.
function Fixtures.clearLairs(run: Types.Run)
	run.lairs = {}
end

-- Wakes the lair as a hero entering it would.
function Fixtures.wake(run: Types.Run, lair: Types.Lair)
	Lairs.wake(run, lair)
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
