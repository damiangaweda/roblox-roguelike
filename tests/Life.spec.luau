--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Life = require("../src/shared/Core/Life")
local Map = require("../src/shared/Core/Map")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

-- Advances the clock and the life rules by `seconds` in steps of `dt`.
local function advance(run: Types.Run, seconds: number, dt: number)
	for _ = 1, math.round(seconds / dt) do
		run.time += dt
		Life.update(run, dt)
	end
end

local function count(events: { Types.Event }, kind: string): number
	local n = 0
	for _, event in events do
		if event.kind == kind then
			n += 1
		end
	end
	return n
end

-- Two players: player 1 downed, player 2 alive beside them and holding the
-- interact button. A third player, if asked for, stands apart.
local function downedPair(players: number?): (Types.Run, Types.Player, Types.Player)
	local run = Fixtures.run(players or 2)
	local downed, helper = run.players[1], run.players[2]
	helper.x, helper.z = downed.x + 3, downed.z
	helper.interacting = true
	Life.damage(run, downed, downed.maxHealth)
	run.events = {}
	return run, downed, helper
end

-- A lone player standing at the centre of the first entry, with dry ground
-- within 30 studs of it.
local function alone(): (Types.Run, Types.Player, Types.MapPoint)
	local run = Fixtures.run(1)
	local player = run.players[1]
	local point = Fixtures.entryOf(run)
	Fixtures.dry(run, point.x, point.z, 30)
	Fixtures.place(run, player, point.x, point.z)
	return run, player, point
end

return {
	["damage reduces health and emits playerHurt"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		Life.damage(run, player, 30)
		Assert.equal(player.health, player.maxHealth - 30)
		Assert.equal(player.state, "alive")
		local event = Assert.findEvent(run.events, "playerHurt")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
		Assert.equal(event.amount, 30)
		Assert.equal(event.enemyId, nil)
		Assert.falsy(Assert.findEvent(run.events, "downed"))
	end,

	["playerHurt names the enemy that did the damage"] = function()
		local run = Fixtures.run(1)
		Life.damage(run, run.players[1], 10, 7)
		Assert.equal(Assert.findEvent(run.events, "playerHurt").enemyId, 7)
	end,

	["damage records when the player was hurt"] = function()
		local run = Fixtures.run(1)
		run.time = 4.5
		Life.damage(run, run.players[1], 10)
		Assert.equal(run.players[1].hurtAt, 4.5)
	end,

	["zero health downs the player"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		run.time = 12
		Life.damage(run, player, player.maxHealth + 50, 3)
		Assert.equal(player.health, 0)
		Assert.equal(player.state, "downed")
		Assert.equal(player.downedAt, 12)
		Assert.equal(player.reviveProgress, 0)
		local hurt = Assert.findEvent(run.events, "playerHurt")
		Assert.equal(hurt.enemyId, 3)
		local event = Assert.findEvent(run.events, "downed")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
	end,

	["damage to a downed player does nothing"] = function()
		local run, downed = downedPair()
		Life.damage(run, downed, 10)
		Assert.equal(downed.health, 0)
		Assert.equal(downed.state, "downed")
		Assert.equal(#run.events, 0)
	end,

	["damage to a dead player does nothing"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.state = "dead"
		player.health = 0
		Life.damage(run, player, 10)
		Assert.equal(player.health, 0)
		Assert.equal(#run.events, 0)
	end,

	["damage that is not positive does nothing"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		Life.damage(run, player, 0)
		Life.damage(run, player, -5)
		Assert.equal(player.health, player.maxHealth)
		Assert.equal(#run.events, 0)
	end,

	["damage resets extraction progress"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.extractProgress = 3
		Life.damage(run, player, 5)
		Assert.equal(player.extractProgress, 0)
	end,

	["damage interrupts drinking"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.potions = 1
		Assert.truthy(Life.drink(run, 1))
		run.events = {}
		Life.damage(run, player, 5)
		Assert.equal(player.drinkingUntil, nil)
		Assert.truthy(Assert.findEvent(run.events, "drinkInterrupted"))
		advance(run, 2, 0.5)
		Assert.equal(player.potions, 1)
		Assert.falsy(Assert.findEvent(run.events, "drank"))
		Assert.equal(player.health, player.maxHealth - 5)
	end,

	["damage without drinking emits no interruption"] = function()
		local run = Fixtures.run(1)
		Life.damage(run, run.players[1], 5)
		Assert.falsy(Assert.findEvent(run.events, "drinkInterrupted"))
	end,

	["a knock pushes the player away from the source and says so"] = function()
		local run, player = alone()
		local startX, startZ = player.x, player.z
		-- The source is behind and below, so the push goes toward +x and +z.
		Life.knockPlayer(run, player, startX - 3, startZ - 4, 10)
		local seconds = run.config.player.knockbackSeconds
		Assert.near(player.knockX, 6 / seconds)
		Assert.near(player.knockZ, 8 / seconds)
		Assert.equal(player.knockUntil, run.time + seconds)
		local event = Assert.findEvent(run.events, "knockback")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
		Assert.near(event.dx, 6)
		Assert.near(event.dz, 8)
		-- Telling the client is not moving the player.
		Assert.equal(player.x, startX)
		Assert.equal(player.z, startZ)
	end,

	["a knock needs an alive player and a positive distance"] = function()
		local run, player = alone()
		Life.knockPlayer(run, player, player.x - 1, player.z, 0)
		Life.knockPlayer(run, player, player.x - 1, player.z, -4)
		player.state = "downed"
		Life.knockPlayer(run, player, player.x - 1, player.z, 4)
		Assert.equal(#run.events, 0)
		Assert.equal(player.knockUntil, 0)
	end,

	["a knock moves the player by its distance over the knockback time"] = function()
		local run, player = alone()
		local startX, startZ = player.x, player.z
		local studs = 8
		Life.knockPlayer(run, player, startX - 5, startZ, studs)
		advance(run, 1, 1 / 30)
		local moved = Geometry.distance(startX, startZ, player.x, player.z)
		-- The last step before the time is up may fall short by up to one step.
		local oneStep = studs / run.config.player.knockbackSeconds / 30
		Assert.near(moved, studs, oneStep + 1e-6)
		Assert.near(player.z, startZ)
		Assert.truthy(player.x > startX)
		-- Afterwards the player stays put.
		local x = player.x
		advance(run, 1, 1 / 30)
		Assert.equal(player.x, x)
	end,

	["a knock leaves the movement budget alone"] = function()
		local run, player = alone()
		local startX, startZ = player.x, player.z
		player.moveBudget = 2
		Life.knockPlayer(run, player, startX, startZ - 5, 6)
		advance(run, 1, 1 / 30)
		-- The run carries the player; the client is pulled along, not paid for.
		Assert.equal(player.moveBudget, 2)
		Assert.truthy(player.z > startZ)
	end,

	["a knock does not push the player through a prop"] = function()
		local run, player, point = alone()
		local wall = Fixtures.prop(point, point.x + 8, point.z, 1, 6)
		local edge = wall.x - wall.halfWidth
		Fixtures.place(run, player, edge - 0.5, point.z)
		local budget = player.moveBudget
		Life.knockPlayer(run, player, player.x - 5, player.z, 10)
		for _ = 1, 30 do
			run.time += 1 / 30
			Life.update(run, 1 / 30)
			Assert.truthy(player.x < edge, "pushed into the prop")
		end
		Assert.near(player.x, edge - 0.5)
		Assert.near(player.z, point.z)
		Assert.equal(player.moveBudget, budget)
	end,

	["a knock keeps the player on walkable ground"] = function()
		local run, player, point = alone()
		Fixtures.prop(point, point.x + 8, point.z, 1, 6)
		-- Water whose middle is 22 studs from the centre along -z.
		Fixtures.water(run, point.x, point.z - 22, 12)
		-- The map's edge nearest the entry, with dry ground beside it.
		local edgeX, edgeZ, outX, outZ = point.x, point.z, 0, 0
		if math.abs(point.x) > math.abs(point.z) then
			edgeX, outX = math.sign(point.x) * (run.map.half - 1), math.sign(point.x)
		else
			edgeZ, outZ = math.sign(point.z) * (run.map.half - 1), math.sign(point.z)
		end
		Fixtures.dry(run, edgeX, edgeZ, 4)
		-- Where each push starts and which way it goes: into the prop, the
		-- water and the edge.
		local pushes = {
			{ point.x + 5, point.z, 1, 0 },
			{ point.x, point.z - 6, 0, -1 },
			{ edgeX, edgeZ, outX, outZ },
		}
		for index, push in pushes do
			Fixtures.place(run, player, push[1], push[2])
			player.knockUntil = 0
			-- The source lies behind the player, so the push goes the given way.
			Life.knockPlayer(run, player, push[1] - push[3], push[2] - push[4], 12)
			advance(run, 0.5, 1 / 30)
			Assert.truthy(Map.walkable(run.map, player.x, player.z), "push " .. index)
		end
	end,

	["drinking is refused without potions"] = function()
		local run = Fixtures.run(1)
		Assert.falsy(Life.drink(run, 1))
		Assert.equal(run.players[1].drinkingUntil, nil)
		Assert.equal(#run.events, 0)
	end,

	["drinking is refused to a downed player and an unknown one"] = function()
		local run, downed = downedPair()
		downed.potions = 1
		Assert.falsy(Life.drink(run, 1))
		Assert.falsy(Life.drink(run, 99))
		Assert.equal(#run.events, 0)
	end,

	["drinking is refused while already drinking"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.potions = 2
		Assert.truthy(Life.drink(run, 1))
		local endsAt = player.drinkingUntil
		run.time = 0.5
		Assert.falsy(Life.drink(run, 1))
		Assert.equal(player.drinkingUntil, endsAt)
		Assert.equal(count(run.events, "drinking"), 1)
	end,

	["a drink takes drinkSeconds, then heals and uses a potion"] = function()
		local run = Fixtures.run(1)
		local config = run.config.player
		local player = run.players[1]
		player.potions = 2
		player.health = 20
		Assert.truthy(Life.drink(run, 1))
		Assert.equal(player.drinkingUntil, run.time + config.drinkSeconds)
		Assert.truthy(Assert.findEvent(run.events, "drinking"))
		-- Still drinking just before the time is up.
		advance(run, config.drinkSeconds - 0.25, 0.25)
		Assert.equal(player.health, 20)
		Assert.equal(player.potions, 2)
		advance(run, 0.25, 0.25)
		Assert.equal(player.health, 20 + config.potionHeal)
		Assert.equal(player.potions, 1)
		Assert.equal(player.drinkingUntil, nil)
		local event = Assert.findEvent(run.events, "drank")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
		Assert.equal(event.amount, config.potionHeal)
		-- One drink is one potion.
		advance(run, 2, 0.25)
		Assert.equal(player.potions, 1)
		Assert.equal(count(run.events, "drank"), 1)
	end,

	["a potion heals no more than the missing health"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		player.potions = 1
		player.health = player.maxHealth - 20
		Life.drink(run, 1)
		advance(run, run.config.player.drinkSeconds, 0.25)
		Assert.equal(player.health, player.maxHealth)
		Assert.equal(Assert.findEvent(run.events, "drank").amount, 20)
	end,

	["Strong Brew multiplies the heal of a potion"] = function()
		local run = Fixtures.run(1)
		local config = run.config
		local player = run.players[1]
		player.maxHealth = 400
		player.health = 10
		player.potions = 2
		local brew = config.perks.pool.strongBrew.mul :: number
		player.perks.strongBrew = 1
		Life.drink(run, 1)
		advance(run, config.player.drinkSeconds, 0.25)
		Assert.near(player.health, 10 + config.player.potionHeal * brew)
		player.perks.strongBrew = 2
		player.health = 10
		Life.drink(run, 1)
		advance(run, config.player.drinkSeconds, 0.25)
		Assert.near(player.health, 10 + config.player.potionHeal * brew ^ 2)
	end,

	["a potion pickup within reach is taken"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local reach = run.config.player.pickupRadius
		State.newPickup(run, "potion", player.x + reach - 0.5, player.z)
		advance(run, 0.1, 0.1)
		Assert.equal(player.potions, 1)
		Assert.equal(#run.pickups, 0)
		local event = Assert.findEvent(run.events, "pickedUp")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
		Assert.equal(event.pickup, "potion")
	end,

	["a potion pickup out of reach stays"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local reach = run.config.player.pickupRadius
		State.newPickup(run, "potion", player.x + reach + 0.5, player.z)
		advance(run, 1, 0.25)
		Assert.equal(player.potions, 0)
		Assert.equal(#run.pickups, 1)
		Assert.falsy(Assert.findEvent(run.events, "pickedUp"))
	end,

	["a downed player takes no pickup"] = function()
		local run, downed = downedPair()
		run.players[2] = nil
		State.newPickup(run, "potion", downed.x, downed.z)
		advance(run, 0.5, 0.5)
		Assert.equal(downed.potions, 0)
		Assert.equal(#run.pickups, 1)
	end,

	["a potion pickup stays when the player carries the most"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local capacity = run.config.player.potionCapacity
		Assert.equal(Life.potionCapacity(run, player), capacity)
		player.potions = capacity
		State.newPickup(run, "potion", player.x, player.z)
		advance(run, 1, 0.25)
		Assert.equal(player.potions, capacity)
		Assert.equal(#run.pickups, 1)
		-- Drinking makes room for it.
		Life.drink(run, 1)
		advance(run, run.config.player.drinkSeconds, 0.25)
		Assert.equal(player.potions, capacity)
		Assert.equal(#run.pickups, 0)
	end,

	["Deep Pockets raises the capacity"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local base = run.config.player.potionCapacity
		player.perks.deepPockets = 1
		Assert.equal(Life.potionCapacity(run, player), base + 1)
		player.perks.deepPockets = 2
		Assert.equal(Life.potionCapacity(run, player), base + 2)

		player.potions = base
		State.newPickup(run, "potion", player.x, player.z)
		advance(run, 0.5, 0.5)
		Assert.equal(player.potions, base + 1)
		Assert.equal(#run.pickups, 0)
	end,

	["a downed player is revived after three seconds near an alive one"] = function()
		local run, downed, helper = downedPair()
		local config = run.config.player
		advance(run, config.reviveSeconds - 0.5, 0.5)
		Assert.equal(downed.state, "downed")
		advance(run, 0.5, 0.5)
		Assert.equal(downed.state, "alive")
		Assert.equal(downed.health, downed.maxHealth * config.reviveHealthFraction)
		Assert.equal(downed.downedAt, nil)
		Assert.equal(downed.reviveProgress, 0)
		local event = Assert.findEvent(run.events, "revived")
		Assert.truthy(event)
		Assert.equal(event.player, downed.id)
		Assert.equal(event.by, helper.id)
	end,

	["the nearest alive player is credited with the revive"] = function()
		local run, downed = downedPair(3)
		run.players[2].x = downed.x + 6
		run.players[3].x, run.players[3].z = downed.x + 1, downed.z
		run.players[3].interacting = true
		advance(run, run.config.player.reviveSeconds, 0.5)
		Assert.equal(downed.state, "alive")
		Assert.equal(Assert.findEvent(run.events, "revived").by, 3)
	end,

	["a player out of revive range does not revive"] = function()
		local run, downed, helper = downedPair()
		helper.x = downed.x + run.config.player.reviveRadius + 1
		advance(run, run.config.player.reviveSeconds, 0.5)
		Assert.equal(downed.state, "downed")
		Assert.equal(downed.reviveProgress, 0)
	end,

	["a downed or dead player does not revive"] = function()
		local run, downed, helper = downedPair()
		helper.state = "downed"
		advance(run, run.config.player.reviveSeconds, 0.5)
		Assert.equal(downed.state, "downed")
		helper.state = "dead"
		advance(run, 1, 0.5)
		Assert.equal(downed.state, "downed")
	end,

	["moving away resets revive progress"] = function()
		local run, downed, helper = downedPair()
		advance(run, 2, 0.5)
		Assert.near(downed.reviveProgress, 2)
		local nearX = helper.x
		helper.x = nearX + 100
		advance(run, 0.5, 0.5)
		Assert.equal(downed.reviveProgress, 0)
		helper.x = nearX
		advance(run, 2, 0.5)
		Assert.equal(downed.state, "downed")
	end,

	["bleeding out pauses while being revived"] = function()
		local run, downed, helper = downedPair()
		local config = run.config.player
		local nearX = helper.x
		-- Bleed for 10 s alone, revive for 2 s, then be left alone again.
		helper.x = nearX + 100
		advance(run, 10, 0.5)
		helper.x = nearX
		advance(run, 2, 0.5)
		helper.x = nearX + 100
		-- 10 s bled; 5 s remain, not the 3 s that a running clock would leave.
		advance(run, config.downedSeconds - 10 - 0.5, 0.5)
		Assert.equal(downed.state, "downed")
		advance(run, 0.5, 0.5)
		Assert.equal(downed.state, "dead")
	end,

	["a player alone dies after fifteen seconds"] = function()
		local run, downed = downedPair()
		run.players[2] = nil
		local downedSeconds = run.config.player.downedSeconds
		advance(run, downedSeconds - 1, 1)
		Assert.equal(downed.state, "downed")
		Assert.falsy(Assert.findEvent(run.events, "died"))
		advance(run, 1, 1)
		Assert.equal(downed.state, "dead")
		local event = Assert.findEvent(run.events, "died")
		Assert.truthy(event)
		Assert.equal(event.player, 1)
	end,

	["standing beside a downed player without holding interact does not revive"] = function()
		local run, downed, helper = downedPair()
		helper.interacting = false
		advance(run, run.config.player.reviveSeconds + 1, 0.5)
		Assert.equal(downed.state, "downed")
		Assert.equal(downed.reviveProgress, 0)
	end,

	["letting go of interact resets revive progress"] = function()
		local run, downed, helper = downedPair()
		advance(run, run.config.player.reviveSeconds / 2, 0.5)
		Assert.truthy(downed.reviveProgress > 0)
		helper.interacting = false
		advance(run, 0.5, 0.5)
		Assert.equal(downed.reviveProgress, 0)
	end,

	["a hit on the reviver starts the revive over"] = function()
		local run, downed, helper = downedPair()
		local seconds = run.config.player.reviveSeconds
		advance(run, seconds / 2, 0.5)
		Assert.truthy(downed.reviveProgress > 0)
		run.time += 0.5
		Life.damage(run, helper, 1)
		Life.update(run, 0.5)
		Assert.equal(downed.reviveProgress, 0)
		Assert.equal(downed.state, "downed")
		-- The next full revive time brings them back, not what was left of it.
		advance(run, seconds - 0.5, 0.5)
		Assert.equal(downed.state, "downed")
		advance(run, 0.5, 0.5)
		Assert.equal(downed.state, "alive")
	end,
}
