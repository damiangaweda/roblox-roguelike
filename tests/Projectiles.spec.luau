--!strict
local Assert = require("./Assert")
local Combat = require("../src/shared/Core/Combat")
local Fixtures = require("./Fixtures")
local Projectiles = require("../src/shared/Core/Projectiles")
local Types = require("../src/shared/Core/Types")

-- A run with one player inside their start room, ten studs left of its
-- centre, facing +x. Rooms are at least 28 studs wide, so offsets up to 18 along
-- x and 12 along z stay inside.
local function setup(playerCount: number?): (Types.Run, Types.Player, Types.Room)
	local run = Fixtures.run(playerCount)
	local player = run.players[1]
	local room = Fixtures.roomOf(run, player)
	Fixtures.place(run, player, room.x - 10, room.z)
	player.facing = 0
	return run, player, room
end

-- A projectile in the run, flying along +x unless `dirZ` says otherwise.
local function launch(
	run: Types.Run,
	owner: "player" | "enemy",
	fields: { [string]: any }
): Types.Projectile
	local projectile: Types.Projectile = {
		id = run.nextProjectileId,
		owner = owner,
		source = 1,
		kind = "fireball",
		x = 0,
		z = 0,
		dirX = 1,
		dirZ = 0,
		speed = 50,
		remaining = 45,
		damage = 10,
		radius = 0,
		knockback = 0,
		tags = {},
		statusFactor = 1,
	}
	for key, value in fields do
		(projectile :: any)[key] = value
	end
	run.nextProjectileId += 1
	table.insert(run.projectiles, projectile)
	return projectile
end

return {
	-- Player projectiles

	["a fireball lands on the first enemy in its path and burns everything in the radius"] = function()
		local run, player = setup()
		local struck = Fixtures.enemy(run, "brute", player.x + 16, player.z)
		local beside = Fixtures.enemy(run, "brute", player.x + 16, player.z + 4)
		local far = Fixtures.enemy(run, "brute", player.x + 16, player.z + 12)
		run.time = 1
		Assert.truthy(Combat.useActive(run, 1, 1))
		Projectiles.step(run, 0.5)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(struck.health, 90)
		Assert.equal(beside.health, 90)
		Assert.equal(far.health, 120)
		Assert.near(struck.burningUntil, 1 + run.config.statuses.burnSeconds)
		Assert.equal(struck.burnSource, 1)
		Assert.equal(far.burningUntil, 0)
		Assert.truthy(struck.knockX > 0)
		local burst = Assert.findEvent(run.events, "burst")
		Assert.equal(burst.skill, "fireball")
		Assert.equal(burst.radius, 7)
		-- The impact is where the projectile first touched the brute (3 studs).
		Assert.near(burst.x, player.x + 13, 1)
		Assert.equal(Assert.findEvent(run.events, "hit").skill, "fireball")
	end,

	["a fireball keeps flying across steps"] = function()
		local run, player = setup()
		Combat.useActive(run, 1, 1)
		Projectiles.step(run, 0.1)
		Assert.equal(#run.projectiles, 1)
		Assert.near(run.projectiles[1].x, player.x + 5)
		Assert.near(run.projectiles[1].remaining, 40)
		Assert.equal(Assert.findEvent(run.events, "burst"), nil)
	end,

	["a fireball bursts where its flight ends"] = function()
		local run, player = setup()
		local enemy = Fixtures.enemy(run, "brute", player.x + 12, player.z + 5)
		Combat.useActive(run, 1, 1, 10)
		Projectiles.step(run, 1)
		Assert.equal(#run.projectiles, 0)
		local burst = Assert.findEvent(run.events, "burst")
		Assert.near(burst.x, player.x + 10, 0.01)
		Assert.equal(enemy.health, 90)
	end,

	["a fireball stops at a wall and bursts there"] = function()
		local run, _, room = setup()
		local player = run.players[1]
		-- Three studs from the east wall, off the corridor's line, aiming at it.
		local edge = room.x + room.halfWidth
		Fixtures.place(run, player, edge - 3, room.z + 8)
		-- Beside the path, so only the burst reaches it.
		local enemy = Fixtures.enemy(run, "brute", edge - 2, room.z + 13)
		Combat.useActive(run, 1, 1)
		Projectiles.step(run, 1)
		Assert.equal(#run.projectiles, 0)
		local burst = Assert.findEvent(run.events, "burst")
		Assert.truthy(burst.x > edge and burst.x <= edge + 1.01)
		-- The enemy was not struck on the way but is inside the burst.
		Assert.equal(enemy.health, 90)
	end,

	["Split Shot's projectiles each land"] = function()
		local run, player = setup()
		player.perks.splitShot = 1
		local enemy = Fixtures.enemy(run, "brute", player.x + 14, player.z)
		Combat.useActive(run, 1, 1)
		-- The outer two fly on until a wall or the end of their range.
		for _ = 1, 5 do
			Projectiles.step(run, 0.5)
		end
		Assert.equal(#run.projectiles, 0)
		local bursts = 0
		for _, event in run.events do
			if event.kind == "burst" then
				bursts += 1
			end
		end
		Assert.equal(bursts, 3)
		Assert.truthy(enemy.health <= 120 - 30)
	end,

	["a fast projectile does not skip a small target"] = function()
		local run, player = setup()
		local enemy = Fixtures.enemy(run, "brute", player.x + 9, player.z)
		launch(run, "player", {
			x = player.x,
			z = player.z,
			speed = 300,
			remaining = 100,
			damage = 20,
			radius = 0,
		})
		Projectiles.step(run, 0.1)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(enemy.health, 100)
		local burst = Assert.findEvent(run.events, "burst")
		Assert.truthy(burst.x < player.x + 9)
	end,

	["a projectile without a radius hits only the enemy it strikes"] = function()
		local run, player = setup()
		local struck = Fixtures.enemy(run, "brute", player.x + 10, player.z)
		local beside = Fixtures.enemy(run, "brute", player.x + 10, player.z + 4)
		launch(run, "player", { x = player.x, z = player.z, damage = 20, knockback = 5 })
		Projectiles.step(run, 0.5)
		Assert.equal(struck.health, 100)
		Assert.equal(beside.health, 120)
		Assert.truthy(struck.knockUntil > 0)
		Assert.equal(beside.knockUntil, 0)
		Assert.equal(#run.projectiles, 0)
	end,

	["a projectile that kills credits its source"] = function()
		local run, player = setup()
		Fixtures.enemy(run, "grunt", player.x + 10, player.z)
		launch(run, "player", { x = player.x, z = player.z, damage = 50 })
		Projectiles.step(run, 0.5)
		Assert.equal(player.kills, 1)
		Assert.equal(#run.enemies, 0)
	end,

	["a projectile past the end of its range with nothing near harms nothing"] = function()
		local run, player = setup()
		launch(run, "player", { x = player.x, z = player.z, remaining = 3 })
		Projectiles.step(run, 1)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(#run.events, 1)
		Assert.equal(run.events[1].kind, "burst")
	end,

	-- Enemy projectiles

	["an enemy projectile hurts the player in its path and vanishes"] = function()
		local run, player, room = setup()
		Fixtures.place(run, player, room.x + 2, room.z)
		launch(run, "enemy", {
			source = 7,
			kind = "spitter",
			x = room.x - 12,
			z = room.z,
			speed = 32,
			remaining = 28,
			damage = 12,
		})
		Projectiles.step(run, 0.25)
		Assert.equal(#run.projectiles, 1)
		Assert.equal(player.health, 100)
		Projectiles.step(run, 0.5)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(player.health, 88)
		local hurt = Assert.findEvent(run.events, "playerHurt")
		Assert.equal(hurt.amount, 12)
		Assert.equal(hurt.enemyId, 7)
		Assert.equal(Assert.findEvent(run.events, "knocked"), nil)
	end,

	["an enemy projectile with knockback pushes the player"] = function()
		local run, player, room = setup()
		Fixtures.place(run, player, room.x + 2, room.z)
		launch(run, "enemy", {
			kind = "spitter",
			x = room.x - 12,
			z = room.z,
			speed = 32,
			damage = 12,
			knockback = 5,
		})
		Projectiles.step(run, 1)
		Assert.equal(player.health, 88)
		Assert.truthy(player.knockX > 0)
		Assert.truthy(Assert.findEvent(run.events, "knocked"))
	end,

	["an enemy projectile misses a player off to the side and ends its flight silently"] = function()
		local run, player, room = setup()
		Fixtures.place(run, player, room.x, room.z + 6)
		launch(run, "enemy", {
			kind = "spitter",
			x = room.x - 12,
			z = room.z,
			speed = 32,
			remaining = 20,
			damage = 12,
		})
		Projectiles.step(run, 1)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(player.health, 100)
		Assert.equal(#run.events, 0)
	end,

	["an enemy projectile ignores a downed player"] = function()
		local run, player, room = setup()
		Fixtures.place(run, player, room.x + 2, room.z)
		player.state = "downed"
		launch(
			run,
			"enemy",
			{ x = room.x - 12, z = room.z, speed = 32, remaining = 20, damage = 12 }
		)
		Projectiles.step(run, 1)
		Assert.equal(player.health, 100)
	end,

	["an enemy projectile vanishes at a wall"] = function()
		local run, player, room = setup()
		local edge = room.x + room.halfWidth
		Fixtures.place(run, player, room.x, room.z - 8)
		launch(run, "enemy", {
			kind = "spitter",
			x = edge - 3,
			z = room.z + 8,
			speed = 32,
			remaining = 28,
			damage = 12,
		})
		Projectiles.step(run, 1)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(player.health, 100)
		Assert.equal(#run.events, 0)
	end,

	["an enemy projectile with a radius bursts at the end of its flight"] = function()
		local run, near, room = setup(2)
		local far = run.players[2]
		Fixtures.place(run, near, room.x - 2, room.z + 4)
		Fixtures.place(run, far, room.x - 2, room.z + 10)
		launch(run, "enemy", {
			source = 3,
			kind = "campLeader",
			x = room.x - 12,
			z = room.z,
			speed = 28,
			remaining = 10,
			damage = 14,
			radius = 3,
			knockback = 4,
		})
		Projectiles.step(run, 1)
		Assert.equal(#run.projectiles, 0)
		-- Lands at room.x - 2: four studs from the near player, within 3 + 1.5.
		Assert.equal(near.health, 86)
		Assert.equal(far.health, 100)
		Assert.truthy(near.knockUntil > 0)
		local burst = Assert.findEvent(run.events, "burst")
		Assert.equal(burst.skill, "campLeader")
		Assert.equal(burst.radius, 3)
		Assert.near(burst.x, room.x - 2, 0.01)
	end,

	["an enemy projectile with a radius bursts on the player it touches"] = function()
		local run, player, room = setup()
		Fixtures.place(run, player, room.x + 2, room.z)
		launch(run, "enemy", {
			kind = "campLeader",
			x = room.x - 12,
			z = room.z,
			speed = 28,
			remaining = 28,
			damage = 14,
			radius = 3,
		})
		Projectiles.step(run, 1)
		Assert.equal(#run.projectiles, 0)
		Assert.equal(player.health, 86)
		-- Once, not once for the touch and once for the burst.
		Assert.equal(#run.events > 0, true)
		local hurts = 0
		for _, event in run.events do
			if event.kind == "playerHurt" then
				hurts += 1
			end
		end
		Assert.equal(hurts, 1)
	end,

	["an enemy projectile never harms enemies"] = function()
		local run, player, room = setup()
		Fixtures.place(run, player, room.x, room.z + 10)
		local enemy = Fixtures.enemy(run, "grunt", room.x - 6, room.z)
		launch(
			run,
			"enemy",
			{ x = room.x - 12, z = room.z, speed = 32, remaining = 20, damage = 12 }
		)
		Projectiles.step(run, 1)
		Assert.equal(enemy.health, 30)
	end,
}
