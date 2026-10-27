--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Progression = require("../src/shared/Core/Progression")

return {
	["xpToNext follows the three bands"] = function()
		local config = Fixtures.config()
		Assert.equal(Progression.xpToNext(config, 1), 5)
		Assert.equal(Progression.xpToNext(config, 2), 15)
		Assert.equal(Progression.xpToNext(config, 19), 185)
		Assert.equal(Progression.xpToNext(config, 20), 195)
		Assert.equal(Progression.xpToNext(config, 39), 442)
		Assert.equal(Progression.xpToNext(config, 40), 455)
		Assert.equal(Progression.xpToNext(config, 41), 471)
	end,

	["xp below the threshold does not level up"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Progression.grantXp(run, player, 4)
		Assert.equal(player.level, 1)
		Assert.equal(player.xp, 4)
		Assert.equal(#run.events, 0)
		Assert.falsy(run.paused)
	end,

	["a level-up keeps the remainder, offers cards and pauses a solo run"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Progression.grantXp(run, player, 6)
		Assert.equal(player.level, 2)
		Assert.equal(player.xp, 1)
		local levelUp = Assert.findEvent(run.events, "levelUp")
		Assert.equal(levelUp.player, 1)
		Assert.equal(levelUp.level, 2)
		Assert.truthy(Assert.findEvent(run.events, "offer"))
		Assert.equal(#player.offers, 1)
		Assert.truthy(run.paused)
	end,

	["the experience passive multiplies what is granted"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.passives = { insight = 1 }
		Progression.grantXp(run, player, 4)
		Assert.near(player.xp, 4 * (1 + run.config.passives.insight.perRank), 1e-9)
	end,

	["one grant can level up several times"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		-- 5 + 15 + 25 = 45 reaches level 4 with 2 left over.
		Progression.grantXp(run, player, 47)
		Assert.equal(player.level, 4)
		Assert.equal(player.xp, 2)
		Assert.equal(Fixtures.count(run.events, "levelUp"), 3)
		Assert.equal(#player.offers, 3)
	end,

	["a crystal carries the enemy's xp times the factor"] = function()
		local run = Fixtures.run()
		Progression.dropCrystal(run, 30, 0, 3)
		Assert.equal(#run.crystals, 1)
		Assert.equal(run.crystals[1].xp, 3 * run.config.progression.crystalFactor)
		local event = Assert.findEvent(run.events, "crystalDropped")
		Assert.equal(event.id, run.crystals[1].id)
		Assert.equal(event.xp, run.crystals[1].xp)
	end,

	["crystals are collected within the pickup range and not beyond"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local range = run.config.player.pickupRange
		Progression.dropCrystal(run, range - 0.5, 0, 1)
		Progression.dropCrystal(run, range + 0.5, 0, 1)
		run.events = {}
		Progression.update(run, 0.1)
		Assert.equal(#run.crystals, 1)
		Assert.near(run.crystals[1].x, range + 0.5, 1e-9)
		local collected = Assert.findEvent(run.events, "crystalCollected")
		Assert.equal(collected.player, 1)
		Assert.equal(player.xp, run.config.progression.crystalFactor)

		-- The pickup passive widens the range.
		player.passives = { lodestone = 1 }
		Progression.update(run, 0.1)
		Assert.equal(#run.crystals, 0)
	end,

	["a dead hero collects nothing"] = function()
		local run = Fixtures.run()
		run.players[1].state = "dead"
		Progression.dropCrystal(run, 1, 0, 1)
		Progression.update(run, 0.1)
		Assert.equal(#run.crystals, 1)
	end,

	["past the cap a crystal's xp joins the nearest one"] = function()
		local config = Fixtures.config()
		config.progression.maxCrystals = 2
		local run = Fixtures.run(1, config)
		Progression.dropCrystal(run, 100, 0, 1)
		Progression.dropCrystal(run, -100, 0, 1)
		run.events = {}
		Progression.dropCrystal(run, 90, 0, 5)
		Assert.equal(#run.crystals, 2)
		local factor = config.progression.crystalFactor
		Assert.equal(run.crystals[1].xp, factor * 6)
		Assert.equal(run.crystals[2].xp, factor)
		Assert.equal(#run.events, 0)
	end,

	["food heals the hero standing on it"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local max = player.health
		player.health -= 20
		Progression.dropFood(run, run.config.player.radius + 0.5, 0, 30)
		Progression.dropFood(run, 20, 0, 30)
		Assert.equal(Fixtures.count(run.events, "foodDropped"), 2)
		Progression.update(run, 0.1)
		Assert.equal(player.health, max)
		Assert.equal(#run.foods, 1)
		Assert.equal(Assert.findEvent(run.events, "foodEaten").amount, 20)
	end,

	["a boss's food heals fully"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.health = 1
		Progression.dropFood(run, 0, 0, math.huge)
		Progression.update(run, 0.1)
		Assert.equal(player.health, run.config.classes.mage.maxHealth)
	end,
}
