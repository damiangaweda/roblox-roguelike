--!strict
-- The lairs feed the horde and hold the bosses (ADR-0021; GLOSSARY: lair,
-- guard, silenced, doom, wraith). Every living lair releases a batch of its
-- own grunts at its own interval, the batch growing with run time; the grunts
-- walk at the nearest hero across the map, and a stray far from every hero
-- despawns and is owed to its lair's next batch. A lair's boss and guard sleep
-- in it until a hero enters or something damages one of them, fight only
-- inside it and fall back asleep when every hero has left. The boss's death
-- silences the lair; the last lair's fall raises the final boss there. From
-- the run's end time doom sends wraiths at every hero.
--
-- Growth: a released grunt, a guard and the final boss get the horde's
-- healthGrowth and damageGrowth at the run's progress when they spawn (a
-- guard again each time it wakes). A boss gets its own growth each time its
-- lair wakes: maxHealth = kind.health × (1 + bossGrowthPerMinute × time / 60),
-- its health keeping the share it had, and damageFactor the same factor.
--
-- What counts toward the alive cap (ADR-0019): grunts and the trials' and
-- summons' elites; never bosses, guards or wraiths.

local Arena = require("./Arena")
local Cards = require("./Cards")
local Geometry = require("./Geometry")
local State = require("./State")
local Types = require("./Types")

local Lairs = {}

-- Draws a spawn spends looking for free ground next to an obstacle.
local FREE_SPOT_TRIES = 8
-- The lair's shape, not a gameplay number: grunts are released between these
-- shares of its radius from its centre, the guard stands on a ring at
-- GUARD_RING of it.
local RELEASE_MIN, RELEASE_MAX = 0.6, 0.9
local GUARD_RING = 0.5
-- A woken boss and guard keep fighting a hero up to this many lair radii from
-- the lair's centre; with none that close the lair falls asleep. They never
-- leave the lair's radius themselves.
local REACH_RADII = 2

-- How far the run is through its duration: 0 at the start, 1 from the end on.
function Lairs.progress(run: Types.Run): number
	return math.min(run.time / run.config.run.durationSeconds, 1)
end

-- The boss's growth factor now: 1 + bossGrowthPerMinute per minute of run time.
function Lairs.bossGrowth(run: Types.Run): number
	return 1 + run.config.lairs.bossGrowthPerMinute * run.time / 60
end

-- An enemy of `kindId` near (x, z) with the horde's growth for the run time,
-- on free ground inside the edge.
function Lairs.spawnKind(run: Types.Run, kindId: string, x: number, z: number): Types.Enemy
	local horde = run.config.horde
	local p = Lairs.progress(run)
	local radius = run.config.enemies[kindId].radius
	local fx, fz = Arena.freeSpot(run.arena, x, z, radius, run.rng, FREE_SPOT_TRIES)
	return State.newEnemy(
		run,
		kindId,
		fx,
		fz,
		1 + horde.healthGrowth * p,
		1 + horde.damageGrowth * p
	)
end

-- Whether the enemy is a lair's guard: an elite tied to a lair.
function Lairs.isGuard(run: Types.Run, enemy: Types.Enemy): boolean
	return enemy.lairId ~= nil and State.kind(run, enemy).role == "elite"
end

-- Enemies alive that count toward the alive cap: neither bosses, guards nor wraiths.
function Lairs.aliveCount(run: Types.Run): number
	local count = 0
	for _, enemy in run.enemies do
		local role = State.kind(run, enemy).role
		if role == "grunt" or (role == "elite" and enemy.lairId == nil) then
			count += 1
		end
	end
	return count
end

-- The lair holding the enemy on its leash: its boss or one of its guard.
function Lairs.leashOf(run: Types.Run, enemy: Types.Enemy): Types.Lair?
	local lairId = enemy.lairId
	if lairId == nil then
		return nil
	end
	local role = State.kind(run, enemy).role
	if role ~= "boss" and role ~= "elite" then
		return nil
	end
	return State.lairById(run, lairId)
end

-- How far from the lair's centre its woken boss and guard still fight a hero.
function Lairs.reach(lair: Types.Lair): number
	return lair.radius * REACH_RADII
end

-- (x, z) pulled inside the lair's radius.
function Lairs.clamp(lair: Types.Lair, x: number, z: number): (number, number)
	local dx, dz = x - lair.x, z - lair.z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance <= lair.radius then
		return x, z
	end
	return lair.x + dx / distance * lair.radius, lair.z + dz / distance * lair.radius
end

local function nearestLair(run: Types.Run, x: number, z: number, living: boolean): Types.Lair?
	local best: Types.Lair? = nil
	local bestDistance = math.huge
	for _, lair in run.lairs do
		if not (living and lair.silenced) then
			local distance = Geometry.distance(x, z, lair.x, lair.z)
			if distance < bestDistance then
				best, bestDistance = lair, distance
			end
		end
	end
	return best
end

-- The grunt kinds spawned near (x, z) by a trial or a summon: the nearest
-- living lair's, else the nearest lair's, else the roster's weakest.
function Lairs.gruntKinds(run: Types.Run, x: number, z: number): { string }
	local lair = nearestLair(run, x, z, true) or nearestLair(run, x, z, false)
	if lair then
		return State.lairKind(run, lair).grunts
	end
	return if #run.map.roster > 0 then { run.map.roster[1] } else {}
end

-- The lair's boss and guard still alive.
local function occupants(run: Types.Run, lair: Types.Lair): { Types.Enemy }
	local found = {}
	for _, enemy in run.enemies do
		if enemy.lairId == lair.id and Lairs.leashOf(run, enemy) == lair then
			table.insert(found, enemy)
		end
	end
	return found
end

-- Puts the lair's boss at its centre and its guard on a ring around it, drawn
-- in turn from the kind's guards, all asleep.
local function populate(run: Types.Run, lair: Types.Lair)
	local kind = State.lairKind(run, lair)
	local boss = Lairs.spawnKind(run, kind.boss, lair.x, lair.z)
	boss.lairId = lair.id
	boss.asleep = true
	lair.bossId = boss.id
	lair.guardIds = {}
	if #kind.guards == 0 then
		return
	end
	for index = 1, kind.guardCount do
		local angle = lair.rotation + (index - 1) * 2 * math.pi / kind.guardCount
		local ring = lair.radius * GUARD_RING
		local guard = Lairs.spawnKind(
			run,
			kind.guards[(index - 1) % #kind.guards + 1],
			lair.x + math.cos(angle) * ring,
			lair.z + math.sin(angle) * ring
		)
		guard.lairId = lair.id
		guard.asleep = true
		table.insert(lair.guardIds, guard.id)
	end
end

-- Health and damage to the growth now, keeping the share of health it had.
local function regrow(enemy: Types.Enemy, base: number, healthFactor: number, damageFactor: number)
	local share = if enemy.maxHealth > 0 then enemy.health / enemy.maxHealth else 1
	enemy.maxHealth = base * healthFactor
	enemy.health = share * enemy.maxHealth
	enemy.damageFactor = damageFactor
end

-- Wakes the lair: its boss and guard together, grown to the run time, their
-- first attack and contact after the horde's contactFirstSeconds.
function Lairs.wake(run: Types.Run, lair: Types.Lair)
	if not lair.asleep then
		return
	end
	lair.asleep = false
	local horde = run.config.horde
	local p = Lairs.progress(run)
	local boss = Lairs.bossGrowth(run)
	for _, enemy in occupants(run, lair) do
		local kind = State.kind(run, enemy)
		enemy.asleep = false
		if State.isBoss(kind) then
			regrow(enemy, kind.health, boss, boss)
		else
			regrow(enemy, kind.health, 1 + horde.healthGrowth * p, 1 + horde.damageGrowth * p)
		end
		enemy.attackReadyAt = math.max(enemy.attackReadyAt, run.time + horde.contactFirstSeconds)
		enemy.contactReadyAt = math.max(enemy.contactReadyAt, run.time + horde.contactFirstSeconds)
	end
	table.insert(run.events, { kind = "lairWoke", lairId = lair.id })
end

-- Wakes the lair of an asleep enemy that took damage.
function Lairs.wakeFor(run: Types.Run, enemy: Types.Enemy)
	local lairId = enemy.lairId
	if not enemy.asleep or lairId == nil then
		return
	end
	local lair = State.lairById(run, lairId)
	if lair then
		Lairs.wake(run, lair)
	end
end

-- Puts the lair back to sleep: the boss and guard stop where they stand, their
-- attacks and damage over time drop, and the boss regains sleepRecoverShare of
-- its missing health.
local function sleep(run: Types.Run, lair: Types.Lair)
	lair.asleep = true
	for _, enemy in occupants(run, lair) do
		enemy.asleep = true
		enemy.state = "chase"
		enemy.target = nil
		enemy.dots = {}
		if State.isBoss(State.kind(run, enemy)) then
			enemy.health += (enemy.maxHealth - enemy.health) * run.config.lairs.sleepRecoverShare
		end
	end
	table.insert(run.events, { kind = "lairSlept", lairId = lair.id })
end

-- The lair's boss is dead (Damage.kill): the lair is silenced for good, its
-- killer gets the great offer, and the last lair's fall starts the final
-- boss's rise there, unless doom has begun. Its guard fights on until dead.
function Lairs.silence(run: Types.Run, lair: Types.Lair, killer: number)
	if lair.silenced then
		return
	end
	lair.silenced = true
	lair.asleep = false
	lair.bossId = nil
	lair.owed = 0
	table.insert(run.events, { kind = "lairSilenced", lairId = lair.id, player = killer })
	local player = run.players[killer]
	if player and player.state == "alive" then
		Cards.offer(run, player, run.config.shrines.greatOfferRanks)
	end
	for _, other in run.lairs do
		if not other.silenced then
			return
		end
	end
	if run.doom or run.finalBossId ~= nil or run.finalRiseAt ~= nil then
		return
	end
	local seconds = run.config.lairs.finalRiseSeconds
	run.finalRiseAt = run.time + seconds
	run.finalRiseX, run.finalRiseZ = lair.x, lair.z
	table.insert(run.events, {
		kind = "finalRising",
		lairId = lair.id,
		x = lair.x,
		z = lair.z,
		seconds = seconds,
	})
end

-- The batch the lair releases now: batchStart growing to batchEnd over the
-- run's duration, plus what its strays are owed, held to the alive cap; its
-- grunts drawn in turn from a random first kind, around its centre.
local function release(run: Types.Run, lair: Types.Lair)
	local lairs = run.config.lairs
	local kind = State.lairKind(run, lair)
	local size = math.floor(
		lairs.batchStart + (lairs.batchEnd - lairs.batchStart) * Lairs.progress(run) + 0.5
	) + lair.owed
	lair.owed = 0
	local count = math.min(size, math.max(run.config.horde.maxAlive - Lairs.aliveCount(run), 0))
	if count <= 0 or #kind.grunts == 0 then
		return
	end
	local first = run.rng:integer(1, #kind.grunts)
	for index = 1, count do
		local kindId = kind.grunts[(first + index - 2) % #kind.grunts + 1]
		local angle = run.rng:next() * 2 * math.pi
		local distance = lair.radius * (RELEASE_MIN + (RELEASE_MAX - RELEASE_MIN) * run.rng:next())
		local grunt = Lairs.spawnKind(
			run,
			kindId,
			lair.x + math.cos(angle) * distance,
			lair.z + math.sin(angle) * distance
		)
		grunt.lairId = lair.id
	end
end

-- Removes every released grunt farther than strayDespawnDistance from every
-- alive hero; its lair is owed it in the next batch, up to batchEnd.
local function despawnStrays(run: Types.Run, players: { Types.Player })
	local lairs = run.config.lairs
	local limit2 = lairs.strayDespawnDistance * lairs.strayDespawnDistance
	for index = #run.enemies, 1, -1 do
		local enemy = run.enemies[index]
		local lairId = enemy.lairId
		if lairId == nil or State.kind(run, enemy).role ~= "grunt" then
			continue
		end
		local near = false
		for _, player in players do
			local dx, dz = enemy.x - player.x, enemy.z - player.z
			if dx * dx + dz * dz <= limit2 then
				near = true
				break
			end
		end
		if not near then
			table.remove(run.enemies, index)
			local lair = State.lairById(run, lairId)
			if lair and not lair.silenced then
				lair.owed = math.min(lair.owed + 1, lairs.batchEnd)
			end
		end
	end
end

-- Doom's wraiths: wraith.count on a ring around every alive hero, evenly
-- spaced from a random bearing, on free ground; no growth.
local function spawnWraiths(run: Types.Run, players: { Types.Player })
	local wraith = run.config.lairs.wraith
	local radius = run.config.enemies[wraith.kind].radius
	for _, player in players do
		local phase = run.rng:next() * 2 * math.pi
		for index = 1, wraith.count do
			local angle = phase + (index - 1) * 2 * math.pi / wraith.count
			local x, z = Arena.freeSpot(
				run.arena,
				player.x + math.cos(angle) * wraith.ringRadius,
				player.z + math.sin(angle) * wraith.ringRadius,
				radius,
				run.rng,
				FREE_SPOT_TRIES
			)
			State.newEnemy(run, wraith.kind, x, z, 1, 1)
		end
	end
end

local function anyWithin(players: { Types.Player }, x: number, z: number, radius: number): boolean
	for _, player in players do
		if Geometry.distance(player.x, player.z, x, z) <= radius then
			return true
		end
	end
	return false
end

-- The lairs for this step: their boss and guard at the first step, doom from
-- the run's end time, the final boss when its rise ends, waking and sleeping,
-- the batches, the strays and the wraiths. Nothing is released while no hero
-- is alive.
function Lairs.update(run: Types.Run, _dt: number)
	for _, lair in run.lairs do
		if not lair.silenced and lair.bossId == nil then
			populate(run, lair)
		end
	end

	local config = run.config
	if not run.doom and run.time >= config.run.durationSeconds then
		run.doom = true
		-- The final boss no longer comes.
		run.finalRiseAt = nil
		run.nextWraithAt = run.time
		table.insert(run.events, { kind = "doomStarted" })
	end

	local players = State.alivePlayers(run)
	if #players == 0 then
		return
	end

	local riseAt = run.finalRiseAt
	if riseAt ~= nil and run.time >= riseAt then
		run.finalRiseAt = nil
		local boss = Lairs.spawnKind(run, run.map.finalBoss, run.finalRiseX, run.finalRiseZ)
		run.finalBossId = boss.id
		table.insert(run.events, {
			kind = "bossSpawned",
			enemyId = boss.id,
			enemyKind = boss.kind,
			final = true,
		})
	end

	for _, lair in run.lairs do
		if lair.silenced then
			continue
		end
		if lair.asleep then
			if anyWithin(players, lair.x, lair.z, lair.radius) then
				Lairs.wake(run, lair)
			end
		elseif not anyWithin(players, lair.x, lair.z, Lairs.reach(lair)) then
			sleep(run, lair)
		end
		if not run.doom and run.finalRiseAt == nil and run.time >= lair.nextBatchAt then
			release(run, lair)
			-- One batch per step at most: a long step does not queue a backlog.
			local interval = State.lairKind(run, lair).intervalSeconds
			lair.nextBatchAt += interval
			if lair.nextBatchAt <= run.time then
				lair.nextBatchAt = run.time + interval
			end
		end
	end

	despawnStrays(run, players)

	if run.doom and run.time >= run.nextWraithAt then
		spawnWraiths(run, players)
		run.nextWraithAt += config.lairs.wraith.intervalSeconds
		if run.nextWraithAt <= run.time then
			run.nextWraithAt = run.time + config.lairs.wraith.intervalSeconds
		end
	end
end

return Lairs
