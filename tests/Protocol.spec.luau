--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Lairs = require("../src/shared/Core/Lairs")
local Protocol = require("../src/shared/Protocol")
local Types = require("../src/shared/Core/Types")

local function projectile(id: number, owner: "player" | "enemy", kind: string): Types.Projectile
	return {
		id = id,
		owner = owner,
		source = 1,
		kind = kind,
		x = 0,
		z = 0,
		dirX = 1,
		dirZ = 0,
		speed = 50,
		remaining = 20,
		damage = 10,
		radius = 0,
		knockback = 0,
		tags = {},
		effect = nil,
		targetId = nil,
		critChance = 0,
	}
end

return {
	["every intent kind parses"] = function()
		local config = Fixtures.config()
		local pick = Protocol.parseIntent(config, "pickClass", "mage") :: any
		Assert.equal(pick.kind, "pickClass")
		Assert.equal(pick.class, "mage")
		local card = Protocol.parseIntent(config, "card", 3) :: any
		Assert.equal(card.kind, "card")
		Assert.equal(card.index, 3)
		local utility = Protocol.parseIntent(config, "utility", 1) :: any
		Assert.equal(utility.kind, "utility")
		Assert.equal(utility.index, 1)
		local open = Protocol.parseIntent(config, "interact", true) :: any
		Assert.equal(open.kind, "interact")
		Assert.equal(open.held, true)
		Assert.equal((Protocol.parseIntent(config, "interact", false) :: any).held, false)
		Assert.equal((Protocol.parseIntent(config, "cast") :: any).kind, "cast")
		Assert.equal((Protocol.parseIntent(config, "enter") :: any).kind, "enter")
		local dash = Protocol.parseIntent(config, "dash", 0.5, -2) :: any
		Assert.equal(dash.kind, "dash")
		Assert.equal(dash.dx, 0.5)
		Assert.equal(dash.dz, -2)
		Assert.equal((Protocol.parseIntent(config, "dash", 0, 1) :: any).dz, 1)
	end,

	["malformed intents are rejected"] = function()
		local config = Fixtures.config()
		Assert.equal(Protocol.parseIntent(config, "pickClass", "dragon"), nil)
		Assert.equal(Protocol.parseIntent(config, "pickClass", 1), nil)
		Assert.equal(Protocol.parseIntent(config, "pickClass", nil), nil)
		for _, kind in { "card", "utility" } do
			Assert.equal(Protocol.parseIntent(config, kind, 0), nil, kind .. " 0")
			Assert.equal(Protocol.parseIntent(config, kind, 7), nil, kind .. " 7")
			Assert.equal(Protocol.parseIntent(config, kind, 1.5), nil, kind .. " 1.5")
			Assert.equal(Protocol.parseIntent(config, kind, "1"), nil, kind .. " string")
			Assert.equal(Protocol.parseIntent(config, kind, 0 / 0), nil, kind .. " nan")
			Assert.equal(Protocol.parseIntent(config, kind, math.huge), nil, kind .. " inf")
			Assert.equal(Protocol.parseIntent(config, kind, 1, 2), nil, kind .. " trailing")
		end
		Assert.equal(Protocol.parseIntent(config, "interact", 1), nil)
		Assert.equal(Protocol.parseIntent(config, "interact", "true"), nil)
		Assert.equal(Protocol.parseIntent(config, "interact", nil), nil)
		Assert.equal(Protocol.parseIntent(config, "cast", 1), nil)
		Assert.equal(Protocol.parseIntent(config, "enter", true), nil)
		Assert.equal(Protocol.parseIntent(config, "dash"), nil, "dash nil")
		Assert.equal(Protocol.parseIntent(config, "dash", 1), nil, "dash one number")
		Assert.equal(Protocol.parseIntent(config, "dash", "1", "0"), nil, "dash strings")
		Assert.equal(Protocol.parseIntent(config, "dash", 0, 0), nil, "dash zero")
		Assert.equal(Protocol.parseIntent(config, "dash", 0 / 0, 1), nil, "dash nan")
		Assert.equal(Protocol.parseIntent(config, "dash", 1, math.huge), nil, "dash inf")
		local max = config.player.dashInputMax
		Assert.equal(Protocol.parseIntent(config, "dash", max + 1, 0), nil, "dash dx too large")
		Assert.equal(Protocol.parseIntent(config, "dash", 0, -max - 1), nil, "dash dz too large")
		Assert.equal(Protocol.parseIntent(config, "dash", 1e300, 1e300), nil, "dash absurd")
		Assert.equal(
			(Protocol.parseIntent(config, "dash", max, -max) :: any).dx,
			max,
			"dash at the bound"
		)
		Assert.equal(Protocol.parseIntent(config, "damage", 100), nil)
		Assert.equal(Protocol.parseIntent(config, nil), nil)
		Assert.equal(Protocol.parseIntent(config, {}), nil)
	end,

	["enemies survive encoding with their flags and phase"] = function()
		local run = Fixtures.run(1)
		local kinds = Protocol.enemyKinds(run.config)
		Assert.truthy(table.find(kinds, "sproutImp"))
		Assert.truthy(table.find(kinds, "thornback"))
		local grunt = Fixtures.enemy(run, "sproutImp", 12.34, -56.78)
		local boss = Fixtures.enemy(run, "thornback", -399.9, 399.9)
		run.time = 5
		grunt.facing = math.pi / 2
		grunt.state = "telegraph"
		grunt.health = grunt.maxHealth / 2
		grunt.slowUntil = 6
		grunt.stunnedUntil = 6
		grunt.rootedUntil = 4
		table.insert(grunt.dots, {
			dps = 3,
			until_ = 7,
			nextTickAt = 5.5,
			status = "burning",
			source = 1,
			tags = { "fire" },
		})
		table.insert(grunt.dots, {
			dps = 3,
			until_ = 4,
			nextTickAt = 5.5,
			status = "poisoned",
			source = 1,
			tags = { "poison" },
		})
		boss.state = "recover"
		boss.phase = 2
		boss.rootedUntil = 6
		boss.fearedUntil = 6
		boss.buffedUntil = 6
		table.insert(boss.dots, {
			dps = 3,
			until_ = 7,
			nextTickAt = 5.5,
			status = "bleeding",
			source = 1,
			tags = { "bleed" },
		})

		local decoded = Protocol.decodeEnemies(Protocol.encodeEnemies(run, kinds), kinds)
		assert(decoded, "decoding failed")
		Assert.equal(#decoded, 2)
		local a, b = decoded[1], decoded[2]
		Assert.equal(a.id, grunt.id)
		Assert.equal(a.kind, "sproutImp")
		Assert.near(a.x, 12.34, 0.1)
		Assert.near(a.z, -56.78, 0.1)
		Assert.near(a.facing, math.pi / 2, 0.03)
		Assert.equal(a.state, "telegraph")
		Assert.near(a.health, 0.5, 0.01)
		Assert.equal(a.slowed, true)
		Assert.equal(a.stunned, true)
		Assert.equal(a.rooted, false, "expired")
		Assert.equal(a.feared, false)
		Assert.equal(a.burning, true)
		Assert.equal(a.poisoned, false, "expired dot")
		Assert.equal(a.bleeding, false)
		Assert.equal(a.buffed, false)
		Assert.equal(a.phase, 1)
		Assert.equal(b.kind, "thornback")
		Assert.near(b.x, -399.9, 0.1)
		Assert.near(b.z, 399.9, 0.1)
		Assert.equal(b.state, "recover")
		Assert.near(b.health, 1, 1e-6)
		Assert.equal(b.slowed, false)
		Assert.equal(b.rooted, true)
		Assert.equal(b.feared, true)
		Assert.equal(b.bleeding, true)
		Assert.equal(b.burning, false)
		Assert.equal(b.buffed, true)
		Assert.equal(b.phase, 2)
	end,

	["a malformed enemy buffer is rejected"] = function()
		local run = Fixtures.run(1)
		local kinds = Protocol.enemyKinds(run.config)
		Assert.equal(Protocol.decodeEnemies("not a buffer", kinds), nil)
		Assert.equal(Protocol.decodeEnemies(buffer.create(1), kinds), nil)
		local short = buffer.create(2)
		buffer.writeu16(short, 0, 3)
		Assert.equal(Protocol.decodeEnemies(short, kinds), nil)
		Assert.equal(#(Protocol.decodeEnemies(buffer.create(2), kinds) :: any), 0)
		Fixtures.enemy(run, "sproutImp", 0, 0)
		local data = Protocol.encodeEnemies(run, kinds)
		buffer.writeu8(data, 2 + 4, #kinds + 1)
		Assert.equal(Protocol.decodeEnemies(data, kinds), nil, "kind out of range")
		buffer.writeu8(data, 2 + 4, 0)
		Assert.equal(Protocol.decodeEnemies(data, kinds), nil, "kind 0")
		local longer = buffer.create(buffer.len(data) + 1)
		buffer.copy(longer, 0, Protocol.encodeEnemies(run, kinds))
		Assert.equal(Protocol.decodeEnemies(longer, kinds), nil, "trailing byte")
	end,

	["projectiles survive encoding"] = function()
		local run = Fixtures.run(1)
		local kinds = Protocol.projectileKinds(run.config)
		Assert.truthy(table.find(kinds, "rimeDart"), "a flying skill")
		Assert.truthy(table.find(kinds, "spitter"), "a shooting enemy")
		Assert.falsy(table.find(kinds, "hoarfrostRing"), "a nova does not fly")
		Assert.falsy(table.find(kinds, "sproutImp"), "a grunt does not shoot")
		local orb = projectile(7, "player", "emberOrb")
		orb.x, orb.z = 10.26, -3.14
		orb.dirX, orb.dirZ = 0, 1
		orb.radius = 8
		table.insert(run.projectiles, orb)
		local spit = projectile(8, "enemy", "spitter")
		spit.dirX, spit.dirZ = -1, 0
		table.insert(run.projectiles, spit)
		local decoded = Protocol.decodeProjectiles(Protocol.encodeProjectiles(run, kinds), kinds)
		assert(decoded, "decoding failed")
		Assert.equal(#decoded, 2)
		Assert.equal(decoded[1].id, 7)
		Assert.equal(decoded[1].kind, "emberOrb")
		Assert.near(decoded[1].x, 10.26, 0.1)
		Assert.near(decoded[1].z, -3.14, 0.1)
		Assert.near(decoded[1].angle, math.pi / 2, 0.03)
		Assert.near(decoded[1].radius, 8, 0.1)
		Assert.equal(decoded[2].kind, "spitter")
		Assert.near(decoded[2].angle, math.pi, 0.03)
		Assert.equal(decoded[2].radius, 0)
	end,

	["a malformed projectile buffer is rejected"] = function()
		local run = Fixtures.run(1)
		local kinds = Protocol.projectileKinds(run.config)
		Assert.equal(Protocol.decodeProjectiles(42, kinds), nil)
		local short = buffer.create(2)
		buffer.writeu16(short, 0, 1)
		Assert.equal(Protocol.decodeProjectiles(short, kinds), nil)
		table.insert(run.projectiles, projectile(1, "player", "rimeDart"))
		local data = Protocol.encodeProjectiles(run, kinds)
		buffer.writeu8(data, 2 + 4, #kinds + 1)
		Assert.equal(Protocol.decodeProjectiles(data, kinds), nil, "kind out of range")
	end,

	["crystals survive encoding"] = function()
		local run = Fixtures.run(1)
		table.insert(run.crystals, { id = 3, x = 101.27, z = -0.04, xp = 12 })
		table.insert(run.crystals, { id = 4, x = -250, z = 33.3, xp = 70000 })
		local decoded = Protocol.decodeCrystals(Protocol.encodeCrystals(run))
		assert(decoded, "decoding failed")
		Assert.equal(#decoded, 2)
		Assert.equal(decoded[1].id, 3)
		Assert.near(decoded[1].x, 101.27, 0.1)
		Assert.near(decoded[1].z, -0.04, 0.1)
		Assert.equal(decoded[1].xp, 12)
		Assert.near(decoded[2].x, -250, 0.1)
		Assert.equal(decoded[2].xp, 65535, "capped")
		Assert.equal(Protocol.decodeCrystals(nil), nil)
		local short = buffer.create(5)
		buffer.writeu16(short, 0, 1)
		Assert.equal(Protocol.decodeCrystals(short), nil)
	end,

	["the world view lists players, areas, the chest, the compass and the portal"] = function()
		local run = Fixtures.run(2)
		run.time = 10
		local player = run.players[2]
		player.castingUntil = 13
		player.openProgress = 0.5
		player.sprintUntil = 12
		player.barrier = 20
		player.barrierUntil = 11
		table.insert(run.areas, {
			id = 50,
			owner = "enemy",
			source = 9,
			kind = "thornback",
			x = 4,
			z = 5,
			radius = 6,
			damage = 3,
			until_ = 14,
			nextTickAt = 11,
			tickSeconds = 1,
			tags = {},
			effect = nil,
			critChance = 0,
			knockback = 0,
		})
		Fixtures.enemy(run, "sproutImp", 0, 0)
		local boss = Fixtures.enemy(run, "thornback", 20, 0)
		run.compassOn = true
		run.portal = { x = 1, z = 2, until_ = 25 }

		local view = Protocol.worldView(run)
		Assert.equal(view.time, 10)
		Assert.equal(#view.players, 2)
		Assert.equal(view.players[1].id, 1)
		local seen = view.players[2]
		Assert.equal(seen.id, 2)
		Assert.equal(seen.class, "mage")
		Assert.equal(seen.maxHealth, run.config.classes.mage.maxHealth)
		Assert.near(seen.castingLeft, 3)
		Assert.near(seen.openProgress, 0.5)
		Assert.equal(seen.sprinting, true)
		Assert.equal(seen.barrier, 20)
		Assert.equal(view.players[1].castingLeft, 0)
		Assert.equal(view.players[1].sprinting, false)
		Assert.equal(#view.areas, 1)
		Assert.equal(view.areas[1].areaKind, "thornback")
		Assert.equal(view.areas[1].owner, "enemy")
		Assert.near(view.areas[1].secondsLeft, 4)
		Assert.near(view.chest.x, run.arena.chestX)
		Assert.near(view.chest.z, run.arena.chestZ)
		Assert.equal(view.chest.opened, false)
		Assert.equal(view.compassOn, true)
		local portal = view.portal
		assert(portal, "the portal is listed")
		Assert.near(portal.x, 1)
		Assert.near(portal.secondsLeft, 15)
		Assert.equal(#view.bossIds, 1)
		Assert.equal(view.bossIds[1], boss.id)

		run.portal = nil
		Assert.equal(Protocol.worldView(run).portal, nil)
	end,

	["the world view lists the shrines and the players' holds and dashes"] = function()
		local run = Fixtures.run(1)
		run.shrines = {}
		run.time = 10
		local boon = Fixtures.shrine(run, "boon", 50, 0)
		local spring = Fixtures.shrine(run, "spring", -50, 0)
		spring.readyAt = 25
		local trial = Fixtures.shrine(run, "trial", 0, 50)
		trial.trialEnemies = { 1 }
		local player = run.players[1]
		player.shrineProgress = 0.75
		player.dashUntil = 10.1
		local view = Protocol.worldView(run)
		Assert.equal(#view.shrines, 3)
		local seen = view.shrines[1]
		Assert.equal(seen.id, boon.id)
		Assert.equal(seen.kind, "boon")
		Assert.equal(seen.x, 50)
		Assert.equal(seen.given, boon.boon)
		Assert.equal(seen.used, false)
		Assert.equal(seen.trial, false)
		Assert.near(view.shrines[2].readyIn, 15)
		Assert.equal(view.shrines[2].given, nil)
		Assert.equal(view.shrines[3].trial, true)
		Assert.near(view.players[1].shrineProgress, 0.75)
		Assert.equal(view.players[1].dashing, true)
		player.dashUntil = 0
		Assert.equal(Protocol.worldView(run).players[1].dashing, false)
	end,

	["the world view lists the lairs, the rise and doom"] = function()
		local run = Fixtures.run(1)
		Fixtures.clearLairs(run)
		local asleep = Fixtures.lair(run, "brambleNest", 200, 0)
		local silenced = Fixtures.lair(run, "bog", -200, 0)
		Lairs.update(run, 0)
		silenced.silenced = true
		silenced.bossId = nil
		run.time = 100
		run.finalRiseAt = 104
		local view = Protocol.worldView(run)
		Assert.equal(#view.lairs, 2)
		local seen = view.lairs[1]
		Assert.equal(seen.id, asleep.id)
		Assert.equal(seen.kind, "brambleNest")
		Assert.equal(seen.x, 200)
		Assert.equal(seen.radius, asleep.radius)
		Assert.equal(seen.asleep, true)
		Assert.equal(seen.silenced, false)
		Assert.equal(seen.bossId, asleep.bossId)
		Assert.equal(view.lairs[2].silenced, true)
		Assert.equal(view.lairs[2].bossId, nil)
		Assert.near(view.finalRiseLeft :: number, 4)
		Assert.equal(view.doom, false)
		Assert.near(view.doomIn, run.config.run.durationSeconds - 100)
		Assert.equal((view :: any).finalBossLeft, nil, "no final boss deadline")
		run.time = run.config.run.durationSeconds + 5
		run.doom = true
		run.finalRiseAt = nil
		view = Protocol.worldView(run)
		Assert.equal(view.doom, true)
		Assert.equal(view.doomIn, 0)
		Assert.equal(view.finalRiseLeft, nil)
	end,

	["the self view carries the dash charges and the boons and pacts taken"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		local config = run.config.player
		run.time = 4
		local view = Protocol.selfView(run, player)
		Assert.equal(view.dashCharges, config.dashCharges)
		Assert.equal(view.dashReadyIn, 0, "every charge held")
		player.dashCharges = config.dashCharges - 1
		player.dashReadyAt = 5.5
		player.shrinesTaken = { "might", "blood" }
		view = Protocol.selfView(run, player)
		Assert.equal(view.dashCharges, config.dashCharges - 1)
		Assert.near(view.dashReadyIn, 1.5)
		Assert.equal(#view.shrinesTaken, 2)
		Assert.equal(view.shrinesTaken[1], "might")
		Assert.equal(view.shrinesTaken[2], "blood")
		table.insert(player.shrinesTaken, "wind")
		Assert.equal(#view.shrinesTaken, 2, "a copy")
	end,

	["the self view carries skills with ranks and readyIn"] = function()
		local run = Fixtures.run(1)
		local player = run.players[1]
		run.time = 4
		player.skills[1].rank = 3
		player.skills[1].readyAt = 6.5
		player.utilityReadyAt[2] = 10
		player.passives.vigor = 2
		player.hasSpell = true
		local view = Protocol.selfView(run, player)
		Assert.equal(view.level, 1)
		Assert.truthy(view.xpToNext > 0)
		Assert.equal(#view.skills, 1)
		local skill = view.skills[1]
		Assert.equal(skill.id, run.config.classes.mage.startSkill)
		Assert.equal(skill.rank, 3)
		Assert.near(skill.readyIn, 2.5)
		Assert.equal(skill.cooldown, run.config.skills[skill.id].cooldownSeconds)
		Assert.equal(#view.utilities, #run.config.utilities)
		Assert.equal(view.utilities[1].readyIn, 0)
		Assert.near(view.utilities[2].readyIn, 6)
		Assert.equal(view.utilities[2].cooldown, run.config.utilities[2].cooldownSeconds)
		Assert.equal(view.passives.vigor, 2)
		Assert.equal(view.hasSpell, true)
		Assert.equal(view.offer, nil)
		Assert.truthy(view.stats.maxHealth > 0)
		local cards: { Types.Card } = { { kind = "heal" } }
		player.offers = { { cards = cards, ranks = 2 } }
		Assert.equal(Protocol.selfView(run, player).offer, cards, "the oldest offer's cards")
		player.skills[1].readyAt = 1
		Assert.equal(Protocol.selfView(run, player).skills[1].readyIn, 0)
	end,

	["private events go to their player only"] = function()
		local private: { Types.Event } = {
			{ kind = "offer", player = 2, cards = { { kind = "heal" } } },
			{ kind = "cardTaken", player = 2, card = { kind = "heal" } },
			{ kind = "levelUp", player = 2, level = 3 },
			{ kind = "utility", player = 2, utility = "sprint" },
		}
		for _, event in private do
			Assert.truthy(Protocol.isPrivate(event), event.kind)
			Assert.equal(Protocol.eventPlayer(event), 2, event.kind)
		end
		local public: { Types.Event } = {
			{ kind = "died", player = 2 },
			{ kind = "chestOpened", player = 2 },
			{ kind = "castStarted", player = 2, seconds = 5 },
			{ kind = "portalClosed" },
			{ kind = "playerHurt", player = 2, amount = 3, enemyId = nil, absorbed = 0 },
		}
		for _, event in public do
			Assert.falsy(Protocol.isPrivate(event), event.kind)
		end
		Assert.equal(Protocol.eventPlayer({ kind = "portalClosed" }), nil)
	end,
}
