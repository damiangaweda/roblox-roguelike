--!strict
-- The map's ground (ADR-0014): a round, flat arena closed by its edge, with
-- obstacles composed anew for every run from the seed (stage 3b): places with
-- their kits on clearings, paths of open ground from the start to each, groves
-- dense at their core and thin at their edge, pines in the north and oaks in
-- the south, and sparse leftovers. Obstacles are circles that block the
-- movement of players and enemies and nothing else, so the queries here are
-- the only collision the core has.

local Geometry = require("./Geometry")
local Types = require("./Types")

local Arena = {}

-- A body stops this far short of an obstacle, so rounding never puts it inside.
local CONTACT_GAP = 1e-3
-- A path's shape, not a gameplay number: a point every PATH_STEP studs, and
-- between PATH_WAVES_MIN and PATH_WAVES_MAX sways over its length.
local PATH_STEP = 12
local PATH_WAVES_MIN, PATH_WAVES_MAX = 0.75, 1.75
-- Leftovers: this share is drawn near a grove, within GROVE_REACH of its radius.
local GROVE_BIAS = 0.7
local GROVE_REACH = 1.5

type ObstacleKind = {
	id: string,
	radius: number,
	weight: number,
	footprint: { { dx: number, dz: number, radius: number } }?,
}

type Circle = { x: number, z: number, radius: number }

type Grove = { x: number, z: number, radius: number, trees: number }

-- What a placement keeps clear of: the chest, the places' clearings, the
-- paths and the obstacles already placed.
type Layout = {
	map: Types.MapConfig,
	inner: number,
	chestX: number,
	chestZ: number,
	places: { Types.Place },
	paths: { Types.Path },
	obstacles: { Types.Obstacle },
	kinds: { [string]: ObstacleKind },
	groups: number,
}

-- An entry of `list` drawn by its weight.
local function pickWeighted<T>(list: { T }, weightOf: (T) -> number, rng: Types.Rng): T
	local total = 0
	for _, entry in list do
		total += weightOf(entry)
	end
	local roll = rng:next() * total
	for _, entry in list do
		roll -= weightOf(entry)
		if roll < 0 then
			return entry
		end
	end
	return list[#list]
end

-- A point uniform by area in the disc of `radius` around the origin.
local function randomInDisc(rng: Types.Rng, radius: number): (number, number)
	local r = radius * math.sqrt(rng:next())
	local angle = rng:next() * 2 * math.pi
	return r * math.cos(angle), r * math.sin(angle)
end

-- (dx, dz) turned by `rotation`, like every angle of the core (from +x toward +z).
local function turn(dx: number, dz: number, rotation: number): (number, number)
	local cos, sin = math.cos(rotation), math.sin(rotation)
	return dx * cos - dz * sin, dx * sin + dz * cos
end

-- The circles a prop of `kind` at (x, z) turned by `rotation` takes: one per
-- footprint entry, its offset turned with the prop, else the kind's single
-- circle at the centre.
local function circlesOf(kind: ObstacleKind, x: number, z: number, rotation: number): { Circle }
	local footprint = kind.footprint
	if footprint == nil or #footprint == 0 then
		return { { x = x, z = z, radius = kind.radius } }
	end
	local circles = table.create(#footprint)
	for _, entry in footprint do
		local dx, dz = turn(entry.dx, entry.dz, rotation)
		table.insert(circles, { x = x + dx, z = z + dz, radius = entry.radius })
	end
	return circles
end

-- The distance from (x, z) to the segment from (ax, az) to (bx, bz).
local function segmentDistance(
	x: number,
	z: number,
	ax: number,
	az: number,
	bx: number,
	bz: number
): number
	local dx, dz = bx - ax, bz - az
	local length2 = dx * dx + dz * dz
	local t = if length2 < 1e-12 then 0 else ((x - ax) * dx + (z - az) * dz) / length2
	t = math.clamp(t, 0, 1)
	return Geometry.distance(x, z, ax + dx * t, az + dz * t)
end

-- The distance from (x, z) to the nearest point of a path.
function Arena.pathDistance(path: Types.Path, x: number, z: number): number
	local best = math.huge
	for index = 2, #path do
		local a, b = path[index - 1], path[index]
		best = math.min(best, segmentDistance(x, z, a.x, a.z, b.x, b.z))
	end
	if #path == 1 then
		best = Geometry.distance(x, z, path[1].x, path[1].z)
	end
	return best
end

-- Whether every circle stays inside the edge and keeps the clear ground of
-- the start, the chest, the places and the paths, and the spacing from the
-- obstacles already placed.
local function fits(layout: Layout, circles: { Circle }): boolean
	local map = layout.map
	for _, circle in circles do
		if
			Geometry.distance(circle.x, circle.z, 0, 0) + circle.radius > layout.inner
			or Geometry.distance(circle.x, circle.z, 0, 0) < map.startClearRadius + circle.radius
			or Geometry.distance(circle.x, circle.z, layout.chestX, layout.chestZ)
				< map.chestClearRadius + circle.radius
		then
			return false
		end
		for _, place in layout.places do
			if
				Geometry.distance(circle.x, circle.z, place.x, place.z)
				< place.radius + circle.radius
			then
				return false
			end
		end
		for _, path in layout.paths do
			if Arena.pathDistance(path, circle.x, circle.z) < map.pathWidth + circle.radius then
				return false
			end
		end
		for _, other in layout.obstacles do
			if
				Geometry.distance(circle.x, circle.z, other.x, other.z)
				< circle.radius + other.radius + map.obstacleSpacing
			then
				return false
			end
		end
	end
	return true
end

-- Adds a prop's circles as one group, the first the anchor, with its look:
-- a scale within the variation and a lean within the degrees.
local function addProp(
	layout: Layout,
	rng: Types.Rng,
	kind: ObstacleKind,
	circles: { Circle },
	rotation: number
)
	local map = layout.map
	local scale = 1 + (rng:next() * 2 - 1) * map.scaleVariation
	local lean = rng:next() * math.rad(map.leanDegrees)
	layout.groups += 1
	for order, circle in circles do
		table.insert(layout.obstacles, {
			id = #layout.obstacles + 1,
			kind = kind.id,
			x = circle.x,
			z = circle.z,
			radius = circle.radius,
			rotation = rotation,
			group = layout.groups,
			anchor = order == 1,
			scale = scale,
			lean = lean,
		})
	end
end

-- The places' kinds in the order they are placed: rounds of every kind, each
-- round drawn without replacement by weight, so no kind repeats before every
-- kind has appeared.
local function dealPlaceKinds(map: Types.MapConfig, rng: Types.Rng): { Types.PlaceKind }
	local dealt: { Types.PlaceKind } = {}
	if #map.placeKinds == 0 then
		return dealt
	end
	while #dealt < map.placeCount do
		local round = table.clone(map.placeKinds)
		while #round > 0 and #dealt < map.placeCount do
			local kind = pickWeighted(round, function(entry: Types.PlaceKind)
				return entry.weight
			end, rng)
			table.insert(dealt, kind)
			table.remove(round, table.find(round, kind) :: number)
		end
	end
	return dealt
end

-- Whether a place of `radius` at (x, z) keeps its distances: from the start,
-- the chest, the edge and the other places, with its path from the start
-- clear of their clearings and theirs of its own.
local function placeFits(layout: Layout, x: number, z: number, radius: number): boolean
	local map = layout.map
	local reach = map.pathWidth + map.pathSway
	if
		Geometry.distance(x, z, 0, 0) < map.placeStartDistance
		or Geometry.distance(x, z, 0, 0) + radius > layout.inner
		or Geometry.distance(x, z, layout.chestX, layout.chestZ) < map.chestClearRadius + radius
	then
		return false
	end
	for _, other in layout.places do
		if
			Geometry.distance(x, z, other.x, other.z) < map.placeSpacing
			or segmentDistance(other.x, other.z, 0, 0, x, z) < other.radius + reach
			or segmentDistance(x, z, 0, 0, other.x, other.z) < radius + reach
		then
			return false
		end
	end
	return true
end

-- Places: each kind's centre found within placementAttempts draws (else the
-- place is skipped), its rotation random, its kit of props turned with it.
local function composePlaces(layout: Layout, rng: Types.Rng)
	local map = layout.map
	for _, kind in dealPlaceKinds(map, rng) do
		for _ = 1, map.placementAttempts do
			local x, z = randomInDisc(rng, layout.inner - kind.radius)
			if placeFits(layout, x, z, kind.radius) then
				local rotation = rng:next() * 2 * math.pi
				table.insert(layout.places, {
					id = #layout.places + 1,
					kind = kind.id,
					x = x,
					z = z,
					radius = kind.radius,
					rotation = rotation,
				})
				for _, prop in kind.props do
					local propKind = layout.kinds[prop.kind]
					if propKind then
						local dx, dz = turn(prop.dx, prop.dz, rotation)
						local propRotation = rotation + (prop.rotation or 0)
						addProp(
							layout,
							rng,
							propKind,
							circlesOf(propKind, x + dx, z + dz, propRotation),
							propRotation
						)
					end
				end
				break
			end
		end
	end
end

-- A path from the start to a place's clearing: a point every PATH_STEP
-- studs, swaying off the straight line by up to pathSway on a smooth wave
-- that is back on the line at both ends.
local function pathTo(map: Types.MapConfig, rng: Types.Rng, place: Types.Place): Types.Path
	local distance = Geometry.distance(0, 0, place.x, place.z)
	local length = math.max(distance - place.radius, 0)
	local ux, uz = Geometry.normalize(place.x, place.z)
	local amplitude = map.pathSway * (0.5 + 0.5 * rng:next()) * (if rng:next() < 0.5 then -1 else 1)
	local waves = PATH_WAVES_MIN + (PATH_WAVES_MAX - PATH_WAVES_MIN) * rng:next()
	local phase = rng:next() * 2 * math.pi
	local steps = math.max(math.ceil(length / PATH_STEP), 1)
	local path: Types.Path = table.create(steps + 1)
	for index = 0, steps do
		local t = index / steps
		local sway = amplitude * math.sin(t * waves * 2 * math.pi + phase) * math.sin(t * math.pi)
		table.insert(path, { x = ux * t * length - uz * sway, z = uz * t * length + ux * sway })
	end
	return path
end

-- The tree kind at depth z: pines in the north (-z), oaks in the south.
local function treeKind(layout: Layout, rng: Types.Rng, z: number): ObstacleKind?
	local map = layout.map
	local share = math.clamp(0.5 + map.northShare * (-z / map.radius), 0.1, 0.9)
	return if rng:next() < share then layout.kinds.pine else layout.kinds.oak
end

-- A tree's offset from its grove's centre, or nil when the draw is thinned
-- out: uniform by area in the disc of `radius`, kept always inside `core` of
-- the radius and ever less often toward the edge.
function Arena.groveOffset(rng: Types.Rng, radius: number, core: number): (number?, number?)
	local dx, dz = randomInDisc(rng, radius)
	local r = math.sqrt(dx * dx + dz * dz)
	local keep = if r < core * radius then 1 else (radius - r) / (radius * (1 - core))
	if rng:next() < keep then
		return dx, dz
	end
	return nil, nil
end

-- Groves: centres kept groveSpacing off the places' clearings and other
-- groves; each tree a point in the disc, full density inside the core and
-- falling to nothing at the edge, skipped when it finds no room.
local function composeGroves(layout: Layout, rng: Types.Rng): { Grove }
	local map = layout.map
	local groves: { Grove } = {}
	for _ = 1, map.groveCount do
		local radius = map.groveRadiusMin + (map.groveRadiusMax - map.groveRadiusMin) * rng:next()
		local trees = rng:integer(map.groveTreesMin, map.groveTreesMax)
		for _ = 1, map.placementAttempts do
			local x, z = randomInDisc(rng, layout.inner)
			local free = true
			for _, place in layout.places do
				if Geometry.distance(x, z, place.x, place.z) < place.radius + map.groveSpacing then
					free = false
					break
				end
			end
			if free then
				for _, other in groves do
					if
						Geometry.distance(x, z, other.x, other.z)
						< radius + other.radius + map.groveSpacing
					then
						free = false
						break
					end
				end
			end
			if free then
				table.insert(groves, { x = x, z = z, radius = radius, trees = trees })
				break
			end
		end
	end

	for _, grove in groves do
		for _ = 1, grove.trees do
			for _ = 1, map.placementAttempts do
				local dx, dz = Arena.groveOffset(rng, grove.radius, map.groveCore)
				if dx and dz then
					local x, z = grove.x + dx, grove.z + dz
					local kind = treeKind(layout, rng, z)
					local rotation = rng:next() * 2 * math.pi
					if kind == nil then
						break
					end
					local circles = circlesOf(kind, x, z, rotation)
					if fits(layout, circles) then
						addProp(layout, rng, kind, circles, rotation)
						break
					end
				end
			end
		end
	end
	return groves
end

-- Leftovers: sparse props of the scatter kinds, most near a grove, the rest
-- anywhere, with the same clear ground as every prop.
local function composeLeftovers(layout: Layout, rng: Types.Rng, groves: { Grove })
	local map = layout.map
	if #map.scatterKinds == 0 then
		return
	end
	for _ = 1, map.scatterCount do
		local pick = pickWeighted(map.scatterKinds, function(entry: { id: string, weight: number })
			return entry.weight
		end, rng)
		local kind = layout.kinds[pick.id]
		if kind == nil then
			continue
		end
		for _ = 1, map.placementAttempts do
			local x, z
			if #groves > 0 and rng:next() < GROVE_BIAS then
				local grove = groves[rng:integer(1, #groves)]
				local dx, dz = randomInDisc(rng, grove.radius * GROVE_REACH)
				x, z = grove.x + dx, grove.z + dz
			else
				x, z = randomInDisc(rng, layout.inner)
			end
			local rotation = rng:next() * 2 * math.pi
			local circles = circlesOf(kind, x, z, rotation)
			if fits(layout, circles) then
				addProp(layout, rng, kind, circles, rotation)
				break
			end
		end
	end
end

-- The shrines' spots (ADR-0020): config.shrines.count kinds dealt
-- round-robin over its kinds and shuffled, each spot clear of the start, the
-- chest, the other spots and every obstacle circle. A spot that finds no
-- room within placementAttempts draws is skipped.
local function scatterShrines(
	map: Types.MapConfig,
	shrines: Types.ShrinesConfig,
	rng: Types.Rng,
	obstacles: { Types.Obstacle },
	chestX: number,
	chestZ: number
): { Types.ShrineSpot }
	local kinds: { Types.ShrineKind } = {}
	if #shrines.kinds > 0 then
		for index = 1, shrines.count do
			table.insert(kinds, shrines.kinds[(index - 1) % #shrines.kinds + 1])
		end
	end
	-- Fisher-Yates.
	for index = #kinds, 2, -1 do
		local other = rng:integer(1, index)
		kinds[index], kinds[other] = kinds[other], kinds[index]
	end

	local inner = map.radius - map.edgeMargin - shrines.radius
	local spots: { Types.ShrineSpot } = {}
	for _, kind in kinds do
		for _ = 1, map.placementAttempts do
			local x, z = randomInDisc(rng, inner)
			local free = Geometry.distance(x, z, 0, 0) >= shrines.startMinDistance
				and Geometry.distance(x, z, chestX, chestZ) >= shrines.chestMinDistance
			if free then
				for _, spot in spots do
					if Geometry.distance(x, z, spot.x, spot.z) < shrines.spacing then
						free = false
						break
					end
				end
			end
			if free then
				for _, obstacle in obstacles do
					if
						Geometry.distance(x, z, obstacle.x, obstacle.z)
						< obstacle.radius + shrines.radius + map.obstacleSpacing
					then
						free = false
						break
					end
				end
			end
			if free then
				local spot: Types.ShrineSpot = { kind = kind :: Types.ShrineKind, x = x, z = z }
				table.insert(spots, spot)
				break
			end
		end
	end
	return spots
end

-- Composes the map for a seed: places the chest, then the places with their
-- kits, a path to each, the groves and the leftovers, and, given the shrines'
-- config, the shrines' spots; the start is the centre. A prop takes one circle
-- per footprint entry, all of one `group`, the first the anchor the builder
-- draws the prop at. Repeatable for a seed: the rng is the run's, consumed in
-- a fixed order.
function Arena.generate(
	map: Types.MapConfig,
	rng: Types.Rng,
	shrines: Types.ShrinesConfig?
): Types.Arena
	local inner = map.radius - map.edgeMargin
	local chestX, chestZ = 0, 0
	for _ = 1, map.placementAttempts do
		local x, z = randomInDisc(rng, inner)
		if Geometry.distance(0, 0, x, z) >= map.chestMinDistance then
			chestX, chestZ = x, z
			break
		end
	end
	if chestX == 0 and chestZ == 0 then
		-- Every draw fell short: put the chest at the minimum distance on a random bearing.
		local angle = rng:next() * 2 * math.pi
		chestX = math.cos(angle) * math.min(map.chestMinDistance, inner)
		chestZ = math.sin(angle) * math.min(map.chestMinDistance, inner)
	end

	local kinds: { [string]: ObstacleKind } = {}
	for _, kind in map.obstacleKinds do
		kinds[kind.id] = kind
	end
	local layout: Layout = {
		map = map,
		inner = inner,
		chestX = chestX,
		chestZ = chestZ,
		places = {},
		paths = {},
		obstacles = {},
		kinds = kinds,
		groups = 0,
	}
	composePlaces(layout, rng)
	for _, place in layout.places do
		table.insert(layout.paths, pathTo(map, rng, place))
	end
	local groves = composeGroves(layout, rng)
	composeLeftovers(layout, rng, groves)

	return {
		radius = map.radius,
		obstacles = layout.obstacles,
		startX = 0,
		startZ = 0,
		chestX = chestX,
		chestZ = chestZ,
		shrineSpots = if shrines
			then scatterShrines(map, shrines, rng, layout.obstacles, chestX, chestZ)
			else {},
		places = layout.places,
		paths = layout.paths,
	}
end

-- Pulls (x, z) inside the edge, keeping a body of `bodyRadius` within it.
function Arena.clamp(arena: Types.Arena, x: number, z: number, bodyRadius: number): (number, number)
	local limit = math.max(arena.radius - bodyRadius, 0)
	local distance = math.sqrt(x * x + z * z)
	if distance <= limit then
		return x, z
	end
	return x / distance * limit, z / distance * limit
end

-- The obstacle a body of `bodyRadius` at (x, z) overlaps, if any.
function Arena.blocking(
	arena: Types.Arena,
	x: number,
	z: number,
	bodyRadius: number
): Types.Obstacle?
	for _, obstacle in arena.obstacles do
		if Geometry.distance(x, z, obstacle.x, obstacle.z) < obstacle.radius + bodyRadius then
			return obstacle
		end
	end
	return nil
end

-- How far along the segment from (fromX, fromZ) to (toX, toZ) a body of
-- `bodyRadius` travels before it touches an obstacle or the edge: the
-- segment's length when nothing is in the way. An obstacle the body already
-- overlaps does not hold it, so nothing is ever stuck.
function Arena.reach(
	arena: Types.Arena,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	bodyRadius: number
): number
	local dx, dz = toX - fromX, toZ - fromZ
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-9 then
		return 0
	end
	local ux, uz = dx / length, dz / length
	local best = length

	for _, obstacle in arena.obstacles do
		local reach = obstacle.radius + bodyRadius
		local ox, oz = obstacle.x - fromX, obstacle.z - fromZ
		local along = ox * ux + oz * uz
		local across2 = ox * ox + oz * oz - along * along
		local inside = ox * ox + oz * oz < reach * reach
		if inside then
			-- Already overlapping (a contact point rounds a hair inside): a move
			-- deeper is held, a move away is free, so nothing is ever stuck.
			if along > 0 then
				return 0
			end
		elseif along > 0 and across2 < reach * reach then
			local hit = along - math.sqrt(reach * reach - across2) - CONTACT_GAP
			if hit < best then
				best = math.max(hit, 0)
			end
		end
	end

	-- The edge: the first point of the segment at distance `limit` from the centre.
	local limit = math.max(arena.radius - bodyRadius, 0)
	local fromDistance2 = fromX * fromX + fromZ * fromZ
	if fromDistance2 < limit * limit then
		local along = -(fromX * ux + fromZ * uz)
		local across2 = fromDistance2 - along * along
		local hit = along + math.sqrt(math.max(limit * limit - across2, 0))
		if hit < best then
			best = math.max(hit, 0)
		end
	end
	return best
end

-- The unit direction a body at (x, z) walks to get toward the target: straight
-- when the next `probe` studs are free, else along the tangent of the first
-- blocking obstacle on the side nearer the target, `margin` studs clear of it.
function Arena.steer(
	arena: Types.Arena,
	x: number,
	z: number,
	targetX: number,
	targetZ: number,
	bodyRadius: number,
	margin: number,
	probe: number
): (number, number)
	local ux, uz = Geometry.normalize(targetX - x, targetZ - z)
	local toTarget = Geometry.distance(x, z, targetX, targetZ)
	local look = math.min(probe, toTarget)
	if look <= 1e-6 then
		return ux, uz
	end
	local reach = Arena.reach(arena, x, z, x + ux * look, z + uz * look, bodyRadius)
	if reach >= look - 1e-6 then
		return ux, uz
	end
	-- The obstacle hit: the one nearest along the ray.
	local hitX, hitZ = x + ux * (reach + 1e-3), z + uz * (reach + 1e-3)
	local nearest: Types.Obstacle? = nil
	local nearestDistance = math.huge
	for _, obstacle in arena.obstacles do
		local d = Geometry.distance(hitX, hitZ, obstacle.x, obstacle.z)
			- obstacle.radius
			- bodyRadius
		if d < nearestDistance then
			nearestDistance = d
			nearest = obstacle
		end
	end
	if nearest == nil then
		-- The edge: slide along it.
		local nx, nz = Geometry.normalize(x, z)
		local tx, tz = -nz, nx
		if tx * ux + tz * uz < 0 then
			tx, tz = -tx, -tz
		end
		return tx, tz
	end
	local obstacle = nearest :: Types.Obstacle
	-- Tangent of the obstacle's circle at the body, on the side the target lies.
	local nx, nz = Geometry.normalize(x - obstacle.x, z - obstacle.z)
	local tx, tz = -nz, nx
	if tx * ux + tz * uz < 0 then
		tx, tz = -tx, -tz
	end
	-- Lean outward when too close, so the body clears the obstacle by `margin`.
	local gap = Geometry.distance(x, z, obstacle.x, obstacle.z) - obstacle.radius - bodyRadius
	if gap < margin then
		local lean = (margin - gap) / margin
		tx += nx * lean
		tz += nz * lean
	end
	return Geometry.normalize(tx, tz)
end

-- A free spot for a body near (x, z): the point itself when nothing blocks it,
-- else a random nearby one within `tries` draws, else the point pushed out of
-- the obstacle it overlaps.
function Arena.freeSpot(
	arena: Types.Arena,
	x: number,
	z: number,
	bodyRadius: number,
	rng: Types.Rng,
	tries: number
): (number, number)
	x, z = Arena.clamp(arena, x, z, bodyRadius)
	local blocker = Arena.blocking(arena, x, z, bodyRadius)
	if blocker == nil then
		return x, z
	end
	for attempt = 1, tries do
		local spread = (blocker.radius + bodyRadius) * (1 + attempt * 0.5)
		local angle = rng:next() * 2 * math.pi
		local cx, cz = Arena.clamp(
			arena,
			x + math.cos(angle) * spread,
			z + math.sin(angle) * spread,
			bodyRadius
		)
		if Arena.blocking(arena, cx, cz, bodyRadius) == nil then
			return cx, cz
		end
	end
	local nx, nz = Geometry.normalize(x - blocker.x, z - blocker.z)
	local push = blocker.radius + bodyRadius + 0.1
	return Arena.clamp(arena, blocker.x + nx * push, blocker.z + nz * push, bodyRadius)
end

return Arena
