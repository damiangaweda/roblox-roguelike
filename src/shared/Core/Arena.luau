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

local function pickKind(
	map: Types.MapConfig,
	rng: Types.Rng
): { id: string, radius: number, weight: number }
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

-- Scatters the obstacles and places the chest; the start is the centre.
-- Repeatable for a seed: the rng is the run's, consumed in a fixed order.
function Arena.generate(map: Types.MapConfig, rng: Types.Rng): Types.Arena
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
		for _ = 1, map.placementAttempts do
			local x, z = randomInDisc(rng, inner - kind.radius)
			local fits = Geometry.distance(x, z, 0, 0) >= map.startClearRadius + kind.radius
				and Geometry.distance(x, z, chestX, chestZ)
					>= map.chestClearRadius + kind.radius
			if fits then
				for _, other in obstacles do
					if
						Geometry.distance(x, z, other.x, other.z)
						< kind.radius + other.radius + map.obstacleSpacing
					then
						fits = false
						break
					end
				end
			end
			if fits then
				table.insert(obstacles, {
					id = index,
					kind = kind.id,
					x = x,
					z = z,
					radius = kind.radius,
					rotation = rng:next() * 2 * math.pi,
					group = index,
					anchor = true,
				})
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
		shrineSpots = {},
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
