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

return {
	["the scatter keeps its spacing and the clear ground"] = function()
		local run = Fixtures.run(1, nil, 7)
		local map = run.map
		local arena = run.arena
		Assert.truthy(
			#arena.obstacles > map.obstacleCount * 0.5,
			"too few obstacles: " .. #arena.obstacles
		)
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
				Geometry.distance(a.x, a.z, 0, 0) + a.radius <= map.radius - map.edgeMargin + 1e-6,
				"inside"
			)
			for j, b in arena.obstacles do
				-- A prop's own circles may touch; props keep their spacing.
				if i < j and a.group ~= b.group then
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
