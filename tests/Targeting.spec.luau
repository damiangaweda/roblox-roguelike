--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Rng = require("../src/shared/Core/Rng")
local Targeting = require("../src/shared/Core/Targeting")
local Types = require("../src/shared/Core/Types")

-- A run with no enemies on open ground. A wild boar's radius is 1.5.
local function setup(): Types.Run
	local run = Fixtures.run()
	Fixtures.clearObstacles(run)
	return run
end

local function boar(run: Types.Run, x: number, z: number): Types.Enemy
	return Fixtures.enemy(run, "wildBoar", x, z)
end

local function idsOf(enemies: { Types.Enemy }): { number }
	local ids = {}
	for _, enemy in enemies do
		table.insert(ids, enemy.id)
	end
	return ids
end

local function sameIds(actual: { Types.Enemy }, expected: { Types.Enemy }, message: string?)
	Assert.equal(#actual, #expected, message)
	for index, enemy in expected do
		Assert.equal(actual[index].id, enemy.id, message)
	end
end

return {
	["nearest counts the enemy's body toward the range"] = function()
		local run = setup()
		local inside = boar(run, 46.4, 0)
		boar(run, 46.6, 0)
		sameIds(Targeting.nearest(run, 0, 0, 45, 5, false), { inside })
	end,

	["nearest takes the count nearest, or the toughest"] = function()
		local run = setup()
		local far = boar(run, 30, 0)
		local near = boar(run, 10, 0)
		local middle = boar(run, 0, 20)
		far.health = 500
		sameIds(Targeting.nearest(run, 0, 0, 45, 2, false), { near, middle })
		sameIds(Targeting.nearest(run, 0, 0, 45, 1, true), { far })
		Assert.equal(#Targeting.nearest(run, 0, 0, 5, 3, false), 0)
	end,

	["within counts half the enemy's body"] = function()
		local run = setup()
		local inside = boar(run, 0, 10.7)
		boar(run, 0, 10.8)
		sameIds(Targeting.within(run, 0, 0, 10), { inside })
	end,

	["a cone aims at the nearest and keeps what touches the hero"] = function()
		local run = setup()
		local aim = boar(run, 2, 0)
		local touching = boar(run, 0, 2.5)
		local ahead = boar(run, 10, 0)
		local at30 = boar(run, 10 * math.cos(math.rad(30)), 10 * math.sin(math.rad(30)))
		boar(run, 10 * math.cos(math.rad(45)), 10 * math.sin(math.rad(45)))
		boar(run, -10, 0)
		local cone = Targeting.cone(run, 0, 0, 25, 37)
		sameIds(cone, { aim, touching, ahead, at30 })
		Assert.equal(#Targeting.cone(run, 100, 100, 25, 37), 0)
	end,

	["a cluster picks the densest enemy, ties to the later candidate"] = function()
		local run = setup()
		boar(run, 10, 10)
		boar(run, 30, 0)
		local last = boar(run, 32, 0)
		boar(run, 30, 3)
		local point = Targeting.cluster(run, 0, 0, 45, 16, 40) :: Types.Point
		-- All three count two others; the farthest of them wins the tie.
		Assert.near(point.x, last.x)
		Assert.near(point.z, last.z)
		Assert.equal(Targeting.cluster(run, 200, 200, 45, 16, 40), nil)
	end,

	["a cluster considers only the nearest candidates"] = function()
		local run = setup()
		local lone = boar(run, 5, 0)
		boar(run, 40, 0)
		boar(run, 41, 0)
		local point = Targeting.cluster(run, 0, 0, 45, 16, 1) :: Types.Point
		Assert.near(point.x, lone.x)
	end,

	["a chain jumps to the nearest unstruck within the jump radius"] = function()
		local run = setup()
		local a = boar(run, 10, 0)
		local b = boar(run, 20, 0)
		local c = boar(run, 30, 0)
		boar(run, 60, 0)
		local path = Targeting.chain(run, 0, 0, 35, 14, 4)
		sameIds(path, { a, b, c })
		sameIds(Targeting.chain(run, 0, 0, 35, 14, 2), { a, b })
		Assert.equal(#Targeting.chain(run, 0, 0, 5, 14, 4), 0)
	end,

	["a scatter picks distinct enemies among the nearest, the same for a seed"] = function()
		local run = setup()
		local pool: { [number]: boolean } = {}
		for index = 1, 10 do
			local enemy = boar(run, index * 4, 0)
			if index <= 6 then
				pool[enemy.id] = true
			end
		end
		local first = Targeting.scatter(run, 0, 0, 60, 2, Rng.new(5))
		local again = Targeting.scatter(run, 0, 0, 60, 2, Rng.new(5))
		Assert.equal(#first, 2)
		Assert.truthy(first[1] ~= first[2], "distinct")
		for _, enemy in first do
			Assert.truthy(pool[enemy.id], "among the count × 3 nearest")
		end
		Assert.equal(table.concat(idsOf(first), ","), table.concat(idsOf(again), ","))
	end,
}
