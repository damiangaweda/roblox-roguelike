--!strict
local Arena = require("../src/shared/Core/Arena")
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")

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
				if i < j then
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
}
