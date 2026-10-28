--!strict
local Arena = require("../src/shared/Core/Arena")
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Rng = require("../src/shared/Core/Rng")
local Terrain = require("../src/shared/Core/Terrain")
local Types = require("../src/shared/Core/Types")

local SEEDS = 10

-- An arena with the lairs, the shrines and the terrain.
local function terrainArenaOf(seed: number): (Types.Arena, Types.Config)
	local config = Fixtures.config()
	local map = config.maps[config.map]
	return Arena.generate(map, Rng.new(seed), config.shrines, config.lairs, config.terrain), config
end

local function streamOf(arena: Types.Arena): Types.Stream
	local stream = arena.terrain.stream
	assert(stream, "the terrain has a stream")
	return stream
end

-- The plateau whose centre the spot stands on, if any.
local function plateauUnder(arena: Types.Arena, x: number, z: number): Types.Plateau?
	for _, plateau in arena.terrain.plateaus do
		if plateau.x == x and plateau.z == z then
			return plateau
		end
	end
	return nil
end

local function lairKind(config: Types.Config, id: string): Types.LairKindConfig
	for _, kind in config.lairs.kinds do
		if kind.id == id then
			return kind
		end
	end
	error("no lair kind " .. id)
end

-- The unit direction across the line at its point `index`.
local function across(points: { { x: number, z: number } }, index: number): (number, number)
	local a = points[math.max(index - 1, 1)]
	local b = points[math.min(index + 1, #points)]
	local ux, uz = Geometry.normalize(b.x - a.x, b.z - a.z)
	return -uz, ux
end

local function hasPad(arena: Types.Arena, x: number, z: number, radius: number): boolean
	for _, pad in arena.terrain.pads do
		if
			Geometry.distance(pad.x, pad.z, x, z) < 1e-9
			and math.abs(pad.radius - radius) < 1e-9
		then
			return true
		end
	end
	return false
end

local function deepEqual(a: any, b: any): boolean
	if type(a) ~= "table" or type(b) ~= "table" then
		return a == b
	end
	for key, value in a do
		if not deepEqual(value, b[key]) then
			return false
		end
	end
	for key in b do
		if a[key] == nil then
			return false
		end
	end
	return true
end

return {
	["plateaus keep their count, sizes and distances"] = function()
		for seed = 1, SEEDS do
			local arena, config = terrainArenaOf(seed)
			local terrain, map = config.terrain, config.maps[config.map]
			local plateaus = arena.terrain.plateaus
			Assert.truthy(
				#plateaus >= terrain.plateauCountMin,
				"seed " .. seed .. ": too few plateaus"
			)
			Assert.truthy(
				#plateaus <= terrain.plateauCountMax,
				"seed " .. seed .. ": too many plateaus"
			)
			for _, plateau in plateaus do
				Assert.truthy(
					plateau.radius >= terrain.plateauRadiusMin
						and plateau.radius <= terrain.plateauRadiusMax
				)
				Assert.truthy(
					plateau.height >= terrain.plateauHeightMin
						and plateau.height <= terrain.plateauHeightMax
				)
				Assert.truthy(
					Geometry.distance(plateau.x, plateau.z, 0, 0) >= terrain.plateauStartDistance
				)
				Assert.truthy(
					Geometry.distance(plateau.x, plateau.z, 0, 0)
							+ plateau.radius
							+ terrain.cliffRadius
						<= map.radius - map.edgeMargin + 1e-9,
					"inside the edge"
				)
				Assert.truthy(
					Geometry.distance(plateau.x, plateau.z, arena.chestX, arena.chestZ)
						>= map.chestClearRadius + plateau.radius,
					"off the chest's ground"
				)
				for _, other in plateaus do
					if other ~= plateau then
						Assert.truthy(
							Geometry.distance(plateau.x, plateau.z, other.x, other.z)
								>= terrain.plateauSpacing + plateau.radius + other.radius,
							"plateau spacing"
						)
					end
				end
			end
		end
	end,

	["a plateau's ramps are in range and at least a right angle apart"] = function()
		for seed = 1, SEEDS do
			local arena, config = terrainArenaOf(seed)
			for _, plateau in arena.terrain.plateaus do
				Assert.truthy(#plateau.ramps >= config.terrain.rampCountMin)
				Assert.truthy(#plateau.ramps <= config.terrain.rampCountMax)
				-- The first ramp faces the start.
				local toStart = Geometry.angle(-plateau.x, -plateau.z)
				Assert.truthy(
					Geometry.angleBetween(plateau.ramps[1], toStart) <= math.pi / 4 + 1e-9
				)
				for index, ramp in plateau.ramps do
					for other = index + 1, #plateau.ramps do
						Assert.truthy(
							Geometry.angleBetween(ramp, plateau.ramps[other]) >= math.pi / 2
						)
					end
				end
			end
		end
	end,

	["the cliff ring stands on the plateau's edge, off the ramps"] = function()
		local arena, config = terrainArenaOf(1)
		local terrain = config.terrain
		local groups: { [number]: boolean } = {}
		for _, obstacle in arena.obstacles do
			if obstacle.kind == "cliff" then
				groups[obstacle.group] = true
				Assert.equal(obstacle.radius, terrain.cliffRadius)
				local found = false
				for _, plateau in arena.terrain.plateaus do
					local distance = Geometry.distance(obstacle.x, obstacle.z, plateau.x, plateau.z)
					if math.abs(distance - plateau.radius) < 1e-6 then
						found = true
						local bearing =
							Geometry.angle(obstacle.x - plateau.x, obstacle.z - plateau.z)
						Assert.falsy(Terrain.onRamp(terrain, plateau, bearing), "a cliff on a ramp")
					end
				end
				Assert.truthy(found, "a cliff off every ring")
			end
		end
		local count = 0
		for _ in groups do
			count += 1
		end
		Assert.equal(count, #arena.terrain.plateaus, "one group per plateau")
	end,

	["a hero crosses the cliff ring at a ramp and nowhere else"] = function()
		for seed = 1, SEEDS do
			local arena, config = terrainArenaOf(seed)
			local body = config.player.radius
			for _, plateau in arena.terrain.plateaus do
				local function crossing(bearing: number): (number, number)
					local cos, sin = math.cos(bearing), math.sin(bearing)
					local inner, outer = plateau.radius - 6, plateau.radius + 6
					local reach = Arena.reach(
						arena,
						plateau.x + cos * inner,
						plateau.z + sin * inner,
						plateau.x + cos * outer,
						plateau.z + sin * outer,
						body
					)
					return reach, outer - inner
				end
				for _, ramp in plateau.ramps do
					local reach, length = crossing(ramp)
					Assert.near(reach, length, 1e-6, "seed " .. seed .. ": a ramp is blocked")
				end
				for step = 0, 71 do
					local bearing = step * 2 * math.pi / 72
					if not Terrain.onRamp(config.terrain, plateau, bearing) then
						local nearRamp = false
						for _, ramp in plateau.ramps do
							-- The ramp's gap reaches a little past its arc between two circles.
							if
								Geometry.angleBetween(bearing, ramp) * plateau.radius
								< config.terrain.rampWidth / 2 + config.terrain.cliffStep + body
							then
								nearRamp = true
							end
						end
						if not nearRamp then
							local reach, length = crossing(bearing)
							Assert.truthy(
								reach < length,
								"seed " .. seed .. ": the cliff lets a hero through"
							)
						end
					end
				end
			end
		end
	end,

	["one or two lairs stand on plateaus, their kits on the top"] = function()
		for seed = 1, SEEDS do
			local arena, config = terrainArenaOf(seed)
			local terrain = config.terrain
			local onPlateaus = 0
			for _, spot in arena.lairSpots do
				local kind = lairKind(config, spot.kind)
				local plateau = plateauUnder(arena, spot.x, spot.z)
				if plateau then
					onPlateaus += 1
					Assert.truthy(plateau.radius >= kind.clearRadius + terrain.cliffRadius)
					local top = plateau.radius - terrain.cliffRadius
					for _, obstacle in arena.obstacles do
						if
							obstacle.kind ~= "cliff"
							and Geometry.distance(obstacle.x, obstacle.z, spot.x, spot.z)
								< kind.clearRadius
						then
							Assert.truthy(
								Geometry.distance(obstacle.x, obstacle.z, spot.x, spot.z)
										+ obstacle.radius
									<= top,
								spot.kind .. ": a kit's prop off the top"
							)
						end
					end
				else
					for _, other in arena.terrain.plateaus do
						Assert.truthy(
							Geometry.distance(spot.x, spot.z, other.x, other.z)
								> other.radius + kind.clearRadius,
							"a plain lair on a plateau"
						)
					end
				end
			end
			Assert.truthy(
				onPlateaus >= terrain.lairsOnPlateauMin,
				"seed " .. seed .. ": too few lairs on plateaus"
			)
			Assert.truthy(
				onPlateaus <= terrain.lairsOnPlateauMax,
				"seed " .. seed .. ": too many lairs on plateaus"
			)
			-- The places keep off the plateaus.
			for _, place in arena.places do
				if plateauUnder(arena, place.x, place.z) == nil then
					for _, plateau in arena.terrain.plateaus do
						Assert.truthy(
							Geometry.distance(place.x, place.z, plateau.x, plateau.z)
								> plateau.radius + place.radius
						)
					end
				end
			end
		end
	end,

	["the stream runs edge to edge, closed, round every clearing"] = function()
		for seed = 1, SEEDS do
			local arena, config = terrainArenaOf(seed)
			local terrain, map = config.terrain, config.maps[config.map]
			local stream = streamOf(arena)
			local points = stream.points
			local first, last = points[1], points[#points]
			Assert.near(Geometry.distance(first.x, first.z, 0, 0), map.radius, 1e-6)
			Assert.near(Geometry.distance(last.x, last.z, 0, 0), map.radius, 1e-6)
			Assert.truthy(
				Geometry.distance(first.x, first.z, last.x, last.z) > map.radius,
				"to the other side"
			)
			local band = terrain.channelHalfWidth + terrain.bankWidth
			for index, point in points do
				Assert.truthy(Geometry.distance(point.x, point.z, 0, 0) <= map.radius + 1e-6)
				local nextPoint = points[index + 1]
				if nextPoint then
					-- Neighbouring channel circles overlap or leave no room for a body.
					Assert.truthy(
						Geometry.distance(point.x, point.z, nextPoint.x, nextPoint.z)
							< 2 * terrain.channelHalfWidth + 2 * config.player.radius,
						"seed " .. seed .. ": a gap in the line"
					)
				end
				Assert.truthy(
					Geometry.distance(point.x, point.z, 0, 0) >= map.startClearRadius + band - 1e-6
				)
				Assert.truthy(
					Geometry.distance(point.x, point.z, arena.chestX, arena.chestZ)
						>= map.chestClearRadius + band - 1e-6
				)
				for _, place in arena.places do
					Assert.truthy(
						Geometry.distance(point.x, point.z, place.x, place.z)
							>= place.radius + band - 1e-6,
						"seed " .. seed .. ": the stream cuts " .. place.kind
					)
				end
				for _, plateau in arena.terrain.plateaus do
					Assert.truthy(
						Geometry.distance(point.x, point.z, plateau.x, plateau.z)
							>= plateau.radius + terrain.cliffRadius + band - 1e-6,
						"seed " .. seed .. ": the stream cuts a plateau"
					)
				end
			end
		end
	end,

	["the channel blocks a hero across the stream except at the fords"] = function()
		for seed = 1, SEEDS do
			local arena, config = terrainArenaOf(seed)
			local terrain = config.terrain
			local stream = streamOf(arena)
			local points = stream.points
			Assert.equal(#stream.fords, terrain.fordCount)
			local channels = 0
			for _, obstacle in arena.obstacles do
				if obstacle.kind == "channel" then
					channels += 1
					Assert.falsy(
						Terrain.inFord(stream, obstacle.x, obstacle.z),
						"a channel circle in a ford"
					)
				end
			end
			Assert.truthy(channels > 0)
			local reachAcross = 7
			for index = 2, #points - 1 do
				local point = points[index]
				if not Terrain.inFord(stream, point.x, point.z) then
					local nearFord = false
					for _, ford in stream.fords do
						if
							Geometry.distance(point.x, point.z, ford.x, ford.z)
							< ford.radius + terrain.channelHalfWidth + config.player.radius
						then
							nearFord = true
						end
					end
					if not nearFord then
						local nx, nz = across(points, index)
						local reach = Arena.reach(
							arena,
							point.x - nx * reachAcross,
							point.z - nz * reachAcross,
							point.x + nx * reachAcross,
							point.z + nz * reachAcross,
							config.player.radius
						)
						Assert.truthy(
							reach < 2 * reachAcross,
							"seed " .. seed .. ": the channel lets a hero through"
						)
					end
				end
			end
			-- A ford is crossed: its length lies along the line, so cross it square.
			for _, ford in stream.fords do
				local nearest, best = 1, math.huge
				for index, point in points do
					local d = Geometry.distance(point.x, point.z, ford.x, ford.z)
					if d < best then
						nearest, best = index, d
					end
				end
				local nx, nz = across(points, nearest)
				local reach = Arena.reach(
					arena,
					ford.x - nx * reachAcross,
					ford.z - nz * reachAcross,
					ford.x + nx * reachAcross,
					ford.z + nz * reachAcross,
					config.player.radius
				)
				Assert.near(reach, 2 * reachAcross, 1e-6, "seed " .. seed .. ": a ford is blocked")
			end
		end
	end,

	["shallow water lines the stream, covers the fords and rims the ponds"] = function()
		local arena, config = terrainArenaOf(1)
		local terrain = config.terrain
		local stream = streamOf(arena)
		local band = terrain.channelHalfWidth + terrain.bankWidth
		for _, point in stream.points do
			local found = false
			for _, zone in arena.terrain.slowZones do
				if zone.x == point.x and zone.z == point.z and zone.radius == band then
					found = true
				end
			end
			Assert.truthy(found, "a point of the line without its shallows")
		end
		for _, ford in stream.fords do
			Assert.equal(Arena.slowFactor(arena, terrain, ford.x, ford.z), terrain.shallowFactor)
		end
		-- The bank slows; beyond it the ground does not.
		local point = stream.points[math.floor(#stream.points / 2)]
		local nx, nz = across(stream.points, math.floor(#stream.points / 2))
		local bank = terrain.channelHalfWidth + terrain.bankWidth / 2
		Assert.equal(
			Arena.slowFactor(arena, terrain, point.x + nx * bank, point.z + nz * bank),
			terrain.shallowFactor
		)
		Assert.equal(Arena.slowFactor(arena, terrain, 0, 0), 1)
		local ponds = 0
		for _, obstacle in arena.obstacles do
			if obstacle.kind == "pond" then
				ponds += 1
			end
		end
		Assert.equal(#arena.terrain.ponds, ponds)
		for _, pond in arena.terrain.ponds do
			Assert.equal(pond.rimWidth, terrain.pondRimWidth)
			local rim = pond.radius + pond.rimWidth / 2
			Assert.equal(
				Arena.slowFactor(arena, terrain, pond.x + rim, pond.z),
				terrain.shallowFactor
			)
			Assert.equal(
				Arena.slowFactor(arena, terrain, pond.x + pond.radius + pond.rimWidth + 1, pond.z),
				1
			)
		end
	end,

	["the shrines keep out of the water"] = function()
		for seed = 1, SEEDS do
			local arena, config = terrainArenaOf(seed)
			for _, spot in arena.shrineSpots do
				Assert.equal(Arena.slowFactor(arena, config.terrain, spot.x, spot.z), 1)
			end
		end
	end,

	["pads flatten the start, the chest, the places, the lairs and the plateau tops"] = function()
		for seed = 1, SEEDS do
			local arena, config = terrainArenaOf(seed)
			local map = config.maps[config.map]
			Assert.truthy(hasPad(arena, 0, 0, map.startClearRadius), "the start")
			Assert.truthy(
				hasPad(arena, arena.chestX, arena.chestZ, map.chestClearRadius),
				"the chest"
			)
			for _, place in arena.places do
				Assert.truthy(hasPad(arena, place.x, place.z, place.radius), place.kind)
			end
			for _, plateau in arena.terrain.plateaus do
				Assert.truthy(
					hasPad(arena, plateau.x, plateau.z, plateau.radius - config.terrain.cliffRadius)
				)
			end
			-- A path's pads stay off the water and the plateaus' rings.
			for _, pad in arena.terrain.pads do
				if pad.radius == map.pathWidth + 2 then
					Assert.equal(Arena.slowFactor(arena, config.terrain, pad.x, pad.z), 1)
				end
			end
		end
	end,

	["the same seed lays out the same terrain and another seed another"] = function()
		local a = terrainArenaOf(4)
		local b = terrainArenaOf(4)
		local c = terrainArenaOf(5)
		Assert.truthy(deepEqual(a.terrain, b.terrain), "the same seed")
		Assert.truthy(deepEqual(a.obstacles, b.obstacles), "the same obstacles")
		Assert.falsy(deepEqual(a.terrain, c.terrain), "another seed")
	end,

	["without the terrain's config the ground stays flat"] = function()
		local config = Fixtures.config()
		local arena =
			Arena.generate(config.maps[config.map], Rng.new(1), config.shrines, config.lairs)
		Assert.equal(#arena.terrain.plateaus, 0)
		Assert.equal(arena.terrain.stream, nil)
		Assert.equal(#arena.terrain.slowZones, 0)
		for _, obstacle in arena.obstacles do
			Assert.truthy(obstacle.kind ~= "cliff" and obstacle.kind ~= "channel")
		end
		Assert.equal(Arena.slowFactor(arena, config.terrain, 0, 0), 1)
	end,
}
