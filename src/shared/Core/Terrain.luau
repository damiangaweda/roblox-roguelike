--!strict
-- The terrain's shapes (ADR-0023), laid out from the seed for Arena.generate:
-- plateaus ringed by cliff circles with ramp gaps, and a stream winding edge
-- to edge whose channel is a chain of circles broken at the fords. Pure
-- geometry on the XZ plane; Arena turns the circles into obstacles, slow zones
-- and pads.

local Geometry = require("./Geometry")
local Types = require("./Types")

local Terrain = {}

-- A stream's shape, not a gameplay number: rounds of pushing the line out of
-- the clearings and smoothing it, and the gap between two points of the line
-- (as a share of channelStep) beyond which the channel would leak.
local RELAX_PASSES = 32
local MAX_GAP_SHARE = 1.5

export type Circle = { x: number, z: number, radius: number }
export type Point = { x: number, z: number }

-- What a plateau's centre keeps clear of: the start, the chest and the edge.
export type PlateauBounds = {
	inner: number,
	chestX: number,
	chestZ: number,
	chestClear: number,
	attempts: number,
	-- The first `bigCount` plateaus draw a radius of at least `bigRadius`, so a
	-- lair's clearing fits on their tops.
	bigCount: number,
	bigRadius: number,
}

-- A point uniform by area in the disc of `radius` around the origin.
function Terrain.randomInDisc(rng: Types.Rng, radius: number): (number, number)
	local r = radius * math.sqrt(rng:next())
	local angle = rng:next() * 2 * math.pi
	return r * math.cos(angle), r * math.sin(angle)
end

-- The ramps' bearings: rampCountMin..rampCountMax, the first facing the start
-- within rampStartConeDegrees, every other at least rampSpacingDegrees from
-- the rest (dropped when no draw finds such a bearing).
local function drawRamps(
	config: Types.TerrainConfig,
	rng: Types.Rng,
	x: number,
	z: number,
	attempts: number
): { number }
	local count = rng:integer(config.rampCountMin, config.rampCountMax)
	local cone = math.rad(config.rampStartConeDegrees)
	local spacing = math.rad(config.rampSpacingDegrees)
	local ramps = { Geometry.angle(-x, -z) + (rng:next() * 2 - 1) * cone }
	for _ = 2, count do
		for _ = 1, attempts do
			local bearing = rng:next() * 2 * math.pi
			local apart = true
			for _, other in ramps do
				if Geometry.angleBetween(bearing, other) < spacing then
					apart = false
					break
				end
			end
			if apart then
				table.insert(ramps, bearing)
				break
			end
		end
	end
	return ramps
end

-- The plateaus: their count drawn in its range, each with its radius and
-- height, its centre found within `attempts` draws (else skipped) at
-- plateauStartDistance from the start, clear of the chest's ground, inside
-- the edge with its cliffs and plateauSpacing beyond the radii from the others.
function Terrain.plateaus(
	config: Types.TerrainConfig,
	rng: Types.Rng,
	bounds: PlateauBounds
): { Types.Plateau }
	local plateaus: { Types.Plateau } = {}
	local count = rng:integer(config.plateauCountMin, config.plateauCountMax)
	for index = 1, count do
		local low = config.plateauRadiusMin
		if index <= bounds.bigCount then
			low = math.clamp(bounds.bigRadius, low, config.plateauRadiusMax)
		end
		local radius = low + (config.plateauRadiusMax - low) * rng:next()
		local height = config.plateauHeightMin
			+ (config.plateauHeightMax - config.plateauHeightMin) * rng:next()
		local outer = radius + config.cliffRadius
		for _ = 1, bounds.attempts do
			local x, z = Terrain.randomInDisc(rng, math.max(bounds.inner - outer, 0))
			local free = Geometry.distance(x, z, 0, 0) >= config.plateauStartDistance
				and Geometry.distance(x, z, bounds.chestX, bounds.chestZ)
					>= bounds.chestClear + outer
			if free then
				for _, other in plateaus do
					if
						Geometry.distance(x, z, other.x, other.z)
						< config.plateauSpacing + radius + other.radius
					then
						free = false
						break
					end
				end
			end
			if free then
				table.insert(plateaus, {
					id = #plateaus + 1,
					x = x,
					z = z,
					radius = radius,
					height = height,
					ramps = drawRamps(config, rng, x, z, bounds.attempts),
				})
				break
			end
		end
	end
	return plateaus
end

-- Whether a cliff circle on the bearing would stand on a ramp: its centre
-- within rampWidth/2 plus its own radius along the ring, so the gap between
-- the circles either side is at least rampWidth.
function Terrain.onRamp(
	config: Types.TerrainConfig,
	plateau: Types.Plateau,
	bearing: number
): boolean
	for _, ramp in plateau.ramps do
		if
			Geometry.angleBetween(bearing, ramp) * plateau.radius
			< config.rampWidth / 2 + config.cliffRadius
		then
			return true
		end
	end
	return false
end

-- The cliff ring: circles of cliffRadius at most cliffStep apart along the
-- ring of the plateau's radius, none on a ramp.
function Terrain.cliffRing(config: Types.TerrainConfig, plateau: Types.Plateau): { Circle }
	local count = math.max(math.ceil(2 * math.pi * plateau.radius / config.cliffStep), 3)
	local circles: { Circle } = {}
	for index = 0, count - 1 do
		local bearing = index * 2 * math.pi / count
		if not Terrain.onRamp(config, plateau, bearing) then
			table.insert(circles, {
				x = plateau.x + math.cos(bearing) * plateau.radius,
				z = plateau.z + math.sin(bearing) * plateau.radius,
				radius = config.cliffRadius,
			})
		end
	end
	return circles
end

-- The foot of a ramp: `reach` studs beyond the ring on its bearing.
function Terrain.rampFoot(plateau: Types.Plateau, bearing: number, reach: number): (number, number)
	local distance = plateau.radius + reach
	return plateau.x + math.cos(bearing) * distance, plateau.z + math.sin(bearing) * distance
end

-- The distance from (x, z) to the nearest point of a polyline.
function Terrain.lineDistance(points: { Point }, x: number, z: number): number
	if #points == 1 then
		return Geometry.distance(x, z, points[1].x, points[1].z)
	end
	local best = math.huge
	for index = 2, #points do
		local a, b = points[index - 1], points[index]
		local dx, dz = b.x - a.x, b.z - a.z
		local length2 = dx * dx + dz * dz
		local t = if length2 < 1e-12 then 0 else ((x - a.x) * dx + (z - a.z) * dz) / length2
		t = math.clamp(t, 0, 1)
		best = math.min(best, Geometry.distance(x, z, a.x + dx * t, a.z + dz * t))
	end
	return best
end

-- The polyline's points every `step` studs along it, its ends kept.
local function resample(points: { Point }, step: number): { Point }
	local out: { Point } = { { x = points[1].x, z = points[1].z } }
	local carried = 0
	for index = 2, #points do
		local a, b = points[index - 1], points[index]
		local length = Geometry.distance(a.x, a.z, b.x, b.z)
		local at = step - carried
		while at <= length - 1e-9 do
			local t = at / length
			table.insert(out, { x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t })
			at += step
		end
		carried = length - (at - step)
	end
	local last = points[#points]
	local tail = out[#out]
	if Geometry.distance(tail.x, tail.z, last.x, last.z) < step * 0.5 and #out > 1 then
		out[#out] = { x = last.x, z = last.z }
	else
		table.insert(out, { x = last.x, z = last.z })
	end
	return out
end

-- Pushes the inner points out of every circle sideways, across the stream's
-- direction (ux, uz), all to the side of the circle the line passes nearest,
-- so the line bends round a clearing rather than through it; then keeps
-- them inside the edge.
local function push(points: { Point }, avoid: { Circle }, ux: number, uz: number, radius: number)
	local nx, nz = -uz, ux
	for _, circle in avoid do
		local side, nearest = 1, math.huge
		for _, point in points do
			local d = Geometry.distance(point.x, point.z, circle.x, circle.z)
			if d < nearest then
				nearest = d
				side = if (point.x - circle.x) * nx + (point.z - circle.z) * nz < 0 then -1 else 1
			end
		end
		if nearest < circle.radius then
			for index = 2, #points - 1 do
				local point = points[index]
				local ox, oz = point.x - circle.x, point.z - circle.z
				if ox * ox + oz * oz < circle.radius * circle.radius then
					local along = ox * ux + oz * uz
					local across = side * math.sqrt(circle.radius * circle.radius - along * along)
					point.x = circle.x + ux * along + nx * across
					point.z = circle.z + uz * along + nz * across
				end
			end
		end
	end
	for index = 2, #points - 1 do
		local point = points[index]
		local d = Geometry.distance(point.x, point.z, 0, 0)
		if d > radius then
			point.x, point.z = point.x / d * radius, point.z / d * radius
		end
	end
end

-- Moves every inner point a quarter of the way to its neighbours' middle.
local function smooth(points: { Point })
	local previous = { x = points[1].x, z = points[1].z }
	for index = 2, #points - 1 do
		local point, nextPoint = points[index], points[index + 1]
		local x = (previous.x + 2 * point.x + nextPoint.x) / 4
		local z = (previous.z + 2 * point.z + nextPoint.z) / 4
		previous = { x = point.x, z = point.z }
		point.x, point.z = x, z
	end
end

-- How many points break a rule: inside a circle, or too far from the next.
local function faults(points: { Point }, avoid: { Circle }, maxGap: number): number
	local count = 0
	for index, point in points do
		for _, circle in avoid do
			if Geometry.distance(point.x, point.z, circle.x, circle.z) < circle.radius - 1e-6 then
				count += 1
				break
			end
		end
		local nextPoint = points[index + 1]
		if nextPoint and Geometry.distance(point.x, point.z, nextPoint.x, nextPoint.z) > maxGap then
			count += 1
		end
	end
	return count
end

-- One draw of the centre line: from the edge on a random bearing to the
-- opposite side, a point every channelStep, swaying across by up to
-- streamSway on one or two sine waves of random phase, back on the chord at
-- both ends; then bent out of the `avoid` circles.
local function drawLine(
	config: Types.TerrainConfig,
	rng: Types.Rng,
	radius: number,
	avoid: { Circle }
): { Point }
	local bearing = rng:next() * 2 * math.pi
	local amplitude = config.streamSway * (0.5 + 0.5 * rng:next())
	local waves = rng:integer(1, 2)
	local phase = rng:next() * 2 * math.pi
	local ax, az = math.cos(bearing) * radius, math.sin(bearing) * radius
	local ux, uz = -math.cos(bearing), -math.sin(bearing)
	local nx, nz = -uz, ux
	local steps = math.max(math.ceil(2 * radius / config.channelStep), 2)
	local points: { Point } = table.create(steps + 1)
	for index = 0, steps do
		local t = index / steps
		local sway = amplitude * math.sin(t * waves * 2 * math.pi + phase) * math.sin(t * math.pi)
		local along = t * 2 * radius
		table.insert(points, { x = ax + ux * along + nx * sway, z = az + uz * along + nz * sway })
	end
	for _ = 1, RELAX_PASSES do
		push(points, avoid, ux, uz, radius)
		smooth(points)
		points = resample(points, config.channelStep)
	end
	push(points, avoid, ux, uz, radius)
	points = resample(points, config.channelStep)
	push(points, avoid, ux, uz, radius)
	return points
end

-- The fords: fordCount points along the line, off its first and last
-- fordEndShare, and fordSpacingShare of its length from each other both
-- along the line and straight across (a line that bends back must not bring
-- two fords together), each found within `attempts` draws, else the draw
-- with the most room.
local function drawFords(
	config: Types.TerrainConfig,
	rng: Types.Rng,
	points: { Point },
	attempts: number
): { Types.Ford }
	local lengths = { 0 }
	for index = 2, #points do
		local a, b = points[index - 1], points[index]
		lengths[index] = lengths[index - 1] + Geometry.distance(a.x, a.z, b.x, b.z)
	end
	local total = lengths[#lengths]
	-- The point at `share` of the line's length.
	local function pointAt(share: number): Point
		local at = share * total
		for index = 2, #points do
			if lengths[index] >= at then
				local a, b = points[index - 1], points[index]
				local piece = lengths[index] - lengths[index - 1]
				local t = if piece < 1e-9 then 0 else (at - lengths[index - 1]) / piece
				return { x = a.x + (b.x - a.x) * t, z = a.z + (b.z - a.z) * t }
			end
		end
		local last = points[#points]
		return { x = last.x, z = last.z }
	end
	local ends = config.fordEndShare
	local span = 1 - 2 * ends
	local spacing = config.fordSpacingShare
	local chosen: { { share: number, point: Point } } = {}
	for _ = 1, config.fordCount do
		-- The draw farthest from the fords chosen, measured in spacings, kept
		-- when none is a full spacing away.
		local pick, pickRoom = nil, -math.huge
		for _ = 1, math.max(attempts, 1) do
			local share = ends + span * rng:next()
			local point = pointAt(share)
			local room = math.huge
			for _, other in chosen do
				room = math.min(
					room,
					math.abs(share - other.share) / spacing,
					Geometry.distance(point.x, point.z, other.point.x, other.point.z)
						/ (spacing * total)
				)
			end
			if room > pickRoom then
				pick, pickRoom = { share = share, point = point }, room
			end
			if room >= 1 then
				break
			end
		end
		table.insert(chosen, pick :: { share: number, point: Point })
	end
	table.sort(chosen, function(a, b)
		return a.share < b.share
	end)
	local fords: { Types.Ford } = {}
	for _, pick in chosen do
		table.insert(fords, { x = pick.point.x, z = pick.point.z, radius = config.fordRadius })
	end
	return fords
end

-- The stream: up to `attempts` draws of the centre line, the first that keeps
-- out of every `avoid` circle with no gap kept, else the one with the fewest
-- faults; then its fords. The circles' radii are the clearings' own: the
-- channel and the bank are added here.
function Terrain.stream(
	config: Types.TerrainConfig,
	rng: Types.Rng,
	radius: number,
	clearings: { Circle },
	attempts: number
): Types.Stream
	local band = config.channelHalfWidth + config.bankWidth
	local avoid: { Circle } = table.create(#clearings)
	for _, clearing in clearings do
		table.insert(avoid, { x = clearing.x, z = clearing.z, radius = clearing.radius + band })
	end
	local maxGap = config.channelStep * MAX_GAP_SHARE
	local best: { Point }? = nil
	local bestFaults = math.huge
	for _ = 1, math.max(attempts, 1) do
		local points = drawLine(config, rng, radius, avoid)
		local count = faults(points, avoid, maxGap)
		if count < bestFaults then
			best, bestFaults = points, count
		end
		if count == 0 then
			break
		end
	end
	local points = best :: { Point }
	return {
		points = points,
		channelHalfWidth = config.channelHalfWidth,
		bankWidth = config.bankWidth,
		fords = drawFords(config, rng, points, attempts),
	}
end

-- Whether (x, z) lies within a ford's radius.
function Terrain.inFord(stream: Types.Stream, x: number, z: number): boolean
	for _, ford in stream.fords do
		if Geometry.distance(x, z, ford.x, ford.z) < ford.radius then
			return true
		end
	end
	return false
end

-- The deep channel: a circle of channelHalfWidth on every point of the line
-- but those whose circle would reach into a ford, so a ford's gap is at
-- least its diameter.
function Terrain.channel(stream: Types.Stream): { Circle }
	local circles: { Circle } = {}
	for _, point in stream.points do
		local open = false
		for _, ford in stream.fords do
			if
				Geometry.distance(point.x, point.z, ford.x, ford.z)
				< ford.radius + stream.channelHalfWidth
			then
				open = true
				break
			end
		end
		if not open then
			table.insert(circles, { x = point.x, z = point.z, radius = stream.channelHalfWidth })
		end
	end
	return circles
end

-- The shallows: a circle of the channel and its bank on every point of the
-- line, the fords included (a ford is shallow all across).
function Terrain.shallows(stream: Types.Stream): { Types.SlowZone }
	local zones: { Types.SlowZone } = {}
	for _, point in stream.points do
		table.insert(zones, {
			x = point.x,
			z = point.z,
			radius = stream.channelHalfWidth + stream.bankWidth,
		})
	end
	return zones
end

return Terrain
