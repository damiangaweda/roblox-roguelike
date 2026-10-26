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

-- Gives the player every perk of the pool at its limit, except those named.
local function maxOutExcept(run: Types.Run, player: Types.Player, left: { string })
	for id, perk in run.config.perks.pool do
		player.perks[id] = if table.find(left, id) then 0 else perk.maxStacks
	end
end

return {
	["the pool holds twenty perks"] = function()
		local n = 0
		for _ in Fixtures.config().perks.pool do
			n += 1
		end
		Assert.equal(n, 20)
	end,

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
		local pool = run.config.perks.pool
		player.perks.splitShot = pool.splitShot.maxStacks
		player.perks.quickHands = pool.quickHands.maxStacks
		for seed = 1, 20 do
			run.rng = Fixtures.run(1, nil, seed).rng
			player.offers = {}
			Perks.offer(run, player)
			for _, perk in player.offers[1] do
				Assert.truthy(perk ~= "splitShot" and perk ~= "quickHands", perk)
			end
		end
	end,

	["a perk below its maximum can still be offered"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.perks.power = run.config.perks.pool.power.maxStacks - 1
		local offered = false
		for seed = 1, 40 do
			run.rng = Fixtures.run(1, nil, seed).rng
			player.offers = {}
			Perks.offer(run, player)
			if table.find(player.offers[1], "power") then
				offered = true
			end
		end
		Assert.truthy(offered, "power was never offered")
	end,

	["the offer shrinks when few perks remain"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		maxOutExcept(run, player, { "power", "wideReach" })
		Perks.offer(run, player)
		Assert.equal(#player.offers[1], 2)
		Assert.falsy(table.find(player.offers[1], "swift"))
	end,

	["no offer when every perk is maxed"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		maxOutExcept(run, player, {})
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

	["a queued offer is drawn again when a choice maxes out one of its perks"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local max = run.config.perks.pool.power.maxStacks
		player.perks.power = max - 1
		player.offers = { { "power", "toughness" }, { "power", "toughness" } }
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(player.perks.power, max)
		Assert.equal(#player.offers, 1)
		Assert.equal(#player.offers[1], run.config.perks.offerSize)
		Assert.falsy(
			table.find(player.offers[1], "power"),
			"the stale offer still holds the maxed perk"
		)
		local announced = Assert.findEvent(run.events, "offer")
		Assert.equal(table.concat(announced.perks, ","), table.concat(player.offers[1], ","))
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(player.perks.power, max)
	end,

	["a queued offer that is still valid is kept"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.offers = { { "power", "toughness" }, { "wideReach", "swift" } }
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(table.concat(player.offers[1], ","), "wideReach,swift")
		Assert.equal(
			table.concat(Assert.findEvent(run.events, "offer").perks, ","),
			"wideReach,swift"
		)
	end,

	["a stale offer is dropped when no perk is left to draw"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		maxOutExcept(run, player, { "power" })
		player.perks.power = run.config.perks.pool.power.maxStacks - 1
		player.offers = { { "power" }, { "power" } }
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(#player.offers, 0)
		Assert.equal(count(run.events, "offer"), 0)
	end,

	["perks never exceed their stacks across many seeds"] = function()
		for seed = 1, 200 do
			local run = Fixtures.run(1, nil, seed)
			local player = run.players[1]
			for _ = 1, 30 do
				Perks.offer(run, player)
			end
			while #player.offers > 0 do
				Perks.choose(run, 1, 1)
			end
			for id, stacks in player.perks do
				Assert.truthy(
					stacks <= run.config.perks.pool[id].maxStacks,
					id .. " over its cap with seed " .. seed
				)
			end
		end
	end,

	["modifiers are empty without perks"] = function()
		local run = Fixtures.run(1)
		local modifiers = Perks.modifiers(run.config, run.players[1])
		Assert.equal(next(modifiers), nil)
		Assert.equal(Perks.value(modifiers, "damage", 10), 10)
	end,

	["modifiers multiply per stack"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local mul = run.config.perks.pool.power.mul :: number
		player.perks.power = 1
		Assert.near(Perks.modifiers(run.config, player).damage.mul, mul)
		player.perks.power = 2
		local modifier = Perks.modifiers(run.config, player).damage
		Assert.near(modifier.mul, mul * mul)
		Assert.near(modifier.mul, 1.15 ^ 2)
		Assert.equal(modifier.add, 0)
	end,

	["modifiers add per stack"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.perks.toughness = 2
		local modifier = Perks.modifiers(run.config, player).maxHealth
		Assert.equal(modifier.add, 50)
		Assert.equal(modifier.mul, 1)
	end,

	["modifiers are kept apart by property"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.perks.power = 1
		player.perks.toughness = 1
		player.perks.ghost = 2
		player.perks.swift = 0
		local modifiers = Perks.modifiers(run.config, player)
		Assert.near(modifiers.damage.mul, 1.15)
		Assert.equal(modifiers.damage.add, 0)
		Assert.equal(modifiers.maxHealth.add, 25)
		Assert.equal(modifiers.maxHealth.mul, 1)
		Assert.falsy(modifiers.moveSpeed)
		Assert.falsy(modifiers.ghost)
	end,

	["value multiplies and then adds"] = function()
		local config = Fixtures.config()
		config.perks.pool.power.add = 5
		local run = Fixtures.run(1, config)
		local player = run.players[1]
		player.perks.power = 2
		local modifiers = Perks.modifiers(config, player)
		Assert.near(Perks.value(modifiers, "damage", 100), 100 * 1.15 ^ 2 + 10)
		Assert.near(Perks.playerValue(config, player, "damage", 100), 100 * 1.15 ^ 2 + 10)
		Assert.equal(Perks.value(modifiers, "range", 100), 100)
	end,

	["Toughness raises maximum health and health"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.offers = { { "toughness", "quickHands" } }
		player.health = 50
		local bonus = run.config.perks.pool.toughness.add :: number
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(bonus, 25)
		Assert.equal(player.maxHealth, run.config.player.maxHealth + bonus)
		Assert.equal(player.health, 50 + bonus)
		Assert.equal(player.perks.toughness, 1)

		player.offers = { { "toughness", "quickHands" } }
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(player.maxHealth, run.config.player.maxHealth + 2 * bonus)
		Assert.equal(player.health, 50 + 2 * bonus)
	end,

	["Toughness taken while downed raises the maximum and leaves the player downed"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.state = "downed"
		player.health = 0
		player.offers = { { "toughness", "quickHands" } }
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(player.state, "downed")
		Assert.equal(player.maxHealth, run.config.player.maxHealth + 25)
	end,

	["Fleet Footed adds a dash charge at once"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local charges = player.dashCharges
		player.offers = { { "fleetFooted", "quickHands" } }
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(player.dashCharges, charges + 1)
		Assert.equal(player.perks.fleetFooted, 1)
	end,

	["a perk of another property changes neither health nor dash charges"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local charges = player.dashCharges
		player.offers = { { "power", "quickHands" } }
		Assert.truthy(Perks.choose(run, 1, 1))
		Assert.equal(player.dashCharges, charges)
		Assert.equal(player.maxHealth, run.config.player.maxHealth)
		Assert.equal(player.health, run.config.player.maxHealth)
	end,
}
