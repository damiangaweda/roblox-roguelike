--!strict
-- Builders for specs: a run on a copy of the real config, which a spec may
-- change without affecting others. The map is generated like the server's,
-- from the seed; a spec that needs a known layout reads run.map, or shapes
-- the ground around it with `dry`, `water` and `prop`.

local Config = require("../src/shared/Config")
local Geometry = require("../src/shared/Core/Geometry")
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

-- A run with `playerCount` Elementalists at the entries, ids 1..n, and no
-- enemies: a spec places the ones it needs, or calls Camps.populate.
function Fixtures.run(playerCount: number?, config: Types.Config?, seed: number?): Types.Run
	local count = playerCount or 1
	local run = State.newRun(config or Fixtures.config(), seed or 1, count)
	for id = 1, count do
		State.newPlayer(run, id)
	end
	return run
end

-- The point whose footprint player `id` stands on.
function Fixtures.pointOf(run: Types.Run, id: number): Types.MapPoint
	local player = run.players[id]
	for _, point in run.map.points do
		if Geometry.distance(player.x, player.z, point.x, point.z) <= point.radius then
			return point
		end
	end
	error("player " .. id .. " stands on no point")
end

-- The first entry, where player 1 starts.
function Fixtures.entryOf(run: Types.Run): Types.MapPoint
	return run.map.points[run.map.entries[1]]
end

-- Calls `visit(row, col)` for every height node within `radius` of (x, z).
local function eachNode(
	run: Types.Run,
	x: number,
	z: number,
	radius: number,
	visit: (row: number, col: number) -> ()
)
	local map = run.map
	for row, line in map.heights do
		for col in line do
			local nx, nz =
				-map.half + (col - 1) * map.heightCell, -map.half + (row - 1) * map.heightCell
			if Geometry.distance(nx, nz, x, z) <= radius then
				visit(row, col)
			end
		end
	end
end

-- Raises the ground within `radius` of (x, z), and a cell beyond, above the
-- water, so a spec has open ground there whatever the seed made.
function Fixtures.dry(run: Types.Run, x: number, z: number, radius: number)
	local map = run.map
	local dry = map.waterLevel + run.config.map.dryMargin
	eachNode(run, x, z, radius + map.heightCell * math.sqrt(2), function(row, col)
		map.heights[row][col] = math.max(map.heights[row][col], dry)
	end)
end

-- Sinks the ground under water: every height node within `radius` of (x, z),
-- so positions within about radius - heightCell of it are water.
function Fixtures.water(run: Types.Run, x: number, z: number, radius: number)
	local map = run.map
	eachNode(run, x, z, radius, function(row, col)
		map.heights[row][col] = map.waterLevel - 1
	end)
end

-- Adds a solid prop (absolute rect) to `point`; it must lie on the point's
-- footprint, where the map looks for props.
function Fixtures.prop(
	point: Types.MapPoint,
	x: number,
	z: number,
	halfWidth: number,
	halfDepth: number
): Types.Rect
	local rect = { x = x, z = z, halfWidth = halfWidth, halfDepth = halfDepth }
	table.insert(point.props, rect)
	return rect
end

-- Places an enemy of `archetype` at (x, z), at home there, and returns it.
function Fixtures.enemy(run: Types.Run, archetype: string, x: number, z: number): Types.Enemy
	return State.newEnemy(run, archetype, 1, x, z)
end

-- Moves a player to (x, z) and refreshes where they stand.
function Fixtures.place(run: Types.Run, player: Types.Player, x: number, z: number)
	player.x, player.z = x, z
	player.pointId = State.pointIdAt(run, x, z)
end

return Fixtures
