--!strict
-- The world of a run (ADR-0008): a graph of rooms joined by corridors,
-- generated from a seed, and the queries the other modules ask of it. Rooms
-- sit on a grid, one per cell, so every corridor is straight and the centres
-- of two joined rooms and their corridor lie on one line.

local Geometry = require("./Geometry")
local Types = require("./Types")

local World = {}

-- How far inside a room or corridor a waypoint at a corridor mouth lies.
local MOUTH_INSET = 1.5

type Cell = { cx: number, cz: number, degree: number }
type Edge = { a: number, b: number }

local OFFSETS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

local function cellKey(cx: number, cz: number): number
	return cx * 100003 + cz
end

-- Grows a connected set of `count` cells from the origin, attaching each new
-- cell to a random occupied neighbour that still has an exit free.
local function growCells(
	config: Types.Config,
	rng: Types.Rng,
	count: number
): ({ Cell }, { Edge }, { [number]: number })
	local cells: { Cell } = { { cx = 0, cz = 0, degree = 0 } }
	local byKey: { [number]: number } = { [cellKey(0, 0)] = 1 }
	local edges: { Edge } = {}

	while #cells < count do
		local candidates: { { parent: number, cx: number, cz: number } } = {}
		local relaxed: { { parent: number, cx: number, cz: number } } = {}
		for index, cell in cells do
			for _, offset in OFFSETS do
				local nx, nz = cell.cx + offset[1], cell.cz + offset[2]
				if byKey[cellKey(nx, nz)] == nil then
					local candidate = { parent = index, cx = nx, cz = nz }
					table.insert(relaxed, candidate)
					if cell.degree < config.world.maxExits then
						table.insert(candidates, candidate)
					end
				end
			end
		end
		-- Every room saturated: let one grow past the limit rather than stop.
		if #candidates == 0 then
			candidates = relaxed
		end
		local pick = candidates[rng:integer(1, #candidates)]
		table.insert(cells, { cx = pick.cx, cz = pick.cz, degree = 1 })
		byKey[cellKey(pick.cx, pick.cz)] = #cells
		cells[pick.parent].degree += 1
		table.insert(edges, { a = pick.parent, b = #cells })
	end
	return cells, edges, byKey
end

-- Joins adjacent cells not yet joined, now and then, so the graph has loops.
local function addLoops(
	config: Types.Config,
	rng: Types.Rng,
	cells: { Cell },
	edges: { Edge },
	byKey: { [number]: number }
)
	local joined: { [number]: boolean } = {}
	for _, edge in edges do
		joined[math.min(edge.a, edge.b) * 100003 + math.max(edge.a, edge.b)] = true
	end
	for index, cell in cells do
		for _, offset in { { 1, 0 }, { 0, 1 } } do
			local other = byKey[cellKey(cell.cx + offset[1], cell.cz + offset[2])]
			if other == nil then
				continue
			end
			local key = math.min(index, other) * 100003 + math.max(index, other)
			if joined[key] then
				continue
			end
			if
				cell.degree < config.world.maxExits
				and cells[other].degree < config.world.maxExits
				and rng:next() < config.world.loopChance
			then
				joined[key] = true
				cell.degree += 1
				cells[other].degree += 1
				table.insert(edges, { a = index, b = other })
			end
		end
	end
end

-- Breadth-first hops from `source` to every room.
local function bfs(rooms: { Types.Room }, source: number): ({ number }, { number })
	local hops: { number } = table.create(#rooms, math.huge)
	local parent: { number } = table.create(#rooms, 0)
	hops[source] = 0
	parent[source] = source
	local queue = { source }
	local head = 1
	while head <= #queue do
		local current = queue[head]
		head += 1
		for _, neighbour in rooms[current].neighbours do
			if hops[neighbour] == math.huge then
				hops[neighbour] = hops[current] + 1
				parent[neighbour] = current
				table.insert(queue, neighbour)
			end
		end
	end
	return hops, parent
end

-- The leaves (or, without any, the rooms with the fewest exits) that will be
-- start rooms: peripheral and far apart.
local function chooseStarts(rooms: { Types.Room }, hops: { { number } }, count: number): { number }
	local fewest = math.huge
	for _, room in rooms do
		fewest = math.min(fewest, #room.neighbours)
	end
	local candidates: { number } = {}
	for _, room in rooms do
		if #room.neighbours == fewest then
			table.insert(candidates, room.id)
		end
	end

	-- The most peripheral candidate first: the one farthest from everything.
	local starts: { number } = {}
	local first, firstScore = candidates[1], -1
	for _, id in candidates do
		local total = 0
		for other = 1, #rooms do
			total += hops[id][other]
		end
		if total > firstScore then
			first, firstScore = id, total
		end
	end
	table.insert(starts, first)

	-- Then the candidate farthest from the starts chosen so far. A graph too
	-- small for the configured spacing still gets its starts, as far apart as
	-- it allows.
	while #starts < math.min(count, #candidates) do
		local best, bestDistance = nil, -1
		for _, id in candidates do
			if table.find(starts, id) then
				continue
			end
			local nearest = math.huge
			for _, start in starts do
				nearest = math.min(nearest, hops[id][start])
			end
			if nearest > bestDistance then
				best, bestDistance = id, nearest
			end
		end
		if best == nil then
			break
		end
		table.insert(starts, best)
	end
	return starts
end

-- Deep rooms far from each other, none a start room.
local function chooseZoneRooms(
	config: Types.Config,
	rooms: { Types.Room },
	hops: { { number } },
	count: number
): { number }
	local zones: { number } = {}
	while #zones < count do
		local best, bestScore = nil, -1
		for _, room in rooms do
			if room.isStart or table.find(zones, room.id) then
				continue
			end
			local apart = math.huge
			for _, zone in zones do
				apart = math.min(apart, hops[room.id][zone])
			end
			if apart == math.huge then
				apart = 0
			end
			local score = room.distance * config.world.zoneDepthWeight + apart
			if score > bestScore then
				best, bestScore = room.id, score
			end
		end
		if best == nil then
			break
		end
		table.insert(zones, best)
	end
	return zones
end

function World.generate(config: Types.Config, rng: Types.Rng, playerCount: number): Types.World
	local settings = config.world
	local players = math.max(1, playerCount)
	local roomCount =
		math.clamp(settings.roomsPerPlayer * players, settings.minRooms, settings.maxRooms)

	local cells, edges, byKey = growCells(config, rng, roomCount)
	addLoops(config, rng, cells, edges, byKey)

	local rooms: { Types.Room } = {}
	for index, cell in cells do
		local template = settings.templates[rng:integer(1, #settings.templates)]
		local x, z = cell.cx * settings.cellSize, cell.cz * settings.cellSize
		local cover: { Types.Point } = {}
		for _, spot in template.cover do
			table.insert(cover, { x = x + spot.x, z = z + spot.z })
		end
		rooms[index] = {
			id = index,
			cellX = cell.cx,
			cellZ = cell.cz,
			x = x,
			z = z,
			halfWidth = template.halfWidth,
			halfDepth = template.halfDepth,
			template = template.id,
			corridors = {},
			neighbours = {},
			distance = 0,
			level = 1,
			isStart = false,
			hasZone = false,
			campX = x + template.camp.x,
			campZ = z + template.camp.z,
			cover = cover,
		}
	end

	local corridors: { Types.Corridor } = {}
	for _, edge in edges do
		local a, b = rooms[edge.a], rooms[edge.b]
		local corridor: Types.Corridor
		if a.cellZ == b.cellZ then
			local left, right = a, b
			if b.x < a.x then
				left, right = b, a
			end
			local from, to = left.x + left.halfWidth, right.x - right.halfWidth
			corridor = {
				id = #corridors + 1,
				roomA = a.id,
				roomB = b.id,
				x = (from + to) / 2,
				z = a.z,
				halfWidth = (to - from) / 2,
				halfDepth = settings.corridorHalfWidth,
			}
		else
			local near, far = a, b
			if b.z < a.z then
				near, far = b, a
			end
			local from, to = near.z + near.halfDepth, far.z - far.halfDepth
			corridor = {
				id = #corridors + 1,
				roomA = a.id,
				roomB = b.id,
				x = a.x,
				z = (from + to) / 2,
				halfWidth = settings.corridorHalfWidth,
				halfDepth = (to - from) / 2,
			}
		end
		table.insert(corridors, corridor)
		table.insert(a.corridors, corridor.id)
		table.insert(a.neighbours, b.id)
		table.insert(b.corridors, corridor.id)
		table.insert(b.neighbours, a.id)
	end

	-- Routing tables: the BFS tree rooted at `to` gives every room's next hop.
	local nextHop: { { number } } = {}
	local hops: { { number } } = {}
	for id = 1, #rooms do
		nextHop[id] = table.create(#rooms, 0)
		hops[id] = table.create(#rooms, 0)
	end
	for to = 1, #rooms do
		local distances, parent = bfs(rooms, to)
		for from = 1, #rooms do
			nextHop[from][to] = parent[from]
			hops[from][to] = distances[from]
		end
	end

	local startCount =
		math.clamp(math.ceil(players / settings.playersPerStart), 1, settings.maxStarts)
	local startRooms = chooseStarts(rooms, hops, startCount)
	for _, id in startRooms do
		rooms[id].isStart = true
	end

	local deepest = 0
	for _, room in rooms do
		local nearest = math.huge
		for _, start in startRooms do
			nearest = math.min(nearest, hops[room.id][start])
		end
		room.distance = nearest
		deepest = math.max(deepest, nearest)
	end
	for _, room in rooms do
		if room.distance == 0 then
			room.level = 1
		else
			room.level = math.clamp(
				math.ceil(room.distance / deepest * settings.maxLevel),
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
	local zoneRooms =
		chooseZoneRooms(config, rooms, hops, math.min(zoneCount, #rooms - #startRooms))
	for _, id in zoneRooms do
		rooms[id].hasZone = true
	end

	local minX, maxX, minZ, maxZ = math.huge, -math.huge, math.huge, -math.huge
	for _, room in rooms do
		minX = math.min(minX, room.x - room.halfWidth)
		maxX = math.max(maxX, room.x + room.halfWidth)
		minZ = math.min(minZ, room.z - room.halfDepth)
		maxZ = math.max(maxZ, room.z + room.halfDepth)
	end

	return {
		rooms = rooms,
		corridors = corridors,
		startRooms = startRooms,
		zoneRooms = zoneRooms,
		nextHop = nextHop,
		hops = hops,
		bounds = {
			x = (minX + maxX) / 2,
			z = (minZ + maxZ) / 2,
			halfWidth = (maxX - minX) / 2,
			halfDepth = (maxZ - minZ) / 2,
		},
	}
end

-- Where (x, z) is. Rooms win over corridors at a shared boundary.
function World.locate(world: Types.World, x: number, z: number): Types.Location
	for _, room in world.rooms do
		if Geometry.insideRect(room, x, z) then
			return { kind = "room", id = room.id }
		end
	end
	for _, corridor in world.corridors do
		if Geometry.insideRect(corridor, x, z) then
			return { kind = "corridor", id = corridor.id }
		end
	end
	return { kind = "outside", id = 0 }
end

function World.roomAt(world: Types.World, x: number, z: number): Types.Room?
	for _, room in world.rooms do
		if Geometry.insideRect(room, x, z) then
			return room
		end
	end
	return nil
end

-- The nearest point inside a room or a corridor.
function World.clamp(world: Types.World, x: number, z: number): (number, number)
	local bestX, bestZ, bestDistance = x, z, math.huge
	local function consider(rect: Types.Rect)
		local cx, cz = Geometry.clampToRect(rect, x, z)
		local d = (cx - x) ^ 2 + (cz - z) ^ 2
		if d < bestDistance then
			bestX, bestZ, bestDistance = cx, cz, d
		end
	end
	for _, room in world.rooms do
		consider(room)
		if bestDistance == 0 then
			return x, z
		end
	end
	for _, corridor in world.corridors do
		consider(corridor)
		if bestDistance == 0 then
			return x, z
		end
	end
	return bestX, bestZ
end

-- Whether (x, z) is within the cover radius of a cover spot of its room.
function World.inCover(world: Types.World, config: Types.Config, x: number, z: number): boolean
	local room = World.roomAt(world, x, z)
	if room == nil then
		return false
	end
	local radius = config.world.coverRadius
	for _, spot in room.cover do
		if (spot.x - x) ^ 2 + (spot.z - z) ^ 2 <= radius * radius then
			return true
		end
	end
	return false
end

-- How far apart the points are that a path is checked at.
local PATH_SAMPLE = 1

-- How far from (fromX, fromZ) toward (toX, toZ) the walkable world reaches, up
-- to the full distance: the first wall stops it.
function World.reach(
	world: Types.World,
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
	local steps = math.ceil(distance / PATH_SAMPLE)
	for step = 1, steps do
		local t = math.min(step * PATH_SAMPLE, distance)
		if
			World.locate(world, fromX + dx / distance * t, fromZ + dz / distance * t).kind
			== "outside"
		then
			return math.max(0, t - PATH_SAMPLE)
		end
	end
	return distance
end

-- Whether no wall lies between the two points.
function World.clearPath(
	world: Types.World,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): boolean
	local dx, dz = toX - fromX, toZ - fromZ
	return World.reach(world, fromX, fromZ, toX, toZ) >= math.sqrt(dx * dx + dz * dz) - 1e-9
end

function World.corridorBetween(world: Types.World, a: number, b: number): Types.Corridor?
	local room = world.rooms[a]
	for index, neighbour in room.neighbours do
		if neighbour == b then
			return world.corridors[room.corridors[index]]
		end
	end
	return nil
end

-- The point on a corridor's centre line at the boundary of `roomId`, moved
-- into the room (`side` "room") or into the corridor (`side` "corridor").
local function mouth(
	world: Types.World,
	corridor: Types.Corridor,
	roomId: number,
	side: "room" | "corridor"
): (number, number)
	local room = world.rooms[roomId]
	local inset = if side == "room" then MOUTH_INSET else -MOUTH_INSET
	if corridor.halfWidth > corridor.halfDepth then
		-- Runs along x; the room is to the left or the right.
		local toward = if room.x < corridor.x then -1 else 1
		return corridor.x + toward * (corridor.halfWidth + inset), corridor.z
	end
	local toward = if room.z < corridor.z then -1 else 1
	return corridor.x, corridor.z + toward * (corridor.halfDepth + inset)
end

-- The rooms a location belongs to: one for a room, both ends for a corridor.
local function roomsOf(world: Types.World, location: Types.Location): { number }
	if location.kind == "room" then
		return { location.id }
	end
	local corridor = world.corridors[location.id]
	return { corridor.roomA, corridor.roomB }
end

-- The room of `candidates` nearest (by hops) to any of `froms`; ties go to the
-- first candidate.
local function nearestRoom(world: Types.World, froms: { number }, candidates: { number }): number
	local best, bestHops = candidates[1], math.huge
	for _, candidate in candidates do
		for _, from in froms do
			local h = world.hops[from][candidate]
			if h < bestHops then
				best, bestHops = candidate, h
			end
		end
	end
	return best
end

-- Where to walk next from (fromX, fromZ) toward (toX, toZ): the target itself
-- when both lie in the same room or corridor, otherwise the mouth of the next
-- corridor on the way. Rooms are convex and corridors straight, so a straight
-- line reaches each waypoint.
function World.waypointToward(
	world: Types.World,
	fromX: number,
	fromZ: number,
	toX: number,
	toZ: number
): (number, number)
	local from = World.locate(world, fromX, fromZ)
	if from.kind == "outside" then
		local cx, cz = World.clamp(world, fromX, fromZ)
		return cx, cz
	end
	local to = World.locate(world, toX, toZ)
	if to.kind == "outside" then
		toX, toZ = World.clamp(world, toX, toZ)
		to = World.locate(world, toX, toZ)
		if to.kind == "outside" then
			return toX, toZ
		end
	end
	if from.kind == to.kind and from.id == to.id then
		return toX, toZ
	end

	if from.kind == "room" then
		if to.kind == "corridor" then
			local corridor = world.corridors[to.id]
			if corridor.roomA == from.id or corridor.roomB == from.id then
				return mouth(world, corridor, from.id, "corridor")
			end
		end
		local target = nearestRoom(world, { from.id }, roomsOf(world, to))
		local next = world.nextHop[from.id][target]
		local corridor = World.corridorBetween(world, from.id, next)
		if corridor == nil then
			return toX, toZ
		end
		return mouth(world, corridor, from.id, "corridor")
	end

	-- In a corridor: walk to the end nearer the target, into that room.
	local corridor = world.corridors[from.id]
	local ends = { corridor.roomA, corridor.roomB }
	local targets = roomsOf(world, to)
	local best, bestHops = ends[1], math.huge
	for _, roomEnd in ends do
		for _, target in targets do
			local h = world.hops[roomEnd][target]
			if h < bestHops then
				best, bestHops = roomEnd, h
			end
		end
	end
	return mouth(world, corridor, best, "room")
end

return World
