--!strict
-- The enemies' flow field (stage 3d, ADR-0023): a grid over the map's disc
-- marks the cells a body cannot stand in (obstacles, cliffs and the channel
-- alike, grown by the hero's radius), and every few steps a flood from each
-- alive hero's cell gives every free cell its walking distance to that hero.
-- An enemy walks toward the neighbouring cell nearer the hero, so a cliff
-- ring or the stream sends it round to a ramp or a ford; the local steering
-- (Arena.steer) still handles bodies and small gaps. One flood per hero, no
-- search per enemy; players in id order and a fixed neighbour order keep it
-- deterministic.

local Geometry = require("./Geometry")
local State = require("./State")
local Types = require("./Types")

local Flow = {}

-- A cell nobody reaches, or one blocked.
local UNREACHED = -1
-- The neighbours in their fixed order, the four sides before the corners,
-- and the cost of each step: 5 along a side, 7 across a corner (about 5 * √2),
-- so the distances stay integers and close to the true length.
local DX = { 1, -1, 0, 0, 1, -1, 1, -1 }
local DZ = { 0, 0, 1, -1, 1, 1, -1, -1 }
local COST = { 5, 5, 5, 5, 7, 7, 7, 7 }
-- Buckets of the flood's queue, by distance modulo this: more than the
-- largest step's cost, so a step never lands in the bucket being emptied.
local RING = 8

-- The flood's queue and each bucket's length, emptied by every flood;
-- nothing yields while it runs.
local buckets: { { number } } = {}
local lengths: { number } = {}
for index = 1, RING do
	buckets[index] = {}
	lengths[index] = 0
end

-- The cell (cx, cz) under (x, z), held inside the grid's blocked border.
local function cellOf(flow: Types.Flow, x: number, z: number): (number, number)
	local last = flow.size - 2
	local cx = math.clamp(math.floor((x + flow.origin) / flow.cellSize), 1, last)
	local cz = math.clamp(math.floor((z + flow.origin) / flow.cellSize), 1, last)
	return cx, cz
end

local function centreOf(flow: Types.Flow, cx: number, cz: number): (number, number)
	return -flow.origin + (cx + 0.5) * flow.cellSize, -flow.origin + (cz + 0.5) * flow.cellSize
end

-- The grid for `arena`: a cell is blocked when its centre lies within an
-- obstacle's radius plus the hero's, or beyond the edge less the hero's. A
-- border of cells wholly beyond the edge rings the disc, so a free cell's
-- neighbours are always on the grid.
function Flow.build(arena: Types.Arena, config: Types.Config): Types.Flow
	local cellSize = config.flow.cellSize
	local margin = config.player.radius
	local size = math.max(math.ceil(2 * arena.radius / cellSize), 1) + 2
	local origin = size * cellSize / 2
	local blocked: { boolean } = table.create(size * size, false)
	local flow: Types.Flow = {
		cellSize = cellSize,
		size = size,
		origin = origin,
		blocked = blocked,
		obstacles = arena.obstacles,
		obstacleCount = #arena.obstacles,
		fields = {},
		spare = {},
		steps = 0,
	}

	local limit = math.max(arena.radius - margin, 0)
	for cz = 0, size - 1 do
		for cx = 0, size - 1 do
			local x, z = centreOf(flow, cx, cz)
			if x * x + z * z > limit * limit then
				blocked[cx + cz * size + 1] = true
			end
		end
	end

	for _, obstacle in arena.obstacles do
		local reach = obstacle.radius + margin
		local fromX, fromZ = cellOf(flow, obstacle.x - reach, obstacle.z - reach)
		local toX, toZ = cellOf(flow, obstacle.x + reach, obstacle.z + reach)
		for cz = fromZ, toZ do
			for cx = fromX, toX do
				local x, z = centreOf(flow, cx, cz)
				local dx, dz = x - obstacle.x, z - obstacle.z
				if dx * dx + dz * dz < reach * reach then
					blocked[cx + cz * size + 1] = true
				end
			end
		end
	end
	return flow
end

-- Fills `field` with every cell's distance from the cell under (x, z), over
-- free cells; a diagonal step needs both side cells free (no corner cutting).
-- The start counts even when blocked, so a hero against a tree still has a
-- field.
local function flood(flow: Types.Flow, field: { number }, x: number, z: number)
	local size, blocked = flow.size, flow.blocked
	for index = 1, size * size do
		field[index] = UNREACHED
	end
	local startX, startZ = cellOf(flow, x, z)
	local start = startX + startZ * size + 1
	field[start] = 0
	buckets[1][1] = start
	lengths[1] = 1

	local pending = 1
	local distance = 0
	while pending > 0 do
		local slot = distance % RING + 1
		local bucket = buckets[slot]
		local length = lengths[slot]
		for index = 1, length do
			local cell = bucket[index]
			-- A cell queued again at a shorter distance is expanded there.
			if field[cell] ~= distance then
				continue
			end
			for k = 1, 8 do
				local dx, dz = DX[k], DZ[k]
				local next = cell + dx + dz * size
				if blocked[next] then
					continue
				end
				if k > 4 and (blocked[cell + dx] or blocked[cell + dz * size]) then
					continue
				end
				local reached = distance + COST[k]
				local known = field[next]
				if known == UNREACHED or reached < known then
					field[next] = reached
					local into = reached % RING + 1
					local count = lengths[into] + 1
					buckets[into][count] = next
					lengths[into] = count
					pending += 1
				end
			end
		end
		-- Stale entries past the length are overwritten by later floods.
		pending -= length
		lengths[slot] = 0
		distance += 1
	end
end

-- Builds the grid at the first step (and again if the obstacles change), and
-- floods each alive hero's field every floodEverySteps steps, the heroes in
-- id order a step apart so the floods do not all land on one step; a hero
-- without a field yet (a late joiner, a fresh grid) is flooded at once. The
-- fields of heroes no longer alive are kept for reuse.
function Flow.update(run: Types.Run)
	local obstacles = run.arena.obstacles
	local flow = run.flow
	if flow == nil or flow.obstacles ~= obstacles or flow.obstacleCount ~= #obstacles then
		local fresh = Flow.build(run.arena, run.config)
		if flow then
			fresh.steps = flow.steps
		end
		run.flow = fresh
		flow = fresh
	end
	local current = flow :: Types.Flow

	local every = run.config.flow.floodEverySteps
	local step = current.steps
	current.steps += 1

	local gone = {}
	for id in current.fields do
		local player = run.players[id]
		if player == nil or player.state ~= "alive" then
			table.insert(gone, id)
		end
	end
	table.sort(gone)
	for _, id in gone do
		table.insert(current.spare, current.fields[id])
		current.fields[id] = nil
	end

	local count = current.size * current.size
	for index, player in State.alivePlayers(run) do
		local field = current.fields[player.id]
		if field == nil then
			field = table.remove(current.spare) or table.create(count, UNREACHED)
			current.fields[player.id] = field
		elseif (step - index + 1) % every ~= 0 then
			continue
		end
		flood(current, field :: { number }, player.x, player.z)
	end
end

-- The unit direction an enemy at (x, z) walks to get nearer the hero
-- `playerId` along the field: toward the centre of the neighbouring cell with
-- the lowest distance (ties by the fixed order). From a blocked cell (inside
-- an obstacle's margin) any free reached neighbour will do. Nil without a
-- field, in the hero's own cell, or where no neighbour is nearer.
function Flow.direction(run: Types.Run, playerId: number, x: number, z: number): (number?, number?)
	local flow = run.flow
	if flow == nil then
		return nil, nil
	end
	local field = flow.fields[playerId]
	if field == nil then
		return nil, nil
	end
	local size, blocked = flow.size, flow.blocked
	local cx, cz = cellOf(flow, x, z)
	local cell = cx + cz * size + 1
	local own = field[cell]
	if own == 0 then
		return nil, nil
	end
	local free = not blocked[cell] and own ~= UNREACHED

	local found, bestX, bestZ = false, 0, 0
	local best = if free then own else math.huge
	for k = 1, 8 do
		local nx, nz = cx + DX[k], cz + DZ[k]
		if nx < 0 or nx >= size or nz < 0 or nz >= size then
			continue
		end
		local next = nx + nz * size + 1
		local distance = field[next]
		if blocked[next] or distance == UNREACHED or distance >= best then
			continue
		end
		if free and k > 4 and (blocked[nx + cz * size + 1] or blocked[cx + nz * size + 1]) then
			continue
		end
		found, best, bestX, bestZ = true, distance, nx, nz
	end
	if not found then
		return nil, nil
	end
	local tx, tz = centreOf(flow, bestX, bestZ)
	local dx, dz = tx - x, tz - z
	if dx * dx + dz * dz < 1e-9 then
		return Geometry.normalize(bestX - cx, bestZ - cz)
	end
	return Geometry.normalize(dx, dz)
end

-- Whether the straight line from (fromX, fromZ) to (toX, toZ) crosses no
-- blocked cell, sampled every half cell; the two ends' own cells do not
-- count. True without a grid.
function Flow.open(run: Types.Run, fromX: number, fromZ: number, toX: number, toZ: number): boolean
	local flow = run.flow
	if flow == nil then
		return true
	end
	local size, blocked = flow.size, flow.blocked
	local fromCX, fromCZ = cellOf(flow, fromX, fromZ)
	local toCX, toCZ = cellOf(flow, toX, toZ)
	local fromCell = fromCX + fromCZ * size + 1
	local toCell = toCX + toCZ * size + 1
	local length = Geometry.distance(fromX, fromZ, toX, toZ)
	local samples = math.ceil(length / (flow.cellSize / 2))
	for index = 1, samples - 1 do
		local t = index / samples
		local cx, cz = cellOf(flow, fromX + (toX - fromX) * t, fromZ + (toZ - fromZ) * t)
		local cell = cx + cz * size + 1
		if cell ~= fromCell and cell ~= toCell and blocked[cell] then
			return false
		end
	end
	return true
end

return Flow
