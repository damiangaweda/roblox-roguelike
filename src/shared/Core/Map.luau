--!strict
-- The map of a run (ADR-0012): an open square of terrain with hand-made
-- points joined by straight paths, generated from a seed, and the queries the
-- other modules ask of it. The rules stay on the (x, z) plane; heights only
-- decide where water is, and are kept for the adapters to draw.

local Geometry = require("./Geometry")
local Types = require("./Types")

local Map = {}

-- How far beyond a prop's edge a position pushed out of it lands.
local PUSH_MARGIN = 1e-3
-- A walker this close to its nearest point's centre counts as standing on it.
local CENTRE_TOLERANCE = 1
-- The headings local steering tries when the straight line is blocked, in
-- degrees turned from the direct one, smaller turns first.
local STEER_TURNS = { 30, -30, 60, -60, 90, -90, 120, -120, 150, -150 }
-- The directions sampled on each ring around an unwalkable position.
local CLAMP_DIRECTIONS = 8
-- How far out from a prop's corner, on both axes, a walk round it turns.
local CORNER_MARGIN = 1

type Centre = { x: number, z: number }
type Edge = { a: number, b: number, length: number }

local function distanceToSegment(
	x: number,
	z: number,
	ax: number,
	az: number,
	bx: number,
	bz: number
): number
	local dx, dz = bx - ax, bz - az
	local lengthSquared = dx * dx + dz * dz
	local t = 0
	if lengthSquared > 1e-12 then
		t = math.clamp(((x - ax) * dx + (z - az) * dz) / lengthSquared, 0, 1)
	end
	return Geometry.distance(x, z, ax + dx * t, az + dz * t)
end

-- Whether segments p1-p2 and q1-q2 cross or touch.
local function segmentsMeet(
	p1x: number,
	p1z: number,
	p2x: number,
	p2z: number,
	q1x: number,
	q1z: number,
	q2x: number,
	q2z: number
): boolean
	local function side(ax: number, az: number, bx: number, bz: number, cx: number, cz: number)
		return (bx - ax) * (cz - az) - (bz - az) * (cx - ax)
	end
	local d1 = side(q1x, q1z, q2x, q2z, p1x, p1z)
	local d2 = side(q1x, q1z, q2x, q2z, p2x, p2z)
	local d3 = side(p1x, p1z, p2x, p2z, q1x, q1z)
	local d4 = side(p1x, p1z, p2x, p2z, q2x, q2z)
	return d1 * d2 <= 0 and d3 * d4 <= 0
end

-- The distance between a segment and a rect; 0 when they meet.
local function segmentToRect(
	rect: Types.Rect,
	ax: number,
	az: number,
	bx: number,
	bz: number
): number
	if Geometry.insideRect(rect, ax, az) or Geometry.insideRect(rect, bx, bz) then
		return 0
	end
	local x0, x1 = rect.x - rect.halfWidth, rect.x + rect.halfWidth
	local z0, z1 = rect.z - rect.halfDepth, rect.z + rect.halfDepth
	local corners = { { x0, z0 }, { x1, z0 }, { x1, z1 }, { x0, z1 } }
	local best = math.huge
	for index, corner in corners do
		local nextCorner = corners[index % 4 + 1]
		if segmentsMeet(ax, az, bx, bz, corner[1], corner[2], nextCorner[1], nextCorner[2]) then
			return 0
		end
		best = math.min(best, distanceToSegment(corner[1], corner[2], ax, az, bx, bz))
	end
	for _, endpoint in { { ax, az }, { bx, bz } } do
		local cx, cz = Geometry.clampToRect(rect, endpoint[1], endpoint[2])
		best = math.min(best, Geometry.distance(endpoint[1], endpoint[2], cx, cz))
	end
	return best
end

local function nearestCentre(centres: { Centre }, x: number, z: number): number
	local nearest = math.huge
	for _, centre in centres do
		nearest = math.min(nearest, Geometry.distance(x, z, centre.x, centre.z))
	end
	return nearest
end

-- Entries on the edge band, as far apart as minEntrySpacing asks, and
-- whether they all are: placing stops at the first entry for which no
-- candidate out of placementAttempts is far enough.
local function placeEntries(
	settings: Types.MapConfig,
	rng: Types.Rng,
	half: number,
	count: number
): ({ Centre }, boolean)
	local entries: { Centre } = {}
	local inner = half - settings.edgeMargin
	while #entries < count do
		local placed = false
		for _ = 1, settings.placementAttempts do
			local along = -inner + rng:next() * 2 * inner
			local inset = inner - rng:next() * settings.entryBand
			local side = rng:integer(1, 4)
			local candidate: Centre
			if side == 1 then
				candidate = { x = along, z = -inset }
			elseif side == 2 then
				candidate = { x = along, z = inset }
			elseif side == 3 then
				candidate = { x = -inset, z = along }
			else
				candidate = { x = inset, z = along }
			end
			if nearestCentre(entries, candidate.x, candidate.z) >= settings.minEntrySpacing then
				table.insert(entries, candidate)
				placed = true
				break
			end
		end
		if not placed then
			return entries, false
		end
	end
	return entries, true
end

-- Adds point centres inside the margin until there are `count`: each is the
-- candidate farthest from the others out of a batch of placementAttempts,
-- taken when it is at least pointSpacing away. Gives up after
-- placementAttempts batches without one.
local function placePoints(
	settings: Types.MapConfig,
	rng: Types.Rng,
	half: number,
	centres: { Centre },
	count: number
)
	local inner = half - settings.edgeMargin
	while #centres < count do
		local placed = false
		for _ = 1, settings.placementAttempts do
			local bestX, bestZ, bestDistance = 0, 0, -1
			for _ = 1, settings.placementAttempts do
				local x = -inner + rng:next() * 2 * inner
				local z = -inner + rng:next() * 2 * inner
				local apart = nearestCentre(centres, x, z)
				if apart > bestDistance then
					bestX, bestZ, bestDistance = x, z, apart
				end
			end
			if bestDistance >= settings.pointSpacing then
				table.insert(centres, { x = bestX, z = bestZ })
				placed = true
				break
			end
		end
		if not placed then
			break
		end
	end
end

-- The relative neighbourhood graph: a-b is an edge when no third point is
-- closer to both of them than they are to each other. Edges in order of a,
-- then b, with a < b.
local function neighbourGraph(centres: { Centre }): { Edge }
	local edges: { Edge } = {}
	for a = 1, #centres do
		for b = a + 1, #centres do
			local length = Geometry.distance(centres[a].x, centres[a].z, centres[b].x, centres[b].z)
			local blocked = false
			for c = 1, #centres do
				if c ~= a and c ~= b then
					local ac =
						Geometry.distance(centres[a].x, centres[a].z, centres[c].x, centres[c].z)
					local bc =
						Geometry.distance(centres[b].x, centres[b].z, centres[c].x, centres[c].z)
					if math.max(ac, bc) < length then
						blocked = true
						break
					end
				end
			end
			if not blocked then
				table.insert(edges, { a = a, b = b, length = length })
			end
		end
	end
	return edges
end

-- Which edges form the minimum spanning tree (Kruskal); ties by edge order.
local function spanningTree(count: number, edges: { Edge }): { boolean }
	local order: { number } = {}
	for index = 1, #edges do
		order[index] = index
	end
	table.sort(order, function(i, j)
		if edges[i].length ~= edges[j].length then
			return edges[i].length < edges[j].length
		end
		return i < j
	end)
	local root: { number } = {}
	for id = 1, count do
		root[id] = id
	end
	local function find(id: number): number
		while root[id] ~= id do
			root[id] = root[root[id]]
			id = root[id]
		end
		return id
	end
	local inTree: { boolean } = table.create(#edges, false)
	for _, index in order do
		local ra, rb = find(edges[index].a), find(edges[index].b)
		if ra ~= rb then
			root[ra] = rb
			inTree[index] = true
		end
	end
	return inTree
end

-- Breadth-first hops from `source` to every point.
local function bfs(points: { Types.MapPoint }, source: number): ({ number }, { number })
	local hops: { number } = table.create(#points, math.huge)
	local parent: { number } = table.create(#points, 0)
	hops[source] = 0
	parent[source] = source
	local queue = { source }
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head += 1
		for _, neighbour in points[current].neighbours do
			if hops[neighbour] == math.huge then
				hops[neighbour] = hops[current] + 1
				parent[neighbour] = current
				table.insert(queue, neighbour)
			end
		end
	end
	return hops, parent
end

-- Points far from the entries and from each other, none an entry. Only the
-- points at least zoneMinDistanceFraction of the farthest distance away are
-- considered while there are enough of them, since on a long chain of points
-- the spread alone would pull a zone close to the entries.
local function chooseZonePoints(
	config: Types.Config,
	points: { Types.MapPoint },
	hops: { { number } },
	count: number
): { number }
	local farthest = 0
	for _, point in points do
		farthest = math.max(farthest, point.distance)
	end
	local nearest = farthest * config.map.zoneMinDistanceFraction
	local far = 0
	for _, point in points do
		if not point.isEntry and point.distance >= nearest then
			far += 1
		end
	end
	if far < count then
		nearest = 0
	end

	local zones: { number } = {}
	while #zones < count do
		local best, bestScore = nil, -1
		for _, point in points do
			if point.isEntry or point.distance < nearest or table.find(zones, point.id) then
				continue
			end
			local apart = math.huge
			for _, zone in zones do
				apart = math.min(apart, hops[point.id][zone])
			end
			if apart == math.huge then
				apart = 0
			end
			local score = point.distance * config.map.zoneDistanceWeight + apart
			if score > bestScore then
				best, bestScore = point.id, score
			end
		end
		if best == nil then
			break
		end
		table.insert(zones, best)
	end
	return zones
end

local function smoothstep(t: number): number
	return t * t * (3 - 2 * t)
end

-- Value noise: random heights in [0, maxHeight] on a lattice of about one
-- hill per 1 / hillFrequency studs, blended smoothly onto the grid.
local function noiseHeights(
	settings: Types.MapConfig,
	rng: Types.Rng,
	half: number,
	size: number
): { { number } }
	local step = 1 / settings.hillFrequency
	local latticeSize = math.ceil(2 * half / step) + 2
	local lattice: { { number } } = {}
	for row = 1, latticeSize do
		lattice[row] = {}
		for col = 1, latticeSize do
			lattice[row][col] = rng:next() * settings.maxHeight
		end
	end
	local heights: { { number } } = {}
	for row = 1, size do
		local v = (row - 1) * settings.heightCell / step
		local lr = math.floor(v)
		local fz = smoothstep(v - lr)
		local line = table.create(size, 0)
		for col = 1, size do
			local u = (col - 1) * settings.heightCell / step
			local lc = math.floor(u)
			local fx = smoothstep(u - lc)
			local low = lattice[lr + 1][lc + 1] * (1 - fx) + lattice[lr + 1][lc + 2] * fx
			local high = lattice[lr + 2][lc + 1] * (1 - fx) + lattice[lr + 2][lc + 2] * fx
			line[col] = low * (1 - fz) + high * fz
		end
		heights[row] = line
	end
	return heights
end

-- Calls `visit(row, col, x, z)` for every grid node within `margin` of the
-- box [minX, maxX] x [minZ, maxZ].
local function eachNodeNear(
	half: number,
	cell: number,
	size: number,
	minX: number,
	maxX: number,
	minZ: number,
	maxZ: number,
	margin: number,
	visit: (row: number, col: number, x: number, z: number) -> ()
)
	local col0 = math.max(1, math.floor((minX - margin + half) / cell) + 1)
	local col1 = math.min(size, math.ceil((maxX + margin + half) / cell) + 1)
	local row0 = math.max(1, math.floor((minZ - margin + half) / cell) + 1)
	local row1 = math.min(size, math.ceil((maxZ + margin + half) / cell) + 1)
	for row = row0, row1 do
		for col = col0, col1 do
			visit(row, col, -half + (col - 1) * cell, -half + (row - 1) * cell)
		end
	end
end

function Map.generate(config: Types.Config, rng: Types.Rng, playerCount: number): Types.Map
	local settings = config.map
	local players = math.max(1, playerCount)
	local half = math.clamp(settings.studsPerPlayer * players, settings.minHalf, settings.maxHalf)
	local pointCount =
		math.clamp(settings.pointsPerPlayer * players, settings.minPoints, settings.maxPoints)
	local entryCount =
		math.clamp(math.ceil(players / settings.playersPerEntry), 1, settings.maxEntries)

	-- A layout whose entries are too close, or that ends short of the count,
	-- is drawn again; the fullest one drawn is kept. A map that still cannot
	-- be laid out is a configuration error: a run on it would be broken.
	local centres: { Centre } = {}
	local spaced = false
	for _ = 1, settings.placementAttempts do
		local layout, ok = placeEntries(settings, rng, half, entryCount)
		if not ok then
			continue
		end
		spaced = true
		placePoints(settings, rng, half, layout, pointCount)
		if #layout > #centres then
			centres = layout
		end
		if #centres >= pointCount then
			break
		end
	end
	if not spaced then
		error(
			string.format(
				"Map.generate: %d entries do not fit %d studs apart on a map %d studs wide "
					.. "after %d layouts; check minEntrySpacing",
				entryCount,
				settings.minEntrySpacing,
				2 * half,
				settings.placementAttempts
			)
		)
	end
	if #centres < settings.minPoints then
		error(
			string.format(
				"Map.generate: only %d of at least %d points fit %d studs apart on a map %d "
					.. "studs wide after %d layouts; check pointSpacing and edgeMargin",
				#centres,
				settings.minPoints,
				settings.pointSpacing,
				2 * half,
				settings.placementAttempts
			)
		)
	end

	local points: { Types.MapPoint } = {}
	local entries: { number } = {}
	for id, centre in centres do
		local isEntry = id <= entryCount
		local template = if isEntry
			then settings.entryTemplate
			else settings.templates[rng:integer(1, #settings.templates)]
		local cover: { Types.Point } = {}
		for _, spot in template.cover do
			table.insert(cover, { x = centre.x + spot.x, z = centre.z + spot.z })
		end
		local props: { Types.Rect } = {}
		for _, prop in template.props do
			table.insert(props, {
				x = centre.x + prop.x,
				z = centre.z + prop.z,
				halfWidth = prop.halfWidth,
				halfDepth = prop.halfDepth,
			})
		end
		local camp = template.camp
		points[id] = {
			id = id,
			x = centre.x,
			z = centre.z,
			template = template.id,
			radius = template.radius,
			paths = {},
			neighbours = {},
			distance = 0,
			level = 1,
			isEntry = isEntry,
			hasZone = false,
			campX = if camp then centre.x + camp.x else nil,
			campZ = if camp then centre.z + camp.z else nil,
			cover = cover,
			props = props,
		}
		if isEntry then
			table.insert(entries, id)
		end
	end

	-- Paths: the spanning tree of the neighbour graph, and each other edge of
	-- it by chance.
	local edges = neighbourGraph(centres)
	local inTree = spanningTree(#points, edges)
	local paths: { Types.Path } = {}
	for index, edge in edges do
		if inTree[index] or rng:next() < settings.extraLinkChance then
			local path: Types.Path =
				{ id = #paths + 1, a = edge.a, b = edge.b, halfWidth = settings.pathHalfWidth }
			table.insert(paths, path)
			local a, b = points[edge.a], points[edge.b]
			table.insert(a.paths, path.id)
			table.insert(a.neighbours, b.id)
			table.insert(b.paths, path.id)
			table.insert(b.neighbours, a.id)
		end
	end

	-- A prop a path band would cross is left out, so a path is clear from
	-- centre to centre.
	for _, path in paths do
		local a, b = points[path.a], points[path.b]
		for _, point in { a, b } do
			local kept: { Types.Rect } = {}
			for _, prop in point.props do
				if segmentToRect(prop, a.x, a.z, b.x, b.z) > path.halfWidth then
					table.insert(kept, prop)
				end
			end
			point.props = kept
		end
	end

	-- Routing tables: the BFS tree rooted at `to` gives every point's next hop.
	local nextHop: { { number } } = {}
	local hops: { { number } } = {}
	for id = 1, #points do
		nextHop[id] = table.create(#points, 0)
		hops[id] = table.create(#points, 0)
	end
	for to = 1, #points do
		local distances, parent = bfs(points, to)
		for from = 1, #points do
			nextHop[from][to] = parent[from]
			hops[from][to] = distances[from]
		end
	end

	local farthest = 0
	for _, point in points do
		local nearest = math.huge
		for _, entry in entries do
			nearest = math.min(nearest, hops[point.id][entry])
		end
		point.distance = nearest
		farthest = math.max(farthest, nearest)
	end
	for _, point in points do
		if point.distance == 0 then
			point.level = 1
		else
			point.level = math.clamp(
				math.ceil(point.distance / farthest * settings.maxLevel),
				1,
				settings.maxLevel
			)
		end
	end

	local zoneCount = math.clamp(
		math.ceil(players / settings.playersPerZone),
		settings.minZones,
		settings.maxZones
	)
	local zonePoints =
		chooseZonePoints(config, points, hops, math.min(zoneCount, #points - #entries))
	for _, id in zonePoints do
		points[id].hasZone = true
	end

	-- Terrain: hills, then every node under a path band or near a footprint
	-- raised dryMargin above the water, then each footprint flattened to the mean of
	-- its nodes. The margin of one cell's diagonal keeps every cell a band or
	-- a disc touches above the water too.
	local cell = settings.heightCell
	local size = math.ceil(2 * half / cell) + 1
	local heights = noiseHeights(settings, rng, half, size)
	local dry = settings.waterLevel + settings.dryMargin
	local diagonal = cell * math.sqrt(2)

	local flat: { number } = {}
	for _, point in points do
		local total, nodes = 0, 0
		eachNodeNear(
			half,
			cell,
			size,
			point.x,
			point.x,
			point.z,
			point.z,
			point.radius,
			function(row, col, x, z)
				if Geometry.distance(x, z, point.x, point.z) <= point.radius then
					total += heights[row][col]
					nodes += 1
				end
			end
		)
		flat[point.id] = math.max(dry, if nodes > 0 then total / nodes else dry)
	end
	for _, path in paths do
		local a, b = points[path.a], points[path.b]
		local margin = path.halfWidth + diagonal
		eachNodeNear(
			half,
			cell,
			size,
			math.min(a.x, b.x),
			math.max(a.x, b.x),
			math.min(a.z, b.z),
			math.max(a.z, b.z),
			margin,
			function(row, col, x, z)
				if distanceToSegment(x, z, a.x, a.z, b.x, b.z) <= margin then
					heights[row][col] = math.max(heights[row][col], dry)
				end
			end
		)
	end
	for _, point in points do
		local margin = point.radius + diagonal
		eachNodeNear(
			half,
			cell,
			size,
			point.x,
			point.x,
			point.z,
			point.z,
			margin,
			function(row, col, x, z)
				if Geometry.distance(x, z, point.x, point.z) <= margin then
					heights[row][col] = math.max(heights[row][col], dry)
				end
			end
		)
	end
	for _, point in points do
		eachNodeNear(
			half,
			cell,
			size,
			point.x,
			point.x,
			point.z,
			point.z,
			point.radius,
			function(row, col, x, z)
				if Geometry.distance(x, z, point.x, point.z) <= point.radius then
					heights[row][col] = flat[point.id]
				end
			end
		)
	end

	-- The grid cells each footprint overlaps, for pointAt.
	local pointCells: { [number]: { number } } = {}
	for _, point in points do
		local col0 = math.max(1, math.floor((point.x - point.radius + half) / cell) + 1)
		local col1 = math.min(size - 1, math.floor((point.x + point.radius + half) / cell) + 1)
		local row0 = math.max(1, math.floor((point.z - point.radius + half) / cell) + 1)
		local row1 = math.min(size - 1, math.floor((point.z + point.radius + half) / cell) + 1)
		for row = row0, row1 do
			for col = col0, col1 do
				local key = (row - 1) * size + col
				local list = pointCells[key]
				if list == nil then
					list = {}
					pointCells[key] = list
				end
				table.insert(list, point.id)
			end
		end
	end

	local map: Types.Map = {
		half = half,
		points = points,
		paths = paths,
		entries = entries,
		zonePoints = zonePoints,
		nextHop = nextHop,
		hops = hops,
		heights = heights,
		heightCell = cell,
		waterLevel = settings.waterLevel,
		sampleStep = settings.sampleStep,
		clampRadius = settings.clampRadius,
		steerProbe = settings.steerProbe,
		fieldCover = {},
		pointCells = pointCells,
	}

	-- Bushes on walkable ground between points, clear of footprints and paths.
	local clearance = settings.fieldCoverClearance
	local inner = half - clearance
	for _ = 1, settings.fieldCoverPerPoint * #points do
		for _ = 1, settings.placementAttempts do
			local x = -inner + rng:next() * 2 * inner
			local z = -inner + rng:next() * 2 * inner
			local clear = Map.walkable(map, x, z)
			if clear then
				for _, point in points do
					if Geometry.distance(x, z, point.x, point.z) <= point.radius + clearance then
						clear = false
						break
					end
				end
			end
			if clear then
				for _, path in paths do
					local a, b = points[path.a], points[path.b]
					if
						distanceToSegment(x, z, a.x, a.z, b.x, b.z)
						<= path.halfWidth + clearance
					then
						clear = false
						break
					end
				end
			end
			if clear then
				table.insert(map.fieldCover, { x = x, z = z })
				break
			end
		end
	end

	return map
end

-- The point ids ordered by their distance from the nearest entry, farthest
-- first, ties by id; at most `count` of them. The camp leaders' points.
function Map.farthestPoints(map: Types.Map, count: number): { number }
	local ids: { number } = {}
	for _, point in map.points do
		table.insert(ids, point.id)
	end
	table.sort(ids, function(a, b)
		local da, db = map.points[a].distance, map.points[b].distance
		if da ~= db then
			return da > db
		end
		return a < b
	end)
	local farthest: { number } = {}
	for index = 1, math.min(count, #ids) do
		farthest[index] = ids[index]
	end
	return farthest
end

-- The grid cell (row, col) whose lower corner is nearest below (x, z),
-- clamped to the grid, and the fractions across it.
local function cellOf(map: Types.Map, x: number, z: number): (number, number, number, number)
	local size = #map.heights
	local u = (math.clamp(x, -map.half, map.half) + map.half) / map.heightCell
	local v = (math.clamp(z, -map.half, map.half) + map.half) / map.heightCell
	local col = math.clamp(math.floor(u) + 1, 1, size - 1)
	local row = math.clamp(math.floor(v) + 1, 1, size - 1)
	return row, col, math.clamp(u - (col - 1), 0, 1), math.clamp(v - (row - 1), 0, 1)
end

-- The terrain height at (x, z), bilinear over the grid, before water.
local function groundAt(map: Types.Map, x: number, z: number): number
	local row, col, fx, fz = cellOf(map, x, z)
	local heights = map.heights
	local low = heights[row][col] * (1 - fx) + heights[row][col + 1] * fx
	local high = heights[row + 1][col] * (1 - fx) + heights[row + 1][col + 1] * fx
	return low * (1 - fz) + high * fz
end

-- The point whose footprint (centre within radius) contains (x, z).
function Map.pointAt(map: Types.Map, x: number, z: number): Types.MapPoint?
	if math.abs(x) > map.half or math.abs(z) > map.half then
		return nil
	end
	local row, col = cellOf(map, x, z)
	local list = map.pointCells[(row - 1) * #map.heights + col]
	if list == nil then
		return nil
	end
	for _, id in list do
		local point = map.points[id]
		if (point.x - x) ^ 2 + (point.z - z) ^ 2 <= point.radius * point.radius then
			return point
		end
	end
	return nil
end

-- The point whose centre is nearest to (x, z); ties go to the lower id.
function Map.nearestPoint(map: Types.Map, x: number, z: number): Types.MapPoint
	local best, bestDistance = map.points[1], math.huge
	for _, point in map.points do
		local d = (point.x - x) ^ 2 + (point.z - z) ^ 2
		if d < bestDistance then
			best, bestDistance = point, d
		end
	end
	return best
end

-- Whether (x, z) can be stood on: inside the square, out of the water and
-- outside every prop.
function Map.walkable(map: Types.Map, x: number, z: number): boolean
	if math.abs(x) > map.half or math.abs(z) > map.half then
		return false
	end
	if groundAt(map, x, z) < map.waterLevel then
		return false
	end
	local point = Map.pointAt(map, x, z)
	if point then
		for _, prop in point.props do
			if Geometry.insideRect(prop, x, z) then
				return false
			end
		end
	end
	return true
end

-- The terrain height at (x, z), bilinear over the grid; over water, the water
-- level.
function Map.heightAt(map: Types.Map, x: number, z: number): number
	return math.max(groundAt(map, x, z), map.waterLevel)
end

-- A walkable position near (x, z): onto the square's edge, out of a prop to
-- its nearest edge, and out of the water to the nearest walkable position on
-- rings a stud apart out to clampRadius. Only when none is found, toward the
-- nearest point's centre (that centre is walkable, so the walk ends by it).
function Map.clamp(map: Types.Map, x: number, z: number): (number, number)
	x = math.clamp(x, -map.half, map.half)
	z = math.clamp(z, -map.half, map.half)
	if Map.walkable(map, x, z) then
		return x, z
	end
	local point = Map.pointAt(map, x, z)
	if point then
		for _, prop in point.props do
			if Geometry.insideRect(prop, x, z) then
				local west = x - (prop.x - prop.halfWidth)
				local east = prop.x + prop.halfWidth - x
				local north = z - (prop.z - prop.halfDepth)
				local south = prop.z + prop.halfDepth - z
				local nearest = math.min(west, east, north, south)
				if nearest == west then
					x = prop.x - prop.halfWidth - PUSH_MARGIN
				elseif nearest == east then
					x = prop.x + prop.halfWidth + PUSH_MARGIN
				elseif nearest == north then
					z = prop.z - prop.halfDepth - PUSH_MARGIN
				else
					z = prop.z + prop.halfDepth + PUSH_MARGIN
				end
				break
			end
		end
		if Map.walkable(map, x, z) then
			return x, z
		end
	end
	-- Every sample on a ring is as far from (x, z) as the others, so the
	-- first walkable one is the nearest found.
	for radius = 1, map.clampRadius do
		for index = 0, CLAMP_DIRECTIONS - 1 do
			local angle = index / CLAMP_DIRECTIONS * 2 * math.pi
			local sx, sz = x + math.cos(angle) * radius, z + math.sin(angle) * radius
			if Map.walkable(map, sx, sz) then
				return sx, sz
			end
		end
	end
	local target = Map.nearestPoint(map, x, z)
	local distance = Geometry.distance(x, z, target.x, target.z)
	local sample = map.sampleStep
	for step = 1, math.ceil(distance / sample) do
		local t = math.min(step * sample, distance) / distance
		local sx, sz = x + (target.x - x) * t, z + (target.z - z) * t
		if Map.walkable(map, sx, sz) then
			return sx, sz
		end
	end
	return target.x, target.z
end

-- Whether (x, z) is within the cover radius of a cover spot: one of the
-- nearest point's (a spot of another point is farther than the spacing
-- allows) or a bush between points.
function Map.inCover(map: Types.Map, config: Types.Config, x: number, z: number): boolean
	local radiusSquared = config.map.coverRadius * config.map.coverRadius
	for _, spot in Map.nearestPoint(map, x, z).cover do
		if (spot.x - x) ^ 2 + (spot.z - z) ^ 2 <= radiusSquared then
			return true
		end
	end
	for _, spot in map.fieldCover do
		if (spot.x - x) ^ 2 + (spot.z - z) ^ 2 <= radiusSquared then
			return true
		end
	end
	return false
end

-- How far from (fromX, fromZ) toward (toX, toZ) the walkable ground reaches,
-- up to the full distance: water, a prop or the edge stops it.
function Map.reach(map: Types.Map, fromX: number, fromZ: number, toX: number, toZ: number): number
	local dx, dz = toX - fromX, toZ - fromZ
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance < 1e-9 then
		return 0
	end
	local sample = map.sampleStep
	for step = 1, math.ceil(distance / sample) do
		local t = math.min(step * sample, distance)
		if not Map.walkable(map, fromX + dx / distance * t, fromZ + dz / distance * t) then
			return math.max(0, t - sample)
		end
	end
	return distance
end

-- Whether nothing unwalkable lies between the two positions.
function Map.clearPath(
	map: Types.Map,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): boolean
	local dx, dz = toX - fromX, toZ - fromZ
	return Map.reach(map, fromX, fromZ, toX, toZ) >= math.sqrt(dx * dx + dz * dz) - 1e-9
end

-- Whether a shot stops at (x, z): off the square or inside a prop. Water
-- does not stop a shot; it flies over.
function Map.blocksShots(map: Types.Map, x: number, z: number): boolean
	if math.abs(x) > map.half or math.abs(z) > map.half then
		return true
	end
	local point = Map.pointAt(map, x, z)
	if point then
		for _, prop in point.props do
			if Geometry.insideRect(prop, x, z) then
				return true
			end
		end
	end
	return false
end

-- How far from (fromX, fromZ) toward (toX, toZ) a shot flies, up to the full
-- distance: a prop or the edge stops it, sampled as reach samples.
function Map.shotReach(
	map: Types.Map,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): number
	local dx, dz = toX - fromX, toZ - fromZ
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance < 1e-9 then
		return 0
	end
	local sample = map.sampleStep
	for step = 1, math.ceil(distance / sample) do
		local t = math.min(step * sample, distance)
		if Map.blocksShots(map, fromX + dx / distance * t, fromZ + dz / distance * t) then
			return math.max(0, t - sample)
		end
	end
	return distance
end

-- Whether nothing that stops a shot lies between the two positions.
function Map.clearShot(
	map: Types.Map,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): boolean
	local dx, dz = toX - fromX, toZ - fromZ
	return Map.shotReach(map, fromX, fromZ, toX, toZ) >= math.sqrt(dx * dx + dz * dz) - 1e-9
end

function Map.pathBetween(map: Types.Map, a: number, b: number): Types.Path?
	local point = map.points[a]
	for index, neighbour in point.neighbours do
		if neighbour == b then
			return map.paths[point.paths[index]]
		end
	end
	return nil
end

-- The prop the straight line from (fromX, fromZ) to (toX, toZ) meets first,
-- sampled as reach samples; nil when water or the edge stops it first, or
-- nothing does.
local function blockingProp(
	map: Types.Map,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): Types.Rect?
	local dx, dz = toX - fromX, toZ - fromZ
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance < 1e-9 then
		return nil
	end
	local sample = map.sampleStep
	for step = 1, math.ceil(distance / sample) do
		local t = math.min(step * sample, distance)
		local x, z = fromX + dx / distance * t, fromZ + dz / distance * t
		if not Map.walkable(map, x, z) then
			local point = Map.pointAt(map, x, z)
			if point then
				for _, prop in point.props do
					if Geometry.insideRect(prop, x, z) then
						return prop
					end
				end
			end
			return nil
		end
	end
	return nil
end

-- The way round `prop` from (fromX, fromZ) to (toX, toZ): the corner, set
-- CORNER_MARGIN out, to walk to first on the shortest route over clear lines
-- that passes one corner, or two along a side. Nil when no such route is
-- clear (water or another prop in the way); a corner the walker stands on
-- is not a way on.
local function aroundProp(
	map: Types.Map,
	prop: Types.Rect,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): (number?, number?)
	local west = prop.x - prop.halfWidth - CORNER_MARGIN
	local east = prop.x + prop.halfWidth + CORNER_MARGIN
	local north = prop.z - prop.halfDepth - CORNER_MARGIN
	local south = prop.z + prop.halfDepth + CORNER_MARGIN
	-- In order round the prop, so neighbours in the list share a side.
	local corners = { { west, north }, { east, north }, { east, south }, { west, south } }
	local open: { boolean } = {}
	local toTarget: { number } = {}
	for index, corner in corners do
		local x, z = corner[1], corner[2]
		open[index] = Map.walkable(map, x, z)
		toTarget[index] = if open[index] and Map.clearPath(map, x, z, toX, toZ)
			then Geometry.distance(x, z, toX, toZ)
			else math.huge
	end
	local lengths: { number } = {}
	local order: { number } = {}
	for index, corner in corners do
		local x, z = corner[1], corner[2]
		local first = Geometry.distance(fromX, fromZ, x, z)
		if not open[index] or first < map.sampleStep then
			continue
		end
		local rest = toTarget[index]
		for _, other in { index % 4 + 1, (index + 2) % 4 + 1 } do
			local ox, oz = corners[other][1], corners[other][2]
			local side = Geometry.distance(x, z, ox, oz)
			if
				toTarget[other] < math.huge
				and side + toTarget[other] < rest
				and Map.clearPath(map, x, z, ox, oz)
			then
				rest = side + toTarget[other]
			end
		end
		if rest < math.huge then
			lengths[index] = first + rest
			table.insert(order, index)
		end
	end
	-- Shortest route first; only its first leg is left to check.
	table.sort(order, function(a, b)
		if lengths[a] ~= lengths[b] then
			return lengths[a] < lengths[b]
		end
		return a < b
	end)
	for _, index in order do
		local x, z = corners[index][1], corners[index][2]
		if Map.clearPath(map, fromX, fromZ, x, z) then
			return x, z
		end
	end
	return nil, nil
end

-- Local steering around what blocks the straight line from (fromX, fromZ)
-- to (toX, toZ): a probe of steerProbe studs along each turned heading, and
-- the end of the first one that runs its full length and ends nearer the
-- target, or else of the one whose walkable part ends nearest it. When no
-- probe ends nearer the target than the walker stands, there is no way on
-- within the probe: the walker's own position.
local function steer(
	map: Types.Map,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): (number, number)
	local probe = map.steerProbe
	local direct = Geometry.angle(toX - fromX, toZ - fromZ)
	local bestX, bestZ = fromX, fromZ
	local bestDistance = Geometry.distance(fromX, fromZ, toX, toZ)
	local here = bestDistance
	for _, turn in STEER_TURNS do
		local angle = direct + math.rad(turn)
		local dirX, dirZ = math.cos(angle), math.sin(angle)
		local reach = Map.reach(map, fromX, fromZ, fromX + dirX * probe, fromZ + dirZ * probe)
		local x, z = fromX + dirX * reach, fromZ + dirZ * reach
		local distance = Geometry.distance(x, z, toX, toZ)
		if reach >= probe - 1e-9 and distance < here then
			return x, z
		end
		if distance < bestDistance then
			bestX, bestZ, bestDistance = x, z, distance
		end
	end
	return bestX, bestZ
end

-- Where to walk next from (fromX, fromZ) toward (toX, toZ): the target itself
-- when the line is clear. When the walker and the target share their nearest
-- point: round the corners of a prop that blocks the line, or else a local
-- steer around what blocks it; the walker's own position when there is no
-- way on. Otherwise the centre of the next point along the
-- paths from the point nearest the walker toward the point nearest the
-- target, or, when that centre is not in a clear line either, the walker's
-- own nearest point's centre first, steered toward when blocked. From a
-- centre, the next point's centre is clear by construction.
function Map.waypointToward(
	map: Types.Map,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): (number, number)
	if Map.clearPath(map, fromX, fromZ, toX, toZ) then
		return toX, toZ
	end
	local from = Map.nearestPoint(map, fromX, fromZ)
	local to = Map.nearestPoint(map, toX, toZ)
	if from.id == to.id then
		local prop = blockingProp(map, fromX, fromZ, toX, toZ)
		if prop then
			local cornerX, cornerZ = aroundProp(map, prop, fromX, fromZ, toX, toZ)
			if cornerX and cornerZ then
				return cornerX, cornerZ
			end
		end
		return steer(map, fromX, fromZ, toX, toZ)
	end
	local atCentre = Geometry.distance(fromX, fromZ, from.x, from.z) < CENTRE_TOLERANCE
	local nextPoint = map.points[map.nextHop[from.id][to.id]]
	if atCentre or Map.clearPath(map, fromX, fromZ, nextPoint.x, nextPoint.z) then
		return nextPoint.x, nextPoint.z
	end
	if Map.clearPath(map, fromX, fromZ, from.x, from.z) then
		return from.x, from.z
	end
	return steer(map, fromX, fromZ, from.x, from.z)
end

return Map
