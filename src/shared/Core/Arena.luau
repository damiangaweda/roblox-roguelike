--!strict
-- The map's ground (ADR-0014): a round, flat arena closed by its edge, with
-- obstacles composed anew for every run from the seed (stage 3b): places with
-- their kits on clearings, paths of open ground from the start to each, groves
-- dense at their core and thin at their edge, pines in the north and oaks in
-- the south, and sparse leftovers. Obstacles are circles that block the
-- movement of players and enemies and nothing else, so the queries here are
-- the only collision the core has. Given the terrain's config (stage 3d,
-- ADR-0023), the plateaus' cliffs and the stream's channel are obstacles too,
-- and the shallows are slow zones.

local Geometry = require("./Geometry")
local Terrain = require("./Terrain")
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
-- A path's pad reaches this far beyond the path's width.
local PATH_PAD_MARGIN = 2
-- The slow zones' lookup grid: a cell's side, not a gameplay number.
local SLOW_CELL = 32

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
	-- The terrain (stage 3d), when its config is given: the plateaus, the
	-- plateau each lair on one stands on (by place id), the stream's centre
	-- line, and the circles props keep off (the ramps' mouths).
	terrain: Types.TerrainConfig?,
	plateaus: { Types.Plateau },
	lairPlateaus: { [number]: Types.Plateau },
	streamPoints: { Terrain.Point }?,
	keepClear: { Circle },
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
local randomInDisc = Terrain.randomInDisc

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
		for _, clear in layout.keepClear do
			if
				Geometry.distance(circle.x, circle.z, clear.x, clear.z)
				< clear.radius + circle.radius
			then
				return false
			end
		end
		local terrain, points = layout.terrain, layout.streamPoints
		if
			terrain
			and points
			and Terrain.lineDistance(points, circle.x, circle.z)
				< terrain.channelHalfWidth + terrain.bankWidth + circle.radius
		then
			return false
		end
	end
	return true
end

-- Whether a clearing of `radius` at (x, z) keeps off every plateau and its cliffs.
local function offPlateaus(layout: Layout, x: number, z: number, radius: number): boolean
	local terrain = layout.terrain
	if terrain == nil then
		return true
	end
	for _, plateau in layout.plateaus do
		if
			Geometry.distance(x, z, plateau.x, plateau.z)
			<= plateau.radius + terrain.cliffRadius + radius
		then
			return false
		end
	end
	return true
end

-- Where the path to a lair on `plateau` ends: the foot of its first ramp.
local function rampEnd(terrain: Types.TerrainConfig, plateau: Types.Plateau): (number, number)
	return Terrain.rampFoot(plateau, plateau.ramps[1], terrain.rampWidth)
end

-- Whether the straight way from the start to (x, z) keeps off every plateau
-- by its cliffs, a path's width and its sway; `own`, the plateau a lair's
-- path climbs, only by its cliffs and a path's width, since the path ends at
-- its ramp's foot where the sway is spent.
local function pathOffPlateaus(layout: Layout, x: number, z: number, own: Types.Plateau?): boolean
	local terrain = layout.terrain
	if terrain == nil then
		return true
	end
	local map = layout.map
	for _, plateau in layout.plateaus do
		local clear = plateau.radius + terrain.cliffRadius + map.pathWidth
		if plateau ~= own then
			clear += map.pathSway
		end
		if segmentDistance(plateau.x, plateau.z, 0, 0, x, z) < clear then
			return false
		end
	end
	return true
end

-- Adds terrain circles of `kind` as one group, the first the anchor: not a
-- prop, so neither turned, scaled nor leaned.
local function addTerrainGroup(layout: Layout, kind: string, circles: { Circle })
	layout.groups += 1
	for order, circle in circles do
		table.insert(layout.obstacles, {
			id = #layout.obstacles + 1,
			kind = kind,
			x = circle.x,
			z = circle.z,
			radius = circle.radius,
			rotation = 0,
			group = layout.groups,
			anchor = order == 1,
			scale = 1,
			lean = 0,
		})
	end
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
		or not offPlateaus(layout, x, z, radius)
		or not pathOffPlateaus(layout, x, z, nil)
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

-- A kit of props around (x, z), every offset and rotation turned by `rotation`.
local function addKit(
	layout: Layout,
	rng: Types.Rng,
	props: { Types.PlaceProp },
	x: number,
	z: number,
	rotation: number
)
	for _, prop in props do
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
				addKit(layout, rng, kind.props, x, z, rotation)
				break
			end
		end
	end
end

-- Whether a lair's clearing of `radius` at (x, z) keeps the lairs' distances
-- (ADR-0021): from the start, the chest and the other lairs, inside the edge,
-- with its path from the start clear of their clearings and theirs of its own,
-- and of the plateaus: a lair on `own` is reached at the foot of its ramp.
local function lairFits(
	layout: Layout,
	lairs: Types.LairsConfig,
	x: number,
	z: number,
	radius: number,
	own: Types.Plateau?
): boolean
	local map = layout.map
	local reach = map.pathWidth + map.pathSway
	local endX, endZ = x, z
	local terrain = layout.terrain
	if own and terrain then
		endX, endZ = rampEnd(terrain, own)
	end
	if
		Geometry.distance(x, z, 0, 0) < lairs.startMinDistance
		or Geometry.distance(x, z, 0, 0) + radius > layout.inner
		or Geometry.distance(x, z, layout.chestX, layout.chestZ) < lairs.chestMinDistance
		or not pathOffPlateaus(layout, endX, endZ, own)
	then
		return false
	end
	for _, other in layout.places do
		if
			Geometry.distance(x, z, other.x, other.z) < lairs.spacing
			or segmentDistance(other.x, other.z, 0, 0, x, z) < other.radius + reach
			or segmentDistance(x, z, 0, 0, other.x, other.z) < radius + reach
		then
			return false
		end
	end
	return true
end

-- Records a lair at (x, z) as a place and a spot, turned at random, with its kit.
local function addLair(
	layout: Layout,
	rng: Types.Rng,
	spots: { Types.LairSpot },
	kind: Types.LairKindConfig,
	x: number,
	z: number
): Types.Place
	local rotation = rng:next() * 2 * math.pi
	local place: Types.Place = {
		id = #layout.places + 1,
		kind = kind.id,
		x = x,
		z = z,
		radius = kind.clearRadius,
		rotation = rotation,
	}
	table.insert(layout.places, place)
	table.insert(spots, { kind = kind.id, x = x, z = z, rotation = rotation })
	addKit(layout, rng, kind.props, x, z, rotation)
	return place
end

-- The free plateau a lair of `kind` may stand on, drawn among those whose top
-- holds its clearing and whose centre keeps the lairs' distances; nil if none.
local function plateauFor(
	layout: Layout,
	rng: Types.Rng,
	lairs: Types.LairsConfig,
	kind: Types.LairKindConfig,
	terrain: Types.TerrainConfig
): Types.Plateau?
	local taken: { [Types.Plateau]: boolean } = {}
	for _, plateau in layout.lairPlateaus do
		taken[plateau] = true
	end
	local candidates: { Types.Plateau } = {}
	for _, plateau in layout.plateaus do
		if
			not taken[plateau]
			and plateau.radius >= kind.clearRadius + terrain.cliffRadius
			and lairFits(layout, lairs, plateau.x, plateau.z, kind.clearRadius, plateau)
		then
			table.insert(candidates, plateau)
		end
	end
	if #candidates == 0 then
		return nil
	end
	return candidates[rng:integer(1, #candidates)]
end

-- The lairs (ADR-0021): config.lairs.count kinds drawn without replacement,
-- each placed within placementAttempts draws (else skipped) and turned at
-- random. A lair is also a place, its clearing the kind's clearRadius, so
-- the paths lead to it, the groves keep off it and the ordinary places keep
-- placeSpacing from it; its kit becomes obstacle groups like a place's.
-- Given the terrain, the first lairsOnPlateauMin..Max of them (a count drawn
-- first) stand at a plateau's centre, their kits on its top, when one fits;
-- the rest keep off the plateaus.
local function composeLairs(
	layout: Layout,
	rng: Types.Rng,
	lairs: Types.LairsConfig
): { Types.LairSpot }
	local map = layout.map
	local terrain = layout.terrain
	local onPlateaus = if terrain and #layout.plateaus > 0
		then rng:integer(terrain.lairsOnPlateauMin, terrain.lairsOnPlateauMax)
		else 0
	local pool = table.clone(lairs.kinds)
	local spots: { Types.LairSpot } = {}
	for index = 1, math.min(lairs.count, #pool) do
		local kind = table.remove(pool, rng:integer(1, #pool)) :: Types.LairKindConfig
		if terrain and index <= onPlateaus then
			local plateau = plateauFor(layout, rng, lairs, kind, terrain)
			if plateau then
				local place = addLair(layout, rng, spots, kind, plateau.x, plateau.z)
				layout.lairPlateaus[place.id] = plateau
				continue
			end
		end
		for _ = 1, map.placementAttempts do
			local x, z = randomInDisc(rng, layout.inner - kind.clearRadius)
			if
				lairFits(layout, lairs, x, z, kind.clearRadius)
				and offPlateaus(layout, x, z, kind.clearRadius)
			then
				addLair(layout, rng, spots, kind, x, z)
				break
			end
		end
	end
	return spots
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
-- chest, the other spots, every obstacle circle and every slow zone. A spot
-- that finds no room within placementAttempts draws is skipped.
local function scatterShrines(
	map: Types.MapConfig,
	shrines: Types.ShrinesConfig,
	rng: Types.Rng,
	obstacles: { Types.Obstacle },
	slowZones: { Types.SlowZone },
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
				for _, zone in slowZones do
					if Geometry.distance(x, z, zone.x, zone.z) < zone.radius + shrines.radius then
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

-- The plateaus with their cliff rings, one obstacle group each; the first
-- lairsOnPlateauMax draw a radius whose top holds the widest lair's clearing.
local function composePlateaus(
	layout: Layout,
	rng: Types.Rng,
	terrain: Types.TerrainConfig,
	lairs: Types.LairsConfig?
)
	local map = layout.map
	local widest = 0
	if lairs then
		for _, kind in lairs.kinds do
			widest = math.max(widest, kind.clearRadius)
		end
	end
	layout.plateaus = Terrain.plateaus(terrain, rng, {
		inner = layout.inner,
		chestX = layout.chestX,
		chestZ = layout.chestZ,
		chestClear = map.chestClearRadius + map.obstacleSpacing,
		attempts = map.placementAttempts,
		bigCount = if lairs then terrain.lairsOnPlateauMax else 0,
		bigRadius = widest + terrain.cliffRadius,
	})
	for _, plateau in layout.plateaus do
		addTerrainGroup(layout, "cliff", Terrain.cliffRing(terrain, plateau))
		-- A ramp's mouth and foot stay free of props.
		for _, ramp in plateau.ramps do
			for _, reach in { 0, terrain.rampWidth } do
				local x, z = Terrain.rampFoot(plateau, ramp, reach)
				table.insert(layout.keepClear, { x = x, z = z, radius = terrain.rampWidth })
			end
		end
	end
end

-- The stream, kept out of the start's, the chest's, every place's and lair's
-- clearing, every plateau with its cliffs and every ramp's mouth and foot;
-- its channel one obstacle group.
local function composeStream(
	layout: Layout,
	rng: Types.Rng,
	terrain: Types.TerrainConfig
): Types.Stream
	local map = layout.map
	local clearings: { Circle } = {
		{ x = 0, z = 0, radius = map.startClearRadius },
		{ x = layout.chestX, z = layout.chestZ, radius = map.chestClearRadius },
	}
	for _, place in layout.places do
		table.insert(clearings, { x = place.x, z = place.z, radius = place.radius })
	end
	for _, plateau in layout.plateaus do
		table.insert(clearings, {
			x = plateau.x,
			z = plateau.z,
			radius = plateau.radius + terrain.cliffRadius,
		})
	end
	-- The ramps' mouths and feet: a stream there would seal the plateau.
	for _, clear in layout.keepClear do
		table.insert(clearings, clear)
	end
	local stream = Terrain.stream(terrain, rng, map.radius, clearings, map.placementAttempts)
	layout.streamPoints = stream.points
	addTerrainGroup(layout, "channel", Terrain.channel(stream))
	return stream
end

-- Whether a disc at (x, z) touches the water or a plateau's ring.
local function onRelief(
	terrain: Types.TerrainConfig,
	plateaus: { Types.Plateau },
	slowZones: { Types.SlowZone },
	x: number,
	z: number,
	radius: number
): boolean
	for _, plateau in plateaus do
		if
			Geometry.distance(x, z, plateau.x, plateau.z)
			< plateau.radius + terrain.cliffRadius + radius
		then
			return true
		end
	end
	for _, zone in slowZones do
		if Geometry.distance(x, z, zone.x, zone.z) < zone.radius + radius then
			return true
		end
	end
	return false
end

-- The ponds and slow zones, then the pads: the start, the chest, every place
-- and lair, every path point off the water and the plateaus, every plateau top.
local function describeTerrain(
	layout: Layout,
	terrain: Types.TerrainConfig,
	stream: Types.Stream
): Types.Terrain
	local map = layout.map
	local slowZones = Terrain.shallows(stream)
	local ponds: { Types.Pond } = {}
	for _, obstacle in layout.obstacles do
		if obstacle.kind == "pond" then
			table.insert(ponds, {
				x = obstacle.x,
				z = obstacle.z,
				radius = obstacle.radius,
				rimWidth = terrain.pondRimWidth,
			})
			table.insert(slowZones, {
				x = obstacle.x,
				z = obstacle.z,
				radius = obstacle.radius + terrain.pondRimWidth,
			})
		end
	end
	local pads: { Types.Pad } = {
		{ x = 0, z = 0, radius = map.startClearRadius },
		{ x = layout.chestX, z = layout.chestZ, radius = map.chestClearRadius },
	}
	for _, place in layout.places do
		table.insert(pads, { x = place.x, z = place.z, radius = place.radius })
	end
	local padRadius = map.pathWidth + PATH_PAD_MARGIN
	for _, path in layout.paths do
		for _, point in path do
			if not onRelief(terrain, layout.plateaus, slowZones, point.x, point.z, padRadius) then
				table.insert(pads, { x = point.x, z = point.z, radius = padRadius })
			end
		end
	end
	for _, plateau in layout.plateaus do
		table.insert(
			pads,
			{ x = plateau.x, z = plateau.z, radius = plateau.radius - terrain.cliffRadius }
		)
	end
	return {
		plateaus = layout.plateaus,
		stream = stream,
		ponds = ponds,
		slowZones = slowZones,
		pads = pads,
	}
end

-- Composes the map for a seed: places the chest, then, given the terrain's
-- config, the plateaus with their cliffs; given the lairs' config, the lairs
-- with their kits (some on the plateaus); the places with theirs, a path to
-- each, the stream with its channel, the groves and the leftovers, the ponds,
-- slow zones and pads, and, given the shrines' config, the shrines' spots;
-- the start is the centre. A prop takes one circle per footprint entry, all
-- of one `group`, the first the anchor the builder draws the prop at.
-- Repeatable for a seed: the rng is the run's, consumed in a fixed order.
function Arena.generate(
	map: Types.MapConfig,
	rng: Types.Rng,
	shrines: Types.ShrinesConfig?,
	lairs: Types.LairsConfig?,
	terrain: Types.TerrainConfig?
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
		terrain = terrain,
		plateaus = {},
		lairPlateaus = {},
		streamPoints = nil,
		keepClear = {},
	}
	if terrain then
		composePlateaus(layout, rng, terrain, lairs)
	end
	local lairSpots = if lairs then composeLairs(layout, rng, lairs) else {}
	composePlaces(layout, rng)
	for _, place in layout.places do
		local plateau = layout.lairPlateaus[place.id]
		if plateau and terrain then
			-- A lair on a plateau is reached by its first ramp: the path ends at its foot.
			local x, z = rampEnd(terrain, plateau)
			local foot =
				{ id = place.id, kind = place.kind, x = x, z = z, radius = 0, rotation = 0 }
			table.insert(layout.paths, pathTo(map, rng, foot))
		else
			table.insert(layout.paths, pathTo(map, rng, place))
		end
	end
	local stream = if terrain then composeStream(layout, rng, terrain) else nil
	local groves = composeGroves(layout, rng)
	composeLeftovers(layout, rng, groves)
	local described: Types.Terrain = if terrain and stream
		then describeTerrain(layout, terrain, stream)
		else { plateaus = {}, stream = nil, ponds = {}, slowZones = {}, pads = {} }

	return {
		radius = map.radius,
		obstacles = layout.obstacles,
		startX = 0,
		startZ = 0,
		chestX = chestX,
		chestZ = chestZ,
		shrineSpots = if shrines
			then scatterShrines(
				map,
				shrines,
				rng,
				layout.obstacles,
				described.slowZones,
				chestX,
				chestZ
			)
			else {},
		lairSpots = lairSpots,
		terrain = described,
		places = layout.places,
		paths = layout.paths,
	}
end

type SlowGrid = { count: number, cells: { [number]: { Types.SlowZone } } }

-- The slow zones by grid cell, built once per zone list (and again when its
-- length changes): a zone sits in every cell its square touches.
local slowGrids: { [{ Types.SlowZone }]: SlowGrid } = setmetatable({}, { __mode = "k" }) :: any

local function cellKey(cx: number, cz: number): number
	return (cx + 32768) * 65536 + (cz + 32768)
end

local function slowGridOf(zones: { Types.SlowZone }): SlowGrid
	local grid = slowGrids[zones]
	if grid and grid.count == #zones then
		return grid
	end
	local cells: { [number]: { Types.SlowZone } } = {}
	for _, zone in zones do
		for cx = math.floor((zone.x - zone.radius) / SLOW_CELL), math.floor((zone.x + zone.radius) / SLOW_CELL) do
			for cz = math.floor((zone.z - zone.radius) / SLOW_CELL), math.floor((zone.z + zone.radius) / SLOW_CELL) do
				local key = cellKey(cx, cz)
				local list = cells[key]
				if list == nil then
					list = {}
					cells[key] = list
				end
				table.insert(list, zone)
			end
		end
	end
	local built: SlowGrid = { count = #zones, cells = cells }
	slowGrids[zones] = built
	return built
end

-- The share of its speed a body at (x, z) keeps: shallowFactor in any slow
-- zone (the stream's shallows, a pond's rim), else 1 (ADR-0023).
function Arena.slowFactor(
	arena: Types.Arena,
	config: Types.TerrainConfig,
	x: number,
	z: number
): number
	local zones = arena.terrain.slowZones
	if #zones == 0 then
		return 1
	end
	local list =
		slowGridOf(zones).cells[cellKey(math.floor(x / SLOW_CELL), math.floor(z / SLOW_CELL))]
	if list then
		for _, zone in list do
			local dx, dz = x - zone.x, z - zone.z
			if dx * dx + dz * dz < zone.radius * zone.radius then
				return config.shallowFactor
			end
		end
	end
	return 1
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

-- The obstacle kinds of the terrain (ADR-0023): what even a leap cannot pass.
local TERRAIN_KINDS: { [string]: boolean } = { cliff = true, channel = true }

local function reachPast(
	arena: Types.Arena,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	bodyRadius: number,
	terrainOnly: boolean
): number
	local dx, dz = toX - fromX, toZ - fromZ
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-9 then
		return 0
	end
	local ux, uz = dx / length, dz / length
	local best = length

	for _, obstacle in arena.obstacles do
		if terrainOnly and not TERRAIN_KINDS[obstacle.kind] then
			continue
		end
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
	return reachPast(arena, fromX, fromZ, toX, toZ, bodyRadius, false)
end

-- How far a body flying over the props (a leap) travels along the segment
-- before a cliff, the channel or the edge holds it, as Arena.reach.
function Arena.flight(
	arena: Types.Arena,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number,
	bodyRadius: number
): number
	return reachPast(arena, fromX, fromZ, toX, toZ, bodyRadius, true)
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
