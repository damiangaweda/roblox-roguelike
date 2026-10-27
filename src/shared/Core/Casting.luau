--!strict
-- Skills cast themselves (ADR-0013): each owned skill fires when its
-- cooldown is up, at what its targeting picks; with nothing to fire at it
-- retries after retrySeconds without spending the cooldown. Ground areas and
-- totems placed earlier tick here too.

local Arena = require("./Arena")
local Damage = require("./Damage")
local Geometry = require("./Geometry")
local Hero = require("./Hero")
local Skills = require("./Skills")
local State = require("./State")
local Targeting = require("./Targeting")
local Types = require("./Types")

local Casting = {}

local function ids(enemies: { Types.Enemy }): { number }
	local list = {}
	for _, enemy in enemies do
		table.insert(list, enemy.id)
	end
	return list
end

local function announce(
	run: Types.Run,
	player: Types.Player,
	skill: Types.EffectiveSkill,
	fromX: number,
	fromZ: number,
	targetX: number?,
	targetZ: number?,
	targets: { number }
)
	table.insert(run.events, {
		kind = "cast",
		player = player.id,
		skill = skill.id,
		x = fromX,
		z = fromZ,
		targetX = targetX,
		targetZ = targetZ,
		radius = skill.radius,
		targets = targets,
	})
end

-- The skill's hit on one enemy, coming from (fromX, fromZ).
local function hitOf(
	player: Types.Player,
	skill: Types.EffectiveSkill,
	amount: number,
	fromX: number,
	fromZ: number
): Damage.Hit
	return {
		source = player.id,
		skill = skill.id,
		amount = amount,
		tags = skill.tags,
		effect = skill.effect,
		critChance = skill.critChance,
		knockback = skill.knockback,
		fromX = fromX,
		fromZ = fromZ,
	}
end

-- Instant hits on each target from the hero; the first target's position
-- is the cast's aim.
local function strikeAll(
	run: Types.Run,
	player: Types.Player,
	skill: Types.EffectiveSkill,
	targets: { Types.Enemy },
	splashRadius: number,
	aimX: number?,
	aimZ: number?
): boolean
	if #targets == 0 then
		return false
	end
	local first = targets[1]
	announce(run, player, skill, player.x, player.z, aimX or first.x, aimZ or first.z, ids(targets))
	for _, enemy in targets do
		Damage.splash(
			run,
			enemy,
			hitOf(player, skill, skill.damage, player.x, player.z),
			splashRadius
		)
	end
	return true
end

-- A projectile per target, homing on it; Projectiles lands the hit.
local function shoot(
	run: Types.Run,
	player: Types.Player,
	skill: Types.EffectiveSkill,
	targets: { Types.Enemy }
)
	announce(run, player, skill, player.x, player.z, targets[1].x, targets[1].z, ids(targets))
	for _, enemy in targets do
		local dirX, dirZ = Geometry.normalize(enemy.x - player.x, enemy.z - player.z)
		table.insert(run.projectiles, {
			id = State.nextId(run),
			owner = "player",
			source = player.id,
			kind = skill.id,
			x = player.x,
			z = player.z,
			dirX = dirX,
			dirZ = dirZ,
			speed = skill.speed,
			-- A homing shot flies until it arrives or its target is gone.
			remaining = math.huge,
			damage = skill.damage,
			radius = skill.radius,
			knockback = skill.knockback,
			tags = skill.tags,
			effect = skill.effect,
			targetId = enemy.id,
			critChance = skill.critChance,
		})
	end
end

-- One tick of a player's area: every enemy inside is hit from beneath, so a
-- block never stops it.
local function tickPlayerArea(run: Types.Run, area: Types.Area)
	for _, enemy in Targeting.within(run, area.x, area.z, area.radius) do
		Damage.hit(run, enemy, {
			source = area.source,
			skill = area.kind,
			amount = area.damage,
			tags = area.tags,
			effect = area.effect,
			critChance = area.critChance,
			knockback = area.knockback,
			fromX = enemy.x,
			fromZ = enemy.z,
		})
	end
end

-- An area of the skill at (x, z): it ticks for its duration, or with no
-- duration bursts once and leaves its damage over time for burstDotSeconds.
local function placeArea(
	run: Types.Run,
	player: Types.Player,
	skill: Types.EffectiveSkill,
	x: number,
	z: number
)
	local ranks = run.config.ranks
	announce(run, player, skill, player.x, player.z, x, z, {})
	local effect = skill.effect
	local burst = skill.durationSeconds <= 0
	if burst and effect and effect.kind == "dot" then
		local lasting = table.clone(effect)
		lasting.seconds = ranks.burstDotSeconds
		effect = lasting
	end
	local area: Types.Area = {
		id = State.nextId(run),
		owner = "player",
		source = player.id,
		kind = skill.id,
		x = x,
		z = z,
		radius = skill.radius,
		damage = skill.damage,
		until_ = run.time + skill.durationSeconds,
		nextTickAt = run.time + ranks.areaFirstTickSeconds,
		tickSeconds = ranks.areaTickSeconds,
		tags = skill.tags,
		effect = effect,
		critChance = skill.critChance,
		knockback = skill.knockback,
	}
	if burst then
		table.insert(
			run.events,
			{ kind = "burst", x = x, z = z, radius = area.radius, skill = skill.id }
		)
		tickPlayerArea(run, area)
		return
	end
	table.insert(run.areas, area)
	table.insert(run.events, {
		kind = "areaPlaced",
		id = area.id,
		owner = "player",
		areaKind = skill.id,
		x = x,
		z = z,
		radius = area.radius,
		seconds = skill.durationSeconds,
	})
end

-- Tries to fire the skill. Returns false when it had nothing to fire at.
local function fire(
	run: Types.Run,
	player: Types.Player,
	skill: Types.EffectiveSkill,
	stats: Types.HeroStats
): boolean
	local ranks = run.config.ranks
	local x, z = player.x, player.z
	local targeting = skill.targeting

	if targeting == "bolt" then
		local targets = Targeting.nearest(run, x, z, skill.range, skill.count, skill.toughest)
		if #targets == 0 then
			return false
		end
		if skill.speed > 0 then
			shoot(run, player, skill, targets)
			return true
		end
		return strikeAll(run, player, skill, targets, skill.radius)
	elseif targeting == "strike" or targeting == "melee" then
		local targets = Targeting.nearest(run, x, z, skill.range, skill.count, skill.toughest)
		local splash = if targeting == "strike" then skill.radius else 0
		return strikeAll(run, player, skill, targets, splash)
	elseif targeting == "nova" or targeting == "aura" then
		return strikeAll(run, player, skill, Targeting.within(run, x, z, skill.radius), 0, x, z)
	elseif targeting == "cone" then
		local targets = Targeting.cone(run, x, z, skill.radius, ranks.coneHalfAngleDegrees)
		return strikeAll(run, player, skill, targets, 0)
	elseif targeting == "orbit" then
		return strikeAll(
			run,
			player,
			skill,
			Targeting.nearest(run, x, z, skill.radius, skill.count, false),
			0
		)
	elseif targeting == "scatter" then
		local targets = Targeting.scatter(run, x, z, skill.range, skill.count, run.rng)
		return strikeAll(run, player, skill, targets, 0)
	elseif targeting == "chain" then
		local path = Targeting.chain(run, x, z, skill.range, skill.radius, skill.count + 1)
		if #path == 0 then
			return false
		end
		announce(run, player, skill, x, z, path[1].x, path[1].z, ids(path))
		-- The bolt jumps from the previous target, which decides a block.
		local fromX, fromZ = x, z
		for index, enemy in path do
			local nextFromX, nextFromZ = enemy.x, enemy.z
			local amount = skill.damage * ranks.chainFalloff ^ (index - 1)
			Damage.hit(run, enemy, hitOf(player, skill, amount, fromX, fromZ))
			fromX, fromZ = nextFromX, nextFromZ
		end
		return true
	elseif targeting == "ground" then
		local point =
			Targeting.cluster(run, x, z, skill.range, skill.radius, ranks.clusterCandidates)
		if point == nil then
			return false
		end
		placeArea(run, player, skill, point.x, point.z)
		return true
	elseif targeting == "groundSelf" then
		local close = Targeting.nearest(run, x, z, skill.radius + ranks.groundSelfMargin, 1, false)
		if #close == 0 then
			return false
		end
		placeArea(run, player, skill, x, z)
		return true
	elseif targeting == "totem" then
		if #Targeting.nearest(run, x, z, skill.range, 1, false) == 0 then
			return false
		end
		local angle = run.rng:next() * 2 * math.pi
		local totemX, totemZ = Arena.clamp(
			run.arena,
			x + math.cos(angle) * ranks.totemOffset,
			z + math.sin(angle) * ranks.totemOffset,
			0
		)
		local totem: Types.Totem = {
			id = State.nextId(run),
			source = player.id,
			skill = skill.id,
			x = totemX,
			z = totemZ,
			until_ = run.time + skill.durationSeconds,
			nextShotAt = run.time + ranks.totemFirstShotSeconds,
		}
		table.insert(run.totems, totem)
		announce(run, player, skill, x, z, totemX, totemZ, {})
		table.insert(run.events, {
			kind = "totemPlaced",
			id = totem.id,
			skill = skill.id,
			x = totemX,
			z = totemZ,
			seconds = skill.durationSeconds,
		})
		return true
	elseif targeting == "shield" then
		player.barrier = skill.damage
		player.barrierUntil = run.time + skill.durationSeconds
		announce(run, player, skill, x, z, nil, nil, {})
		return true
	elseif targeting == "heal" then
		if player.health >= ranks.healBelowShare * stats.maxHealth or player.healPending > 0 then
			return false
		end
		player.healPending = skill.damage
		player.healRate = if skill.durationSeconds > 0
			then skill.damage / skill.durationSeconds
			else skill.damage
		announce(run, player, skill, x, z, nil, nil, {})
		return true
	elseif targeting == "thorns" then
		if #Targeting.nearest(run, x, z, ranks.thornsTriggerRange, 1, false) == 0 then
			return false
		end
		player.thorns = skill.damage
		player.thornsUntil = run.time + skill.durationSeconds
		announce(run, player, skill, x, z, nil, nil, {})
		return true
	end
	return false
end

-- The skill's numbers for its owner's current rank and stats.
local function effectiveFor(
	run: Types.Run,
	player: Types.Player,
	skillId: string
): Types.EffectiveSkill
	local rank = 1
	for _, owned in player.skills do
		if owned.id == skillId then
			rank = owned.rank
		end
	end
	return Skills.effective(run.config, run.config.skills[skillId], rank, Hero.stats(run, player))
end

local function updateAreas(run: Types.Run)
	local time = run.time
	local config = run.config
	for _, area in table.clone(run.areas) do
		while area.nextTickAt <= time and area.nextTickAt <= area.until_ do
			if area.owner == "player" then
				tickPlayerArea(run, area)
			else
				local reach = area.radius + config.player.radius
				for _, player in State.alivePlayers(run) do
					if Geometry.distance(area.x, area.z, player.x, player.z) <= reach then
						Hero.damage(run, player, area.damage, area.source)
					end
				end
			end
			area.nextTickAt += area.tickSeconds
		end
		if area.until_ <= time then
			local index = table.find(run.areas, area)
			if index then
				table.remove(run.areas, index)
			end
		end
	end
end

local function updateTotems(run: Types.Run)
	local time = run.time
	local ranks = run.config.ranks
	for _, totem in table.clone(run.totems) do
		local owner = run.players[totem.source]
		if owner and owner.state == "alive" then
			while totem.nextShotAt <= time and totem.nextShotAt <= totem.until_ do
				totem.nextShotAt += ranks.totemShotSeconds
				local skill = effectiveFor(run, owner, totem.skill)
				local targets = Targeting.nearest(run, totem.x, totem.z, skill.range, 1, false)
				local target = targets[1]
				if target then
					announce(run, owner, skill, totem.x, totem.z, target.x, target.z, { target.id })
					Damage.hit(run, target, hitOf(owner, skill, skill.damage, totem.x, totem.z))
				end
			end
		end
		if totem.until_ <= time or owner == nil or owner.state ~= "alive" then
			local index = table.find(run.totems, totem)
			if index then
				table.remove(run.totems, index)
			end
		end
	end
end

-- Fires every ready skill of every alive hero, then ticks areas and totems.
function Casting.update(run: Types.Run, _dt: number)
	local config = run.config
	for _, player in State.alivePlayers(run) do
		local stats = Hero.stats(run, player)
		for _, owned in player.skills do
			if owned.readyAt <= run.time and player.state == "alive" then
				local skill = Skills.effective(config, config.skills[owned.id], owned.rank, stats)
				if fire(run, player, skill, stats) then
					owned.readyAt = run.time + skill.cooldownSeconds
				else
					owned.readyAt = run.time + config.ranks.retrySeconds
				end
			end
		end
	end
	updateAreas(run)
	updateTotems(run)
end

return Casting
