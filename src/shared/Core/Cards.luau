--!strict
-- Level-up cards (GLOSSARY: card): the weighted draw, the offer that pauses a
-- solo run, and taking a card.

local Hero = require("./Hero")
local State = require("./State")
local Types = require("./Types")

local Cards = {}

type Candidate = { card: Types.Card, weight: number }

local function owns(player: Types.Player, skillId: string): Types.OwnedSkill?
	for _, owned in player.skills do
		if owned.id == skillId then
			return owned
		end
	end
	return nil
end

-- Every card the player may be offered now, with its draw weight, in a fixed
-- order so the same seed draws the same cards.
local function candidates(run: Types.Run, player: Types.Player): { Candidate }
	local config = run.config
	local cards = config.cards
	local list: { Candidate } = {}

	for _, owned in player.skills do
		if owned.rank < config.ranks.maxRank then
			table.insert(list, {
				card = { kind = "skillRank", skill = owned.id, rank = owned.rank + 1 },
				weight = cards.weightSkillRank,
			})
		end
	end
	if #player.skills < cards.maxSkills then
		for _, skillId in config.classes[player.class].pool do
			if owns(player, skillId) == nil then
				table.insert(
					list,
					{ card = { kind = "newSkill", skill = skillId }, weight = cards.weightNewSkill }
				)
			end
		end
	end

	local passiveIds: { string } = {}
	for id in config.passives do
		table.insert(passiveIds, id)
	end
	table.sort(passiveIds)
	local held = 0
	for _, rank in player.passives do
		if rank > 0 then
			held += 1
		end
	end
	for _, id in passiveIds do
		local rank = player.passives[id] or 0
		if rank > 0 then
			if rank < config.passives[id].maxRank then
				table.insert(list, {
					card = { kind = "passiveRank", passive = id, rank = rank + 1 },
					weight = cards.weightPassiveRank,
				})
			end
		elseif held < cards.maxPassives then
			table.insert(
				list,
				{ card = { kind = "newPassive", passive = id }, weight = cards.weightNewPassive }
			)
		end
	end
	return list
end

-- Up to offerSize distinct cards drawn by weight without replacement; the
-- heal card alone when nothing else is left.
function Cards.draw(run: Types.Run, player: Types.Player): { Types.Card }
	local pool = candidates(run, player)
	if #pool == 0 then
		return { { kind = "heal" } }
	end
	local drawn: { Types.Card } = {}
	for _ = 1, math.min(run.config.cards.offerSize, #pool) do
		local total = 0
		for _, candidate in pool do
			total += candidate.weight
		end
		local roll = run.rng:next() * total
		local pick = #pool
		for index, candidate in pool do
			roll -= candidate.weight
			if roll < 0 then
				pick = index
				break
			end
		end
		table.insert(drawn, pool[pick].card)
		table.remove(pool, pick)
	end
	return drawn
end

local function countPlayers(run: Types.Run): number
	local count = 0
	for _ in run.players do
		count += 1
	end
	return count
end

local function announce(run: Types.Run, player: Types.Player, offer: { Types.Card })
	table.insert(run.events, { kind = "offer", player = player.id, cards = table.clone(offer) })
end

-- Queues a fresh draw for the player; only the oldest offer is announced. A
-- solo run stands still until the player chooses.
function Cards.offer(run: Types.Run, player: Types.Player)
	local offer = Cards.draw(run, player)
	table.insert(player.offers, offer)
	if #player.offers == 1 then
		announce(run, player, offer)
	end
	if countPlayers(run) == 1 then
		run.paused = true
	end
end

local function apply(run: Types.Run, player: Types.Player, card: Types.Card)
	if card.kind == "skillRank" then
		local owned = owns(player, card.skill)
		if owned ~= nil and owned.rank < run.config.ranks.maxRank then
			owned.rank += 1
		end
	elseif card.kind == "newSkill" then
		if owns(player, card.skill) == nil then
			table.insert(player.skills, {
				id = card.skill,
				rank = 1,
				readyAt = run.time + run.config.ranks.firstCooldownSeconds,
			})
		end
	elseif card.kind == "passiveRank" or card.kind == "newPassive" then
		local rank = player.passives[card.passive] or 0
		if rank < run.config.passives[card.passive].maxRank then
			player.passives[card.passive] = rank + 1
		end
	elseif card.kind == "heal" then
		local maxHealth = Hero.stats(run, player).maxHealth
		Hero.heal(run, player, maxHealth * run.config.cards.healShare)
	end
end

-- Takes card `index` of the player's oldest offer. The next queued offer is
-- drawn again, since this choice may have changed what can be offered; the
-- run resumes once no player has an offer left. Returns false when there is
-- no such card or the player cannot choose now.
function Cards.choose(run: Types.Run, playerId: number, index: number): boolean
	local player = run.players[playerId]
	if player == nil or player.state ~= "alive" then
		return false
	end
	local offer = player.offers[1]
	if offer == nil or index % 1 ~= 0 or index < 1 or index > #offer then
		return false
	end

	local card = offer[index]
	apply(run, player, card)
	table.insert(run.events, { kind = "cardTaken", player = player.id, card = card })
	table.remove(player.offers, 1)
	if #player.offers > 0 then
		player.offers[1] = Cards.draw(run, player)
		announce(run, player, player.offers[1])
	end

	local waiting = false
	for _, other in State.sortedPlayers(run) do
		if #other.offers > 0 then
			waiting = true
			break
		end
	end
	if not waiting then
		run.paused = false
	end
	return true
end

return Cards
