--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Progression = require("../src/shared/Core/Progression")

return {
	["xpToNext follows the configured curve"] = function()
		local config = Fixtures.config()
		Assert.equal(Progression.xpToNext(config, 1), 5)
		Assert.equal(Progression.xpToNext(config, 2), 7) -- 6.5 rounds up
		Assert.equal(Progression.xpToNext(config, 3), 8) -- 8.45
		Assert.equal(Progression.xpToNext(config, 4), 11) -- 10.985
		Assert.equal(Progression.xpToNext(config, 5), 14) -- 14.2805
	end,

	["xp below the threshold does not level up"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Progression.grantXp(run, player, 4)
		Assert.equal(player.level, 1)
		Assert.equal(player.xp, 4)
		Assert.equal(#run.events, 0)
	end,

	["reaching the threshold levels up, keeps the remainder and offers a perk"] = function()
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
	end,

	["one grant can level up several times"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		-- 5 + 7 + 8 = 20 reaches level 4 with 2 left over.
		Progression.grantXp(run, player, 22)
		Assert.equal(player.level, 4)
		Assert.equal(player.xp, 2)
		local levelUps = 0
		for _, event in run.events do
			if event.kind == "levelUp" then
				levelUps += 1
			end
		end
		Assert.equal(levelUps, 3)
		Assert.equal(#player.offers, 3)
	end,
}
