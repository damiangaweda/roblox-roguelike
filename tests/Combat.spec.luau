--!strict
local Assert = require("./Assert")
local Combat = require("../src/shared/Core/Combat")
local Fixtures = require("./Fixtures")
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
	-- Basic attack

	["the basic attack hits the nearest enemy in range"] = function()
		local run = Fixtures.run()
		local far = Fixtures.enemy(run, "grunt", 30, 0)
		local near = Fixtures.enemy(run, "grunt", 10, 0)
		Combat.basicAttacks(run)
		Assert.equal(near.health, 20 - run.config.basicAttack.damage)
		Assert.equal(far.health, 20)
		local hit = Assert.findEvent(run.events, "hit")
		Assert.equal(hit.enemyId, near.id)
		Assert.equal(hit.source, 1)
		Assert.equal(hit.amount, run.config.basicAttack.damage)
		Assert.falsy(hit.synergy)
		Assert.falsy(hit.skill)
	end,

	["the basic attack ignores enemies out of range and stays ready"] = function()
		local run = Fixtures.run()
		local enemy = Fixtures.enemy(run, "grunt", run.config.basicAttack.range + 1, 0)
		Combat.basicAttacks(run)
		Assert.equal(enemy.health, 20)
		Assert.equal(#run.events, 0)
		Assert.equal(run.players[1].basicReadyAt, 0)
	end,

	["the basic attack waits for its interval"] = function()
		local run = Fixtures.run()
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		Combat.basicAttacks(run)
		Assert.equal(enemy.health, 70)
		Assert.near(run.players[1].basicReadyAt, run.config.basicAttack.intervalSeconds)

		run.time = run.config.basicAttack.intervalSeconds - 0.01
		Combat.basicAttacks(run)
		Assert.equal(enemy.health, 70)

		run.time = run.config.basicAttack.intervalSeconds
		Combat.basicAttacks(run)
		Assert.equal(enemy.health, 60)
	end,

	["Quick Hands shortens the interval per stack"] = function()
		local run = Fixtures.run()
		run.players[1].perks.quickHands = 2
		Fixtures.enemy(run, "brute", 5, 0)
		run.time = 10
		Combat.basicAttacks(run)
		local expected = 10 + 0.6 * 0.85 ^ 2
		Assert.near(run.players[1].basicReadyAt, expected)
	end,

	["only alive players attack, in ascending id order"] = function()
		local run = Fixtures.run(3)
		run.players[2].state = "downed"
		Fixtures.enemy(run, "brute", 5, 0)
		Combat.basicAttacks(run)
		local sources = {}
		for _, event in run.events do
			if event.kind == "hit" then
				table.insert(sources, event.source)
			end
		end
		Assert.equal(table.concat(sources, ","), "1,3")
	end,

	["searing bolts ignite and frost bolts chill"] = function()
		local run = Fixtures.run(2)
		run.players[1].perks.searingBolts = 1
		run.players[2].perks.frostBolts = 1
		run.players[2].x = 1000
		local burnt = Fixtures.enemy(run, "brute", 5, 0)
		local chilled = Fixtures.enemy(run, "brute", 1000, 5)
		run.time = 1
		Combat.basicAttacks(run)
		Assert.near(burnt.burningUntil, 1 + run.config.statuses.burnSeconds)
		Assert.equal(burnt.burnSource, 1)
		Assert.equal(burnt.chilledUntil, 0)
		Assert.near(chilled.chilledUntil, 1 + run.config.statuses.chillSeconds)
		Assert.equal(chilled.burningUntil, 0)
	end,

	-- Kills

	["a kill removes the enemy, emits kill and grants xp"] = function()
		local run = Fixtures.run()
		local enemy = Fixtures.enemy(run, "grunt", 5, 0)
		enemy.health = 5
		Combat.basicAttacks(run)
		Assert.equal(#run.enemies, 0)
		local kill = Assert.findEvent(run.events, "kill")
		Assert.equal(kill.enemyId, enemy.id)
		Assert.equal(kill.source, 1)
		Assert.equal(run.players[1].kills, 1)
		Assert.equal(run.players[1].xp, run.config.horde.kinds.grunt.xp)
	end,

	["a kill that fills the xp bar levels the player up"] = function()
		local run = Fixtures.run()
		run.players[1].xp = 4
		local enemy = Fixtures.enemy(run, "grunt", 5, 0)
		enemy.health = 1
		Combat.basicAttacks(run)
		Assert.equal(run.players[1].level, 2)
		Assert.truthy(Assert.findEvent(run.events, "levelUp"))
	end,

	-- Synergy

	["fire damage shatters a chilled enemy"] = function()
		local run = Fixtures.run()
		run.players[1].perks.searingBolts = 1
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		enemy.chilledUntil = 2
		run.time = 1
		Combat.basicAttacks(run)
		local damage = run.config.basicAttack.damage * run.config.synergy.shatterMultiplier
		Assert.equal(enemy.health, 80 - damage)
		local hit = Assert.findEvent(run.events, "hit")
		Assert.equal(hit.amount, damage)
		Assert.truthy(hit.synergy)
	end,

	["fire damage on an unchilled enemy does not shatter"] = function()
		local run = Fixtures.run()
		run.players[1].perks.searingBolts = 1
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		enemy.chilledUntil = 1
		run.time = 1 -- the chill has just ended
		Combat.basicAttacks(run)
		Assert.equal(enemy.health, 80 - run.config.basicAttack.damage)
		Assert.falsy(Assert.findEvent(run.events, "hit").synergy)
	end,

	["non-fire damage on a chilled enemy does not shatter"] = function()
		local run = Fixtures.run()
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		enemy.chilledUntil = 2
		run.time = 1
		Combat.basicAttacks(run)
		Assert.equal(enemy.health, 80 - run.config.basicAttack.damage)
	end,

	["a fire and ice bolt does not shatter its own chill"] = function()
		local run = Fixtures.run()
		run.players[1].perks.searingBolts = 1
		run.players[1].perks.frostBolts = 1
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		Combat.basicAttacks(run)
		Assert.equal(enemy.health, 80 - run.config.basicAttack.damage)
		Assert.falsy(Assert.findEvent(run.events, "hit").synergy)
		Assert.truthy(enemy.chilledUntil > run.time)
		Assert.truthy(enemy.burningUntil > run.time)

		-- The next one does.
		run.time = 1
		Combat.basicAttacks(run)
		Assert.truthy(Assert.findEvent(run.events, "hit"))
		local last
		for _, event in run.events do
			if event.kind == "hit" then
				last = event
			end
		end
		Assert.truthy(last.synergy)
	end,

	-- Skill

	["the skill hits every enemy within its radius of the aim point"] = function()
		local run = Fixtures.run()
		local skill = run.config.skill
		local a = Fixtures.enemy(run, "brute", 20, 0)
		local b = Fixtures.enemy(run, "brute", 20 + skill.radius, 0)
		local c = Fixtures.enemy(run, "brute", 20 + skill.radius + 1, 0)
		Assert.truthy(Combat.useSkill(run, 1, { x = 20, z = 0 }))
		Assert.equal(a.health, 80 - skill.damage)
		Assert.equal(b.health, 80 - skill.damage)
		Assert.equal(c.health, 80)
		local hit = Assert.findEvent(run.events, "hit")
		Assert.truthy(hit.skill)
		Assert.equal(count(run.events, "hit"), 2)
	end,

	["the skill goes on cooldown"] = function()
		local run = Fixtures.run()
		local skill = run.config.skill
		Fixtures.enemy(run, "brute", 5, 0)
		Assert.truthy(Combat.useSkill(run, 1, { x = 5, z = 0 }))
		Assert.near(run.players[1].skillReadyAt, skill.cooldownSeconds)
		run.time = skill.cooldownSeconds - 0.01
		Assert.falsy(Combat.useSkill(run, 1, { x = 5, z = 0 }))
		run.time = skill.cooldownSeconds
		Assert.truthy(Combat.useSkill(run, 1, { x = 5, z = 0 }))
	end,

	["an aim beyond range is pulled back onto the range circle"] = function()
		local run = Fixtures.run()
		local skill = run.config.skill
		local onCircle = Fixtures.enemy(run, "brute", skill.range + skill.radius - 1, 0)
		local pastIt = Fixtures.enemy(run, "brute", skill.range + skill.radius + 1, 0)
		Assert.truthy(Combat.useSkill(run, 1, { x = 500, z = 0 }))
		Assert.equal(onCircle.health, 80 - skill.damage)
		Assert.equal(pastIt.health, 80, "the blast is centred at the range, not at the aim")
	end,

	["the skill auto-aims at the nearest enemy in range"] = function()
		local run = Fixtures.run()
		local skill = run.config.skill
		local target = Fixtures.enemy(run, "brute", 15, 0)
		Fixtures.enemy(run, "brute", 30, 0)
		Assert.truthy(Combat.useSkill(run, 1, nil))
		Assert.equal(target.health, 80 - skill.damage)
	end,

	["the skill without a target in range fails and keeps its cooldown"] = function()
		local run = Fixtures.run()
		Fixtures.enemy(run, "brute", run.config.skill.range + 1, 0)
		Assert.falsy(Combat.useSkill(run, 1, nil))
		Assert.equal(run.players[1].skillReadyAt, 0)
		Assert.equal(#run.events, 0)
	end,

	["the skill with an aim succeeds even when it hits nothing"] = function()
		local run = Fixtures.run()
		Assert.truthy(Combat.useSkill(run, 1, { x = 0, z = 10 }))
		Assert.near(run.players[1].skillReadyAt, run.config.skill.cooldownSeconds)
	end,

	["the skill needs an alive player"] = function()
		local run = Fixtures.run()
		Fixtures.enemy(run, "brute", 5, 0)
		Assert.falsy(Combat.useSkill(run, 7, nil))
		run.players[1].state = "downed"
		Assert.falsy(Combat.useSkill(run, 1, nil))
		Assert.falsy(Combat.useSkill(run, 1, { x = 5, z = 0 }))
	end,

	["blast perks tag the skill"] = function()
		local run = Fixtures.run()
		run.players[1].perks.fireBlast = 1
		run.players[1].perks.iceBlast = 1
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		Assert.truthy(Combat.useSkill(run, 1, nil))
		Assert.truthy(enemy.burningUntil > 0)
		Assert.truthy(enemy.chilledUntil > 0)
		Assert.falsy(Assert.findEvent(run.events, "hit").synergy)
	end,

	["a fire blast shatters chilled enemies"] = function()
		local run = Fixtures.run()
		run.players[1].perks.fireBlast = 1
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		enemy.chilledUntil = 5
		Assert.truthy(Combat.useSkill(run, 1, nil))
		Assert.equal(
			enemy.health,
			80 - run.config.skill.damage * run.config.synergy.shatterMultiplier
		)
		Assert.truthy(Assert.findEvent(run.events, "hit").synergy)
	end,

	["a skill that kills several enemies credits and removes each"] = function()
		local run = Fixtures.run()
		for i = 1, 3 do
			Fixtures.enemy(run, "grunt", i, 0)
		end
		Assert.truthy(Combat.useSkill(run, 1, { x = 2, z = 0 }))
		Assert.equal(#run.enemies, 0)
		Assert.equal(count(run.events, "kill"), 3)
		Assert.equal(run.players[1].kills, 3)
	end,

	-- Burning

	["burning deals burnDps per second without hit events"] = function()
		local run = Fixtures.run()
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		enemy.burningUntil = 3
		enemy.burnSource = 1
		run.time = 1
		Combat.burn(run, 0.5)
		Assert.near(enemy.health, 80 - run.config.statuses.burnDps * 0.5)
		Assert.equal(count(run.events, "hit"), 0)
	end,

	["burning stops when the status ends"] = function()
		local run = Fixtures.run()
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		enemy.burningUntil = 3
		enemy.burnSource = 1
		run.time = 3
		Combat.burn(run, 1)
		Assert.equal(enemy.health, 80)
	end,

	["a burn tick does not renew the burn"] = function()
		local run = Fixtures.run()
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		enemy.burningUntil = 3
		enemy.burnSource = 1
		run.time = 2
		Combat.burn(run, 0.1)
		Assert.equal(enemy.burningUntil, 3)
	end,

	["burning a chilled enemy shatters"] = function()
		local run = Fixtures.run()
		local enemy = Fixtures.enemy(run, "brute", 5, 0)
		enemy.burningUntil = 3
		enemy.burnSource = 1
		enemy.chilledUntil = 3
		run.time = 1
		Combat.burn(run, 1)
		Assert.near(
			enemy.health,
			80 - run.config.statuses.burnDps * run.config.synergy.shatterMultiplier
		)
	end,

	["a burn kill is credited to the burn source"] = function()
		local run = Fixtures.run(2)
		local enemy = Fixtures.enemy(run, "grunt", 5, 0)
		enemy.health = 1
		enemy.burningUntil = 3
		enemy.burnSource = 2
		run.time = 1
		Combat.burn(run, 1)
		Assert.equal(#run.enemies, 0)
		local kill = Assert.findEvent(run.events, "kill")
		Assert.equal(kill.source, 2)
		Assert.equal(run.players[2].kills, 1)
		Assert.equal(run.players[1].kills, 0)
		Assert.equal(run.players[2].xp, run.config.horde.kinds.grunt.xp)
	end,

	["a burn kill whose source left the run still removes the enemy"] = function()
		local run = Fixtures.run()
		local enemy = Fixtures.enemy(run, "grunt", 5, 0)
		enemy.health = 1
		enemy.burningUntil = 3
		enemy.burnSource = 9
		run.time = 1
		Combat.burn(run, 1)
		Assert.equal(#run.enemies, 0)
		Assert.equal(run.players[1].kills, 0)
	end,
}
