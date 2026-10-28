--!strict
local Assert = require("./Assert")
local Damage = require("../src/shared/Core/Damage")
local Fixtures = require("./Fixtures")
local Types = require("../src/shared/Core/Types")

-- A run of one hero of `class` at (0, 0) on open ground.
local function setup(class: string?, seed: number?): (Types.Run, Types.Player)
	local run = Fixtures.run(1, nil, seed, class)
	Fixtures.clearObstacles(run)
	return run, run.players[1]
end

-- A wild boar (radius 1.5) with `health`, so a spec's hits do not kill it.
local function foe(run: Types.Run, x: number, z: number, health: number?): Types.Enemy
	local enemy = Fixtures.enemy(run, "wildBoar", x, z)
	enemy.health = health or 1000
	enemy.maxHealth = enemy.health
	return enemy
end

local function hitOf(fields: { [string]: any }): Damage.Hit
	local hit: Damage.Hit = {
		source = 1,
		skill = "test",
		amount = 10,
		tags = {},
		effect = nil,
		critChance = 0,
		knockback = 0,
		fromX = 0,
		fromZ = 0,
	}
	for key, value in fields do
		(hit :: any)[key] = value
	end
	return hit
end

local function events(run: Types.Run, kind: string): { any }
	local found = {}
	for _, event in run.events do
		if event.kind == kind then
			table.insert(found, event)
		end
	end
	return found
end

local function lastHit(run: Types.Run): any
	local hits = events(run, "hit")
	return hits[#hits]
end

return {
	["a hit takes health, credits the player and is announced"] = function()
		local run, player = setup()
		local enemy = foe(run, 10, 0)
		Assert.equal(Damage.hit(run, enemy, hitOf({ amount = 12 })), 12)
		Assert.equal(enemy.health, 988)
		Assert.equal(player.damageDone, 12)
		local hit = lastHit(run)
		Assert.equal(hit.amount, 12)
		Assert.equal(hit.crit, false)
		Assert.equal(hit.blocked, false)
		Assert.equal(hit.source, 1)
	end,

	["a crit doubles the hit, the same for a seed"] = function()
		local run = setup()
		local enemy = foe(run, 10, 0)
		Assert.equal(Damage.hit(run, enemy, hitOf({ critChance = 1 })), 20)
		Assert.equal(lastHit(run).crit, true)

		local function rolls(seed: number): string
			local seeded = setup(nil, seed)
			local target = foe(seeded, 10, 0, 1e6)
			local out = {}
			for _ = 1, 30 do
				table.insert(out, tostring(Damage.hit(seeded, target, hitOf({ critChance = 0.5 }))))
			end
			return table.concat(out, ",")
		end
		local first = rolls(11)
		Assert.equal(rolls(11), first)
		Assert.truthy(string.find(first, "20", 1, true), "some crits")
		Assert.truthy(string.find(first, "10", 1, true), "some plain hits")
	end,

	["the shieldbearer blocks a hit from its front and takes one from behind"] = function()
		local run = setup()
		local shield = Fixtures.enemy(run, "shieldbearer", 10, 0)
		shield.facing = 0
		local effect: Types.EffectConfig = { kind = "slow", factor = 0.5, seconds = 2 }
		local dealt = Damage.hit(
			run,
			shield,
			hitOf({ fromX = 15, fromZ = 0, effect = effect, tags = { "ice" } })
		)
		Assert.equal(dealt, 0)
		Assert.equal(shield.health, 140)
		Assert.equal(shield.slowFactor, 1)
		Assert.equal(shield.chilledUntil, 0)
		local hit = lastHit(run)
		Assert.equal(hit.blocked, true)
		Assert.equal(hit.amount, 0)
		-- From behind, and 90 degrees off a 150-degree arc.
		Assert.equal(Damage.hit(run, shield, hitOf({ fromX = 5, fromZ = 0 })), 10)
		Assert.equal(Damage.hit(run, shield, hitOf({ fromX = 10, fromZ = 5 })), 10)
		Assert.equal(shield.health, 120)
	end,

	["slows keep the strongest factor and the longest duration"] = function()
		local run = setup()
		local enemy = foe(run, 10, 0)
		Damage.applyStatus(run, enemy, "slowed", 2, 0.5)
		Damage.applyStatus(run, enemy, "slowed", 4, 0.8)
		Assert.near(enemy.slowFactor, 0.5)
		Assert.near(enemy.slowUntil, 4)
		Assert.truthy(Damage.hasStatus(run, enemy, "slowed"))
		Assert.truthy(Assert.findEvent(run.events, "statusApplied"))
		run.time = 4
		Damage.update(run, 0)
		Assert.near(enemy.slowFactor, 1)
	end,

	["an ice hit chills"] = function()
		local run = setup()
		local enemy = foe(run, 10, 0)
		Damage.hit(run, enemy, hitOf({ tags = { "ice" } }))
		Assert.near(enemy.chilledUntil, run.config.statuses.chillSeconds)
		Assert.near(enemy.slowFactor, run.config.statuses.chillFactor)
		Assert.truthy(Damage.hasStatus(run, enemy, "chilled"))
	end,

	["roots, stuns and fear last; weaken overwrites"] = function()
		local run = setup()
		local enemy = foe(run, 10, 0)
		Damage.applyEffect(run, enemy, { kind = "root", seconds = 2.5 }, 1, {})
		Damage.applyEffect(run, enemy, { kind = "root", seconds = 1 }, 1, {})
		Damage.applyEffect(run, enemy, { kind = "stun", seconds = 0.8 }, 1, {})
		Damage.applyEffect(run, enemy, { kind = "fear", seconds = 3 }, 1, {})
		Damage.applyEffect(run, enemy, { kind = "weaken", factor = 0.5, seconds = 5 }, 1, {})
		Damage.applyEffect(run, enemy, { kind = "weaken", factor = 0.8, seconds = 2 }, 1, {})
		Assert.near(enemy.rootedUntil, 2.5)
		Assert.near(enemy.stunnedUntil, 0.8)
		Assert.near(enemy.fearedUntil, 3)
		Assert.near(enemy.weakenFactor, 0.8)
		Assert.near(enemy.weakenUntil, 2)
		for _, status: Types.Status in { "rooted", "stunned", "feared", "weakened" } do
			Assert.truthy(Damage.hasStatus(run, enemy, status), status)
		end
		run.time = 2
		Damage.update(run, 0)
		Assert.near(enemy.weakenFactor, 1)
	end,

	["a drain heals the hero a share of the hit"] = function()
		local run, player = setup()
		player.health = 50
		local enemy = foe(run, 10, 0)
		Damage.hit(run, enemy, hitOf({ amount = 20, effect = { kind = "drain", factor = 0.5 } }))
		Assert.near(player.health, 60)
	end,

	["an execute kills below the share, not above it, and never a boss"] = function()
		local run = setup()
		local execute: Types.EffectConfig = { kind = "execute", factor = 0.3 }
		local high = foe(run, 10, 0, 100)
		Damage.hit(run, high, hitOf({ amount = 10, effect = execute }))
		Assert.equal(high.health, 90)
		local low = foe(run, 12, 0, 100)
		low.health = 35
		Damage.hit(run, low, hitOf({ amount = 10, effect = execute }))
		Assert.truthy(low.health <= 0, "executed")
		Assert.equal(Fixtures.count(run.events, "kill"), 1)
		local boss = Fixtures.enemy(run, "thornback", 20, 0)
		boss.health = 0.1 * boss.maxHealth
		local before = boss.health
		Damage.hit(run, boss, hitOf({ amount = 10, effect = execute }))
		Assert.near(boss.health, before - 10)
	end,

	["a boss resists slows to the floor, shortens control and ignores fear"] = function()
		local run = setup()
		local boss = Fixtures.enemy(run, "thornback", 20, 0)
		local horde = run.config.horde
		Damage.applyStatus(run, boss, "slowed", 3, 0.5)
		Assert.near(boss.slowFactor, horde.bossSlowFloor)
		Damage.applyStatus(run, boss, "rooted", 2.5)
		Assert.near(boss.rootedUntil, 2.5 * horde.bossControlShare)
		Damage.applyStatus(run, boss, "stunned", 2)
		Assert.near(boss.stunnedUntil, 2 * horde.bossControlShare)
		Damage.applyStatus(run, boss, "feared", 3)
		Assert.equal(boss.fearedUntil, 0)
		Damage.applyStatus(run, boss, "weakened", 5, 0.5)
		Assert.near(boss.weakenFactor, 0.5)
	end,

	["damage over time stacks up to the cap, the oldest dropped"] = function()
		local run = setup()
		local enemy = foe(run, 10, 0)
		local cap = run.config.statuses.maxDotStacks
		for index = 1, cap + 1 do
			Damage.applyEffect(
				run,
				enemy,
				{ kind = "dot", status = "burning", dps = index, seconds = 4 },
				1,
				{ "fire" }
			)
		end
		Assert.equal(#enemy.dots, cap)
		Assert.equal(enemy.dots[1].dps, 2)
		Assert.equal(enemy.dots[cap].dps, cap + 1)
		Assert.truthy(Damage.hasStatus(run, enemy, "burning"))
	end,

	["damage over time ticks each second, never crits, and ends"] = function()
		local run, player = setup()
		local enemy = foe(run, 10, 0)
		Damage.applyEffect(
			run,
			enemy,
			{ kind = "dot", status = "bleeding", dps = 3, seconds = 2 },
			1,
			{ "bleed" }
		)
		run.time = 0.5
		Damage.update(run, 0.5)
		Assert.equal(enemy.health, 1000)
		run.time = 1
		Damage.update(run, 0.5)
		Assert.equal(enemy.health, 997)
		run.time = 2.5
		Damage.update(run, 1.5)
		Assert.equal(enemy.health, 994)
		Assert.equal(#enemy.dots, 0)
		Assert.equal(player.damageDone, 6)
		Assert.equal(lastHit(run).crit, false)
	end,

	["a damage-over-time kill goes to the stack's source"] = function()
		local run, player = setup()
		local enemy = foe(run, 10, 0, 2)
		Damage.applyEffect(
			run,
			enemy,
			{ kind = "dot", status = "poisoned", dps = 5, seconds = 3 },
			1,
			{ "poison" }
		)
		run.time = 1
		Damage.update(run, 1)
		local kill = Assert.findEvent(run.events, "kill")
		Assert.equal(kill.source, 1)
		Assert.equal(player.kills, 1)
		Assert.equal(#run.enemies, 0)
	end,

	["shatter: fire on a chilled enemy, not on the hit that chills"] = function()
		local run = setup("mage")
		local enemy = foe(run, 10, 0)
		Damage.hit(run, enemy, hitOf({ tags = { "fire", "ice" } }))
		Assert.equal(lastHit(run).amount, 10)
		Damage.hit(run, enemy, hitOf({ tags = { "fire" } }))
		Assert.near(lastHit(run).amount, 15)
		Assert.equal(lastHit(run).synergy, "shatter")
	end,

	["conduct: lightning on a burning enemy spreads burning nearby"] = function()
		local run = setup("mage")
		local enemy = foe(run, 10, 0)
		local near = foe(run, 15, 0)
		local far = foe(run, 25, 0)
		Damage.applyEffect(
			run,
			enemy,
			{ kind = "dot", status = "burning", dps = 3, seconds = 3 },
			1,
			{ "fire" }
		)
		Damage.hit(run, enemy, hitOf({ tags = { "lightning" } }))
		Assert.equal(lastHit(run).synergy, "conduct")
		Assert.equal(lastHit(run).amount, 10)
		Assert.equal(#near.dots, 1)
		Assert.equal(near.dots[1].status, "burning")
		Assert.equal(near.dots[1].dps, 4)
		Assert.near(near.dots[1].until_, 3)
		Assert.equal(#far.dots, 0)
	end,

	["open wound: steel on a bleeding enemy"] = function()
		local run = setup("warrior")
		local enemy = foe(run, 10, 0)
		Damage.applyEffect(
			run,
			enemy,
			{ kind = "dot", status = "bleeding", dps = 3, seconds = 3 },
			1,
			{ "bleed" }
		)
		Damage.hit(run, enemy, hitOf({ tags = { "physical" } }))
		Assert.near(lastHit(run).amount, 13)
		Assert.equal(lastHit(run).synergy, "openWound")
	end,

	["crushing blow: steel on a stunned enemy"] = function()
		local run = setup("warrior")
		local enemy = foe(run, 10, 0)
		Damage.hit(
			run,
			enemy,
			hitOf({ tags = { "physical" }, effect = { kind = "stun", seconds = 1 } })
		)
		Assert.equal(lastHit(run).synergy, nil)
		Damage.hit(run, enemy, hitOf({ tags = { "physical" } }))
		Assert.near(lastHit(run).amount, 15)
		Assert.equal(lastHit(run).synergy, "crushingBlow")
	end,

	["marked prey: an arrow on a slowed enemy"] = function()
		local run = setup("archer")
		local enemy = foe(run, 10, 0)
		Damage.applyStatus(run, enemy, "slowed", 3, 0.5)
		Damage.hit(run, enemy, hitOf({ tags = { "physical" } }))
		Assert.near(lastHit(run).amount, 13)
		Assert.equal(lastHit(run).synergy, "markedPrey")
	end,

	["toxic flare: fire on a poisoned enemy"] = function()
		local run = setup("archer")
		local enemy = foe(run, 10, 0)
		Damage.applyEffect(
			run,
			enemy,
			{ kind = "dot", status = "poisoned", dps = 4, seconds = 9 },
			1,
			{ "poison" }
		)
		Damage.hit(run, enemy, hitOf({ tags = { "fire" } }))
		Assert.near(lastHit(run).amount, 16)
		Assert.equal(lastHit(run).synergy, "toxicFlare")
	end,

	["a synergy belongs to the hitting player's class"] = function()
		local run = setup("warrior")
		local enemy = foe(run, 10, 0)
		Damage.applyStatus(run, enemy, "chilled", 3, 0.5)
		Damage.hit(run, enemy, hitOf({ tags = { "fire" } }))
		Assert.equal(lastHit(run).amount, 10)
		Assert.equal(lastHit(run).synergy, nil)
	end,

	["knockback pushes an enemy away from the hit, not a boss"] = function()
		local run = setup()
		local enemy = foe(run, 10, 0)
		Damage.hit(run, enemy, hitOf({ knockback = 4 }))
		Assert.truthy(enemy.knockX > 0, "pushed away")
		Assert.near(enemy.knockUntil, run.config.player.knockbackSeconds)
		local boss = Fixtures.enemy(run, "thornback", 20, 0)
		Damage.hit(run, boss, hitOf({ knockback = 4 }))
		Assert.equal(boss.knockX, 0)
	end,

	["a kill drops a crystal and counts for the player"] = function()
		local run, player = setup()
		local enemy = foe(run, 10, 0, 5)
		Damage.hit(run, enemy, hitOf({ amount = 10 }))
		local kill = Assert.findEvent(run.events, "kill")
		Assert.equal(kill.enemyId, enemy.id)
		Assert.equal(kill.enemyKind, "wildBoar")
		Assert.equal(player.kills, 1)
		Assert.equal(#run.enemies, 0)
		Assert.equal(Fixtures.count(run.events, "crystalDropped"), 1)
		-- A dead enemy takes no further hits.
		Assert.equal(Damage.hit(run, enemy, hitOf({})), 0)
	end,

	["a boss drops food, a grunt by chance"] = function()
		local run = setup()
		local boss = Fixtures.enemy(run, "thornback", 20, 0)
		Damage.kill(run, boss, 1)
		Assert.equal(Fixtures.count(run.events, "foodDropped"), 1)
		run.config.horde.foodChance = 1
		Damage.kill(run, foe(run, 10, 0), 1)
		Assert.equal(Fixtures.count(run.events, "foodDropped"), 2)
		run.config.horde.foodChance = 0
		Damage.kill(run, foe(run, 10, 0), 1)
		Assert.equal(Fixtures.count(run.events, "foodDropped"), 2)
	end,
}
