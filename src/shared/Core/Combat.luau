--!strict
-- Damage to enemies and the player's skills (ADR-0009): every shape a skill
-- can fire, burning, the synergies and kills. Enemies lose health only here.

local Enemies = require("./Enemies")
local Geometry = require("./Geometry")
local Map = require("./Map")
local Perks = require("./Perks")
local Progression = require("./Progression")
local Skills = require("./Skills")
local State = require("./State")
local Types = require("./Types")

local Combat = {}

local function hasTag(tags: { Types.Tag }, tag: Types.Tag): boolean
	return table.find(tags, tag) ~= nil
end

-- The alive enemy nearest to (x, z) within `range` that `accept` allows. Ties
-- go to the oldest.
local function nearest(
	run: Types.Run,
	x: number,
	z: number,
	range: number,
	accept: (Types.Enemy) -> boolean
): Types.Enemy?
	local best: Types.Enemy? = nil
	local bestDistance = math.huge
	for _, enemy in run.enemies do
		local d = Geometry.distance(x, z, enemy.x, enemy.z)
		if d <= range and d < bestDistance and accept(enemy) then
			best = enemy
			bestDistance = d
		end
	end
	return best
end

-- The enemy's end of a kill: removal, credit, experience and the camp leader's drop.
local function kill(run: Types.Run, enemy: Types.Enemy, source: number?)
	local config = run.config
	local archetype = State.archetype(run, enemy)
	State.removeEnemy(run, enemy)
	table.insert(run.events, {
		kind = "kill",
		source = source or 0,
		enemyId = enemy.id,
		archetype = enemy.archetype,
	})

	local player = if source then run.players[source] else nil
	if player then
		player.kills += 1
		Progression.grantXp(
			run,
			player,
			archetype.xp * Perks.playerValue(config, player, "xpGain", 1)
		)
	end

	if enemy.archetype == config.enemies.campLeader then
		State.newPickup(run, "potion", enemy.x, enemy.z)
		table.insert(run.events, { kind = "dropped", x = enemy.x, z = enemy.z, pickup = "potion" })
	end
end

-- Damages an enemy. `source` is the player credited (nil for an unowned
-- source). `tags` apply statuses. `skill` names the skill for the event.
-- (fromX, fromZ) is where the hit comes from; nil means it cannot be blocked.
-- `statusFactor` multiplies status durations (default 1). Returns true when
-- the enemy died.
function Combat.damageEnemy(
	run: Types.Run,
	enemy: Types.Enemy,
	source: number?,
	amount: number,
	tags: { Types.Tag },
	skill: string,
	fromX: number?,
	fromZ: number?,
	statusFactor: number?
): boolean
	local config = run.config
	local statuses = config.statuses
	local factor = statusFactor or 1

	local blockArc = State.archetype(run, enemy).blockArcDegrees
	if
		blockArc
		and fromX
		and fromZ
		and Geometry.inArc(enemy.x, enemy.z, enemy.facing, blockArc, fromX, fromZ)
	then
		table.insert(run.events, {
			kind = "hit",
			source = source or 0,
			enemyId = enemy.id,
			amount = 0,
			synergy = nil,
			skill = skill,
			blocked = true,
		})
		if source then
			Enemies.provoke(run, enemy, source)
		end
		return false
	end

	-- The synergies read the statuses as they were before this hit's own apply.
	local time = run.time
	local chilled = time < enemy.chilledUntil
	local burning = time < enemy.burningUntil
	local wasBrittle = time < enemy.brittleUntil
	local synergy: string? = nil
	if chilled and hasTag(tags, "fire") then
		local sourcePlayer = if source then run.players[source] else nil
		local bonus = if sourcePlayer
			then Perks.playerValue(config, sourcePlayer, "synergyBonus", 1)
			else 1
		amount *= config.synergy.shatterMultiplier * bonus
		synergy = "shatter"
	end
	if hasTag(tags, "lightning") then
		if burning then
			local spreadUntil = time + statuses.burnSeconds * factor
			for _, other in run.enemies do
				if
					other ~= enemy
					and Geometry.distance(enemy.x, enemy.z, other.x, other.z)
						<= statuses.conductRadius
				then
					other.burningUntil = math.max(other.burningUntil, spreadUntil)
					other.burnSource = source
				end
			end
			synergy = "conduct"
		end
		-- When both apply, brittle is the one reported; the spread still happens.
		if chilled then
			enemy.brittleUntil = time + statuses.brittleSeconds * factor
			synergy = "brittle"
		end
	end

	if wasBrittle then
		amount *= statuses.brittleMultiplier
	end

	enemy.health -= amount
	table.insert(run.events, {
		kind = "hit",
		source = source or 0,
		enemyId = enemy.id,
		amount = amount,
		synergy = synergy,
		skill = skill,
		blocked = false,
	})

	if hasTag(tags, "fire") then
		enemy.burningUntil = time + statuses.burnSeconds * factor
		enemy.burnSource = source
	end
	if hasTag(tags, "ice") then
		enemy.chilledUntil = time + statuses.chillSeconds * factor
	end

	if enemy.health <= 0 then
		kill(run, enemy, source)
		return true
	end
	if source then
		Enemies.provoke(run, enemy, source)
	end
	return false
end

-- Pushes an enemy `studs` away from (fromX, fromZ) over
-- config.player.knockbackSeconds; Enemies.step moves it.
function Combat.knockEnemy(
	run: Types.Run,
	enemy: Types.Enemy,
	fromX: number,
	fromZ: number,
	studs: number
)
	if studs <= 0 then
		return
	end
	local seconds = run.config.player.knockbackSeconds
	local dx, dz = Geometry.normalize(enemy.x - fromX, enemy.z - fromZ)
	enemy.knockX = dx * studs / seconds
	enemy.knockZ = dz * studs / seconds
	enemy.knockUntil = run.time + seconds
end

-- Burning damage over `dt`. Not a hit: no event, no statuses, no block and no
-- synergy; the kill goes to whoever set the enemy alight.
function Combat.burn(run: Types.Run, dt: number)
	local config = run.config
	-- Kills remove enemies from the list being walked.
	for _, enemy in table.clone(run.enemies) do
		if run.time >= enemy.burningUntil then
			continue
		end
		local source = enemy.burnSource
		local owner = if source then run.players[source] else nil
		local amount = config.statuses.burnDps * dt
		if owner then
			amount *= Perks.playerValue(config, owner, "burnDamage", 1)
		end
		if run.time < enemy.brittleUntil then
			amount *= config.statuses.brittleMultiplier
		end
		enemy.health -= amount
		if enemy.health <= 0 then
			kill(run, enemy, source)
		end
	end
end

-- The player's aim: the facing, or with assist on, snapped to the nearest enemy
-- in the assist cone.
function Combat.resolveAim(run: Types.Run, player: Types.Player): number
	if not player.assist then
		return player.facing
	end
	local aim = run.config.aim
	local target = nearest(run, player.x, player.z, aim.assistRange, function(enemy)
		return Geometry.inArc(
			player.x,
			player.z,
			player.facing,
			aim.assistConeDegrees,
			enemy.x,
			enemy.z
		)
	end)
	if target == nil then
		return player.facing
	end
	return Geometry.angle(target.x - player.x, target.z - player.z)
end

-- Knocks an enemy that survived its hit.
local function knockSurvivor(
	run: Types.Run,
	enemy: Types.Enemy,
	died: boolean,
	fromX: number,
	fromZ: number,
	studs: number
)
	if not died then
		Combat.knockEnemy(run, enemy, fromX, fromZ, studs)
	end
end

-- A player projectile lands at (x, z). With a radius it hits everything in
-- reach; without one, only the enemy it struck.
function Combat.burst(
	run: Types.Run,
	projectile: Types.Projectile,
	x: number,
	z: number,
	struck: Types.Enemy?
)
	table.insert(run.events, {
		kind = "burst",
		x = x,
		z = z,
		radius = projectile.radius,
		skill = projectile.kind,
	})

	local victims: { Types.Enemy } = {}
	if projectile.radius > 0 then
		for _, enemy in run.enemies do
			local reach = projectile.radius + State.archetype(run, enemy).radius
			if
				Geometry.distance(x, z, enemy.x, enemy.z) <= reach
				and Map.clearShot(run.map, x, z, enemy.x, enemy.z)
			then
				table.insert(victims, enemy)
			end
		end
	elseif struck then
		table.insert(victims, struck)
	end

	for _, enemy in victims do
		local died = Combat.damageEnemy(
			run,
			enemy,
			projectile.source,
			projectile.damage,
			projectile.tags,
			projectile.kind,
			x,
			z,
			projectile.statusFactor
		)
		knockSurvivor(run, enemy, died, x, z, projectile.knockback)
	end
end

-- Arcane Bolt: a burst along the ray, as far as the first prop.
local function fireLine(
	run: Types.Run,
	player: Types.Player,
	skill: Types.EffectiveSkill,
	aim: number
)
	local dx, dz = math.cos(aim), math.sin(aim)
	local range = Map.shotReach(
		run.map,
		player.x,
		player.z,
		player.x + dx * skill.range,
		player.z + dz * skill.range
	)
	local hits: { { enemy: Types.Enemy, along: number } } = {}
	for _, enemy in run.enemies do
		local relX, relZ = enemy.x - player.x, enemy.z - player.z
		local along = relX * dx + relZ * dz
		local across = math.abs(relX * dz - relZ * dx)
		if
			along >= 0
			and along <= range
			and across <= skill.width / 2 + State.archetype(run, enemy).radius
		then
			table.insert(hits, { enemy = enemy, along = along })
		end
	end
	table.sort(hits, function(a, b)
		if a.along ~= b.along then
			return a.along < b.along
		end
		return a.enemy.id < b.enemy.id
	end)

	for index = 1, math.min(#hits, 1 + math.floor(skill.pierce)) do
		local enemy = hits[index].enemy
		local died = Combat.damageEnemy(
			run,
			enemy,
			player.id,
			skill.damage,
			skill.tags,
			skill.id,
			player.x,
			player.z,
			skill.statusFactor
		)
		knockSurvivor(run, enemy, died, player.x, player.z, skill.knockback)
	end
end

-- Fireball: `count` projectiles fanned over the split spread, centred on aim.
local function fireProjectiles(
	run: Types.Run,
	player: Types.Player,
	skill: Types.EffectiveSkill,
	aim: number,
	aimDistance: number?
)
	local count = math.max(1, math.floor(skill.count + 0.5))
	local spread = math.rad(run.config.perks.splitSpreadDegrees)
	local travel = skill.range
	if aimDistance and aimDistance > 0 then
		travel = math.min(skill.range, aimDistance)
	end
	for index = 1, count do
		local angle = aim
		if count > 1 then
			angle = aim - spread / 2 + spread * (index - 1) / (count - 1)
		end
		table.insert(run.projectiles, {
			id = run.nextProjectileId,
			owner = "player",
			source = player.id,
			kind = skill.id,
			x = player.x,
			z = player.z,
			dirX = math.cos(angle),
			dirZ = math.sin(angle),
			speed = skill.speed,
			remaining = travel,
			damage = skill.damage,
			radius = skill.radius,
			knockback = skill.knockback,
			tags = skill.tags,
			statusFactor = skill.statusFactor,
		})
		run.nextProjectileId += 1
	end
end

-- Frost Nova: everything within reach of the player.
local function fireRing(run: Types.Run, player: Types.Player, skill: Types.EffectiveSkill)
	table.insert(run.events, {
		kind = "burst",
		x = player.x,
		z = player.z,
		radius = skill.radius,
		skill = skill.id,
	})
	local victims: { Types.Enemy } = {}
	for _, enemy in run.enemies do
		local reach = skill.radius + State.archetype(run, enemy).radius
		if
			Geometry.distance(player.x, player.z, enemy.x, enemy.z) <= reach
			and Map.clearShot(run.map, player.x, player.z, enemy.x, enemy.z)
		then
			table.insert(victims, enemy)
		end
	end
	for _, enemy in victims do
		local died = Combat.damageEnemy(
			run,
			enemy,
			player.id,
			skill.damage,
			skill.tags,
			skill.id,
			player.x,
			player.z,
			skill.statusFactor
		)
		knockSurvivor(run, enemy, died, player.x, player.z, skill.knockback)
	end
end

-- Chain Lightning: the nearest enemy in the aim cone, then on to the nearest
-- enemy not yet hit. Returns false when nothing is in the cone, so a miss
-- costs no cooldown.
local function fireChain(
	run: Types.Run,
	player: Types.Player,
	skill: Types.EffectiveSkill,
	aim: number
): boolean
	local cone = skill.coneDegrees
	local target = nearest(run, player.x, player.z, skill.range, function(enemy)
		return Geometry.inArc(player.x, player.z, aim, cone, enemy.x, enemy.z)
			and Map.clearShot(run.map, player.x, player.z, enemy.x, enemy.z)
	end)
	if target == nil then
		return false
	end

	local struck: { [number]: boolean } = {}
	local fromX, fromZ = player.x, player.z
	for _ = 1, math.floor(skill.jumps + 0.5) do
		if target == nil then
			break
		end
		struck[target.id] = true
		-- Read before the hit: a kill removes the enemy.
		local x, z = target.x, target.z
		-- The lightning comes from the previous position, which decides a block.
		Combat.damageEnemy(
			run,
			target,
			player.id,
			skill.damage,
			skill.tags,
			skill.id,
			fromX,
			fromZ,
			skill.statusFactor
		)
		fromX, fromZ = x, z
		target = nearest(run, x, z, skill.jumpRange, function(enemy)
			return not struck[enemy.id] and Map.clearShot(run.map, x, z, enemy.x, enemy.z)
		end)
	end
	return true
end

-- Fires `skill` from the player along `aim`. False when nothing was fired.
local function fire(
	run: Types.Run,
	player: Types.Player,
	skill: Types.EffectiveSkill,
	aim: number,
	aimDistance: number?
): boolean
	if skill.shape == "line" then
		fireLine(run, player, skill, aim)
	elseif skill.shape == "projectile" then
		fireProjectiles(run, player, skill, aim, aimDistance)
	elseif skill.shape == "ring" then
		fireRing(run, player, skill)
	else
		return fireChain(run, player, skill, aim)
	end
	return true
end

-- Fires the basic attack while the input is held and the interval is over. It
-- emits no skillUsed: the client draws its tracers from the hits.
function Combat.fireBasic(run: Types.Run, player: Types.Player)
	if
		player.state ~= "alive"
		or not player.firing
		or player.drinkingUntil ~= nil
		or run.time < player.basicReadyAt
	then
		return
	end
	local config = run.config
	local skill = Skills.effective(config, player, config.classes[player.class].basic, true)
	if fire(run, player, skill, Combat.resolveAim(run, player), nil) then
		player.basicReadyAt = run.time + skill.cooldownSeconds
	end
end

-- Uses active skill number `index`. `aimDistance` is how far the player aimed,
-- which shortens a projectile's flight. Returns false when the skill cannot
-- be used now.
function Combat.useActive(
	run: Types.Run,
	playerId: number,
	index: number,
	aimDistance: number?
): boolean
	local player = run.players[playerId]
	if player == nil or player.state ~= "alive" or player.drinkingUntil ~= nil then
		return false
	end
	local config = run.config
	local actives = config.classes[player.class].actives
	if index % 1 ~= 0 or index < 1 or index > #actives then
		return false
	end
	if run.time < (player.skillReadyAt[index] or 0) then
		return false
	end

	local skill = Skills.effective(config, player, actives[index], false)
	local aim = Combat.resolveAim(run, player)
	if not fire(run, player, skill, aim, aimDistance) then
		return false
	end
	player.skillReadyAt[index] = run.time + skill.cooldownSeconds
	table.insert(run.events, {
		kind = "skillUsed",
		player = player.id,
		skill = skill.id,
		x = player.x,
		z = player.z,
		facing = aim,
	})
	return true
end

return Combat
