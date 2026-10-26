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

-- A run with one player inside their start room, ten studs left of its
-- centre, facing +x. Rooms are at least 28 studs wide, so offsets up to 18 along
-- x and 12 along z stay inside.
local function setup(): (Types.Run, Types.Player, Types.Room)
	local run = Fixtures.run()
	local player = run.players[1]
	local room = Fixtures.roomOf(run, player)
	Fixtures.place(run, player, room.x - 10, room.z)
	player.facing = 0
	return run, player, room
end

-- An enemy `distance` studs from the player at `degrees` off the +x axis.
local function enemyAt(
	run: Types.Run,
	archetype: string,
	player: Types.Player,
	distance: number,
	degrees: number?
): Types.Enemy
	local angle = math.rad(degrees or 0)
	return Fixtures.enemy(
		run,
		archetype,
		player.x + distance * math.cos(angle),
		player.z + distance * math.sin(angle)
	)
end

local function hitCount(run: Types.Run): number
	return count(run.events, "hit")
end

return {

	["a hit provokes an idle enemy and its camp"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local room = Fixtures.roomOf(run, player)
		Fixtures.place(run, player, room.x - 12, room.z)
		player.facing = 0
		local first = Fixtures.enemy(run, "grunt", room.x + 10, room.z)
		local second = Fixtures.enemy(run, "grunt", room.x + 10, room.z + 10)
		local camp: Types.Camp = {
			id = 1,
			roomId = room.id,
			x = room.x + 10,
			z = room.z,
			level = 1,
			members = { first.id, second.id },
			alerted = false,
			scaledFor = 0,
			leaderId = nil,
		}
		table.insert(run.camps, camp)
		first.campId, second.campId = 1, 1
		Combat.damageEnemy(run, first, 1, 1, {}, "arcaneBolt", player.x, player.z)
		Assert.equal(first.state, "chase")
		Assert.equal(first.target, 1)
		Assert.equal(second.state, "chase")
		Assert.truthy(camp.alerted)
		Assert.truthy(Assert.findEvent(run.events, "campAlerted"))
	end,

	["a blocked hit still provokes the shieldbearer"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local room = Fixtures.roomOf(run, player)
		Fixtures.place(run, player, room.x - 10, room.z)
		local bearer = Fixtures.enemy(run, "shieldbearer", room.x, room.z)
		bearer.facing = math.pi
		Combat.damageEnemy(run, bearer, 1, 10, {}, "arcaneBolt", player.x, player.z)
		Assert.equal(bearer.health, bearer.maxHealth)
		Assert.equal(bearer.state, "chase")
	end,

	["a wall stops Arcane Bolt"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local room = Fixtures.roomOf(run, player)
		-- Beside the north wall, off any corridor's line, firing north.
		Fixtures.place(run, player, room.x + 3, room.z - room.halfDepth + 2)
		player.facing = -math.pi / 2
		player.firing = true
		-- Behind the wall; an enemy may not stand there, but a bolt that ignored
		-- walls would hit it.
		local behind = Fixtures.enemy(run, "grunt", room.x + 3, room.z - room.halfDepth - 4)
		Combat.fireBasic(run, player)
		Assert.equal(behind.health, behind.maxHealth)
		Assert.equal(Assert.findEvent(run.events, "hit"), nil)
	end,

	["a wall keeps Frost Nova out"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local room = Fixtures.roomOf(run, player)
		Fixtures.place(run, player, room.x + 3, room.z - room.halfDepth + 1)
		local behind = Fixtures.enemy(run, "grunt", room.x + 3, room.z - room.halfDepth - 3)
		local inside = Fixtures.enemy(run, "grunt", room.x + 3, room.z - room.halfDepth + 6)
		Assert.truthy(Combat.useActive(run, 1, 2))
		Assert.equal(behind.health, behind.maxHealth)
		Assert.truthy(inside.health < inside.maxHealth)
	end,
	-- Arcane Bolt and the basic attack

	["Arcane Bolt hits the nearest enemy on the ray and pierces one more"] = function()
		local run, player = setup()
		local third = enemyAt(run, "brute", player, 30)
		local second = enemyAt(run, "brute", player, 20)
		local first = enemyAt(run, "brute", player, 10)
		player.firing = true
		Combat.fireBasic(run, player)
		Assert.equal(first.health, 120 - 8)
		Assert.equal(second.health, 120 - 8)
		Assert.equal(third.health, 120)
		Assert.equal(hitCount(run), 2)
		local hit = Assert.findEvent(run.events, "hit")
		Assert.equal(hit.enemyId, first.id)
		Assert.equal(hit.source, 1)
		Assert.equal(hit.skill, "arcaneBolt")
		Assert.falsy(hit.blocked)
		Assert.falsy(hit.synergy)
		Assert.equal(count(run.events, "skillUsed"), 0)
	end,

	["Arcane Bolt ignores an enemy off the ray and one behind or beyond"] = function()
		local run, player = setup()
		-- width 3, brute radius 2.5: the edge is 4 studs from the ray.
		local edge = Fixtures.enemy(run, "brute", player.x + 10, player.z + 3.9)
		local off = Fixtures.enemy(run, "brute", player.x + 10, player.z + 4.2)
		local behind = Fixtures.enemy(run, "brute", player.x - 5, player.z)
		local beyond = Fixtures.enemy(run, "brute", player.x + 45, player.z)
		player.firing = true
		Combat.fireBasic(run, player)
		Assert.equal(edge.health, 112)
		Assert.equal(off.health, 120)
		Assert.equal(behind.health, 120)
		Assert.equal(beyond.health, 120)
	end,

	["Piercing lets the bolt pass through more enemies"] = function()
		local run, player = setup()
		player.perks.piercing = 2
		local enemies = {}
		for i = 1, 5 do
			table.insert(enemies, enemyAt(run, "brute", player, 5 + i * 5))
		end
		player.firing = true
		Combat.fireBasic(run, player)
		Assert.equal(hitCount(run), 4)
		Assert.equal(enemies[4].health, 112)
		Assert.equal(enemies[5].health, 120)
	end,

	["the interval sets basicReadyAt and the next shot waits for it"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "brute", player, 10)
		player.firing = true
		run.time = 2
		Combat.fireBasic(run, player)
		Assert.near(player.basicReadyAt, 2 + run.config.classes.elementalist.basic.cooldownSeconds)
		Assert.equal(enemy.health, 112)

		run.time = player.basicReadyAt - 0.01
		Combat.fireBasic(run, player)
		Assert.equal(enemy.health, 112)

		run.time = player.basicReadyAt
		Combat.fireBasic(run, player)
		Assert.equal(enemy.health, 104)
	end,

	["Rapid Fire shortens the basic interval"] = function()
		local run, player = setup()
		player.perks.rapidFire = 1
		enemyAt(run, "brute", player, 10)
		player.firing = true
		Combat.fireBasic(run, player)
		Assert.near(player.basicReadyAt, 0.35 * 0.85)
	end,

	["the basic attack does nothing when not firing, downed, drinking or not ready"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "brute", player, 10)

		Combat.fireBasic(run, player)
		Assert.equal(enemy.health, 120)

		player.firing = true
		player.state = "downed"
		Combat.fireBasic(run, player)
		Assert.equal(enemy.health, 120)

		player.state = "alive"
		player.drinkingUntil = 5
		Combat.fireBasic(run, player)
		Assert.equal(enemy.health, 120)

		player.drinkingUntil = nil
		player.basicReadyAt = 1
		Combat.fireBasic(run, player)
		Assert.equal(enemy.health, 120)
		Assert.equal(#run.events, 0)
	end,

	["the basic attack with no enemy still starts the interval"] = function()
		local run, player = setup()
		player.firing = true
		Combat.fireBasic(run, player)
		Assert.near(player.basicReadyAt, 0.35)
		Assert.equal(#run.events, 0)
	end,

	-- Aim

	["aim assist snaps to an enemy inside the cone"] = function()
		local run, player = setup()
		player.assist = true
		local enemy = enemyAt(run, "grunt", player, 15, 10)
		local expected = math.atan2(enemy.z - player.z, enemy.x - player.x)
		Assert.near(Combat.resolveAim(run, player), expected)
	end,

	["aim assist ignores enemies outside the cone or the range"] = function()
		local run, player = setup()
		player.assist = true
		enemyAt(run, "grunt", player, 15, 20)
		enemyAt(run, "grunt", player, run.config.aim.assistRange + 5, 0)
		Assert.equal(Combat.resolveAim(run, player), 0)
	end,

	["aim assist picks the nearest enemy in the cone"] = function()
		local run, player = setup()
		player.assist = true
		enemyAt(run, "grunt", player, 25, 5)
		local near = enemyAt(run, "grunt", player, 12, -8)
		local expected = math.atan2(near.z - player.z, near.x - player.x)
		Assert.near(Combat.resolveAim(run, player), expected)
	end,

	["without assist the aim is the facing"] = function()
		local run, player = setup()
		player.facing = 0.4
		enemyAt(run, "grunt", player, 15, 0)
		Assert.equal(Combat.resolveAim(run, player), 0.4)
	end,

	["the bolt fires along the assisted aim"] = function()
		local run, player = setup()
		player.assist = true
		player.firing = true
		-- 11 degrees off the facing puts it 3.8 studs from the ray, past the
		-- 3.0 the bolt reaches: it only lands by turning.
		local enemy = enemyAt(run, "grunt", player, 20, 11)
		Combat.fireBasic(run, player)
		Assert.equal(enemy.health, 22)
		player.assist = false
		player.basicReadyAt = 0
		Combat.fireBasic(run, player)
		Assert.equal(enemy.health, 22)
	end,

	-- Fireball

	["Fireball spawns one projectile along the aim and sets the cooldown"] = function()
		local run, player = setup()
		player.facing = math.pi / 2
		Assert.truthy(Combat.useActive(run, 1, 1))
		Assert.equal(#run.projectiles, 1)
		local projectile = run.projectiles[1]
		Assert.equal(projectile.owner, "player")
		Assert.equal(projectile.source, 1)
		Assert.equal(projectile.kind, "fireball")
		Assert.near(projectile.dirX, 0)
		Assert.near(projectile.dirZ, 1)
		Assert.equal(projectile.x, player.x)
		Assert.equal(projectile.z, player.z)
		Assert.equal(projectile.remaining, 45)
		Assert.equal(projectile.speed, 50)
		Assert.equal(projectile.damage, 30)
		Assert.equal(projectile.radius, 7)
		Assert.equal(projectile.knockback, 4)
		Assert.equal(projectile.tags[1], "fire")
		Assert.equal(run.nextProjectileId, 2)
		Assert.equal(player.skillReadyAt[1], 5)
		local used = Assert.findEvent(run.events, "skillUsed")
		Assert.equal(used.skill, "fireball")
		Assert.equal(used.player, 1)
		Assert.near(used.facing, math.pi / 2)
		Assert.equal(used.x, player.x)
	end,

	["Fireball flies only as far as the player aimed"] = function()
		local run = setup()
		Assert.truthy(Combat.useActive(run, 1, 1, 20))
		Assert.equal(run.projectiles[1].remaining, 20)
		local longer = Fixtures.run()
		Assert.truthy(Combat.useActive(longer, 1, 1, 100))
		Assert.equal(longer.projectiles[1].remaining, 45)
	end,

	["a skill cannot be used again before its cooldown ends"] = function()
		local run = setup()
		Assert.truthy(Combat.useActive(run, 1, 1))
		Assert.falsy(Combat.useActive(run, 1, 1))
		Assert.equal(#run.projectiles, 1)
		Assert.equal(count(run.events, "skillUsed"), 1)
		run.time = 4.99
		Assert.falsy(Combat.useActive(run, 1, 1))
		run.time = 5
		Assert.truthy(Combat.useActive(run, 1, 1))
		Assert.equal(#run.projectiles, 2)
	end,

	["useActive refuses a missing, downed or drinking player and a bad index"] = function()
		local run, player = setup()
		Assert.falsy(Combat.useActive(run, 9, 1))
		Assert.falsy(Combat.useActive(run, 1, 0))
		Assert.falsy(Combat.useActive(run, 1, 4))
		Assert.falsy(Combat.useActive(run, 1, 1.5))
		player.drinkingUntil = 3
		Assert.falsy(Combat.useActive(run, 1, 1))
		player.drinkingUntil = nil
		player.state = "downed"
		Assert.falsy(Combat.useActive(run, 1, 1))
		Assert.equal(#run.projectiles, 0)
		Assert.equal(#run.events, 0)
		Assert.equal(player.skillReadyAt[1], 0)
	end,

	["Split Shot fans three projectiles over the spread"] = function()
		local run = setup()
		run.players[1].perks.splitShot = 1
		Assert.truthy(Combat.useActive(run, 1, 1))
		Assert.equal(#run.projectiles, 3)
		local half = math.rad(run.config.perks.splitSpreadDegrees) / 2
		Assert.near(math.atan2(run.projectiles[1].dirZ, run.projectiles[1].dirX), -half)
		Assert.near(math.atan2(run.projectiles[2].dirZ, run.projectiles[2].dirX), 0)
		Assert.near(math.atan2(run.projectiles[3].dirZ, run.projectiles[3].dirX), half)
		Assert.equal(run.projectiles[1].id, 1)
		Assert.equal(run.projectiles[3].id, 3)
		Assert.equal(run.nextProjectileId, 4)
		Assert.equal(run.projectiles[2].damage, 30)
	end,

	["perks the skill does not carry change nothing on Fireball"] = function()
		local run = setup()
		run.players[1].perks.piercing = 2
		run.players[1].perks.arcing = 2
		Assert.truthy(Combat.useActive(run, 1, 1))
		Assert.equal(#run.projectiles, 1)
		Assert.equal(run.projectiles[1].radius, 7)
		Assert.equal(run.projectiles[1].remaining, 45)
		Assert.equal(run.projectiles[1].damage, 30)
	end,

	-- Frost Nova

	["Frost Nova damages, chills and knocks back every enemy in reach"] = function()
		local run, player = setup()
		local ahead = enemyAt(run, "brute", player, 8)
		local above = Fixtures.enemy(run, "brute", player.x, player.z + 10)
		local far = enemyAt(run, "brute", player, 20)
		run.time = 1
		Assert.truthy(Combat.useActive(run, 1, 2))
		Assert.equal(ahead.health, 105)
		Assert.equal(above.health, 105)
		Assert.equal(far.health, 120)
		Assert.near(ahead.chilledUntil, 1 + run.config.statuses.chillSeconds)
		Assert.equal(far.chilledUntil, 0)
		-- 10 studs over the knockback duration.
		local speed = 10 / run.config.player.knockbackSeconds
		Assert.near(ahead.knockX, speed)
		Assert.near(ahead.knockZ, 0)
		Assert.near(above.knockX, 0)
		Assert.near(above.knockZ, speed)
		Assert.near(ahead.knockUntil, 1 + run.config.player.knockbackSeconds)
		Assert.equal(far.knockUntil, 0)
		local burst = Assert.findEvent(run.events, "burst")
		Assert.equal(burst.skill, "frostNova")
		Assert.equal(burst.radius, 12)
		Assert.equal(burst.x, player.x)
		Assert.equal(player.skillReadyAt[2], 1 + 8)
	end,

	["Frost Nova reaches the edge of an enemy's body"] = function()
		local run, player = setup()
		-- radius 12 + brute radius 2.5
		local inside = enemyAt(run, "brute", player, 14.4)
		local outside = enemyAt(run, "brute", player, 14.6, 90)
		Combat.useActive(run, 1, 2)
		Assert.equal(inside.health, 105)
		Assert.equal(outside.health, 120)
	end,

	["Wide Reach grows the Frost Nova"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "brute", player, 16)
		Combat.useActive(run, 1, 2)
		Assert.equal(enemy.health, 120)

		local wide, widePlayer = setup()
		widePlayer.perks.wideReach = 1
		local reached = enemyAt(wide, "brute", widePlayer, 16)
		Combat.useActive(wide, 1, 2)
		Assert.equal(reached.health, 105)
		Assert.equal(Assert.findEvent(wide.events, "burst").radius, 15)
	end,

	-- Chain Lightning

	["Chain Lightning jumps up to its jump count between nearby enemies"] = function()
		local run, player = setup()
		local chain = {}
		for i = 0, 5 do
			table.insert(chain, enemyAt(run, "brute", player, 10 + i * 12))
		end
		Assert.truthy(Combat.useActive(run, 1, 3))
		for i = 1, 4 do
			Assert.equal(chain[i].health, 120 - 22, "enemy " .. i)
		end
		Assert.equal(chain[5].health, 120)
		Assert.equal(chain[6].health, 120)
		Assert.equal(hitCount(run), 4)
		Assert.equal(run.players[1].skillReadyAt[3], 6)
	end,

	["Chain Lightning does not jump beyond the jump range"] = function()
		local run, player = setup()
		local first = enemyAt(run, "brute", player, 10)
		local second = enemyAt(run, "brute", player, 25)
		Combat.useActive(run, 1, 3)
		Assert.equal(first.health, 98)
		Assert.equal(second.health, 120)
	end,

	["Chain Lightning never hits the same enemy twice"] = function()
		local run, player = setup()
		local only = enemyAt(run, "brute", player, 10)
		Combat.useActive(run, 1, 3)
		Assert.equal(only.health, 98)
		Assert.equal(hitCount(run), 1)
	end,

	["Arcing adds jumps"] = function()
		local run, player = setup()
		player.perks.arcing = 1
		local chain = {}
		for i = 0, 6 do
			table.insert(chain, enemyAt(run, "brute", player, 10 + i * 12))
		end
		Combat.useActive(run, 1, 3)
		Assert.equal(hitCount(run), 6)
		Assert.equal(chain[6].health, 98)
		Assert.equal(chain[7].health, 120)
	end,

	["Wide Reach does not lengthen a chain's jump"] = function()
		local run, player = setup()
		player.perks.wideReach = 3
		local first = enemyAt(run, "brute", player, 10)
		local second = enemyAt(run, "brute", player, 26)
		Combat.useActive(run, 1, 3)
		Assert.equal(first.health, 98)
		Assert.equal(second.health, 120)
	end,

	["Chain Lightning with no enemy in the cone returns false and costs no cooldown"] = function()
		local run, player = setup()
		enemyAt(run, "brute", player, 10, 30)
		enemyAt(run, "brute", player, 40, 0)
		Assert.falsy(Combat.useActive(run, 1, 3))
		Assert.equal(player.skillReadyAt[3], 0)
		Assert.equal(#run.events, 0)
		Assert.equal(hitCount(run), 0)
	end,

	["a chain hit comes from the previous target, which decides a block"] = function()
		local run, player = setup()
		local first = enemyAt(run, "grunt", player, 10)
		-- The lightning arrives from the -x side, where this shieldbearer faces.
		local shield = enemyAt(run, "shieldbearer", player, 20)
		shield.facing = math.pi
		Combat.useActive(run, 1, 3)
		Assert.equal(shield.health, 90)
		Assert.equal(first.health, 30 - 22)
		local blocked = nil
		for _, event in run.events do
			if event.kind == "hit" and event.enemyId == shield.id then
				blocked = event.blocked
			end
		end
		Assert.equal(blocked, true)

		local behind, behindPlayer = setup()
		enemyAt(behind, "grunt", behindPlayer, 10)
		local turned = enemyAt(behind, "shieldbearer", behindPlayer, 20)
		turned.facing = 0
		Combat.useActive(behind, 1, 3)
		Assert.equal(turned.health, 90 - 22)
	end,

	-- Synergies

	["fire on a chilled enemy shatters for double damage"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "brute", player, 10)
		enemy.chilledUntil = 5
		Assert.equal(Combat.damageEnemy(run, enemy, 1, 10, { "fire" }, "fireball"), false)
		Assert.equal(enemy.health, 100)
		local hit = Assert.findEvent(run.events, "hit")
		Assert.equal(hit.synergy, "shatter")
		Assert.equal(hit.amount, 20)
		Assert.near(enemy.burningUntil, run.config.statuses.burnSeconds)
	end,

	["fire on an unchilled enemy does not shatter"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "brute", player, 10)
		Combat.damageEnemy(run, enemy, 1, 10, { "fire" }, "fireball")
		Assert.equal(enemy.health, 110)
		Assert.falsy(Assert.findEvent(run.events, "hit").synergy)
	end,

	["Resonance multiplies the shatter bonus"] = function()
		local run, player = setup()
		player.perks.resonance = 1
		local enemy = enemyAt(run, "brute", player, 10)
		enemy.chilledUntil = 5
		Combat.damageEnemy(run, enemy, 1, 10, { "fire" }, "fireball")
		Assert.near(enemy.health, 120 - 10 * 2 * 1.25)
	end,

	["lightning on a burning enemy conducts the burn to a neighbour within reach"] = function()
		local run, player = setup()
		local struck = enemyAt(run, "brute", player, 10)
		local near = Fixtures.enemy(run, "brute", struck.x, struck.z + 6)
		local far = Fixtures.enemy(run, "brute", struck.x, struck.z + 12)
		struck.burningUntil = 5
		run.time = 1
		Combat.damageEnemy(run, struck, 1, 10, { "lightning" }, "chainLightning", nil, nil, 2)
		Assert.equal(Assert.findEvent(run.events, "hit").synergy, "conduct")
		Assert.near(near.burningUntil, 1 + run.config.statuses.burnSeconds * 2)
		Assert.equal(near.burnSource, 1)
		Assert.equal(far.burningUntil, 0)
		Assert.equal(struck.burningUntil, 5)
		Assert.equal(struck.brittleUntil, 0)
	end,

	["lightning on a chilled enemy makes it brittle for the next hit"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "brute", player, 10)
		enemy.chilledUntil = 10
		run.time = 1
		Combat.damageEnemy(run, enemy, 1, 10, { "lightning" }, "chainLightning")
		Assert.equal(Assert.findEvent(run.events, "hit").synergy, "brittle")
		Assert.near(enemy.brittleUntil, 1 + run.config.statuses.brittleSeconds)
		-- The hit that made it brittle is not multiplied.
		Assert.equal(enemy.health, 110)

		table.clear(run.events)
		Combat.damageEnemy(run, enemy, 1, 10, { "lightning" }, "chainLightning")
		Assert.equal(Assert.findEvent(run.events, "hit").amount, 15)
		Assert.equal(enemy.health, 95)

		run.time = enemy.brittleUntil
		table.clear(run.events)
		Combat.damageEnemy(run, enemy, 1, 10, { "lightning" }, "chainLightning")
		Assert.equal(Assert.findEvent(run.events, "hit").amount, 10)
	end,

	["lightning on a chilled and burning enemy reports brittle and still conducts"] = function()
		local run, player = setup()
		local struck = enemyAt(run, "brute", player, 10)
		local neighbour = Fixtures.enemy(run, "brute", struck.x + 4, struck.z)
		struck.chilledUntil = 10
		struck.burningUntil = 10
		Combat.damageEnemy(run, struck, 1, 10, { "lightning" }, "chainLightning")
		Assert.equal(Assert.findEvent(run.events, "hit").synergy, "brittle")
		Assert.truthy(neighbour.burningUntil > 0)
		Assert.truthy(struck.brittleUntil > 0)
	end,

	["Lingering lengthens the statuses a hit applies"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "brute", player, 10)
		Combat.damageEnemy(run, enemy, 1, 5, { "fire", "ice" }, "x", nil, nil, 1.3)
		Assert.near(enemy.burningUntil, run.config.statuses.burnSeconds * 1.3)
		Assert.near(enemy.chilledUntil, run.config.statuses.chillSeconds * 1.3)
	end,

	-- Shieldbearer

	["a hit inside the shieldbearer's frontal arc is blocked"] = function()
		local run, player = setup()
		local shield = enemyAt(run, "shieldbearer", player, 10)
		shield.facing = 0
		local died =
			Combat.damageEnemy(run, shield, 1, 10, { "fire" }, "fireball", shield.x + 5, shield.z)
		Assert.equal(died, false)
		Assert.equal(shield.health, 90)
		Assert.equal(shield.burningUntil, 0)
		local hit = Assert.findEvent(run.events, "hit")
		Assert.equal(hit.blocked, true)
		Assert.equal(hit.amount, 0)
		Assert.equal(hit.source, 1)
		Assert.equal(hit.skill, "fireball")
	end,

	["a hit from behind or the side lands, and an unlocated one is never blocked"] = function()
		local run, player = setup()
		local shield = enemyAt(run, "shieldbearer", player, 10)
		shield.facing = 0
		Combat.damageEnemy(run, shield, 1, 10, {}, "x", shield.x - 5, shield.z)
		Assert.equal(shield.health, 80)
		-- 90 degrees off the facing; the block arc is 150, so 75 each side.
		Combat.damageEnemy(run, shield, 1, 10, {}, "x", shield.x, shield.z + 5)
		Assert.equal(shield.health, 70)
		Combat.damageEnemy(run, shield, 1, 10, {}, "x", nil, nil)
		Assert.equal(shield.health, 60)
	end,

	["an enemy without a block takes a hit from the front"] = function()
		local run, player = setup()
		local grunt = enemyAt(run, "grunt", player, 10)
		grunt.facing = 0
		Combat.damageEnemy(run, grunt, 1, 10, {}, "x", grunt.x + 5, grunt.z)
		Assert.equal(grunt.health, 20)
	end,

	["Arcane Bolt from the front is blocked by a shieldbearer"] = function()
		local run, player = setup()
		local shield = enemyAt(run, "shieldbearer", player, 10)
		shield.facing = math.pi
		player.firing = true
		Combat.fireBasic(run, player)
		Assert.equal(shield.health, 90)
		Assert.equal(Assert.findEvent(run.events, "hit").blocked, true)
	end,

	-- Burning

	["burning deals damage over time and credits the kill"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "grunt", player, 10)
		enemy.burningUntil = 3
		enemy.burnSource = 1
		enemy.health = 2
		Combat.burn(run, 0.5)
		Assert.equal(enemy.health, 2 - 5 * 0.5)
		Assert.equal(count(run.events, "hit"), 0)

		enemy.health = 2
		Combat.burn(run, 1)
		Assert.equal(#run.enemies, 0)
		Assert.equal(player.kills, 1)
		local kill = Assert.findEvent(run.events, "kill")
		Assert.equal(kill.source, 1)
		Assert.equal(hitCount(run), 0)
	end,

	["Kindling multiplies burning damage"] = function()
		local run, player = setup()
		player.perks.kindling = 1
		local enemy = enemyAt(run, "brute", player, 10)
		enemy.burningUntil = 3
		enemy.burnSource = 1
		Combat.burn(run, 1)
		Assert.near(enemy.health, 120 - 5 * 1.5)
	end,

	["an expired burn does nothing and a burn is never blocked or renewed"] = function()
		local run, player = setup()
		local expired = enemyAt(run, "brute", player, 10)
		expired.burningUntil = 1
		run.time = 1
		Combat.burn(run, 1)
		Assert.equal(expired.health, 120)

		local shield = enemyAt(run, "shieldbearer", player, 20)
		shield.facing = 0
		shield.burningUntil = 4
		Combat.burn(run, 1)
		Assert.equal(shield.health, 85)
		Assert.equal(shield.burningUntil, 4)
	end,

	["burning damage on a brittle enemy is multiplied"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "brute", player, 10)
		enemy.burningUntil = 3
		enemy.brittleUntil = 3
		Combat.burn(run, 1)
		Assert.near(enemy.health, 120 - 5 * 1.5)
	end,

	["burning kills every enemy that runs out of health in one tick"] = function()
		local run, player = setup()
		for i = 1, 3 do
			local enemy = enemyAt(run, "grunt", player, 10 + i)
			enemy.burningUntil = 3
			enemy.burnSource = 1
			enemy.health = 1
		end
		Combat.burn(run, 1)
		Assert.equal(#run.enemies, 0)
		Assert.equal(player.kills, 3)
	end,

	-- Kills

	["a kill removes the enemy, leaves its camp and credits kills and xp"] = function()
		local run, player, room = setup()
		local enemy = enemyAt(run, "grunt", player, 10)
		local other = enemyAt(run, "grunt", player, 12)
		table.insert(run.camps, {
			id = 1,
			roomId = room.id,
			x = room.x,
			z = room.z,
			level = 1,
			members = { enemy.id, other.id },
			alerted = false,
			scaledFor = 1,
			leaderId = nil,
		})
		enemy.campId = 1
		other.campId = 1
		Assert.equal(Combat.damageEnemy(run, enemy, 1, 100, {}, "x"), true)
		Assert.equal(#run.enemies, 1)
		Assert.equal(run.enemies[1], other)
		Assert.equal(#run.camps[1].members, 1)
		Assert.equal(run.camps[1].members[1], other.id)
		Assert.equal(player.kills, 1)
		Assert.equal(player.xp, run.config.enemies.archetypes.grunt.xp)
		local kill = Assert.findEvent(run.events, "kill")
		Assert.equal(kill.enemyId, enemy.id)
		Assert.equal(kill.source, 1)
		Assert.equal(kill.archetype, "grunt")
		Assert.equal(count(run.events, "hit"), 1)
	end,

	["Scholar multiplies the experience of a kill"] = function()
		local run, player = setup()
		player.perks.scholar = 1
		local enemy = enemyAt(run, "grunt", player, 10)
		Combat.damageEnemy(run, enemy, 1, 100, {}, "x")
		Assert.near(player.xp, 1.25)
	end,

	["a kill that fills the xp bar levels the player up"] = function()
		local run, player = setup()
		player.xp = 4.5
		local enemy = enemyAt(run, "grunt", player, 10)
		Combat.damageEnemy(run, enemy, 1, 100, {}, "x")
		Assert.equal(player.level, 2)
		Assert.truthy(Assert.findEvent(run.events, "levelUp"))
	end,

	["an unowned source kills without credit"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "grunt", player, 10)
		Combat.damageEnemy(run, enemy, nil, 100, {}, "x")
		Assert.equal(#run.enemies, 0)
		Assert.equal(player.kills, 0)
		Assert.equal(player.xp, 0)
		Assert.equal(Assert.findEvent(run.events, "kill").source, 0)
		Assert.equal(Assert.findEvent(run.events, "hit").source, 0)
	end,

	["a camp leader drops a potion and others do not"] = function()
		local run, player = setup()
		local grunt = enemyAt(run, "grunt", player, 8)
		Combat.damageEnemy(run, grunt, 1, 100, {}, "x")
		Assert.equal(#run.pickups, 0)
		Assert.falsy(Assert.findEvent(run.events, "dropped"))

		local leader = enemyAt(run, "campLeader", player, 12)
		leader.health = 1
		Combat.damageEnemy(run, leader, 1, 5, {}, "x")
		Assert.equal(#run.pickups, 1)
		Assert.equal(run.pickups[1].kind, "potion")
		Assert.equal(run.pickups[1].x, leader.x)
		Assert.equal(run.pickups[1].z, leader.z)
		local dropped = Assert.findEvent(run.events, "dropped")
		Assert.equal(dropped.pickup, "potion")
		Assert.equal(dropped.x, leader.x)
	end,

	-- Knockback

	["knockEnemy pushes away from the point over the knockback time"] = function()
		local run, player = setup()
		local enemy = enemyAt(run, "brute", player, 10)
		run.time = 2
		Combat.knockEnemy(run, enemy, player.x, player.z, 6)
		Assert.near(enemy.knockX, 6 / run.config.player.knockbackSeconds)
		Assert.near(enemy.knockZ, 0)
		Assert.near(enemy.knockUntil, 2 + run.config.player.knockbackSeconds)
		local still = enemyAt(run, "brute", player, 10, 90)
		Combat.knockEnemy(run, still, player.x, player.z, 0)
		Assert.equal(still.knockUntil, 0)
	end,

	["a line shot knocks back by the skill's knockback"] = function()
		local run, player = setup()
		run.config.classes.elementalist.basic.knockback = 3
		local enemy = enemyAt(run, "brute", player, 10)
		player.firing = true
		Combat.fireBasic(run, player)
		Assert.near(enemy.knockX, 3 / run.config.player.knockbackSeconds)
	end,

	-- Burst

	["a radius-zero burst damages only the struck enemy"] = function()
		local run, player = setup()
		local struck = enemyAt(run, "brute", player, 10)
		local beside = Fixtures.enemy(run, "brute", struck.x, struck.z + 1)
		local projectile: Types.Projectile = {
			id = 1,
			owner = "player",
			source = 1,
			kind = "fireball",
			x = struck.x,
			z = struck.z,
			dirX = 1,
			dirZ = 0,
			speed = 10,
			remaining = 0,
			damage = 10,
			radius = 0,
			knockback = 0,
			tags = {},
			statusFactor = 1,
		}
		Combat.burst(run, projectile, struck.x, struck.z, struck)
		Assert.equal(struck.health, 110)
		Assert.equal(beside.health, 120)
		Assert.truthy(Assert.findEvent(run.events, "burst"))
	end,
}
