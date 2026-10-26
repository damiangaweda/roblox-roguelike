--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Perks = require("../src/shared/Core/Perks")
local Types = require("../src/shared/Core/Types")

local function count(events: { Types.Event }, kind: string): number
	local n = 0
	for _, event in events do
		if event.kind == kind then
			n += 1
		end
	end
	return n
end

return {
	["an offer has offerSize distinct perks from the pool"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Perks.offer(run, player)
		local offer = player.offers[1]
		Assert.equal(#offer, run.config.perks.offerSize)
		local seen = {}
		for _, perk in offer do
			Assert.truthy(run.config.perks.pool[perk], "not in the pool: " .. perk)
			Assert.falsy(seen[perk], "repeated: " .. perk)
			seen[perk] = true
		end
	end,

	["the same seed offers the same perks"] = function()
		local function offerFor(seed: number): { string }
			local run = Fixtures.run(1, nil, seed)
			Perks.offer(run, run.players[1])
			return run.players[1].offers[1]
		end
		for seed = 1, 20 do
			Assert.equal(table.concat(offerFor(seed), ","), table.concat(offerFor(seed), ","))
		end
	end,

	["different seeds can offer different perks"] = function()
		local distinct = {}
		for seed = 1, 20 do
			local run = Fixtures.run(1, nil, seed)
			Perks.offer(run, run.players[1])
			distinct[table.concat(run.players[1].offers[1], ",")] = true
		end
		local n = 0
		for _ in distinct do
			n += 1
		end
		Assert.truthy(n > 1, "every seed gave the same offer")
	end,

	["perks at their maximum are not offered"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.perks.searingBolts = 1
		player.perks.quickHands = 5
		for seed = 1, 20 do
			run.rng = Fixtures.run(1, nil, seed).rng
			player.offers = {}
			Perks.offer(run, player)
			for _, perk in player.offers[1] do
				Assert.truthy(perk ~= "searingBolts" and perk ~= "quickHands", perk)
			end
		end
	end,

	["the offer shrinks when few perks remain"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		for id, perk in run.config.perks.pool do
			player.perks[id] = perk.maxStacks
		end
		player.perks.frostBolts = nil
		player.perks.iceBlast = nil
		Perks.offer(run, player)
		Assert.equal(#player.offers[1], 2)
	end,

	["no offer when every perk is maxed"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		for id, perk in run.config.perks.pool do
			player.perks[id] = perk.maxStacks
		end
		Perks.offer(run, player)
		Assert.equal(#player.offers, 0)
		Assert.equal(#run.events, 0)
	end,

	["only the oldest offer is announced"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Perks.offer(run, player)
		Perks.offer(run, player)
		Assert.equal(#player.offers, 2)
		Assert.equal(count(run.events, "offer"), 1)
		local event = Assert.findEvent(run.events, "offer")
		Assert.equal(event.player, 1)
		Assert.equal(table.concat(event.perks, ","), table.concat(player.offers[1], ","))
	end,

	["choosing takes the perk and re-announces the next offer"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Perks.offer(run, player)
		Perks.offer(run, player)
		local second = player.offers[2]
		local first = player.offers[1]
		run.events = {}

		Assert.truthy(Perks.choose(run, 1, 2))
		Assert.equal(player.perks[first[2]], 1)
		Assert.equal(#player.offers, 1)
		local taken = Assert.findEvent(run.events, "perkTaken")
		Assert.equal(taken.perk, first[2])
		Assert.equal(taken.player, 1)
		local offer = Assert.findEvent(run.events, "offer")
		Assert.equal(table.concat(offer.perks, ","), table.concat(second, ","))

		run.events = {}
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(#player.offers, 0)
		Assert.equal(count(run.events, "offer"), 0)
	end,

	["choose rejects a bad index, no offer and unknown players"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Assert.falsy(Perks.choose(run, 1, 1), "no offer")
		Perks.offer(run, player)
		Assert.falsy(Perks.choose(run, 1, 0))
		Assert.falsy(Perks.choose(run, 1, 4))
		Assert.falsy(Perks.choose(run, 1, 1.5))
		Assert.falsy(Perks.choose(run, 9, 1))
		Assert.equal(#player.offers, 1)
	end,

	["choose works while downed but not once dead or extracted"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Perks.offer(run, player)
		player.state = "dead"
		Assert.falsy(Perks.choose(run, 1, 1))
		player.state = "extracted"
		Assert.falsy(Perks.choose(run, 1, 1))
		player.state = "downed"
		Assert.truthy(Perks.choose(run, 1, 1))
	end,

	["toughness raises max health and health"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.offers = { { "toughness", "quickHands" } }
		player.health = 50
		local bonus = run.config.perks.toughnessHealth
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(player.maxHealth, run.config.player.maxHealth + bonus)
		Assert.equal(player.health, 50 + bonus)
		Assert.equal(player.perks.toughness, 1)
	end,
}
