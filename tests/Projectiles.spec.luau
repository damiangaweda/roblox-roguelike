--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Projectiles = require("../src/shared/Core/Projectiles")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

-- A run of one hero at (0, 0) on open ground, with no crits.
local function setup(): (Types.Run, Types.Player)
	local config = Fixtures.config()
	config.player.baseCritChance = 0
	local run = Fixtures.run(1, config)
	Fixtures.clearObstacles(run)
	return run, run.players[1]
end

local function foe(run: Types.Run, x: number, z: number): Types.Enemy
	local enemy = Fixtures.enemy(run, "wildBoar", x, z)
	enemy.health = 1000
	enemy.maxHealth = 1000
	return enemy
end

-- A projectile with `fields` over a hero's homing bolt from (0, 0).
local function launch(run: Types.Run, fields: { [string]: any }): Types.Projectile
	local projectile: Types.Projectile = {
		id = State.nextId(run),
		owner = "player",
		source = 1,
		kind = "testBolt",
		x = 0,
		z = 0,
		dirX = 1,
		dirZ = 0,
		speed = 30,
		remaining = math.huge,
		damage = 10,
		radius = 0,
		knockback = 0,
		tags = {},
		effect = nil,
		targetId = nil,
		critChance = 0,
	}
	for key, value in fields do
		(projectile :: any)[key] = value
	end
	table.insert(run.projectiles, projectile)
	return projectile
end

local function fly(run: Types.Run, seconds: number)
	local dt = 0.1
	for _ = 1, math.floor(seconds / dt + 0.5) do
		run.time += dt
		Projectiles.step(run, dt)
	end
end

return {
	["a homing bolt hits its target on arrival, even when it moved"] = function()
		local run = setup()
		local enemy = foe(run, 20, 0)
		launch(run, { targetId = enemy.id })
		fly(run, 0.3)
		Assert.equal(enemy.health, 1000)
		Assert.equal(#run.projectiles, 1)
		enemy.z = 10
		fly(run, 1)
		Assert.equal(enemy.health, 990)
		Assert.equal(#run.projectiles, 0)
		Assert.truthy(Assert.findEvent(run.events, "burst"))
		local hit = Assert.findEvent(run.events, "hit")
		Assert.equal(hit.skill, "testBolt")
	end,

	["a homing bolt passes by other enemies on its way"] = function()
		local run = setup()
		local blocker = foe(run, 10, 0)
		local target = foe(run, 20, 0)
		launch(run, { targetId = target.id })
		fly(run, 1)
		Assert.equal(blocker.health, 1000)
		Assert.equal(target.health, 990)
	end,

	["a bolt whose target is gone lands where it is"] = function()
		local run = setup()
		local enemy = foe(run, 20, 0)
		launch(run, { targetId = enemy.id })
		fly(run, 0.2)
		State.removeEnemy(run, enemy)
		fly(run, 0.1)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(Fixtures.count(run.events, "hit"), 0)
		Assert.equal(Fixtures.count(run.events, "burst"), 1)
	end,

	["a bolt splashes others at the splash share"] = function()
		local run = setup()
		local target = foe(run, 20, 0)
		local beside = foe(run, 25, 0)
		local outside = foe(run, 35, 0)
		launch(run, { targetId = target.id, radius = 8, damage = 20 })
		fly(run, 1)
		Assert.equal(target.health, 980)
		Assert.near(beside.health, 1000 - 20 * run.config.ranks.splashShare)
		Assert.equal(outside.health, 1000)
	end,

	["a bolt carries its effect and knockback to the target"] = function()
		local run = setup()
		local target = foe(run, 20, 0)
		launch(run, {
			targetId = target.id,
			knockback = 4,
			effect = { kind = "slow", factor = 0.5, seconds = 2 },
		})
		fly(run, 1)
		Assert.near(target.slowFactor, 0.5)
		Assert.truthy(target.knockX > 0, "pushed away")
	end,

	["an enemy shot hurts and pushes the hero it touches"] = function()
		local run, player = setup()
		local health = player.health
		launch(run, {
			owner = "enemy",
			source = 7,
			kind = "spitter",
			x = 20,
			dirX = -1,
			remaining = 40,
			damage = 12,
			knockback = 3,
		})
		fly(run, 1)
		Assert.near(player.health, health - 12)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(Assert.findEvent(run.events, "playerHurt").enemyId, 7)
		Assert.truthy(player.knockX < 0, "pushed along the shot")
	end,

	["an enemy shot that misses vanishes at the end of its flight"] = function()
		local run, player = setup()
		local health = player.health
		launch(run, { owner = "enemy", x = 20, z = 10, dirX = -1, remaining = 10 })
		fly(run, 1)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(player.health, health)
	end,

	["an enemy burst at the end of its flight hurts every hero within its radius"] = function()
		local run = Fixtures.run(2)
		Fixtures.clearObstacles(run)
		Fixtures.place(run, 1, 0, 3)
		Fixtures.place(run, 2, 0, 20)
		local near, far = run.players[1], run.players[2]
		local healthNear, healthFar = near.health, far.health
		launch(run, {
			owner = "enemy",
			x = -20,
			z = 0,
			dirX = 1,
			remaining = 20,
			damage = 18,
			radius = 3,
		})
		fly(run, 1)
		Assert.near(near.health, healthNear - 18)
		Assert.equal(far.health, healthFar)
		Assert.equal(Fixtures.count(run.events, "burst"), 1)
	end,

	["obstacles never block a shot"] = function()
		local run, player = setup()
		table.insert(
			run.arena.obstacles,
			{ id = 1, kind = "rock", x = 10, z = 0, radius = 3, rotation = 0 }
		)
		local enemy = foe(run, 20, 0)
		launch(run, { targetId = enemy.id })
		launch(run, { owner = "enemy", x = 20, dirX = -1, remaining = 40, damage = 5 })
		local health = player.health
		fly(run, 1)
		Assert.equal(enemy.health, 990)
		Assert.near(player.health, health - 5)
	end,
}
