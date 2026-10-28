--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Flow = require("../src/shared/Core/Flow")
local Geometry = require("../src/shared/Core/Geometry")
local Types = require("../src/shared/Core/Types")

-- A run on open ground, no lairs, hero 1 at (x, z).
local function open(x: number, z: number): Types.Run
	local run = Fixtures.run(1)
	Fixtures.clearObstacles(run)
	Fixtures.clearLairs(run)
	Fixtures.place(run, 1, x, z)
	return run
end

local function cellAt(flow: Types.Flow, x: number, z: number): number
	local cx = math.floor((x + flow.origin) / flow.cellSize)
	local cz = math.floor((z + flow.origin) / flow.cellSize)
	return cx + cz * flow.size + 1
end

local function fieldOf(run: Types.Run, id: number): { number }
	local flow = run.flow :: Types.Flow
	return flow.fields[id]
end

-- A wall of rocks along x = `x` from z = -half to half.
local function wall(run: Types.Run, x: number, half: number)
	for z = -half, half, 4 do
		Fixtures.obstacle(run, x, z, 2.5)
	end
end

-- Walks a point one stud at a time down hero 1's field; returns where it
-- ended and the farthest x it passed.
local function follow(run: Types.Run, x: number, z: number, steps: number): (number, number, number)
	local player = run.players[1]
	local farthest = x
	for _ = 1, steps do
		if Geometry.distance(x, z, player.x, player.z) <= 3 then
			break
		end
		local dx, dz = Flow.direction(run, 1, x, z)
		if dx == nil or dz == nil then
			-- In the hero's cell: straight on.
			dx, dz = Geometry.normalize(player.x - x, player.z - z)
		end
		x += dx :: number
		z += dz :: number
		farthest = math.max(farthest, x)
	end
	return x, z, farthest
end

return {
	["the grid marks obstacles and the edge"] = function()
		local run = open(0, 0)
		Fixtures.obstacle(run, 20, 0, 3)
		local flow = Flow.build(run.arena, run.config)
		Assert.truthy(flow.blocked[cellAt(flow, 20, 0)], "the obstacle's cell is free")
		-- 3 + the hero's 1.5 reaches the centre (22, 2), 2.8 studs off.
		Assert.truthy(flow.blocked[cellAt(flow, 22, 2)], "the margin is free")
		Assert.falsy(flow.blocked[cellAt(flow, 30, 0)], "open ground is blocked")
		Assert.falsy(flow.blocked[cellAt(flow, 0, 0)], "the centre is blocked")
		local edge = run.arena.radius
		Assert.falsy(flow.blocked[cellAt(flow, edge - 10, 0)], "inside the edge is blocked")
		Assert.truthy(
			flow.blocked[cellAt(flow, edge * 0.75, edge * 0.75)],
			"beyond the edge is free"
		)
	end,

	["a flood reaches round a wall, farther than straight"] = function()
		local run = open(0, 0)
		wall(run, 20, 40)
		Flow.update(run)
		local field = fieldOf(run, 1)
		local flow = run.flow :: Types.Flow
		Assert.equal(field[cellAt(flow, 0, 0)], 0)
		local behind = field[cellAt(flow, 40, 0)]
		Assert.truthy(behind > 0, "the cell behind the wall is unreached")
		-- Straight it is 10 cells (50); round the wall's ends much more.
		Assert.truthy(behind > 80, "the flood went through the wall: " .. behind)
		Assert.equal(field[cellAt(flow, 20, 0)], -1, "a blocked cell got a distance")
	end,

	["a hero walled in leaves the outside unreached"] = function()
		local run = open(0, 0)
		Fixtures.cliffRing(run, 0, 0, 30, 0)
		-- Close the gap.
		Fixtures.obstacle(run, 30, 0, 8, "cliff")
		Flow.update(run)
		local flow = run.flow :: Types.Flow
		Assert.equal(fieldOf(run, 1)[cellAt(flow, -60, 0)], -1)
		Assert.equal(Flow.direction(run, 1, -60, 0), nil)
	end,

	["the field leads round a cliff ring to its ramp and in"] = function()
		local run = open(100, 0)
		-- The ramp faces +x, the enemy stands on the far side.
		Fixtures.cliffRing(run, 100, 0, 30, 0)
		Flow.update(run)
		local x, z, farthest = follow(run, 40, 0, 300)
		Assert.truthy(
			Geometry.distance(x, z, 100, 0) <= 3,
			string.format("stopped at (%.1f, %.1f)", x, z)
		)
		Assert.truthy(farthest > 125, "it did not come in through the ramp")
	end,

	["an enemy inside an obstacle's margin still gets a way out"] = function()
		local run = open(0, 0)
		wall(run, 20, 40)
		Flow.update(run)
		-- Against the wall's far face, inside the hero's margin of a rock.
		local dx, dz = Flow.direction(run, 1, 23.5, 0)
		Assert.truthy(dx ~= nil and dz ~= nil, "no way out of a blocked cell")
	end,

	["no field, no direction; the hero's own cell gives none"] = function()
		local run = open(0, 0)
		Assert.equal(Flow.direction(run, 1, 30, 0), nil)
		Flow.update(run)
		Assert.equal(Flow.direction(run, 2, 30, 0), nil)
		Assert.equal(Flow.direction(run, 1, 0.5, 0.5), nil)
		Assert.truthy(Flow.direction(run, 1, 30, 0) ~= nil)
	end,

	["floods come every floodEverySteps steps"] = function()
		local run = open(0, 0)
		Flow.update(run)
		local flow = run.flow :: Types.Flow
		local start = cellAt(flow, 0, 0)
		Fixtures.place(run, 1, 40, 0)
		for _ = 2, run.config.flow.floodEverySteps do
			Flow.update(run)
			Assert.equal(fieldOf(run, 1)[start], 0, "flooded before its time")
		end
		Flow.update(run)
		Assert.equal(fieldOf(run, 1)[cellAt(flow, 40, 0)], 0)
		Assert.truthy(fieldOf(run, 1)[start] > 0)
	end,

	["two heroes flood a step apart"] = function()
		local run = Fixtures.run(2)
		Fixtures.clearObstacles(run)
		Fixtures.clearLairs(run)
		Fixtures.place(run, 1, 0, 0)
		Fixtures.place(run, 2, 0, 0)
		Flow.update(run)
		local flow = run.flow :: Types.Flow
		local moved = cellAt(flow, 40, 0)
		Fixtures.place(run, 1, 40, 0)
		Fixtures.place(run, 2, 40, 0)
		-- Step 1 is hero 2's; step floodEverySteps is hero 1's.
		Flow.update(run)
		Assert.equal(fieldOf(run, 2)[moved], 0)
		Assert.truthy(fieldOf(run, 1)[moved] > 0, "hero 1 flooded on hero 2's step")
		for _ = 2, run.config.flow.floodEverySteps do
			Flow.update(run)
		end
		Assert.equal(fieldOf(run, 1)[moved], 0)
	end,

	["a fallen hero's field goes, a new one floods at once"] = function()
		local run = Fixtures.run(2)
		Fixtures.clearLairs(run)
		Flow.update(run)
		local flow = run.flow :: Types.Flow
		Assert.truthy(flow.fields[2] ~= nil)
		run.players[2].state = "dead"
		Flow.update(run)
		Assert.equal(flow.fields[2], nil)
		Assert.equal(#flow.spare, 1)
		run.players[2].state = "alive"
		Flow.update(run)
		Assert.truthy(flow.fields[2] ~= nil)
		Assert.equal(#flow.spare, 0)
	end,

	["changed obstacles rebuild the grid"] = function()
		local run = open(0, 0)
		Flow.update(run)
		local first = run.flow
		Fixtures.obstacle(run, 20, 0, 3)
		Flow.update(run)
		Assert.truthy(run.flow ~= first, "the grid was not rebuilt")
		local flow = run.flow :: Types.Flow
		Assert.truthy(flow.blocked[cellAt(flow, 20, 0)])
	end,

	["the same seed floods the same field"] = function()
		local a = Fixtures.run(1, nil, 7)
		local b = Fixtures.run(1, nil, 7)
		Flow.update(a)
		Flow.update(b)
		local fieldA, fieldB = fieldOf(a, 1), fieldOf(b, 1)
		Assert.equal(#fieldA, #fieldB)
		for index = 1, #fieldA do
			Assert.equal(fieldA[index], fieldB[index], "cell " .. index)
		end
	end,

	["the line test sees a wall and open ground"] = function()
		local run = open(0, 0)
		wall(run, 20, 40)
		Flow.update(run)
		Assert.falsy(Flow.open(run, 0, 0, 40, 0))
		Assert.truthy(Flow.open(run, 0, 0, 0, 40))
	end,
}
