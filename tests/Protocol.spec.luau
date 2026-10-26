--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Protocol = require("../src/shared/Protocol")

return {
	["skill intent with an aim point"] = function()
		local intent = Protocol.parseIntent("activeSkill", 3.5, -2) :: any
		Assert.equal(intent.kind, "activeSkill")
		Assert.equal(intent.aim.x, 3.5)
		Assert.equal(intent.aim.z, -2)
	end,

	["skill intent without an aim auto-aims"] = function()
		local intent = Protocol.parseIntent("activeSkill", nil, nil) :: any
		Assert.equal(intent.kind, "activeSkill")
		Assert.equal(intent.aim, nil)
	end,

	["malformed skill intents are rejected"] = function()
		Assert.equal(Protocol.parseIntent("activeSkill", 1, nil), nil)
		Assert.equal(Protocol.parseIntent("activeSkill", "1", 2), nil)
		Assert.equal(Protocol.parseIntent("activeSkill", 0 / 0, 2), nil)
		Assert.equal(Protocol.parseIntent("activeSkill", math.huge, 2), nil)
		Assert.equal(Protocol.parseIntent("activeSkill", {}, 2), nil)
	end,

	["perk intent takes a small whole index"] = function()
		local intent = Protocol.parseIntent("perk", 2) :: any
		Assert.equal(intent.kind, "perk")
		Assert.equal(intent.index, 2)
		Assert.equal(Protocol.parseIntent("perk", 0), nil)
		Assert.equal(Protocol.parseIntent("perk", 1.5), nil)
		Assert.equal(Protocol.parseIntent("perk", 17), nil)
		Assert.equal(Protocol.parseIntent("perk", "1"), nil)
		Assert.equal(Protocol.parseIntent("perk", 1, 2), nil)
	end,

	["unknown intents are rejected"] = function()
		Assert.equal(Protocol.parseIntent("damage", 100), nil)
		Assert.equal(Protocol.parseIntent(nil), nil)
	end,

	["enemies survive encoding"] = function()
		local run = Fixtures.run(1)
		local names = Protocol.kindNames(run.config)
		local grunt = Fixtures.enemy(run, "grunt", 12.34, -56.78)
		local brute = Fixtures.enemy(run, "brute", -119.99, 119.99)
		run.time = 5
		grunt.chilledUntil = 6
		brute.burningUntil = 7
		local decoded = Protocol.decodeEnemies(Protocol.encodeEnemies(run, names), names) :: any
		Assert.equal(#decoded, 2)
		Assert.equal(decoded[1].id, grunt.id)
		Assert.equal(decoded[1].kind, "grunt")
		Assert.near(decoded[1].x, 12.34, 0.01)
		Assert.near(decoded[1].z, -56.78, 0.01)
		Assert.truthy(decoded[1].chilled)
		Assert.falsy(decoded[1].burning)
		Assert.equal(decoded[2].kind, "brute")
		Assert.near(decoded[2].x, -119.99, 0.01)
		Assert.truthy(decoded[2].burning)
	end,

	["a full horde fits the encoding"] = function()
		local run = Fixtures.run(1)
		local names = Protocol.kindNames(run.config)
		for i = 1, run.config.horde.maxAlive do
			Fixtures.enemy(run, "grunt", i % 100, -(i % 100))
		end
		local decoded = Protocol.decodeEnemies(Protocol.encodeEnemies(run, names), names) :: any
		Assert.equal(#decoded, run.config.horde.maxAlive)
	end,

	["malformed enemy buffers are rejected"] = function()
		local names = { "brute", "grunt" }
		Assert.equal(Protocol.decodeEnemies("nope", names), nil)
		Assert.equal(Protocol.decodeEnemies(buffer.create(1), names), nil)
		local short = buffer.create(2)
		buffer.writeu16(short, 0, 3)
		Assert.equal(Protocol.decodeEnemies(short, names), nil)
	end,

	["private events go to their player only"] = function()
		Assert.truthy(Protocol.isPrivate({ kind = "offer", player = 1, perks = {} }))
		Assert.falsy(Protocol.isPrivate({ kind = "downed", player = 1 }))
		Assert.equal(Protocol.eventPlayer({ kind = "levelUp", player = 4, level = 2 }), 4)
		Assert.equal(Protocol.eventPlayer({ kind = "flood" }), nil)
	end,

	["the arena fits the position encoding"] = function()
		-- Positions travel as int16 hundredths of a stud; a bigger arena would wrap.
		local config = Fixtures.config()
		Assert.truthy(
			config.arena.halfSize * 100 <= 32767,
			"arena.halfSize is too big for the encoding"
		)
	end,

	["interact intent carries whether the button is held"] = function()
		local down = Protocol.parseIntent("interact", true) :: any
		Assert.equal(down.kind, "interact")
		Assert.equal(down.held, true)
		Assert.equal((Protocol.parseIntent("interact", false) :: any).held, false)
		Assert.equal(Protocol.parseIntent("interact", 1), nil)
		Assert.equal(Protocol.parseIntent("interact", nil), nil)
		Assert.equal(Protocol.parseIntent("interact", true, 2), nil)
	end,
}
