--!strict
-- The map's ground (ADR-0014): a round, flat arena closed by its edge, with
-- obstacles scattered anew for every run from the seed. Obstacles are circles
-- that block the movement of players and enemies and nothing else, so the
-- queries here are the only collision the core has.

local Geometry = require("./Geometry")
local Types = require("./Types")

local Arena = {}

-- A body stops this far short of an obstacle, so rounding never puts it inside.
local CONTACT_GAP = 1e-3

type ObstacleKind = {
	id: string,
	radius: number,
	weight: number,
	footprint: { { dx: number, dz: number, radius: number } }?,
}

type Circle = { x: number, z: number, radius: number }

local function pickKind(map: Types.MapConfig, rng: Types.Rng): ObstacleKind
	local total = 0
	for _, kind in map.obstacleKinds do
		total += kind.weight
	end
	local roll = rng:next() * total
	for _, kind in map.obstacleKinds do
		roll -= kind.weight
		if roll < 0 then
			return kind
		end
	end
	return map.obstacleKinds[#map.obstacleKinds]
end

-- A point uniform by area in the disc of `radius` around the origin.
local function randomInDisc(rng: Types.Rng, radius: number): (number, number)
	local r = radius * math.sqrt(rng:next())
	local angle = rng:next() * 2 * math.pi
	return r * math.cos(angle), r * math.sin(angle)
end

-- The circles a prop of `kind` at (x, z) turned by `rotation` takes: one per
-- footprint entry, its offset turned like every angle of the core (from +x
-- toward +z), else the kind's single circle at the centre.
local function circlesOf(kind: ObstacleKind, x: number, z: number, rotation: number): { Circle }
	local footprint = kind.footprint
	if footprint == nil or #footprint == 0 then
		return { { x = x, z = z, radius = kind.radius } }
	end
	local cos, sin = math.cos(rotation), math.sin(rotation)
	local circles = table.create(#footprint)
	for _, entry in footprint do
		table.insert(circles, {
			x = x + entry.dx * cos - entry.dz * sin,
			z = z + entry.dx * sin + entry.dz * cos,
			radius = entry.radius,
		})
	end
	return circles
end

-- How far from its centre a prop of `kind` reaches, whatever its rotation.
local function extentOf(kind: ObstacleKind): number
	local footprint = kind.footprint
	if footprint == nil or #footprint == 0 then
		return kind.radius
	end
	local extent = 0
	for _, entry in footprint do
		extent =
			math.max(extent, math.sqrt(entry.dx * entry.dx + entry.dz * entry.dz) + entry.radius)
	end
	return extent
end

-- Whether every circle keeps the clear ground and the spacing from the
-- obstacles already placed.
local function fits(
	map: Types.MapConfig,
	obstacles: { Types.Obstacle },
	circles: { Circle },
	chestX: number,
	chestZ: number
): boolean
	for _, circle in circles do
		if
			Geometry.distance(circle.x, circle.z, 0, 0) < map.startClearRadius + circle.radius
			or Geometry.distance(circle.x, circle.z, chestX, chestZ)
				< map.chestClearRadius + circle.radius
		then
			return false
		end
		for _, other in obstacles do
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

-- Scatters the obstacles, places the chest and, given the shrines' config,
-- the shrines' spots; the start is the centre. A prop with a footprint takes
-- one circle per entry, all of one `group` (the prop's index), the first the
-- anchor the builder draws the prop at. Repeatable for a seed: the rng is the
-- run's, consumed in a fixed order.
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

	local obstacles: { Types.Obstacle } = {}
	for index = 1, map.obstacleCount do
		local kind = pickKind(map, rng)
		local extent = extentOf(kind)
		for _ = 1, map.placementAttempts do
			local x, z = randomInDisc(rng, inner - extent)
			local rotation = rng:next() * 2 * math.pi
			local circles = circlesOf(kind, x, z, rotation)
			if fits(map, obstacles, circles, chestX, chestZ) then
				for order, circle in circles do
					table.insert(obstacles, {
						id = #obstacles + 1,
						kind = kind.id,
						x = circle.x,
						z = circle.z,
						radius = circle.radius,
						rotation = rotation,
						group = index,
						anchor = order == 1,
					})
				end
				break
			end
		end
	end

	return {
		radius = map.radius,
		obstacles = obstacles,
		startX = 0,
		startZ = 0,
		chestX = chestX,
		chestZ = chestZ,
		shrineSpots = if shrines
			then scatterShrines(map, shrines, rng, obstacles, chestX, chestZ)
			else {},
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
