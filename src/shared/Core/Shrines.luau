--!strict
-- Shrines (ADR-0020, GLOSSARY: shrine): the hold that activates one, what
-- each kind gives (a boon, a pact, a trial, a spring), the trial's ring and
-- its great offer, and the spring's recharge.

local Cards = require("./Cards")
local Geometry = require("./Geometry")
local Hero = require("./Hero")
local Horde = require("./Horde")
local State = require("./State")
local Types = require("./Types")

local Shrines = {}

-- A pact never takes a stat that multiplies a base too low: the lowered
-- share stops at config.shrines.pactMinShare (passives only add, so the stat
-- stays at least 1 + pactMinShare of its base). Flat stats (armour, haste,
-- regeneration, crit chance) are not held.
local SCALED: { [Types.Stat]: boolean } = {
	damage = true,
	maxHealth = true,
	speed = true,
	area = true,
	pickupRange = true,
	experience = true,
}

-- Whether the shrine can be activated now: unused and, for a spring, back;
-- a trial being fought cannot.
local function usable(run: Types.Run, shrine: Types.Shrine): boolean
	return not shrine.used and shrine.readyAt <= run.time and shrine.trialEnemies == nil
end

-- The shrine within the config's reach of the player, if any; the chest wins
-- over a shrine, so a hero at both opens the chest.
function Shrines.inReach(run: Types.Run, player: Types.Player): Types.Shrine?
	if player.state ~= "alive" then
		return nil
	end
	local arena = run.arena
	if
		not run.chestOpened
		and Geometry.distance(player.x, player.z, arena.chestX, arena.chestZ)
			<= run.config.extraction.openRadius
	then
		return nil
	end
	local best: Types.Shrine? = nil
	local bestDistance = run.config.shrines.reach
	for _, shrine in run.shrines do
		local distance = Geometry.distance(player.x, player.z, shrine.x, shrine.z)
		if distance <= bestDistance and usable(run, shrine) then
			best, bestDistance = shrine, distance
		end
	end
	return best
end

-- The interact button went down (`held`) or up. Holding beside an unused
-- (or recharged) shrine for config.shrines.holdSeconds activates it; a hit
-- resets the hold (Hero.damage clears shrineProgress). A press out of reach
-- holds nothing yet; Shrines.update starts the hold once a shrine is in reach.
function Shrines.setHolding(run: Types.Run, playerId: number, held: boolean)
	local player = run.players[playerId]
	if player == nil then
		return
	end
	local shrine = if held then Shrines.inReach(run, player) else nil
	player.shrineId = if shrine then shrine.id else nil
	player.shrineProgress = 0
end

local function boonById(run: Types.Run, id: string?): Types.BoonConfig?
	for _, boon in run.config.shrines.boons do
		if boon.id == id then
			return boon
		end
	end
	return nil
end

local function pactById(run: Types.Run, id: string?): Types.PactConfig?
	for _, pact in run.config.shrines.pacts do
		if pact.id == id then
			return pact
		end
	end
	return nil
end

local function addShare(run: Types.Run, player: Types.Player, stat: Types.Stat, amount: number)
	local share = (player.shrineShares[stat] or 0) + amount
	if SCALED[stat] then
		share = math.max(share, run.config.shrines.pactMinShare)
	end
	player.shrineShares[stat] = share
end

-- A trial whose ring is all dead deals its great offer to the hero who
-- started it, or to the first hero alive when they are not.
local function finishTrial(run: Types.Run, shrine: Types.Shrine)
	local remaining = {}
	for _, id in shrine.trialEnemies :: { number } do
		if State.enemyById(run, id) ~= nil then
			table.insert(remaining, id)
		end
	end
	if #remaining > 0 then
		shrine.trialEnemies = remaining
		return
	end
	local starter = if shrine.trialBy then run.players[shrine.trialBy :: number] else nil
	local recipient = if starter and starter.state == "alive"
		then starter
		else State.alivePlayers(run)[1]
	shrine.used = true
	shrine.trialEnemies = nil
	table.insert(run.events, {
		kind = "trialCompleted",
		shrineId = shrine.id,
		player = if recipient then recipient.id else shrine.trialBy or 0,
	})
	if recipient then
		Cards.offer(run, recipient, run.config.shrines.greatOfferRanks)
	end
end

-- The trial's ring around the shrine: the window's grunts in turn with the
-- elites spread evenly among them, all on one ring. Not held to the alive
-- target, though they count toward it while they live; held to the cap
-- (ADR-0019): the elites take the room first and grunts fill what is left.
-- A ring with no room at all is cleared at once and deals its offer now.
local function startTrial(run: Types.Run, player: Types.Player, shrine: Types.Shrine)
	local config = run.config.shrines
	local window = Horde.windowKinds(run)
	local elites = run.map.elites
	local room = math.max(run.config.horde.maxAlive - Horde.aliveCount(run), 0)
	local eliteCount = math.min(if #elites > 0 then config.trialEliteCount else 0, room)
	local gruntCount = math.min(if #window > 0 then config.trialRingCount else 0, room - eliteCount)
	local total = gruntCount + eliteCount
	local phase = run.rng:next() * 2 * math.pi
	local ids = table.create(total)
	local grunt = 0
	for index = 1, total do
		local kindId
		-- An elite where the running share of elites steps up, so they spread.
		if
			math.floor(index * eliteCount / total) > math.floor((index - 1) * eliteCount / total)
		then
			kindId = elites[run.rng:integer(1, #elites)]
		else
			grunt += 1
			kindId = window[(grunt - 1) % #window + 1]
		end
		local angle = phase + (index - 1) * 2 * math.pi / total
		local enemy = Horde.spawnKind(
			run,
			kindId,
			shrine.x + math.cos(angle) * config.trialRingRadius,
			shrine.z + math.sin(angle) * config.trialRingRadius
		)
		table.insert(ids, enemy.id)
	end
	shrine.trialEnemies = ids
	shrine.trialBy = player.id
	table.insert(run.events, { kind = "trialStarted", shrineId = shrine.id, count = total })
	if total == 0 then
		finishTrial(run, shrine)
	end
end

local function activate(run: Types.Run, player: Types.Player, shrine: Types.Shrine)
	player.shrineId = nil
	player.shrineProgress = 0
	local given: string? = nil
	if shrine.kind == "boon" then
		local boon = boonById(run, shrine.boon)
		if boon then
			addShare(run, player, boon.stat, boon.amount)
			given = boon.id
			table.insert(player.shrinesTaken, boon.id)
		end
		shrine.used = true
	elseif shrine.kind == "pact" then
		local pact = pactById(run, shrine.pact)
		if pact then
			addShare(run, player, pact.up, pact.upAmount)
			addShare(run, player, pact.down, -pact.downAmount)
			given = pact.id
			table.insert(player.shrinesTaken, pact.id)
			-- A lowered max health takes the health above it.
			player.health = math.min(player.health, Hero.stats(run, player).maxHealth)
		end
		shrine.used = true
	end
	table.insert(run.events, {
		kind = "shrineActivated",
		player = player.id,
		shrineId = shrine.id,
		shrineKind = shrine.kind,
		given = given,
	})

	if shrine.kind == "trial" then
		startTrial(run, player, shrine)
	elseif shrine.kind == "spring" then
		Hero.heal(run, player, Hero.stats(run, player).maxHealth)
		for index in player.utilityReadyAt do
			player.utilityReadyAt[index] = run.time
		end
		player.dashCharges = run.config.player.dashCharges
		player.dashReadyAt = run.time
		shrine.readyAt = run.time + run.config.shrines.springRechargeSeconds
	end
end

-- Advances every hold, finishes trials whose enemies are all dead and
-- recharges springs. A hold lasts while its shrine stays the one in reach;
-- stepping away (or toward the chest) drops it. While the button stays held,
-- a usable shrine coming into reach starts a new hold from zero.
function Shrines.update(run: Types.Run, dt: number)
	local holdSeconds = run.config.shrines.holdSeconds
	for _, player in State.sortedPlayers(run) do
		local shrineId = player.shrineId
		if shrineId == nil and player.interacting then
			local found = Shrines.inReach(run, player)
			if found then
				shrineId = found.id
				player.shrineId = shrineId
				player.shrineProgress = 0
			end
		end
		if shrineId == nil then
			continue
		end
		local shrine = State.shrineById(run, shrineId)
		if shrine == nil or Shrines.inReach(run, player) ~= shrine then
			player.shrineId = nil
			player.shrineProgress = 0
			continue
		end
		player.shrineProgress += dt
		if player.shrineProgress >= holdSeconds then
			activate(run, player, shrine)
		end
	end

	for _, shrine in run.shrines do
		if shrine.trialEnemies ~= nil then
			finishTrial(run, shrine)
		end
		-- A spring is back the step its recharge passes.
		if
			shrine.kind == "spring"
			and shrine.readyAt > 0
			and shrine.readyAt <= run.time
			and shrine.readyAt > run.time - dt
		then
			table.insert(run.events, { kind = "shrineReady", shrineId = shrine.id })
		end
	end
end

return Shrines
