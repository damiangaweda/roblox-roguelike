--!strict
local Arena = require("../src/shared/Core/Arena")
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Rng = require("../src/shared/Core/Rng")
local Types = require("../src/shared/Core/Types")

-- The obstacle kind of `id` on the run's map.
local function kindOf(map: Types.MapConfig, id: string): any
	for _, kind in map.obstacleKinds do
		if kind.id == id then
			return kind
		end
	end
	error("no obstacle kind " .. id)
end

-- The obstacles of each group, in the order placed.
local function groups(arena: Types.Arena): { [number]: { Types.Obstacle } }
	local byGroup: { [number]: { Types.Obstacle } } = {}
	for _, obstacle in arena.obstacles do
		local list = byGroup[obstacle.group] or {}
		table.insert(list, obstacle)
		byGroup[obstacle.group] = list
	end
	return byGroup
end

local function spots(seed: number): { Types.ShrineSpot }
	local config = Fixtures.config()
	local map = config.maps[config.map]
	return Arena.generate(map, Rng.new(seed), config.shrines).shrineSpots
end

-- An arena with the lairs, as the run generates it.
local function lairArenaOf(seed: number): (Types.Arena, Types.MapConfig, Types.LairsConfig)
	local config = Fixtures.config()
	local map = config.maps[config.map]
	return Arena.generate(map, Rng.new(seed), config.shrines, config.lairs), map, config.lairs
end

local function arenaOf(seed: number): (Types.Arena, Types.MapConfig)
	local config = Fixtures.config()
	local map = config.maps[config.map]
	return Arena.generate(map, Rng.new(seed), config.shrines), map
end

-- Whether the circle is the terrain's (ADR-0023): a cliff or the channel,
-- which reach the edge and border the kits and each other.
local function isTerrain(obstacle: Types.Obstacle): boolean
	return obstacle.kind == "cliff" or obstacle.kind == "channel"
end

-- The place whose clearing holds the circle's centre: its kit's props are the
-- only obstacles there.
local function placeOf(arena: Types.Arena, obstacle: Types.Obstacle): Types.Place?
	for _, place in arena.places do
		if Geometry.distance(obstacle.x, obstacle.z, place.x, place.z) <= place.radius then
			return place
		end
	end
	return nil
end

local function placeKindOf(map: Types.MapConfig, id: string): Types.PlaceKind
	for _, kind in map.placeKinds do
		if kind.id == id then
			return kind
		end
	end
	error("no place kind " .. id)
end

local function turn(dx: number, dz: number, rotation: number): (number, number)
	local cos, sin = math.cos(rotation), math.sin(rotation)
	return dx * cos - dz * sin, dx * sin + dz * cos
end

local function deepEqual(a: any, b: any, path: string)
	if type(a) ~= "table" or type(b) ~= "table" then
		Assert.equal(a, b, path)
		return
	end
	for key, value in a do
		deepEqual(value, b[key], path .. "." .. tostring(key))
	end
	for key in b do
		Assert.truthy(a[key] ~= nil, path .. "." .. tostring(key) .. " missing")
	end
end

return {
	["the composition keeps its spacing and the clear ground"] = function()
		local run = Fixtures.run(1, nil, 7)
		local map = run.map
		local arena = run.arena
		Assert.truthy(#arena.obstacles > 100, "too few obstacles: " .. #arena.obstacles)
		for i, a in arena.obstacles do
			Assert.truthy(
				Geometry.distance(a.x, a.z, 0, 0) >= map.startClearRadius + a.radius - 1e-6,
				"start clear"
			)
			Assert.truthy(
				Geometry.distance(a.x, a.z, arena.chestX, arena.chestZ)
					>= map.chestClearRadius + a.radius - 1e-6,
				"chest clear"
			)
			Assert.truthy(
				isTerrain(a)
					or Geometry.distance(a.x, a.z, 0, 0) + a.radius
						<= map.radius - map.edgeMargin + 1e-6,
				"inside"
			)
			local placeA = placeOf(arena, a)
			for j, b in arena.obstacles do
				-- A prop's own circles may touch, and so may a place's kit; the
				-- terrain's circles border each other and the kits; every other
				-- prop keeps its spacing.
				local placeB = placeOf(arena, b)
				local terrainPair = (isTerrain(a) and (isTerrain(b) or placeB ~= nil))
					or (isTerrain(b) and placeA ~= nil)
				if
					i < j
					and a.group ~= b.group
					and (placeA == nil or placeA ~= placeB)
					and not terrainPair
				then
					Assert.truthy(
						Geometry.distance(a.x, a.z, b.x, b.z)
							>= a.radius + b.radius + map.obstacleSpacing - 1e-6,
						"spacing"
					)
				end
			end
		end
		Assert.truthy(
			Geometry.distance(0, 0, arena.chestX, arena.chestZ) >= map.chestMinDistance,
			"chest far"
		)
	end,

	["places are dealt every kind before a repeat and keep their distances"] = function()
		for seed = 1, 8 do
			local arena, map = arenaOf(seed)
			-- A site shadowed by a plateau may be skipped, never added.
			Assert.truthy(#arena.places <= map.placeCount, "seed " .. seed .. ": too many")
			Assert.truthy(#arena.places >= map.placeCount - 3, "seed " .. seed .. ": too few")
			local seen: { [string]: boolean } = {}
			for index = 1, #map.placeKinds do
				local kind = arena.places[index].kind
				Assert.falsy(seen[kind], "repeated before every kind: " .. kind)
				seen[kind] = true
			end
			for i, place in arena.places do
				Assert.truthy(
					Geometry.distance(place.x, place.z, 0, 0) >= map.placeStartDistance,
					"start"
				)
				Assert.truthy(
					Geometry.distance(place.x, place.z, arena.chestX, arena.chestZ)
						>= map.chestClearRadius + place.radius,
					"chest"
				)
				Assert.truthy(
					Geometry.distance(place.x, place.z, 0, 0) + place.radius
						<= map.radius - map.edgeMargin + 1e-6,
					"inside"
				)
				for j, other in arena.places do
					if i < j then
						Assert.truthy(
							Geometry.distance(place.x, place.z, other.x, other.z)
								>= map.placeSpacing,
							"spacing"
						)
					end
				end
			end
		end
	end,

	["every prop of a place's kit stands at its turned offset"] = function()
		local arena, map = arenaOf(3)
		local byGroup = groups(arena)
		for _, place in arena.places do
			for _, prop in placeKindOf(map, place.kind).props do
				local dx, dz = turn(prop.dx, prop.dz, place.rotation)
				local x, z = place.x + dx, place.z + dz
				local rotation = place.rotation + (prop.rotation or 0)
				local kind = kindOf(map, prop.kind)
				local found = false
				for _, circles in byGroup do
					local anchor = circles[1]
					if anchor.kind == prop.kind and math.abs(anchor.rotation - rotation) < 1e-9 then
						-- The prop's centre, found from the anchor's footprint offset.
						local fx, fz = 0, 0
						if kind.footprint then
							fx, fz = turn(kind.footprint[1].dx, kind.footprint[1].dz, rotation)
						end
						if Geometry.distance(anchor.x - fx, anchor.z - fz, x, z) < 1e-6 then
							found = true
							break
						end
					end
				end
				Assert.truthy(found, place.kind .. ": " .. prop.kind .. " missing")
			end
		end
	end,

	["a lair is a place: its clearing, its path, its kit and the places' spacing"] = function()
		for seed = 1, 5 do
			local arena, map, lairs = lairArenaOf(seed)
			Assert.equal(#arena.lairSpots, lairs.count, "seed " .. seed)
			Assert.equal(#arena.paths, #arena.places)
			local byGroup = groups(arena)
			for _, spot in arena.lairSpots do
				local kind: Types.LairKindConfig? = nil
				for _, candidate in lairs.kinds do
					if candidate.id == spot.kind then
						kind = candidate
					end
				end
				local lairKind = kind :: Types.LairKindConfig
				local place: Types.Place? = nil
				for _, candidate in arena.places do
					if candidate.x == spot.x and candidate.z == spot.z then
						place = candidate
					end
				end
				assert(place, "the lair is a place")
				Assert.equal(place.kind, spot.kind)
				Assert.equal(place.radius, lairKind.clearRadius)
				Assert.equal(place.rotation, spot.rotation)
				for _, other in arena.places do
					if other ~= place then
						local gap = Geometry.distance(other.x, other.z, place.x, place.z)
						Assert.truthy(gap >= math.min(map.placeSpacing, lairs.spacing), "spacing")
					end
				end
				-- Only its kit stands in its clearing; every prop at its turned offset.
				local kitKinds = {}
				for _, prop in lairKind.props do
					kitKinds[prop.kind] = true
					local dx, dz = turn(prop.dx, prop.dz, spot.rotation)
					local rotation = spot.rotation + (prop.rotation or 0)
					local propKind = kindOf(map, prop.kind)
					local found = false
					for _, circles in byGroup do
						local anchor = circles[1]
						if
							anchor.kind == prop.kind
							and math.abs(anchor.rotation - rotation) < 1e-9
						then
							local fx, fz = 0, 0
							if propKind.footprint then
								fx, fz = turn(
									propKind.footprint[1].dx,
									propKind.footprint[1].dz,
									rotation
								)
							end
							if
								Geometry.distance(
									anchor.x - fx,
									anchor.z - fz,
									spot.x + dx,
									spot.z + dz
								) < 1e-6
							then
								found = true
								break
							end
						end
					end
					Assert.truthy(found, spot.kind .. ": " .. prop.kind .. " missing")
				end
				for _, obstacle in arena.obstacles do
					if placeOf(arena, obstacle) == place then
						Assert.truthy(
							kitKinds[obstacle.kind],
							obstacle.kind .. " in a lair's clearing"
						)
					end
				end
			end
		end
	end,

	["a grove's trees lie in its disc, densest at the core"] = function()
		local rng = Rng.new(11)
		local radius, core = 40, 0.5
		local inside, outside = 0, 0
		for _ = 1, 20000 do
			local dx, dz = Arena.groveOffset(rng, radius, core)
			if dx and dz then
				local r = math.sqrt(dx * dx + dz * dz)
				Assert.truthy(r <= radius, "inside the disc")
				if r < core * radius then
					inside += 1
				else
					outside += 1
				end
			end
		end
		-- Per area: the core holds a quarter of the disc.
		local coreArea = core * core
		local inner = inside / coreArea
		local outer = outside / (1 - coreArea)
		Assert.truthy(inner > outer * 1.8, "core " .. inner .. " edge " .. outer)
	end,

	["no prop but its own place's kit comes within a path's width"] = function()
		for seed = 1, 5 do
			local arena, map = arenaOf(seed)
			Assert.equal(#arena.paths, #arena.places)
			for index, path in arena.paths do
				local place = arena.places[index]
				Assert.near(path[1].x, 0, 1e-9)
				Assert.near(path[1].z, 0, 1e-9)
				Assert.near(
					Geometry.distance(path[#path].x, path[#path].z, place.x, place.z),
					place.radius,
					1e-6,
					"ends at the clearing"
				)
				for _, obstacle in arena.obstacles do
					if placeOf(arena, obstacle) ~= place then
						Assert.truthy(
							Arena.pathDistance(path, obstacle.x, obstacle.z)
								>= map.pathWidth + obstacle.radius - 1e-6,
							"seed " .. seed .. ": " .. obstacle.kind .. " on a path"
						)
					end
				end
			end
		end
	end,

	["pines rule the north and oaks the south"] = function()
		local north = { pine = 0, oak = 0 }
		local south = { pine = 0, oak = 0 }
		for seed = 1, 12 do
			local arena = arenaOf(seed)
			for _, obstacle in arena.obstacles do
				local kind = obstacle.kind
				if (kind == "pine" or kind == "oak") and placeOf(arena, obstacle) == nil then
					if obstacle.z < -200 then
						north[kind] += 1
					elseif obstacle.z > 200 then
						south[kind] += 1
					end
				end
			end
		end
		Assert.truthy(north.pine > north.oak * 2, "north " .. north.pine .. "/" .. north.oak)
		Assert.truthy(south.oak > south.pine * 2, "south " .. south.oak .. "/" .. south.pine)
	end,

	["every prop varies its scale and lean within the config"] = function()
		local arena, map = arenaOf(2)
		local varied = false
		for _, circles in groups(arena) do
			local first = circles[1]
			Assert.truthy(math.abs(first.scale - 1) <= map.scaleVariation + 1e-9, "scale")
			Assert.truthy(
				first.lean >= 0 and first.lean <= math.rad(map.leanDegrees) + 1e-9,
				"lean"
			)
			for _, circle in circles do
				Assert.equal(circle.scale, first.scale, "one scale per group")
				Assert.equal(circle.lean, first.lean, "one lean per group")
			end
			varied = varied or math.abs(first.scale - 1) > map.scaleVariation * 0.5
		end
		Assert.truthy(varied, "some scale varies")
	end,

	["the same seed composes the same map"] = function()
		local a = arenaOf(21)
		local b = arenaOf(21)
		deepEqual(a, b, "arena")
		local c = arenaOf(22)
		Assert.truthy(a.places[1].x ~= c.places[1].x, "another seed, another map")
	end,

	["the same seed scatters the same obstacles and a different seed others"] = function()
		local a = Fixtures.run(1, nil, 3).arena
		local b = Fixtures.run(1, nil, 3).arena
		local c = Fixtures.run(1, nil, 4).arena
		Assert.equal(#a.obstacles, #b.obstacles)
		for i, obstacle in a.obstacles do
			Assert.equal(obstacle.x, b.obstacles[i].x)
			Assert.equal(obstacle.kind, b.obstacles[i].kind)
		end
		Assert.truthy(a.obstacles[1].x ~= c.obstacles[1].x or a.obstacles[1].z ~= c.obstacles[1].z)
	end,

	["an obstacle blocks movement and reach stops at it"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		table.insert(
			run.arena.obstacles,
			{ id = 1, kind = "rock", x = 20, z = 0, radius = 3, rotation = 0 }
		)
		Assert.near(Arena.reach(run.arena, 0, 0, 40, 0, 1.5), 20 - 4.5, 2e-3)
		Assert.near(Arena.reach(run.arena, 0, 10, 40, 10, 1.5), 40, 1e-6)
		Assert.truthy(Arena.blocking(run.arena, 19, 0, 1.5) ~= nil)
		Assert.truthy(Arena.blocking(run.arena, 0, 0, 1.5) == nil)
		-- Already inside: not held.
		Assert.near(Arena.reach(run.arena, 20, 0, 40, 0, 1.5), 20, 1e-6)
	end,

	["a body at the contact point never walks into the obstacle"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		table.insert(
			run.arena.obstacles,
			{ id = 1, kind = "rock", x = 20, z = 0, radius = 3, rotation = 0 }
		)
		local x, z = 0, 0
		for step = 1, 200 do
			-- Pushing into the rock with a little jitter, as a held key does.
			local tx, tz = x + 2, z + math.sin(step) * 0.3
			local reach = Arena.reach(run.arena, x, z, tx, tz, 1.5)
			local dx, dz = tx - x, tz - z
			local length = math.sqrt(dx * dx + dz * dz)
			x += dx / length * reach
			z += dz / length * reach
			Assert.truthy(
				Arena.blocking(run.arena, x, z, 1.5) == nil,
				"inside the rock at step " .. step
			)
		end
		Assert.truthy(x > 15, "reached the rock: " .. x)
		-- Backing away is always free.
		Assert.truthy(Arena.reach(run.arena, x, z, x - 5, z, 1.5) > 4.9)
	end,

	["the edge clamps and stops a walk"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		local x, z = Arena.clamp(run.arena, 1000, 0, 1.5)
		Assert.near(x, run.arena.radius - 1.5, 1e-6)
		Assert.near(z, 0, 1e-6)
		Assert.near(Arena.reach(run.arena, 0, 0, 1000, 0, 1.5), run.arena.radius - 1.5, 1e-6)
	end,

	["steer goes round an obstacle and straight when the way is free"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		local dx, dz = Arena.steer(run.arena, 0, 0, 40, 0, 1.5, 1.5, 6)
		Assert.near(dx, 1, 1e-6)
		Assert.near(dz, 0, 1e-6)
		table.insert(
			run.arena.obstacles,
			{ id = 1, kind = "rock", x = 6, z = 0.5, radius = 3, rotation = 0 }
		)
		dx, dz = Arena.steer(run.arena, 0, 0, 40, 0, 1.5, 1.5, 6)
		Assert.truthy(math.abs(dz) > 0.5, "turned aside: " .. dz)
		Assert.truthy(dz < 0, "on the target's side")
	end,

	["a free spot leaves an obstacle"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		table.insert(
			run.arena.obstacles,
			{ id = 1, kind = "rock", x = 0, z = 0, radius = 5, rotation = 0 }
		)
		local x, z = Arena.freeSpot(run.arena, 0, 0, 1.5, run.rng, 8)
		Assert.truthy(Arena.blocking(run.arena, x, z, 1.5) == nil)
	end,

	["a prop with a footprint takes one circle per entry, turned with it"] = function()
		local run = Fixtures.run(1, nil, 7)
		local map = run.map
		local seen = 0
		for group, circles in groups(run.arena) do
			local first = circles[1]
			local kind = kindOf(map, first.kind)
			local footprint = kind.footprint
			for order, circle in circles do
				Assert.equal(circle.kind, first.kind, "one kind per group")
				Assert.equal(circle.rotation, first.rotation, "one rotation per group")
				Assert.equal(circle.anchor, order == 1, "only the first is the anchor")
			end
			if isTerrain(first) then
				continue
			end
			if footprint == nil then
				Assert.equal(#circles, 1, "a plain kind is one circle")
				Assert.equal(first.radius, kind.radius)
				continue
			end
			seen += 1
			Assert.equal(#circles, #footprint, "group " .. group)
			-- The centre, found from the anchor, puts every circle at its turned offset.
			local cos, sin = math.cos(first.rotation), math.sin(first.rotation)
			local cx = first.x - (footprint[1].dx * cos - footprint[1].dz * sin)
			local cz = first.z - (footprint[1].dx * sin + footprint[1].dz * cos)
			for order, entry in footprint do
				local circle = circles[order]
				Assert.near(circle.x, cx + entry.dx * cos - entry.dz * sin, 1e-6)
				Assert.near(circle.z, cz + entry.dx * sin + entry.dz * cos, 1e-6)
				Assert.equal(circle.radius, entry.radius)
			end
		end
		Assert.truthy(seen > 5, "props with footprints placed: " .. seen)
	end,

	["a footprint's offset turns with the rotation"] = function()
		local config = Fixtures.config()
		local map = config.maps[config.map]
		map.obstacleKinds = {
			{
				id = "log",
				radius = 1,
				weight = 1,
				footprint = { { dx = 0, dz = 0, radius = 1 }, { dx = 5, dz = 0, radius = 1 } },
			},
		}
		local arena = Arena.generate(map, Rng.new(5))
		local turned = 0
		for _, circles in groups(arena) do
			local a, b = circles[1], circles[2]
			Assert.near(Geometry.distance(a.x, a.z, b.x, b.z), 5, 1e-6)
			Assert.near(b.x - a.x, 5 * math.cos(a.rotation), 1e-6)
			Assert.near(b.z - a.z, 5 * math.sin(a.rotation), 1e-6)
			if math.abs(b.z - a.z) > 1 then
				turned += 1
			end
		end
		Assert.truthy(turned > 0, "some logs turned")
	end,

	["without the shrines' config no spots are scattered"] = function()
		local config = Fixtures.config()
		Assert.equal(#Arena.generate(config.maps[config.map], Rng.new(1)).shrineSpots, 0)
	end,

	["shrine spots are dealt round-robin, two of each kind"] = function()
		local config = Fixtures.config()
		for seed = 1, 5 do
			local list = spots(seed)
			Assert.equal(#list, config.shrines.count, "seed " .. seed)
			local counts: { [string]: number } = {}
			for _, spot in list do
				counts[spot.kind] = (counts[spot.kind] or 0) + 1
			end
			for _, kind in config.shrines.kinds do
				Assert.equal(counts[kind], 2, kind)
			end
		end
	end,

	["shrine spots keep their distances"] = function()
		local config = Fixtures.config()
		local shrines = config.shrines
		local map = config.maps[config.map]
		for seed = 1, 5 do
			local arena = Arena.generate(map, Rng.new(seed), shrines)
			for i, spot in arena.shrineSpots do
				Assert.truthy(
					Geometry.distance(spot.x, spot.z, 0, 0) >= shrines.startMinDistance,
					"start"
				)
				Assert.truthy(
					Geometry.distance(spot.x, spot.z, arena.chestX, arena.chestZ)
						>= shrines.chestMinDistance,
					"chest"
				)
				Assert.truthy(
					Geometry.distance(spot.x, spot.z, 0, 0) + shrines.radius
						<= map.radius - map.edgeMargin + 1e-6,
					"inside"
				)
				for j, other in arena.shrineSpots do
					if i < j then
						Assert.truthy(
							Geometry.distance(spot.x, spot.z, other.x, other.z) >= shrines.spacing,
							"spacing"
						)
					end
				end
				for _, obstacle in arena.obstacles do
					Assert.truthy(
						Geometry.distance(spot.x, spot.z, obstacle.x, obstacle.z)
							>= obstacle.radius + shrines.radius + map.obstacleSpacing,
						"clear of obstacles"
					)
				end
			end
		end
	end,

	["the same seed scatters the same shrine spots"] = function()
		local a, b, c = spots(9), spots(9), spots(10)
		Assert.equal(#a, #b)
		for i, spot in a do
			Assert.equal(spot.kind, b[i].kind)
			Assert.equal(spot.x, b[i].x)
			Assert.equal(spot.z, b[i].z)
		end
		Assert.truthy(a[1].x ~= c[1].x or a[1].z ~= c[1].z, "another seed, other spots")
	end,

	["a spot that never fits is skipped"] = function()
		local config = Fixtures.config()
		config.shrines.spacing = 10000
		Assert.equal(
			#Arena.generate(config.maps[config.map], Rng.new(1), config.shrines).shrineSpots,
			1
		)
	end,
}
