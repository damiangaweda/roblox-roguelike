--!strict
local Assert = require("./Assert")
local Casting = require("../src/shared/Core/Casting")
local Enemies = require("../src/shared/Core/Enemies")
local Fixtures = require("./Fixtures")
local Hero = require("../src/shared/Core/Hero")
local Projectiles = require("../src/shared/Core/Projectiles")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

-- Advances the clock and the hero rules by `seconds` in steps of `dt`.
local function advance(run: Types.Run, seconds: number, dt: number)
	for _ = 1, math.round(seconds / dt) do
		run.time += dt
		Hero.update(run, dt)
	end
end

-- A hero on open ground at the centre, in a dash that lasts `seconds`
-- without moving them, so every hit can be aimed at them.
local function dashing(seconds: number): (Types.Run, Types.Player)
	local run = Fixtures.run()
	Fixtures.clearObstacles(run)
	local player = run.players[1]
	player.dashUntil = run.time + seconds
	return run, player
end

-- The index of the utility of `kind` among the three buttons.
local function utilityIndex(run: Types.Run, kind: string): number
	for index, utility in run.config.utilities do
		if utility.kind == kind then
			return index
		end
	end
	error("no utility " .. kind)
end

return {
	["stats without passives are the class's"] = function()
		local run = Fixtures.run(1, nil, 1, "warrior")
		local stats = Hero.stats(run, run.players[1])
		local class = run.config.classes.warrior
		Assert.equal(stats.maxHealth, class.maxHealth)
		Assert.equal(stats.speed, class.walkSpeed)
		Assert.equal(stats.damage, 1)
		Assert.equal(stats.area, 1)
		Assert.equal(stats.experience, 1)
		Assert.equal(stats.regeneration, 0)
		Assert.equal(stats.haste, 0)
		Assert.equal(stats.armour, 0)
		Assert.equal(stats.critChance, run.config.player.baseCritChance)
		Assert.equal(stats.pickupRange, run.config.player.pickupRange)
	end,

	["each passive raises its own stat and no other"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local base = Hero.stats(run, player)
		local class = run.config.classes[player.class]
		for id, passive in run.config.passives do
			player.passives = { [id] = 2 }
			local stats = Hero.stats(run, player)
			local v = passive.perRank * 2
			local expected: { [string]: number } = {
				damage = 1 + v,
				maxHealth = class.maxHealth * (1 + v),
				speed = class.walkSpeed * (1 + v),
				regeneration = v,
				haste = v,
				area = 1 + v,
				pickupRange = run.config.player.pickupRange * (1 + v),
				experience = 1 + v,
				armour = v,
				critChance = run.config.player.baseCritChance + v,
			}
			for stat, value in stats :: any do
				if stat == passive.stat then
					Assert.near(value, expected[stat], 1e-9, id .. " " .. stat)
				else
					Assert.near(value, (base :: any)[stat], 1e-9, id .. " moved " .. stat)
				end
			end
		end
	end,

	["walk speed rises while sprinting"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local speed = Hero.walkSpeed(run, player)
		local index = utilityIndex(run, "sprint")
		local sprint = run.config.utilities[index]
		Assert.truthy(Hero.useUtility(run, 1, index))
		Assert.near(Hero.walkSpeed(run, player), speed * (sprint.factor :: number), 1e-9)
		run.time += (sprint.seconds :: number) + 0.01
		Assert.near(Hero.walkSpeed(run, player), speed, 1e-9)
	end,

	["damage goes through the barrier, then armour, down to the minimum"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local max = player.health
		player.passives = { hide = 3 }
		player.barrier = 10
		player.barrierUntil = 5

		local result = Hero.damage(run, player, 8, 42)
		Assert.equal(result.taken, 0)
		Assert.equal(player.health, max)
		Assert.equal(player.barrier, 2)
		local hurt = Assert.findEvent(run.events, "playerHurt")
		Assert.equal(hurt.amount, 0)
		Assert.equal(hurt.absorbed, 8)
		Assert.equal(hurt.enemyId, 42)

		run.events = {}
		result = Hero.damage(run, player, 10)
		-- 2 absorbed, 8 left, 3 armour.
		Assert.equal(result.taken, 5)
		Assert.equal(player.health, max - 5)
		Assert.equal(player.barrier, 0)
		Assert.equal(Assert.findEvent(run.events, "playerHurt").absorbed, 2)

		result = Hero.damage(run, player, 2)
		Assert.equal(result.taken, run.config.player.minDamage)
		Assert.equal(player.health, max - 5 - run.config.player.minDamage)
	end,

	["an expired barrier absorbs nothing"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.barrier = 50
		player.barrierUntil = 1
		run.time = 2
		local result = Hero.damage(run, player, 10)
		Assert.equal(result.taken, 10)
		Assert.equal(Assert.findEvent(run.events, "playerHurt").absorbed, 0)
	end,

	["death comes once at zero health"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Hero.damage(run, player, player.health + 100)
		Assert.equal(player.health, 0)
		Assert.equal(player.state, "dead")
		local result = Hero.damage(run, player, 10)
		Assert.equal(result.taken, 0)
		Assert.equal(Fixtures.count(run.events, "died"), 1)
		Assert.equal(Fixtures.count(run.events, "playerHurt"), 1)
	end,

	["a hit interrupts the cast and the chest opening"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.castingUntil = 5
		player.openProgress = 1.2
		run.time = 1
		Hero.damage(run, player, 3)
		Assert.equal(player.castingUntil, nil)
		Assert.equal(player.openProgress, 0)
		Assert.equal(player.hurtAt, 1)
		Assert.equal(Fixtures.count(run.events, "castInterrupted"), 1)
		Hero.damage(run, player, 3)
		Assert.equal(Fixtures.count(run.events, "castInterrupted"), 1)
	end,

	["thorns are reflected while they last"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.thorns = 14
		player.thornsUntil = 3
		Assert.equal(Hero.damage(run, player, 5).reflected, 14)
		run.time = 4
		Assert.equal(Hero.damage(run, player, 5).reflected, 0)
	end,

	["a heal is capped at max health"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local max = player.health
		Hero.heal(run, player, 10)
		Assert.equal(player.health, max)
		Assert.equal(Fixtures.count(run.events, "healed"), 0)
		player.health = max - 4
		Hero.heal(run, player, math.huge)
		Assert.equal(player.health, max)
		Assert.equal(Assert.findEvent(run.events, "healed").amount, 4)
	end,

	["the utilities fire and respect their cooldowns"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local max = player.health

		local barrierIndex = utilityIndex(run, "barrier")
		local barrier = run.config.utilities[barrierIndex]
		Assert.truthy(Hero.useUtility(run, 1, barrierIndex))
		Assert.equal(player.barrier, barrier.amount :: number)
		Assert.falsy(Hero.useUtility(run, 1, barrierIndex), "on cooldown")
		local result = Hero.damage(run, player, 20)
		Assert.equal(result.taken, 0)
		Assert.equal(player.health, max)

		local healIndex = utilityIndex(run, "heal")
		local heal = run.config.utilities[healIndex]
		player.health = max - 10
		Assert.truthy(Hero.useUtility(run, 1, healIndex))
		Assert.equal(player.health, max, "capped")
		player.health = max - (heal.amount :: number) - 30
		Assert.falsy(Hero.useUtility(run, 1, healIndex), "on cooldown")
		run.time += heal.cooldownSeconds
		Assert.truthy(Hero.useUtility(run, 1, healIndex))
		Assert.equal(player.health, max - 30)
		Assert.equal(Fixtures.count(run.events, "utility"), 3)
	end,

	["utilities are refused for a bad index or a dead hero"] = function()
		local run = Fixtures.run()
		Assert.falsy(Hero.useUtility(run, 1, 0))
		Assert.falsy(Hero.useUtility(run, 1, #run.config.utilities + 1))
		Assert.falsy(Hero.useUtility(run, 9, 1))
		run.players[1].state = "dead"
		Assert.falsy(Hero.useUtility(run, 1, 1))
	end,

	["the barrier drops when its time is up"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local index = utilityIndex(run, "barrier")
		Hero.useUtility(run, 1, index)
		advance(run, (run.config.utilities[index].seconds :: number) + 0.1, 0.1)
		Assert.equal(player.barrier, 0)
	end,

	["regeneration heals only with the passive and only while alive"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.health -= 20
		advance(run, 2, 0.1)
		Assert.equal(player.health, run.config.classes.mage.maxHealth - 20)
		player.passives = { mending = 2 }
		local perSecond = run.config.passives.mending.perRank * 2
		advance(run, 2, 0.1)
		Assert.near(player.health, run.config.classes.mage.maxHealth - 20 + 2 * perSecond, 1e-6)
		player.state = "dead"
		local health = player.health
		advance(run, 2, 0.1)
		Assert.equal(player.health, health)
	end,

	["a pending heal drains at its rate"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.health -= 50
		player.healPending = 30
		player.healRate = 10
		advance(run, 1, 0.1)
		Assert.near(player.health, run.config.classes.mage.maxHealth - 40, 1e-6)
		advance(run, 5, 0.1)
		Assert.near(player.health, run.config.classes.mage.maxHealth - 20, 1e-6)
		Assert.equal(player.healPending, 0)
	end,

	["a knockback carries the hero and stops at the edge"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		local player = run.players[1]
		Hero.knock(run, player, 6, 0)
		Assert.truthy(Assert.findEvent(run.events, "knockback"))
		advance(run, 1, 0.05)
		Assert.near(player.x, 6, 1e-6)
		Assert.near(player.z, 0, 1e-6)

		local edge = run.arena.radius - run.config.player.radius
		Fixtures.place(run, 1, edge - 1, 0)
		Hero.knock(run, player, 10, 0)
		advance(run, 1, 0.05)
		Assert.near(player.x, edge, 1e-6)
	end,

	["a dash spends a charge; with none left it is refused"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		local player = run.players[1]
		local config = run.config.player
		Assert.equal(player.dashCharges, config.dashCharges)
		for _ = 1, config.dashCharges do
			Assert.truthy(Hero.dash(run, player, 1, 0))
		end
		Assert.equal(player.dashCharges, 0)
		Assert.falsy(Hero.dash(run, player, 1, 0), "no charge left")
		Assert.falsy(Hero.dash(run, player, 0, 0), "no direction")
		player.dashCharges = 1
		Assert.falsy(Hero.dash(run, player, 1e-12, 0), "too short to normalise")
		Assert.falsy(Hero.dash(run, player, 1e300, 1e300), "too long to normalise")
		Assert.falsy(Hero.dash(run, player, 0 / 0, 1), "not a number")
		Assert.equal(player.dashCharges, 1, "a refused dash spends nothing")
		player.state = "dead"
		Assert.falsy(Hero.dash(run, player, 1, 0), "dead")
	end,

	["dash charges come back one per cooldown"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		local player = run.players[1]
		local config = run.config.player
		Hero.dash(run, player, 1, 0)
		Hero.dash(run, player, -1, 0)
		advance(run, config.dashCooldownSeconds - 0.1, 0.05)
		Assert.equal(player.dashCharges, 0, "not yet")
		advance(run, 0.2, 0.05)
		Assert.equal(player.dashCharges, 1, "one back")
		advance(run, config.dashCooldownSeconds, 0.05)
		Assert.equal(player.dashCharges, 2, "both back")
		advance(run, config.dashCooldownSeconds * 3, 0.05)
		Assert.equal(player.dashCharges, config.dashCharges, "never above the charges")
	end,

	["a dash is stopped by an obstacle and by the wall"] = function()
		local run = Fixtures.run()
		Fixtures.clearObstacles(run)
		local player = run.players[1]
		local radius = run.config.player.radius
		table.insert(run.arena.obstacles, {
			id = 1,
			kind = "rock",
			x = 8,
			z = 0,
			radius = 2,
			rotation = 0,
			group = 1,
			anchor = true,
		})
		Hero.dash(run, player, 1, 0)
		advance(run, 0.5, 0.05)
		Assert.near(player.x, 8 - 2 - radius, 1e-2)
		Assert.near(player.z, 0, 1e-6)

		local edge = run.arena.radius - radius
		Fixtures.place(run, 1, edge - 5, 0)
		Hero.dash(run, player, 1, 0)
		advance(run, 0.5, 0.05)
		Assert.near(player.x, edge, 1e-6)
	end,

	["a dashing hero takes no contact hit and the grunt's hit waits"] = function()
		local run, player = dashing(1)
		local grunt = Fixtures.enemy(run, "greyWolf", 3, 0)
		grunt.contactReadyAt = 0
		local health = player.health
		for _ = 1, 9 do
			run.time += 0.1
			Enemies.step(run, 0.1)
		end
		Assert.equal(player.health, health)
		Assert.equal(Fixtures.count(run.events, "playerHurt"), 0)
		Assert.truthy(grunt.contactReadyAt <= run.time, "the contact was not spent")
		-- The dash over, the waiting hit lands at once.
		run.time += 0.2
		Enemies.step(run, 0.1)
		Assert.truthy(player.health < health, "hit after the dash")
	end,

	["a dashing hero takes no attack and no knockback"] = function()
		local run, player = dashing(30)
		Fixtures.place(run, 1, 4, 0)
		local brute = Fixtures.enemy(run, "brute", 0, 0)
		brute.attackReadyAt = 0
		local boss = Fixtures.enemy(run, "thornback", -30, 0)
		boss.attackReadyAt = 0
		local health = player.health
		for _ = 1, 100 do
			run.time += 0.1
			Enemies.step(run, 0.1)
		end
		Assert.truthy(Fixtures.count(run.events, "enemyAttack") > 0, "they attacked")
		Assert.equal(player.health, health)
		Assert.equal(Fixtures.count(run.events, "playerHurt"), 0)
		Assert.equal(Fixtures.count(run.events, "knockback"), 0)
		Assert.equal(player.knockUntil, 0)
		Assert.falsy(boss.chargedPlayers[player.id], "a charge through a dash does not count")
	end,

	["a shot flies through a dashing hero"] = function()
		local run, player = dashing(5)
		local health = player.health
		local shot: Types.Projectile = {
			id = State.nextId(run),
			owner = "enemy",
			source = 7,
			kind = "spitter",
			x = 20,
			z = 0,
			dirX = -1,
			dirZ = 0,
			speed = 30,
			remaining = 30,
			damage = 12,
			radius = 0,
			knockback = 3,
			tags = {},
			effect = nil,
			targetId = nil,
			critChance = 0,
		}
		table.insert(run.projectiles, shot)
		for _ = 1, 8 do
			run.time += 0.1
			Projectiles.step(run, 0.1)
		end
		Assert.equal(player.health, health)
		Assert.equal(player.knockUntil, 0)
		Assert.truthy(shot.x < -1, "past the hero: " .. shot.x)
	end,

	["an area does not hurt a dashing hero"] = function()
		local run, player = dashing(5)
		local health = player.health
		table.insert(run.areas, {
			id = State.nextId(run),
			owner = "enemy",
			source = 7,
			kind = "hollowShade",
			x = 0,
			z = 0,
			radius = 5,
			damage = 10,
			until_ = 2,
			nextTickAt = 0.1,
			tickSeconds = 0.1,
			tags = {},
			effect = nil,
			critChance = 0,
			knockback = 0,
		})
		for _ = 1, 10 do
			run.time += 0.1
			Casting.update(run, 0.1)
		end
		Assert.equal(player.health, health)
		Assert.equal(Hero.damage(run, player, 50, nil).taken, 0)
		Assert.truthy(Hero.untouchable(run, player))
	end,
}
