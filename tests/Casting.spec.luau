--!strict
local Assert = require("./Assert")
local Casting = require("../src/shared/Core/Casting")
local Damage = require("../src/shared/Core/Damage")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Projectiles = require("../src/shared/Core/Projectiles")
local Types = require("../src/shared/Core/Types")

-- A test skill: the configuration's defaults with `fields` over them.
local function custom(
	id: string,
	targeting: Types.Targeting,
	fields: { [string]: any }
): Types.SkillConfig
	local skill: Types.SkillConfig = {
		id = id,
		name = id,
		targeting = targeting,
		toughest = false,
		damage = 10,
		cooldownSeconds = 2,
		range = 45,
		radius = 0,
		count = 1,
		durationSeconds = 0,
		speed = 0,
		knockback = 0,
		tags = {},
		effect = nil,
	}
	for key, value in fields do
		(skill :: any)[key] = value
	end
	return skill
end

-- A hero of `class` at (0, 0) on open ground holding only `skillId` at
-- `rank`, ready now, with no crits so damage is exact. `extra` adds test skills.
local function setup(
	class: string,
	skillId: string,
	rank: number?,
	extra: { Types.SkillConfig }?
): (Types.Run, Types.Player)
	local config = Fixtures.config()
	config.player.baseCritChance = 0
	for _, skill in extra or {} do
		config.skills[skill.id] = skill
	end
	local run = Fixtures.run(1, config, 1, class)
	Fixtures.clearObstacles(run)
	local player = run.players[1]
	player.skills = { { id = skillId, rank = rank or 1, readyAt = 0 } }
	return run, player
end

-- A wild boar (radius 1.5) with plenty of health.
local function foe(run: Types.Run, x: number, z: number, health: number?): Types.Enemy
	local enemy = Fixtures.enemy(run, "wildBoar", x, z)
	enemy.health = health or 1000
	enemy.maxHealth = enemy.health
	return enemy
end

local function lost(enemy: Types.Enemy): number
	return enemy.maxHealth - enemy.health
end

local function lastCast(run: Types.Run): any
	local found = nil
	for _, event in run.events do
		if event.kind == "cast" then
			found = event
		end
	end
	return found
end

return {
	["a bolt launches a homing projectile at the nearest and spends its cooldown"] = function()
		local run, player = setup("mage", "rimeDart")
		foe(run, 40, 0)
		local near = foe(run, 20, 0)
		Casting.update(run, 0)
		Assert.equal(#run.projectiles, 1)
		local projectile = run.projectiles[1]
		Assert.equal(projectile.targetId, near.id)
		Assert.equal(projectile.owner, "player")
		Assert.near(projectile.damage, 12)
		Assert.near(player.skills[1].readyAt, 1.3)
		local cast = lastCast(run)
		Assert.equal(cast.skill, "rimeDart")
		Assert.equal(cast.targets[1], near.id)
		Assert.near(cast.targetX, 20)
	end,

	["an instant bolt hits at once"] = function()
		local run = setup("mage", "zap", 1, { custom("zap", "bolt", { damage = 9 }) })
		local enemy = foe(run, 20, 0)
		Casting.update(run, 0)
		Assert.equal(#run.projectiles, 0)
		Assert.near(lost(enemy), 9)
	end,

	["a skill with no target retries without spending its cooldown"] = function()
		local run, player = setup("mage", "rimeDart")
		run.time = 1
		Casting.update(run, 0)
		Assert.near(player.skills[1].readyAt, 1 + run.config.ranks.retrySeconds)
		Assert.equal(Fixtures.count(run.events, "cast"), 0)
		foe(run, 70, 0)
		run.time = 1.2
		Casting.update(run, 0)
		Assert.near(player.skills[1].readyAt, 1.2 + run.config.ranks.retrySeconds)
	end,

	["a strike hits the nearest at once and splashes at the splash share"] = function()
		local run = setup("mage", "cinderSnap")
		local near = foe(run, 10, 0)
		local far = foe(run, 30, 0)
		Casting.update(run, 0)
		Assert.near(lost(near), 26)
		Assert.equal(lost(far), 0)

		local splashRun = setup("mage", "blast", 1, { custom("blast", "strike", { radius = 6 }) })
		local target = foe(splashRun, 10, 0)
		local beside = foe(splashRun, 14, 0)
		local outside = foe(splashRun, 20, 0)
		Casting.update(splashRun, 0)
		Assert.near(lost(target), 10)
		Assert.near(lost(beside), 10 * splashRun.config.ranks.splashShare)
		Assert.equal(lost(outside), 0)
	end,

	["a melee hits the count nearest within reach"] = function()
		local run = setup("warrior", "wideCut")
		local a = foe(run, 5, 0)
		local b = foe(run, 0, 8)
		local c = foe(run, -11, 0)
		local d = foe(run, 0, -12.5)
		local e = foe(run, 20, 0)
		Casting.update(run, 0)
		Assert.near(lost(a), 14)
		Assert.near(lost(b), 14)
		Assert.near(lost(c), 14)
		Assert.equal(lost(d), 0)
		Assert.equal(lost(e), 0)
		Assert.equal(#lastCast(run).targets, 3)
	end,

	["a nova hits everything within its radius and pushes it"] = function()
		local run = setup("mage", "pulseBurst")
		local inside = foe(run, 10, 0)
		local outside = foe(run, 17, 0)
		Casting.update(run, 0)
		Assert.near(lost(inside), 10)
		Assert.equal(lost(outside), 0)
		Assert.truthy(inside.knockX > 0, "pushed")
		Assert.near(lastCast(run).targetX, 0)
	end,

	["a cone hits toward the nearest and chills"] = function()
		local run = setup("mage", "frostBreath")
		local ahead = foe(run, 10, 0)
		local inside = foe(run, 15 * math.cos(math.rad(30)), 15 * math.sin(math.rad(30)))
		local outside = foe(run, 15 * math.cos(math.rad(60)), 15 * math.sin(math.rad(60)))
		local behind = foe(run, -12, 0)
		Casting.update(run, 0)
		Assert.near(lost(ahead), 14)
		Assert.near(lost(inside), 14)
		Assert.equal(lost(outside), 0)
		Assert.equal(lost(behind), 0)
		Assert.truthy(ahead.chilledUntil > 0, "chilled")
		Assert.near(ahead.slowFactor, 0.5)
	end,

	["a ground area lands on the densest cluster and ticks"] = function()
		local run = setup("mage", "sleetfall")
		local lone = foe(run, 10, 10)
		local trio = { foe(run, 30, 0), foe(run, 32, 0), foe(run, 30, 3) }
		Casting.update(run, 0)
		Assert.equal(#run.areas, 1)
		local area = run.areas[1]
		Assert.truthy(area.x >= 30, "on the cluster")
		Assert.truthy(Assert.findEvent(run.events, "areaPlaced"))
		Assert.equal(lost(trio[1]), 0)
		run.time = run.config.ranks.areaFirstTickSeconds
		Casting.update(run, 0)
		for _, enemy in trio do
			Assert.near(lost(enemy), 7)
		end
		Assert.equal(lost(lone), 0)
		run.time += run.config.ranks.areaTickSeconds
		Casting.update(run, 0)
		Assert.near(lost(trio[1]), 14)
		run.time = 6
		Casting.update(run, 0)
		Assert.equal(#run.areas, 0)
	end,

	["a burst area hits once and leaves its damage over time"] = function()
		local run = setup("archer", "blastSnare")
		local enemy = foe(run, 20, 0)
		Casting.update(run, 0)
		Assert.equal(#run.areas, 0)
		Assert.near(lost(enemy), 22)
		Assert.equal(#enemy.dots, 1)
		Assert.near(enemy.dots[1].until_, run.config.ranks.burstDotSeconds)
		Assert.truthy(Assert.findEvent(run.events, "burst"))
	end,

	["a ground area under the hero waits for an enemy close by"] = function()
		local run, player = setup("archer", "thornSnare")
		local enemy = foe(run, 30, 0)
		Casting.update(run, 0)
		Assert.equal(#run.areas, 0)
		Assert.near(player.skills[1].readyAt, run.config.ranks.retrySeconds)
		enemy.x = 20
		run.time = 0.2
		Casting.update(run, 0)
		Assert.equal(#run.areas, 1)
		Assert.near(run.areas[1].x, 0)
		Assert.near(run.areas[1].z, 0)
	end,

	["a chain jumps along its path with falling damage"] = function()
		local run = setup("mage", "arcLash")
		local path = { foe(run, 10, 0), foe(run, 20, 0), foe(run, 30, 0), foe(run, 40, 0) }
		local beyond = foe(run, 50, 0)
		Casting.update(run, 0)
		local falloff = run.config.ranks.chainFalloff
		for index, enemy in path do
			Assert.near(lost(enemy), 22 * falloff ^ (index - 1), 1e-6, "jump " .. index)
		end
		Assert.equal(lost(beyond), 0)
		local cast = lastCast(run)
		for index, enemy in path do
			Assert.equal(cast.targets[index], enemy.id)
		end
	end,

	["a scatter hits distinct enemies at random among the nearest"] = function()
		local run = setup("archer", "spray", 1, { custom("spray", "scatter", { count = 2 }) })
		for index = 1, 8 do
			foe(run, index * 3, 0)
		end
		Casting.update(run, 0)
		local struck = 0
		for _, enemy in run.enemies do
			if lost(enemy) > 0 then
				struck += 1
				Assert.truthy(enemy.x <= 18, "among the six nearest")
			end
		end
		Assert.equal(struck, 2)
	end,

	["an aura pulses on everything around the hero"] = function()
		local run, player = setup("warrior", "relentlessEdge")
		local inside = foe(run, 8, 0)
		local outside = foe(run, 20, 0)
		Casting.update(run, 0)
		Assert.near(lost(inside), 6)
		Assert.equal(lost(outside), 0)
		Assert.near(player.skills[1].readyAt, 0.6)
	end,

	["an orbit hits the count nearest around the hero"] = function()
		local run = setup(
			"mage",
			"ring",
			1,
			{ custom("ring", "orbit", { radius = 10, count = 2, cooldownSeconds = 1 }) }
		)
		local a = foe(run, 3, 0)
		local b = foe(run, 0, 6)
		local c = foe(run, 9, 0)
		local d = foe(run, 15, 0)
		Casting.update(run, 0)
		Assert.near(lost(a), 10)
		Assert.near(lost(b), 10)
		Assert.equal(lost(c), 0)
		Assert.equal(lost(d), 0)
	end,

	["a totem stands by the hero and shoots the nearest until it expires"] = function()
		local run = setup("archer", "falconPerch")
		local enemy = foe(run, 20, 0)
		Casting.update(run, 0)
		Assert.equal(#run.totems, 1)
		local totem = run.totems[1]
		Assert.near(Geometry.distance(0, 0, totem.x, totem.z), run.config.ranks.totemOffset)
		Assert.truthy(Assert.findEvent(run.events, "totemPlaced"))
		Assert.equal(lost(enemy), 0)
		run.time = run.config.ranks.totemFirstShotSeconds
		Casting.update(run, 0)
		Assert.near(lost(enemy), 10)
		run.time = 8
		Casting.update(run, 0)
		Assert.equal(#run.totems, 0)
	end,

	["a shield needs an enemy near and keeps the larger barrier"] = function()
		local run, player = setup("warrior", "bulwark")
		-- No enemy near: the shield waits.
		for index = #run.enemies, 1, -1 do
			table.remove(run.enemies, index)
		end
		Casting.update(run, 0)
		Assert.near(player.barrier, 0)
		Assert.near(player.skills[1].readyAt, run.config.ranks.retrySeconds)

		run.time = 1
		Fixtures.enemy(run, "sproutImp", player.x + 5, player.z)
		player.barrier = 5
		player.barrierUntil = 2
		Casting.update(run, 0)
		Assert.near(player.barrier, 40)
		Assert.near(player.barrierUntil, 7)
		Assert.near(player.skills[1].readyAt, 21)

		-- A larger barrier already up is kept, and its time only grows.
		player.barrier = 90
		player.barrierUntil = 30
		player.skills[1].readyAt = 0
		Casting.update(run, 0)
		Assert.near(player.barrier, 90)
		Assert.near(player.barrierUntil, 30)
	end,

	["a heal fires only below its threshold and with nothing pending"] = function()
		local run, player = setup(
			"mage",
			"mend",
			1,
			{ custom("mend", "heal", { damage = 30, durationSeconds = 3, cooldownSeconds = 10 }) }
		)
		Casting.update(run, 0)
		Assert.equal(player.healPending, 0)
		player.health = 50
		run.time = 0.2
		Casting.update(run, 0)
		Assert.near(player.healPending, 30)
		Assert.near(player.healRate, 10)
		Assert.near(player.skills[1].readyAt, 10.2)
	end,

	["thorns rise only when an enemy is close"] = function()
		local run, player = setup("warrior", "ironRiposte")
		local enemy = foe(run, 30, 0)
		Casting.update(run, 0)
		Assert.equal(player.thorns, 0)
		enemy.x = 10
		run.time = 0.2
		Casting.update(run, 0)
		Assert.near(player.thorns, 14)
		Assert.near(player.thornsUntil, 8.2)
	end,

	["rank and might raise what a skill deals"] = function()
		local run = setup("mage", "cinderSnap", 8)
		local enemy = foe(run, 10, 0)
		Casting.update(run, 0)
		Assert.near(lost(enemy), 26 * (1 + 0.3 * 7))
	end,

	["an enemy's area hurts heroes inside it"] = function()
		local run, player = setup("mage", "rimeDart")
		player.skills = {}
		table.insert(run.areas, {
			id = 99,
			owner = "enemy",
			source = 5,
			kind = "hollowShade",
			x = 3,
			z = 0,
			radius = 4,
			damage = 12,
			until_ = 2,
			nextTickAt = 0,
			tickSeconds = 0.5,
			tags = {},
			effect = nil,
			critChance = 0,
			knockback = 0,
		})
		local health = player.health
		Casting.update(run, 0)
		Assert.near(player.health, health - 12)
		local hurt = Assert.findEvent(run.events, "playerHurt")
		Assert.equal(hurt.enemyId, 5)
	end,

	["two runs with the same seed give the same events"] = function()
		local function play(seed: number): string
			local config = Fixtures.config()
			config.player.baseCritChance = 0.5
			config.skills.spray = custom("spray", "scatter", { count = 2, cooldownSeconds = 0.5 })
			local run = Fixtures.run(1, config, seed, "mage")
			Fixtures.clearObstacles(run)
			local player = run.players[1]
			player.skills = {
				{ id = "rimeDart", rank = 3, readyAt = 0 },
				{ id = "arcLash", rank = 1, readyAt = 0 },
				{ id = "spray", rank = 1, readyAt = 0 },
				{ id = "emberOrb", rank = 2, readyAt = 0 },
			}
			for index = 1, 20 do
				local angle = index * 0.7
				local enemy = Fixtures.enemy(
					run,
					"wildBoar",
					math.cos(angle) * index * 2,
					math.sin(angle) * index * 2
				)
				enemy.health = 60
				enemy.maxHealth = 60
			end
			local dt = 1 / 30
			for _ = 1, 90 do
				run.time += dt
				Casting.update(run, dt)
				Projectiles.step(run, dt)
				Damage.update(run, dt)
			end
			local out = {}
			for _, event in run.events do
				local e = event :: any
				table.insert(
					out,
					string.format(
						"%s:%s:%s:%s",
						e.kind,
						tostring(e.enemyId),
						tostring(e.amount),
						tostring(e.crit)
					)
				)
			end
			return table.concat(out, "|")
		end
		local first = play(21)
		Assert.equal(play(21), first)
		Assert.truthy(string.find(first, ":true", 1, true), "some crits")
		Assert.truthy(string.find(first, "kill:", 1, true), "some kills")
	end,
}
