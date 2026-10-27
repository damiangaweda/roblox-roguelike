--!strict
-- Constructors and lookups for the run's state (ADR-0002). Every entity's id
-- comes from State.nextId, so a seed replays the same ids.

local Arena = require("./Arena")
local Rng = require("./Rng")
local Types = require("./Types")

local State = {}

function State.newRun(config: Types.Config, seed: number): Types.Run
	local map = config.maps[config.map]
	local rng = Rng.new(seed)
	return {
		config = config,
		map = map,
		rng = rng,
		seed = seed,
		time = 0,
		arena = Arena.generate(map, rng),
		nextId = 1,
		enemies = {},
		projectiles = {},
		areas = {},
		totems = {},
		crystals = {},
		foods = {},
		players = {},
		nextSpawnAt = 0,
		bossesSpawned = 0,
		ringsSpawned = 0,
		finalBossId = nil,
		finalBossDeadline = nil,
		chestOpened = false,
		compassOn = false,
		portal = nil,
		paused = false,
		ended = false,
		events = {},
	}
end

function State.nextId(run: Types.Run): number
	local id = run.nextId
	run.nextId += 1
	return id
end

-- A hero of `class` at the start, with the class's starting skill.
function State.newPlayer(run: Types.Run, id: number, class: string): Types.Player
	local classConfig = run.config.classes[class]
	local player: Types.Player = {
		id = id,
		class = class,
		x = run.arena.startX,
		z = run.arena.startZ,
		facing = 0,
		state = "alive",
		health = classConfig.maxHealth,
		level = 1,
		xp = 0,
		skills = {
			{
				id = classConfig.startSkill,
				rank = 1,
				readyAt = run.time + run.config.ranks.firstCooldownSeconds,
			},
		},
		passives = {},
		offers = {},
		utilityReadyAt = {},
		sprintUntil = 0,
		sprintFactor = 1,
		barrier = 0,
		barrierUntil = 0,
		thorns = 0,
		thornsUntil = 0,
		healPending = 0,
		healRate = 0,
		kills = 0,
		moveBudget = classConfig.walkSpeed
			* run.config.player.moveTolerance
			* run.config.player.moveBurstSeconds,
		opening = false,
		openProgress = 0,
		castingUntil = nil,
		hasSpell = false,
		hurtAt = -math.huge,
		knockX = 0,
		knockZ = 0,
		knockUntil = 0,
		damageDone = 0,
	}
	for index = 1, #run.config.utilities do
		player.utilityReadyAt[index] = 0
	end
	run.players[id] = player
	return player
end

-- Players in id order, so a step treats them the same for a seed.
function State.sortedPlayers(run: Types.Run): { Types.Player }
	local players = {}
	for _, player in run.players do
		table.insert(players, player)
	end
	table.sort(players, function(a, b)
		return a.id < b.id
	end)
	return players
end

function State.alivePlayers(run: Types.Run): { Types.Player }
	local alive = {}
	for _, player in State.sortedPlayers(run) do
		if player.state == "alive" then
			table.insert(alive, player)
		end
	end
	return alive
end

function State.kind(run: Types.Run, enemy: Types.Enemy): Types.EnemyKindConfig
	return run.config.enemies[enemy.kind]
end

function State.isBoss(kind: Types.EnemyKindConfig): boolean
	return kind.role == "boss" or kind.role == "finalBoss"
end

-- An enemy of `kindId` at (x, z) with the horde's growth applied: health
-- times healthFactor, attacks and contact damage times damageFactor.
function State.newEnemy(
	run: Types.Run,
	kindId: string,
	x: number,
	z: number,
	healthFactor: number,
	damageFactor: number
): Types.Enemy
	local kind = run.config.enemies[kindId]
	local enemy: Types.Enemy = {
		id = State.nextId(run),
		kind = kindId,
		x = x,
		z = z,
		facing = 0,
		health = kind.health * healthFactor,
		maxHealth = kind.health * healthFactor,
		damageFactor = damageFactor,
		state = "chase",
		stateUntil = 0,
		target = nil,
		attack = 1,
		aimX = x,
		aimZ = z,
		attackReadyAt = run.time + run.config.horde.contactFirstSeconds,
		contactReadyAt = run.time + run.config.horde.contactFirstSeconds,
		slowFactor = 1,
		slowUntil = 0,
		chilledUntil = 0,
		rootedUntil = 0,
		stunnedUntil = 0,
		fearedUntil = 0,
		weakenFactor = 1,
		weakenUntil = 0,
		buffedUntil = 0,
		dots = {},
		knockX = 0,
		knockZ = 0,
		knockUntil = 0,
		phase = 1,
		chargedPlayers = {},
		chargeEndX = x,
		chargeEndZ = z,
		bornAt = run.time,
	}
	table.insert(run.enemies, enemy)
	return enemy
end

function State.enemyById(run: Types.Run, id: number): Types.Enemy?
	for _, enemy in run.enemies do
		if enemy.id == id then
			return enemy
		end
	end
	return nil
end

-- Removes the enemy; callers iterating run.enemies walk a copy or backwards.
function State.removeEnemy(run: Types.Run, enemy: Types.Enemy)
	local index = table.find(run.enemies, enemy)
	if index then
		table.remove(run.enemies, index)
	end
end

return State
