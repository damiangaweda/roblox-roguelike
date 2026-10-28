--!strict
local Assert = require("./Assert")
local Enemies = require("../src/shared/Core/Enemies")
local Fixtures = require("./Fixtures")
local Geometry = require("../src/shared/Core/Geometry")
local Arena = require("../src/shared/Core/Arena")
local Horde = require("../src/shared/Core/Horde")
local State = require("../src/shared/Core/State")
local Types = require("../src/shared/Core/Types")

local DT = 0.1

-- Advances the clock by `dt`, then the enemies.
local function tick(run: Types.Run, dt: number?)
	local step = dt or DT
	run.time += step
	Enemies.step(run, step)
end

-- A run on open ground with `playerCount` heroes, hero 1 at the centre.
local function open(playerCount: number?): (Types.Run, Types.Player)
	local run = Fixtures.run(playerCount)
	Fixtures.clearObstacles(run)
	return run, run.players[1]
end

local function maxHealth(run: Types.Run, player: Types.Player): number
	return run.config.classes[player.class].maxHealth
end

-- An enemy ready to attack at once.
local function fighter(run: Types.Run, kind: string, x: number, z: number): Types.Enemy
	local enemy = Fixtures.enemy(run, kind, x, z)
	enemy.attackReadyAt = 0
	return enemy
end

local function rock(run: Types.Run, x: number, z: number, radius: number)
	table.insert(run.arena.obstacles, {
		id = #run.arena.obstacles + 1,
		kind = "rock",
		x = x,
		z = z,
		radius = radius,
		rotation = 0,
	})
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

-- Starts a telegraph for an enemy that already has its target in range,
-- checks that the attack lands exactly when its time comes, and returns the
-- time it landed.
local function windUp(run: Types.Run, enemy: Types.Enemy, landed: () -> boolean): number
	local attack = State.kind(run, enemy).attacks[enemy.attack]
	local start = run.time
	Enemies.step(run, 0)
	Assert.equal(enemy.state, "telegraph")
	Assert.near(enemy.stateUntil, start + attack.telegraphSeconds)
	local event = Assert.findEvent(run.events, "telegraph")
	Assert.truthy(event, "no telegraph event")
	Assert.equal(event.enemyId, enemy.id)
	Assert.equal(event.attackKind, attack.kind)
	Assert.near(event.seconds, attack.telegraphSeconds)
	Assert.falsy(landed(), "landed during the wind-up")

	run.time = enemy.stateUntil - 0.01
	Enemies.step(run, 0)
	Assert.equal(enemy.state, "telegraph")
	Assert.falsy(landed(), "landed early")

	run.time = enemy.stateUntil
	Enemies.step(run, 0)
	Assert.truthy(landed(), "did not land on time")
	local attacked = Assert.findEvent(run.events, "enemyAttack")
	Assert.truthy(attacked, "no enemyAttack event")
	Assert.equal(attacked.attackKind, attack.kind)
	return run.time
end

local function attacked(run: Types.Run): () -> boolean
	return function()
		return Assert.findEvent(run.events, "enemyAttack") ~= nil
	end
end

-- Checks the recovery after an attack that landed at `landedAt`.
local function expectRecovery(run: Types.Run, enemy: Types.Enemy, landedAt: number)
	local attack = State.kind(run, enemy).attacks[1]
	Assert.near(enemy.attackReadyAt, landedAt + attack.cooldownSeconds)
	if attack.recoverSeconds > 0 then
		Assert.equal(enemy.state, "recover")
		Assert.near(enemy.stateUntil, landedAt + attack.recoverSeconds)
	end
end

return {
	["a grunt walks straight at the hero and stops at contact"] = function()
		local run, player = open()
		local grunt = Fixtures.enemy(run, "sproutImp", 20, 0)
		local speed = run.config.enemies.sproutImp.speed
		tick(run)
		Assert.near(grunt.x, 20 - speed * DT)
		Assert.near(grunt.z, 0)
		Assert.near(grunt.facing, math.pi)
		for _ = 1, 40 do
			tick(run)
		end
		local touching = run.config.player.radius + run.config.enemies.sproutImp.radius
		local distance = Geometry.distance(grunt.x, grunt.z, player.x, player.z)
		Assert.truthy(distance >= touching - 1e-6, "walked into the hero: " .. distance)
		Assert.truthy(distance <= touching + 0.35, "stopped short: " .. distance)
	end,

	["a grunt hits on contact after the first delay, then on its interval"] = function()
		local run, player = open()
		local horde = run.config.horde
		local grunt = Fixtures.enemy(run, "greyWolf", 3, 0)
		local damage = run.config.enemies.greyWolf.damage
		local hits: { number } = {}
		for _ = 1, 40 do
			local before = #events(run, "playerHurt")
			tick(run)
			if #events(run, "playerHurt") > before then
				table.insert(hits, run.time)
			end
		end
		Assert.truthy(#hits >= 3, "hits: " .. #hits)
		Assert.truthy(hits[1] >= horde.contactFirstSeconds - 1e-6, "too early: " .. hits[1])
		Assert.truthy(hits[1] <= horde.contactFirstSeconds + DT + 1e-6, "too late: " .. hits[1])
		for index = 2, #hits do
			local gap = hits[index] - hits[index - 1]
			Assert.truthy(
				gap >= horde.contactSeconds - 1e-6 and gap <= horde.contactSeconds + DT + 1e-6,
				"interval: " .. gap
			)
		end
		Assert.near(player.health, maxHealth(run, player) - damage * #hits)
		Assert.equal(Assert.findEvent(run.events, "playerHurt").enemyId, grunt.id)
	end,

	["a grunt walks round an obstacle and still reaches the hero"] = function()
		local run, player = open()
		rock(run, 12, 0.3, 4)
		local grunt = Fixtures.enemy(run, "sproutImp", 24, 0)
		local kind = run.config.enemies.sproutImp
		local reached = false
		for _ = 1, 50 do
			tick(run)
			Assert.falsy(
				Arena.blocking(run.arena, grunt.x, grunt.z, kind.radius),
				"inside the rock"
			)
			if
				Geometry.distance(grunt.x, grunt.z, player.x, player.z)
				<= run.config.player.radius + kind.radius + 0.35
			then
				reached = true
				break
			end
		end
		Assert.truthy(reached, string.format("stuck at %.2f, %.2f", grunt.x, grunt.z))
	end,

	["overlapping enemies are pushed apart"] = function()
		local run = open()
		local a = Fixtures.enemy(run, "sproutImp", 50, 0)
		local b = Fixtures.enemy(run, "sproutImp", 50, 0)
		a.rootedUntil, b.rootedUntil = 100, 100
		tick(run)
		local distance = Geometry.distance(a.x, a.z, b.x, b.z)
		Assert.truthy(distance > 0, "not pushed")
		Assert.truthy(distance <= run.config.horde.separationRadius + 1e-6)
	end,

	["an enemy pushed into an obstacle is put back outside it"] = function()
		local run = open()
		rock(run, 50, 0, 4)
		local kind = run.config.enemies.sproutImp
		local grunt = Fixtures.enemy(run, "sproutImp", 50.5, 0.2)
		grunt.rootedUntil = 100
		tick(run)
		Assert.falsy(Arena.blocking(run.arena, grunt.x, grunt.z, kind.radius))
		Assert.truthy(grunt.x > 50, "left on the far side")
	end,

	["knockback carries an enemy and suspends it"] = function()
		local run = open()
		local grunt = Fixtures.enemy(run, "sproutImp", 10, 0)
		grunt.knockX, grunt.knockZ = 20, 0
		grunt.knockUntil = run.time + 0.25
		tick(run)
		Assert.near(grunt.x, 12)
		tick(run)
		Assert.near(grunt.x, 14)
		-- The last step covers what is left of the push; then it walks at the hero.
		tick(run)
		Assert.near(grunt.x, 15)
		tick(run)
		Assert.truthy(grunt.x < 15)
	end,

	["a knocked enemy's telegraph still lands"] = function()
		local run = open()
		local brute = fighter(run, "brute", 4, 0)
		Enemies.step(run, 0)
		Assert.equal(brute.state, "telegraph")
		brute.knockX, brute.knockZ = 1, 0
		brute.knockUntil = run.time + 10
		run.time = brute.stateUntil
		Enemies.step(run, 0)
		Assert.truthy(Assert.findEvent(run.events, "enemyAttack"))
		Assert.equal(brute.state, "recover")
	end,

	["a brute hits in its arc, not behind, and knocks back"] = function()
		local run, front = open(2)
		local behind = run.players[2]
		Fixtures.place(run, 1, 4, 0)
		Fixtures.place(run, 2, -6, 0)
		local brute = fighter(run, "brute", 0, 0)
		local landedAt = windUp(run, brute, attacked(run))
		expectRecovery(run, brute, landedAt)
		Assert.near(brute.facing, 0)
		Assert.equal(front.health, maxHealth(run, front) - 25)
		Assert.equal(behind.health, maxHealth(run, behind))
		local knocked = Assert.findEvent(run.events, "knockback")
		Assert.equal(knocked.player, front.id)
		Assert.near(knocked.dx, 12)
		Assert.near(knocked.dz, 0)
		local event = Assert.findEvent(run.events, "telegraph")
		Assert.near(event.x, 0)
		Assert.equal(event.radius, 7)
	end,

	["a recovering enemy goes back to chasing"] = function()
		local run = open()
		Fixtures.place(run, 1, 4, 0)
		local brute = fighter(run, "brute", 0, 0)
		windUp(run, brute, attacked(run))
		run.time = brute.stateUntil - 0.01
		Enemies.step(run, 0)
		Assert.equal(brute.state, "recover")
		run.time = brute.stateUntil
		Enemies.step(run, 0)
		Assert.equal(brute.state, "chase")
	end,

	["a shieldbearer swings with its own telegraph"] = function()
		local run, player = open()
		Fixtures.place(run, 1, 3, 0)
		local shield = fighter(run, "shieldbearer", 0, 0)
		local landedAt = windUp(run, shield, attacked(run))
		expectRecovery(run, shield, landedAt)
		Assert.equal(player.health, maxHealth(run, player) - 12)
	end,

	["a spitter backs away when the hero is too close"] = function()
		local run = open()
		Fixtures.place(run, 1, 10, 0)
		local spitter = Fixtures.enemy(run, "spitter", 0, 0)
		spitter.attackReadyAt = 1e9
		tick(run)
		Assert.near(spitter.x, -run.config.enemies.spitter.speed * DT)
		Assert.near(spitter.facing, 0)
		Assert.equal(spitter.state, "chase")
	end,

	["a spitter fires at the locked aim from range"] = function()
		local run, player = open()
		Fixtures.place(run, 1, 20, 0)
		local spitter = fighter(run, "spitter", 0, 0)
		Enemies.step(run, 0)
		local event = Assert.findEvent(run.events, "telegraph")
		Assert.near(event.x, 20)
		Assert.near(event.radius, 1)
		-- The hero moves; the shot still goes where they were.
		Fixtures.place(run, 1, 0, 20)
		run.time = spitter.stateUntil
		Enemies.step(run, 0)
		Assert.equal(#run.projectiles, 1)
		local shot = run.projectiles[1]
		Assert.equal(shot.owner, "enemy")
		Assert.equal(shot.source, spitter.id)
		Assert.equal(shot.kind, "spitter")
		Assert.near(shot.dirX, 1)
		Assert.near(shot.dirZ, 0)
		Assert.equal(shot.speed, 32)
		Assert.equal(shot.damage, 12)
		Assert.near(shot.remaining, 30 * run.config.projectiles.overshoot)
		expectRecovery(run, spitter, run.time)
		-- Hurts nobody on its own: Projectiles moves and lands it.
		Assert.equal(player.health, maxHealth(run, player))
	end,

	["an exploder bursts and is gone"] = function()
		local run, player = open(2)
		local bystander = run.players[2]
		Fixtures.place(run, 1, 3, 0)
		Fixtures.place(run, 2, -10, 0)
		local exploder = fighter(run, "exploder", 0, 0)
		windUp(run, exploder, function()
			return Assert.findEvent(run.events, "exploded") ~= nil
		end)
		Assert.equal(State.enemyById(run, exploder.id), nil)
		Assert.equal(player.health, maxHealth(run, player) - 35)
		Assert.equal(bystander.health, maxHealth(run, bystander))
		Assert.falsy(Assert.findEvent(run.events, "kill"))
		Assert.equal(Assert.findEvent(run.events, "exploded").radius, 7)
	end,

	["a shaman heals and buffs a hurt neighbour in its radius only"] = function()
		local run = open()
		Fixtures.place(run, 1, 30, 0)
		local shaman = fighter(run, "shaman", 0, 0)
		local near = Fixtures.enemy(run, "mossTroll", 0, 6)
		local far = Fixtures.enemy(run, "mossTroll", 0, -25)
		near.health = near.maxHealth - 20
		far.health = far.maxHealth - 20
		local landedAt = windUp(run, shaman, function()
			return Assert.findEvent(run.events, "enemyHealed") ~= nil
		end)
		expectRecovery(run, shaman, landedAt)
		Assert.equal(near.health, near.maxHealth)
		Assert.near(near.buffedUntil, landedAt + 4)
		Assert.equal(far.health, far.maxHealth - 20)
		Assert.equal(far.buffedUntil, 0)
		for _, event in events(run, "enemyHealed") do
			Assert.equal(event.by, shaman.id)
		end
	end,

	["a shaman with nothing to heal does not wind up"] = function()
		local run = open()
		Fixtures.place(run, 1, 30, 0)
		fighter(run, "shaman", 0, 0)
		Fixtures.enemy(run, "mossTroll", 0, 6)
		tick(run, 0)
		Assert.falsy(Assert.findEvent(run.events, "telegraph"))
	end,

	["a buffed grunt hits harder and walks faster"] = function()
		local run, player = open()
		local horde = run.config.horde
		local walker = Fixtures.enemy(run, "sproutImp", -20, 0)
		walker.buffedUntil = 100
		local grunt = Fixtures.enemy(run, "greyWolf", 3, 0)
		grunt.buffedUntil = 100
		run.time = 0.5
		Enemies.step(run, DT)
		Assert.near(walker.x, -20 + run.config.enemies.sproutImp.speed * horde.buffSpeedFactor * DT)
		Assert.near(
			player.health,
			maxHealth(run, player) - run.config.enemies.greyWolf.damage * horde.buffDamageFactor
		)
	end,

	["a charge hits a hero on its line once and ends past the aim"] = function()
		local run, player = open()
		Fixtures.place(run, 1, 30, 0)
		local boss = fighter(run, "thornback", 0, 0)
		local attack = run.config.enemies.thornback.attacks[1]
		Enemies.step(run, 0)
		local event = Assert.findEvent(run.events, "telegraph")
		Assert.equal(event.attackKind, "charge")
		Assert.near(event.endX :: number, 30 + attack.chargeOvershoot :: number)
		Assert.near(event.endZ :: number, 0)
		run.time = boss.stateUntil
		Enemies.step(run, 0)
		Assert.equal(boss.state, "charge")
		for _ = 1, 20 do
			tick(run)
			if boss.state ~= "charge" then
				break
			end
		end
		Assert.equal(boss.state, "recover")
		Assert.near(boss.x, 30 + attack.chargeOvershoot :: number, 1e-6)
		Assert.equal(#events(run, "playerHurt"), 1)
		Assert.equal(player.health, maxHealth(run, player) - attack.damage)
		Assert.truthy(Assert.findEvent(run.events, "knockback"))
		Assert.equal(boss.attack, 2)
	end,

	["a charge stops against an obstacle"] = function()
		local run, player = open()
		Fixtures.place(run, 1, 30, 0)
		rock(run, 18, 0, 3)
		local boss = fighter(run, "thornback", 0, 0)
		Enemies.step(run, 0)
		run.time = boss.stateUntil
		Enemies.step(run, 0)
		for _ = 1, 20 do
			tick(run)
			if boss.state ~= "charge" then
				break
			end
		end
		Assert.equal(boss.state, "recover")
		Assert.truthy(boss.x < 18 - 3, "through the rock: " .. boss.x)
		Assert.equal(player.health, maxHealth(run, player))
	end,

	["a leap lands on the aim with a burst there"] = function()
		local run, player = open()
		Fixtures.place(run, 1, 25, 0)
		local boss = fighter(run, "mossmaw", 0, 0)
		boss.attack = 2
		local attack = run.config.enemies.mossmaw.attacks[2]
		windUp(run, boss, attacked(run))
		Assert.near(boss.x, 25, 1e-6)
		Assert.near(boss.z, 0, 1e-6)
		Assert.equal(player.health, maxHealth(run, player) - attack.damage)
		local event = Assert.findEvent(run.events, "telegraph")
		Assert.near(event.x, 25)
	end,

	["a projectile attack fans its shots over the spread"] = function()
		local run = open()
		Fixtures.place(run, 1, 30, 0)
		local boss = fighter(run, "mossmaw", 0, 0)
		local attack = run.config.enemies.mossmaw.attacks[1]
		windUp(run, boss, attacked(run))
		Assert.equal(#run.projectiles, attack.projectileCount)
		local half = math.rad(attack.spreadDegrees :: number) / 2
		Assert.near(run.projectiles[1].dirZ, -math.sin(half), 1e-6)
		Assert.near(run.projectiles[3].dirX, 1, 1e-6)
		Assert.near(run.projectiles[5].dirZ, math.sin(half), 1e-6)

		-- A full circle spaces its shots evenly.
		local ring = open()
		Fixtures.place(ring, 1, 5, 0)
		local warden = fighter(ring, "ironbarkWarden", 0, 0)
		warden.attack = 2
		windUp(ring, warden, attacked(ring))
		local count = ring.config.enemies.ironbarkWarden.attacks[2].projectileCount :: number
		Assert.equal(#ring.projectiles, count)
		local sumX, sumZ = 0, 0
		for _, shot in ring.projectiles do
			sumX += shot.dirX
			sumZ += shot.dirZ
		end
		Assert.near(sumX, 0, 1e-6)
		Assert.near(sumZ, 0, 1e-6)
	end,

	["a summon spawns its count around the boss"] = function()
		local run = open()
		Fixtures.place(run, 1, 50, 0)
		local boss = fighter(run, "hollowShade", 0, 0)
		boss.attack = 2
		local attack = run.config.enemies.hollowShade.attacks[2]
		windUp(run, boss, attacked(run))
		Assert.equal(#run.enemies, 1 + attack.summonCount :: number)
		local kindId = Horde.windowKinds(run)[1]
		for _, enemy in run.enemies do
			if enemy ~= boss then
				Assert.equal(enemy.kind, kindId)
				Assert.near(Geometry.distance(enemy.x, enemy.z, 0, 0), attack.radius, 1e-6)
			end
		end
	end,

	["a summon at the cap gives way to the next attack"] = function()
		local run = open()
		run.config.horde.maxAlive = 0
		Fixtures.place(run, 1, 20, 0)
		local boss = fighter(run, "hollowShade", 0, 0)
		boss.attack = 2
		Enemies.step(run, 0)
		Assert.equal(boss.attack, 1)
		Assert.falsy(Assert.findEvent(run.events, "telegraph"))
	end,

	["a summon fills the horde only up to its cap"] = function()
		local run = open()
		Fixtures.place(run, 1, 50, 0)
		local boss = fighter(run, "hollowShade", 0, 0)
		run.config.horde.maxAlive = 3
		boss.attack = 2
		windUp(run, boss, attacked(run))
		Assert.equal(#run.enemies, 1 + 3)
	end,

	["a ground attack leaves an area at the aim for its lifetime"] = function()
		local run = open()
		Fixtures.place(run, 1, 20, 0)
		local boss = fighter(run, "hollowShade", 0, 0)
		local attack = run.config.enemies.hollowShade.attacks[1]
		local landedAt = windUp(run, boss, attacked(run))
		Assert.equal(#run.areas, 1)
		local area = run.areas[1]
		Assert.equal(area.owner, "enemy")
		Assert.equal(area.kind, "hollowShade")
		Assert.equal(area.source, boss.id)
		Assert.near(area.x, 20)
		Assert.near(area.z, 0)
		Assert.equal(area.radius, attack.radius)
		Assert.equal(area.damage, attack.damage)
		Assert.near(area.until_, landedAt + attack.groundSeconds :: number)
		Assert.near(area.tickSeconds, attack.groundTickSeconds :: number)
		Assert.near(area.nextTickAt, landedAt + attack.groundTickSeconds :: number)
		local placed = Assert.findEvent(run.events, "areaPlaced")
		Assert.equal(placed.id, area.id)
		Assert.equal(placed.areaKind, "hollowShade")
		Assert.equal(placed.seconds, attack.groundSeconds)
	end,

	["the final boss enters its second phase at half health"] = function()
		local run, hero = open()
		local kind = run.config.enemies.forestHeart
		-- Survives the burst, so the boss keeps a target.
		hero.health = 1e6
		Fixtures.place(run, 1, 5, 0)
		local heart = fighter(run, "forestHeart", 0, 0)
		Enemies.step(run, 0)
		Assert.equal(heart.phase, 1)
		heart.state = "chase"
		heart.attackReadyAt = 0
		heart.health = heart.maxHealth * (kind.phaseHealthShare :: number)
		local landedAt = windUp(run, heart, attacked(run))
		Assert.equal(heart.phase, 2)
		local phase = Assert.findEvent(run.events, "bossPhase")
		Assert.equal(phase.enemyId, heart.id)
		Assert.equal(#events(run, "bossPhase"), 1)
		Assert.near(
			heart.attackReadyAt,
			landedAt + kind.attacks[1].cooldownSeconds * (kind.phaseCooldownFactor :: number)
		)
	end,

	["a stunned enemy neither attacks nor hits on contact"] = function()
		local run, player = open()
		Fixtures.place(run, 1, 4, 0)
		local brute = fighter(run, "brute", 0, 0)
		brute.stunnedUntil = 100
		local grunt = Fixtures.enemy(run, "greyWolf", -3, 0)
		grunt.stunnedUntil = 100
		grunt.contactReadyAt = 0
		tick(run)
		Assert.equal(brute.state, "chase")
		Assert.falsy(Assert.findEvent(run.events, "telegraph"))
		Assert.equal(player.health, maxHealth(run, player))
		-- A stun cuts a telegraph short.
		brute.stunnedUntil = 0
		Enemies.step(run, 0)
		Assert.equal(brute.state, "telegraph")
		brute.stunnedUntil = 100
		run.time = brute.stateUntil
		Enemies.step(run, 0)
		Assert.equal(brute.state, "chase")
		Assert.falsy(Assert.findEvent(run.events, "enemyAttack"))
	end,

	["a rooted enemy stays put but still hits"] = function()
		local run, player = open()
		local walker = Fixtures.enemy(run, "sproutImp", 20, 0)
		walker.rootedUntil = 100
		local grunt = Fixtures.enemy(run, "greyWolf", -3, 0)
		grunt.rootedUntil = 100
		grunt.contactReadyAt = 0
		tick(run)
		Assert.near(walker.x, 20)
		Assert.near(player.health, maxHealth(run, player) - run.config.enemies.greyWolf.damage)
	end,

	["a feared enemy walks away and does not hit"] = function()
		local run, player = open()
		local grunt = Fixtures.enemy(run, "greyWolf", 3, 0)
		grunt.fearedUntil = 100
		grunt.contactReadyAt = 0
		tick(run)
		Assert.near(grunt.x, 3 + run.config.enemies.greyWolf.speed * DT)
		Assert.equal(player.health, maxHealth(run, player))
	end,

	["a weakened enemy deals half damage"] = function()
		local run, player = open()
		local grunt = Fixtures.enemy(run, "greyWolf", 3, 0)
		grunt.weakenFactor = 0.5
		grunt.contactReadyAt = 0
		tick(run)
		Assert.near(
			player.health,
			maxHealth(run, player) - run.config.enemies.greyWolf.damage * 0.5
		)

		local other, hero = open()
		Fixtures.place(other, 1, 4, 0)
		local brute = fighter(other, "brute", 0, 0)
		brute.weakenFactor = 0.5
		windUp(other, brute, attacked(other))
		Assert.near(hero.health, maxHealth(other, hero) - 12.5)
	end,

	["the horde's damage growth scales contact hits"] = function()
		local run, player = open()
		local grunt = State.newEnemy(run, "greyWolf", 3, 0, 1, 1.5)
		grunt.contactReadyAt = 0
		tick(run)
		Assert.near(
			player.health,
			maxHealth(run, player) - run.config.enemies.greyWolf.damage * 1.5
		)
	end,

	["thorns return a contact hit's damage to the grunt"] = function()
		local run, player = open()
		player.thorns = 5
		player.thornsUntil = 100
		local grunt = Fixtures.enemy(run, "mossTroll", 3.5, 0)
		grunt.contactReadyAt = 0
		tick(run)
		local hit = Assert.findEvent(run.events, "hit")
		Assert.truthy(hit, "no hit back")
		Assert.equal(hit.skill, "thorns")
		Assert.equal(hit.enemyId, grunt.id)
		Assert.truthy(grunt.health < grunt.maxHealth)
	end,

	["the same seed moves the same horde"] = function()
		local function play(): { number }
			local run = Fixtures.run(1, nil, 11)
			for index = 1, 30 do
				local angle = index * 0.7
				Fixtures.enemy(run, "sproutImp", math.cos(angle) * 30, math.sin(angle) * 30)
			end
			for _ = 1, 30 do
				tick(run)
			end
			local positions = {}
			for _, enemy in run.enemies do
				table.insert(positions, enemy.x)
				table.insert(positions, enemy.z)
			end
			return positions
		end
		local a, b = play(), play()
		Assert.equal(#a, #b)
		for index, value in a do
			Assert.equal(value, b[index])
		end
	end,
}
