--!strict
-- The horde around the party (ADR-0014): grunts and elites spawned on a ring
-- around a hero, their number, kinds and strength rising with run time; the
-- bosses on the clock and the final boss at the end (ADR-0015); a closing
-- ring halfway before each boss; strays moved back in front of the heroes.
-- Bosses never count toward the alive target.

local Arena = require("./Arena")
local Geometry = require("./Geometry")
local State = require("./State")
local Types = require("./Types")

local Horde = {}

-- Draws a spawn spends looking for free ground next to an obstacle.
local FREE_SPOT_TRIES = 8

-- How far the run is through its duration: 0 at the start, 1 from the end on.
function Horde.progress(run: Types.Run): number
	return math.min(run.time / run.config.run.durationSeconds, 1)
end

-- Grunts and elites wanted alive now.
function Horde.aliveTarget(run: Types.Run): number
	local horde = run.config.horde
	return math.min(
		horde.maxAlive,
		math.floor(horde.aliveAtStart + horde.aliveGrowth * Horde.progress(run))
	)
end

-- The window of adjacent roster kinds spawning now, weakest first
-- (GLOSSARY: roster).
function Horde.windowKinds(run: Types.Run): { string }
	local horde = run.config.horde
	local roster = run.map.roster
	local size = math.min(horde.windowSize, #roster)
	local step = math.floor(run.time / horde.windowStepSeconds)
	local span = #roster - size
	local lo = math.min(math.floor(math.max(step - 1, 0) * span / horde.windowSteps), span)
	local kinds = {}
	for index = lo + 1, lo + size do
		table.insert(kinds, roster[index])
	end
	return kinds
end

-- An enemy of `kindId` near (x, z) with the horde's growth for the run time,
-- on free ground inside the edge.
function Horde.spawnKind(run: Types.Run, kindId: string, x: number, z: number): Types.Enemy
	local horde = run.config.horde
	local p = Horde.progress(run)
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

-- Grunts and elites alive: what the alive target and the summon cap count.
function Horde.aliveCount(run: Types.Run): number
	local count = 0
	for _, enemy in run.enemies do
		if not State.isBoss(State.kind(run, enemy)) then
			count += 1
		end
	end
	return count
end

local function randomPlayer(run: Types.Run, players: { Types.Player }): Types.Player
	return players[run.rng:integer(1, #players)]
end

-- A point at `distance` from the player on a random bearing.
local function around(run: Types.Run, player: Types.Player, distance: number): (number, number)
	local angle = run.rng:next() * 2 * math.pi
	return player.x + math.cos(angle) * distance, player.z + math.sin(angle) * distance
end

local function spawnBatch(run: Types.Run, players: { Types.Player })
	local horde = run.config.horde
	local target = Horde.aliveTarget(run)
	local alive = Horde.aliveCount(run)
	if alive >= target then
		return
	end
	local count = math.min(horde.spawnBatchMax, math.ceil((target - alive) / horde.spawnShare))
	local p = Horde.progress(run)
	local eliteShare = horde.eliteShareStart + (horde.eliteShareEnd - horde.eliteShareStart) * p
	local window = Horde.windowKinds(run)
	local elites = run.map.elites
	for _ = 1, count do
		local player = randomPlayer(run, players)
		local distance = horde.ringMin + (horde.ringMax - horde.ringMin) * run.rng:next()
		local x, z = around(run, player, distance)
		local kindId
		if #elites > 0 and run.rng:next() < eliteShare then
			kindId = elites[run.rng:integer(1, #elites)]
		else
			kindId = window[run.rng:integer(1, #window)]
		end
		Horde.spawnKind(run, kindId, x, z)
	end
end

local function spawnBoss(
	run: Types.Run,
	players: { Types.Player },
	kindId: string,
	final: boolean
): Types.Enemy
	local x, z = around(run, randomPlayer(run, players), run.config.horde.bossDistance)
	local boss = Horde.spawnKind(run, kindId, x, z)
	table.insert(run.events, {
		kind = "bossSpawned",
		enemyId = boss.id,
		enemyKind = kindId,
		final = final,
	})
	return boss
end

-- When closing ring `k` comes: halfway between boss k - 1 (or the start) and boss k.
local function ringDue(bosses: { Types.BossScheduleEntry }, k: number): number
	local at = bosses[k].atSeconds
	local previous = if k > 1 then bosses[k - 1].atSeconds else 0
	return at - (at - previous) / 2
end

local function spawnRing(run: Types.Run, players: { Types.Player })
	local horde = run.config.horde
	-- The ring never takes the horde past its cap (the budget of ADR-0004).
	local room = math.max(horde.maxAlive - Horde.aliveCount(run), 0)
	local count = math.min(
		horde.ringCountStart + math.floor(horde.ringCountGrowth * Horde.progress(run)),
		room
	)
	if count == 0 then
		return
	end
	local kindId = Horde.windowKinds(run)[1]
	local player = randomPlayer(run, players)
	local phase = run.rng:next() * 2 * math.pi
	for index = 1, count do
		local angle = phase + (index - 1) * 2 * math.pi / count
		Horde.spawnKind(
			run,
			kindId,
			player.x + math.cos(angle) * horde.ringRadius,
			player.z + math.sin(angle) * horde.ringRadius
		)
	end
	table.insert(run.events, { kind = "closingRing", count = count })
end

-- Moves every enemy farther than strayDistance from every hero to
-- strayReturnDistance beyond the nearest hero, on the side away from where
-- it was, so it walks at them again.
local function returnStrays(run: Types.Run, players: { Types.Player })
	local horde = run.config.horde
	for _, enemy in run.enemies do
		local nearest: Types.Player? = nil
		local nearestDistance = math.huge
		for _, player in players do
			local distance = Geometry.distance(enemy.x, enemy.z, player.x, player.z)
			if distance < nearestDistance then
				nearest, nearestDistance = player, distance
			end
		end
		if nearest == nil or nearestDistance <= horde.strayDistance then
			continue
		end
		local player = nearest :: Types.Player
		local nx, nz = Geometry.normalize(player.x - enemy.x, player.z - enemy.z)
		local radius = State.kind(run, enemy).radius
		enemy.x, enemy.z = Arena.freeSpot(
			run.arena,
			player.x + nx * horde.strayReturnDistance,
			player.z + nz * horde.strayReturnDistance,
			radius,
			run.rng,
			FREE_SPOT_TRIES
		)
		-- A rush toward a point now far away ends.
		if enemy.state == "charge" then
			enemy.state = "chase"
		end
	end
end

-- Spawns, bosses, closing rings and strays for this step. Nothing happens
-- while no hero is alive.
function Horde.update(run: Types.Run, _dt: number)
	local players = State.alivePlayers(run)
	if #players == 0 then
		return
	end
	local config = run.config
	local horde = config.horde

	if run.time >= run.nextSpawnAt then
		spawnBatch(run, players)
		-- One batch per step at most: a long step does not queue a backlog.
		run.nextSpawnAt += horde.spawnIntervalSeconds
		if run.nextSpawnAt <= run.time then
			run.nextSpawnAt = run.time + horde.spawnIntervalSeconds
		end
	end

	local bosses = run.map.bosses
	while run.bossesSpawned < #bosses and bosses[run.bossesSpawned + 1].atSeconds <= run.time do
		run.bossesSpawned += 1
		spawnBoss(run, players, bosses[run.bossesSpawned].kind, false)
	end

	if run.time >= config.run.durationSeconds and run.finalBossId == nil then
		local boss = spawnBoss(run, players, run.map.finalBoss, true)
		run.finalBossId = boss.id
		run.finalBossDeadline = run.time + horde.finalBossSeconds
		table.insert(run.events, { kind = "finalBossTimer", seconds = horde.finalBossSeconds })
	end

	while run.ringsSpawned < #bosses and ringDue(bosses, run.ringsSpawned + 1) <= run.time do
		run.ringsSpawned += 1
		spawnRing(run, players)
	end

	returnStrays(run, players)
end

return Horde
