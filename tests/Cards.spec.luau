--!strict
local Assert = require("./Assert")
local Cards = require("../src/shared/Core/Cards")
local Fixtures = require("./Fixtures")
local Progression = require("../src/shared/Core/Progression")
local Types = require("../src/shared/Core/Types")

-- A key naming a card, to compare draws and spot repeats.
local function key(card: Types.Card): string
	if card.kind == "skillRank" or card.kind == "newSkill" then
		return card.kind .. ":" .. card.skill
	elseif card.kind == "passiveRank" or card.kind == "newPassive" then
		return card.kind .. ":" .. card.passive
	end
	return card.kind
end

local function keys(cards: { Types.Card }): string
	local list = {}
	for _, card in cards do
		table.insert(list, key(card))
	end
	return table.concat(list, ",")
end

-- Gives the player every skill of the class pool at max rank and every
-- passive at max rank: nothing is left to draw.
local function maxOut(run: Types.Run, player: Types.Player)
	player.skills = {}
	for _, skillId in run.config.classes[player.class].pool do
		table.insert(player.skills, { id = skillId, rank = run.config.ranks.maxRank, readyAt = 0 })
	end
	player.passives = {}
	for id, passive in run.config.passives do
		player.passives[id] = passive.maxRank
	end
end

local function sortedPassives(run: Types.Run): { string }
	local ids = {}
	for id in run.config.passives do
		table.insert(ids, id)
	end
	table.sort(ids)
	return ids
end

return {
	["a draw gives three distinct cards"] = function()
		for seed = 1, 50 do
			local run = Fixtures.run(1, nil, seed)
			local drawn = Cards.draw(run, run.players[1])
			Assert.equal(#drawn, run.config.cards.offerSize)
			local seen = {}
			for _, card in drawn do
				Assert.falsy(seen[key(card)], "repeated: " .. key(card))
				Assert.truthy(card.kind ~= "heal", "heal while cards are left")
				seen[key(card)] = true
			end
		end
	end,

	["the same seed draws the same cards"] = function()
		local function drawFor(seed: number): string
			local run = Fixtures.run(1, nil, seed)
			return keys(Cards.draw(run, run.players[1]))
		end
		local distinct = {}
		for seed = 1, 20 do
			Assert.equal(drawFor(seed), drawFor(seed))
			distinct[drawFor(seed)] = true
		end
		local n = 0
		for _ in distinct do
			n += 1
		end
		Assert.truthy(n > 1, "every seed drew the same cards")
	end,

	["no new skill is drawn at six skills"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local pool = run.config.classes.mage.pool
		player.skills = {}
		for index = 1, run.config.cards.maxSkills do
			table.insert(player.skills, { id = pool[index], rank = 1, readyAt = 0 })
		end
		for seed = 1, 50 do
			run.rng = Fixtures.run(1, nil, seed).rng
			for _, card in Cards.draw(run, player) do
				Assert.truthy(card.kind ~= "newSkill", key(card))
			end
		end
	end,

	["no new passive is drawn at six passives"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local ids = sortedPassives(run)
		for index = 1, run.config.cards.maxPassives do
			player.passives[ids[index]] = 1
		end
		for seed = 1, 50 do
			run.rng = Fixtures.run(1, nil, seed).rng
			for _, card in Cards.draw(run, player) do
				Assert.truthy(card.kind ~= "newPassive", key(card))
			end
		end
	end,

	["no rank above the maximum is drawn"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		maxOut(run, player)
		-- One skill and one passive below the maximum, everything else maxed.
		player.skills[1].rank = run.config.ranks.maxRank - 1
		player.passives.vigor = run.config.passives.vigor.maxRank - 1
		local drawn = Cards.draw(run, player)
		Assert.equal(#drawn, 2)
		for _, card in drawn do
			if card.kind == "skillRank" then
				Assert.equal(card.skill, player.skills[1].id)
				Assert.equal(card.rank, run.config.ranks.maxRank)
			elseif card.kind == "passiveRank" then
				Assert.equal(card.passive, "vigor")
				Assert.equal(card.rank, run.config.passives.vigor.maxRank)
			else
				error("unexpected " .. key(card))
			end
		end
	end,

	["the heal is drawn only when nothing else is left"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		maxOut(run, player)
		local drawn = Cards.draw(run, player)
		Assert.equal(keys(drawn), "heal")
	end,

	["an offer is announced and pauses a solo run but not a party"] = function()
		local run = Fixtures.run()
		Cards.offer(run, run.players[1])
		Assert.truthy(run.paused)
		local event = Assert.findEvent(run.events, "offer")
		Assert.equal(event.player, 1)
		Assert.equal(keys(event.cards), keys(run.players[1].offers[1].cards))

		local party = Fixtures.run(2)
		Cards.offer(party, party.players[1])
		Assert.falsy(party.paused)
	end,

	["choosing a new skill adds it at rank 1 and unpauses"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		run.time = 10
		player.offers =
			{ { cards = { { kind = "newSkill", skill = "emberOrb", rank = 1 } }, ranks = 1 } }
		run.paused = true
		Assert.truthy(Cards.choose(run, 1, 1))
		local owned = player.skills[#player.skills]
		Assert.equal(owned.id, "emberOrb")
		Assert.equal(owned.rank, 1)
		Assert.near(owned.readyAt, 10 + run.config.ranks.firstCooldownSeconds, 1e-9)
		Assert.falsy(run.paused)
		Assert.equal(#player.offers, 0)
		Assert.equal(Assert.findEvent(run.events, "cardTaken").card.kind, "newSkill")
	end,

	["choosing ranks a skill and a passive"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		local skillId = player.skills[1].id
		player.offers = {
			{ cards = { { kind = "skillRank", skill = skillId, rank = 2 } }, ranks = 1 },
		}
		Assert.truthy(Cards.choose(run, 1, 1))
		Assert.equal(player.skills[1].rank, 2)
		player.offers =
			{ { cards = { { kind = "newPassive", passive = "hide", rank = 1 } }, ranks = 1 } }
		Assert.truthy(Cards.choose(run, 1, 1))
		Assert.equal(player.passives.hide, 1)
		player.offers =
			{ { cards = { { kind = "passiveRank", passive = "hide", rank = 2 } }, ranks = 1 } }
		Assert.truthy(Cards.choose(run, 1, 1))
		Assert.equal(player.passives.hide, 2)
	end,

	["the heal card restores health"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		player.health = 1
		player.offers = { { cards = { { kind = "heal" } }, ranks = 1 } }
		Assert.truthy(Cards.choose(run, 1, 1))
		Assert.equal(
			player.health,
			math.min(
				1 + run.config.classes.mage.maxHealth * run.config.cards.healShare,
				run.config.classes.mage.maxHealth
			)
		)
	end,

	["choose rejects a bad index, no offer and unknown players"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Assert.falsy(Cards.choose(run, 1, 1), "no offer")
		Cards.offer(run, player)
		Assert.falsy(Cards.choose(run, 1, 0))
		Assert.falsy(Cards.choose(run, 1, #player.offers[1].cards + 1))
		Assert.falsy(Cards.choose(run, 1, 1.5))
		Assert.falsy(Cards.choose(run, 9, 1))
		Assert.equal(#player.offers, 1)
		Assert.truthy(run.paused)
	end,

	["two level-ups at once give two offers in turn"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		Progression.grantXp(run, player, 5 + 15)
		Assert.equal(player.level, 3)
		Assert.equal(#player.offers, 2)
		Assert.equal(Fixtures.count(run.events, "offer"), 1)
		Assert.truthy(run.paused)

		run.events = {}
		Assert.truthy(Cards.choose(run, 1, 1))
		Assert.equal(#player.offers, 1)
		Assert.truthy(run.paused, "the second offer still waits")
		local next = Assert.findEvent(run.events, "offer")
		Assert.equal(keys(next.cards), keys(player.offers[1].cards))

		Assert.truthy(Cards.choose(run, 1, 1))
		Assert.equal(#player.offers, 0)
		Assert.falsy(run.paused)
	end,

	["a queued offer is drawn again after a choice"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		maxOut(run, player)
		player.passives.vigor = run.config.passives.vigor.maxRank - 1
		local card: Types.Card = { kind = "passiveRank", passive = "vigor", rank = 5 }
		player.offers = { { cards = { card }, ranks = 1 }, { cards = { card }, ranks = 1 } }
		Assert.truthy(Cards.choose(run, 1, 1))
		Assert.equal(keys(player.offers[1].cards), "heal")
	end,

	["ranks never pass their limits over many draws"] = function()
		for seed = 1, 30 do
			local run = Fixtures.run(1, nil, seed)
			local player = run.players[1]
			for _ = 1, 80 do
				Cards.offer(run, player)
				Assert.truthy(Cards.choose(run, 1, run.rng:integer(1, #player.offers[1].cards)))
			end
			Assert.truthy(#player.skills <= run.config.cards.maxSkills, "skills")
			local held = 0
			for id, rank in player.passives do
				held += 1
				Assert.truthy(rank <= run.config.passives[id].maxRank, id)
			end
			Assert.truthy(held <= run.config.cards.maxPassives, "passives")
			for _, owned in player.skills do
				Assert.truthy(owned.rank <= run.config.ranks.maxRank, owned.id)
			end
		end
	end,

	["a draw of two ranks gives cards worth two ranks, held to the maximum"] = function()
		for seed = 1, 30 do
			local run = Fixtures.run(1, nil, seed)
			local player = run.players[1]
			local maxRank = run.config.ranks.maxRank
			player.skills[1].rank = maxRank - 1
			player.passives.vigor = 1
			for _, card in Cards.draw(run, player, 2) do
				if card.kind == "newSkill" then
					Assert.equal(card.rank, 2)
				elseif card.kind == "skillRank" then
					Assert.equal(card.rank, maxRank, "capped at the maximum")
				elseif card.kind == "newPassive" then
					Assert.equal(card.rank, math.min(2, run.config.passives[card.passive].maxRank))
				elseif card.kind == "passiveRank" then
					Assert.equal(card.rank, math.min(3, run.config.passives[card.passive].maxRank))
				end
			end
			-- A level-up's draw stays one rank.
			for _, card in Cards.draw(run, player) do
				if card.kind == "newSkill" or card.kind == "newPassive" then
					Assert.equal(card.rank, 1)
				end
			end
		end
	end,

	["a great offer's new skill arrives at rank two"] = function()
		local run = Fixtures.run()
		local player = run.players[1]
		run.time = 10
		player.offers =
			{ { cards = { { kind = "newSkill", skill = "emberOrb", rank = 2 } }, ranks = 2 } }
		run.paused = true
		Assert.truthy(Cards.choose(run, 1, 1))
		Assert.equal(player.skills[#player.skills].rank, 2)
		player.offers =
			{ { cards = { { kind = "skillRank", skill = "emberOrb", rank = 4 } }, ranks = 2 } }
		Assert.truthy(Cards.choose(run, 1, 1))
		Assert.equal(player.skills[#player.skills].rank, 4)
	end,
}
