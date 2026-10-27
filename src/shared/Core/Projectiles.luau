--!strict
-- Projectiles in flight: a hero's bolts homing on their target and enemy
-- shots flying straight. A bolt hits when it reaches its target, or lands
-- where it is when the target is gone; an enemy shot hurts the hero it
-- touches and with a radius bursts there or where its flight ends. Obstacles
-- never block a shot.

local Damage = require("./Damage")
local Geometry = require("./Geometry")
local Hero = require("./Hero")
local State = require("./State")
local Targeting = require("./Targeting")
local Types = require("./Types")

local Projectiles = {}

local function remove(run: Types.Run, projectile: Types.Projectile)
	local index = table.find(run.projectiles, projectile)
	if index then
		table.remove(run.projectiles, index)
	end
end

local function burstEvent(run: Types.Run, projectile: Types.Projectile)
	table.insert(run.events, {
		kind = "burst",
		x = projectile.x,
		z = projectile.z,
		radius = projectile.radius,
		skill = projectile.kind,
	})
end

local function hitOf(projectile: Types.Projectile, amount: number): Damage.Hit
	return {
		source = projectile.source,
		skill = projectile.kind,
		amount = amount,
		tags = projectile.tags,
		effect = projectile.effect,
		critChance = projectile.critChance,
		knockback = projectile.knockback,
		fromX = projectile.x,
		fromZ = projectile.z,
	}
end

-- A hero's bolt lands: on `struck` with its splash, or with no enemy struck
-- as a splash alone.
local function landBolt(run: Types.Run, projectile: Types.Projectile, struck: Types.Enemy?)
	burstEvent(run, projectile)
	if struck then
		Damage.splash(run, struck, hitOf(projectile, projectile.damage), projectile.radius)
	elseif projectile.radius > 0 then
		local amount = projectile.damage * run.config.ranks.splashShare
		for _, enemy in Targeting.within(run, projectile.x, projectile.z, projectile.radius) do
			Damage.hit(run, enemy, hitOf(projectile, amount))
		end
	end
end

-- An enemy shot bursts: every alive hero within its radius is hurt and
-- pushed away from the point.
local function burstOnPlayers(run: Types.Run, projectile: Types.Projectile)
	burstEvent(run, projectile)
	local reach = projectile.radius + run.config.player.radius
	for _, player in State.alivePlayers(run) do
		if Geometry.distance(projectile.x, projectile.z, player.x, player.z) <= reach then
			Hero.damage(run, player, projectile.damage, projectile.source)
			if projectile.knockback > 0 then
				local dx, dz = Geometry.normalize(player.x - projectile.x, player.z - projectile.z)
				Hero.knock(run, player, dx * projectile.knockback, dz * projectile.knockback)
			end
		end
	end
end

local function touchedPlayer(run: Types.Run, x: number, z: number): Types.Player?
	local reach = run.config.player.radius + run.config.projectiles.touchMargin
	local best: Types.Player? = nil
	local bestDistance = math.huge
	for _, player in State.alivePlayers(run) do
		local distance = Geometry.distance(x, z, player.x, player.z)
		if distance <= reach and distance < bestDistance then
			best = player
			bestDistance = distance
		end
	end
	return best
end

local function touchedEnemy(run: Types.Run, x: number, z: number): Types.Enemy?
	local margin = run.config.projectiles.touchMargin
	local best: Types.Enemy? = nil
	local bestDistance = math.huge
	for _, enemy in run.enemies do
		local distance = Geometry.distance(x, z, enemy.x, enemy.z)
		if distance <= State.kind(run, enemy).radius + margin and distance < bestDistance then
			best = enemy
			bestDistance = distance
		end
	end
	return best
end

-- A hero's bolt: homing on its target, or straight without one. Returns true
-- when it landed.
local function stepPlayer(run: Types.Run, projectile: Types.Projectile, dt: number): boolean
	local travel = math.min(projectile.remaining, projectile.speed * dt)
	local targetId = projectile.targetId
	if targetId ~= nil then
		local target = State.enemyById(run, targetId)
		if target == nil then
			landBolt(run, projectile, nil)
			return true
		end
		local x, z = Geometry.stepToward(projectile.x, projectile.z, target.x, target.z, travel)
		projectile.dirX, projectile.dirZ = Geometry.normalize(x - projectile.x, z - projectile.z)
		projectile.x, projectile.z = x, z
		projectile.remaining -= travel
		local reach = State.kind(run, target).radius + run.config.projectiles.touchMargin
		if Geometry.distance(x, z, target.x, target.z) <= reach then
			landBolt(run, projectile, target)
			return true
		end
	else
		projectile.x += projectile.dirX * travel
		projectile.z += projectile.dirZ * travel
		projectile.remaining -= travel
		local struck = touchedEnemy(run, projectile.x, projectile.z)
		if struck then
			landBolt(run, projectile, struck)
			return true
		end
	end
	if projectile.remaining <= 1e-9 then
		landBolt(run, projectile, nil)
		return true
	end
	return false
end

-- An enemy shot flying straight. Returns true when it landed.
local function stepEnemy(run: Types.Run, projectile: Types.Projectile, dt: number): boolean
	local travel = math.min(projectile.remaining, projectile.speed * dt)
	projectile.x += projectile.dirX * travel
	projectile.z += projectile.dirZ * travel
	projectile.remaining -= travel
	local player = touchedPlayer(run, projectile.x, projectile.z)
	if player then
		if projectile.radius > 0 then
			burstOnPlayers(run, projectile)
		else
			Hero.damage(run, player, projectile.damage, projectile.source)
			if projectile.knockback > 0 then
				Hero.knock(
					run,
					player,
					projectile.dirX * projectile.knockback,
					projectile.dirZ * projectile.knockback
				)
			end
		end
		return true
	end
	if projectile.remaining <= 1e-9 then
		if projectile.radius > 0 then
			burstOnPlayers(run, projectile)
		end
		return true
	end
	return false
end

-- Moves every projectile by speed × dt and lands those that arrive.
function Projectiles.step(run: Types.Run, dt: number)
	-- Landing removes projectiles from the list being walked.
	for _, projectile in table.clone(run.projectiles) do
		local landed = if projectile.owner == "player"
			then stepPlayer(run, projectile, dt)
			else stepEnemy(run, projectile, dt)
		if landed then
			remove(run, projectile)
		end
	end
end

return Projectiles
