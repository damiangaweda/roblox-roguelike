--!strict
-- Projectiles in flight: player fireballs and enemy spit. Each lands on what
-- it strikes, at a prop or the map's edge, or where its flight ends; it flies
-- over water.

local Combat = require("./Combat")
local Geometry = require("./Geometry")
local Life = require("./Life")
local Map = require("./Map")
local State = require("./State")
local Types = require("./Types")

local Projectiles = {}

-- The longest a projectile moves between two collision checks.
local SUBSTEP = 1

-- An enemy projectile lands at (x, z): with a radius it hurts every alive
-- player in reach, otherwise it vanishes.
local function enemyBurst(run: Types.Run, projectile: Types.Projectile, x: number, z: number)
	if projectile.radius <= 0 then
		return
	end
	table.insert(run.events, {
		kind = "burst",
		x = x,
		z = z,
		radius = projectile.radius,
		skill = projectile.kind,
	})
	local reach = projectile.radius + run.config.player.radius
	for _, player in State.sortedPlayers(run) do
		if player.state == "alive" and Geometry.distance(x, z, player.x, player.z) <= reach then
			Life.damage(run, player, projectile.damage, projectile.source)
			Life.knockPlayer(run, player, x, z, projectile.knockback)
		end
	end
end

-- The alive player nearest to the projectile within touching distance.
local function touchedPlayer(run: Types.Run, x: number, z: number): Types.Player?
	local reach = run.config.player.radius + run.config.projectiles.touchMargin
	local best: Types.Player? = nil
	local bestDistance = math.huge
	for _, player in State.sortedPlayers(run) do
		local d = Geometry.distance(x, z, player.x, player.z)
		if player.state == "alive" and d <= reach and d < bestDistance then
			best = player
			bestDistance = d
		end
	end
	return best
end

local function touchedEnemy(run: Types.Run, x: number, z: number): Types.Enemy?
	local best: Types.Enemy? = nil
	local bestDistance = math.huge
	for _, enemy in run.enemies do
		local d = Geometry.distance(x, z, enemy.x, enemy.z)
		if
			d <= State.archetype(run, enemy).radius + run.config.projectiles.touchMargin
			and d < bestDistance
		then
			best = enemy
			bestDistance = d
		end
	end
	return best
end

-- Checks the projectile at its current point. Returns true when it landed (and
-- did what landing does); the caller removes it.
local function collide(run: Types.Run, projectile: Types.Projectile): boolean
	local x, z = projectile.x, projectile.z
	-- Stopped at a prop or the edge: the flight was cut short by the step.
	local outside = projectile.remaining <= 1e-9

	if projectile.owner == "player" then
		if outside then
			Combat.burst(run, projectile, x, z, nil)
			return true
		end
		local enemy = touchedEnemy(run, x, z)
		if enemy then
			Combat.burst(run, projectile, x, z, enemy)
			return true
		end
		return false
	end

	if outside then
		enemyBurst(run, projectile, x, z)
		return true
	end
	local player = touchedPlayer(run, x, z)
	if player then
		if projectile.radius > 0 then
			enemyBurst(run, projectile, x, z)
		else
			Life.damage(run, player, projectile.damage, projectile.source)
			Life.knockPlayer(run, player, x, z, projectile.knockback)
		end
		return true
	end
	return false
end

-- The end of a flight: it lands where it stopped.
local function expire(run: Types.Run, projectile: Types.Projectile)
	if projectile.owner == "player" then
		Combat.burst(run, projectile, projectile.x, projectile.z, nil)
	else
		enemyBurst(run, projectile, projectile.x, projectile.z)
	end
end

-- Advances every projectile by speed * dt, in sub-steps of at most one stud so
-- a fast one cannot skip a target.
function Projectiles.step(run: Types.Run, dt: number)
	-- Landing removes projectiles from the list being walked.
	for _, projectile in table.clone(run.projectiles) do
		local travel = math.min(projectile.remaining, projectile.speed * dt)
		local steps = math.ceil(travel / SUBSTEP)
		local length = if steps > 0 then travel / steps else 0

		local landed = false
		for _ = 1, steps do
			local lastX, lastZ = projectile.x, projectile.z
			projectile.x += projectile.dirX * length
			projectile.z += projectile.dirZ * length
			projectile.remaining -= length
			-- A prop is hit at the last point before it, so the burst stays on
			-- this side of the prop.
			if Map.blocksShots(run.map, projectile.x, projectile.z) then
				projectile.x, projectile.z = lastX, lastZ
				projectile.remaining = 0
			end
			if collide(run, projectile) then
				landed = true
				break
			end
		end

		if not landed and projectile.remaining <= 1e-9 then
			expire(run, projectile)
			landed = true
		end
		if landed then
			local index = table.find(run.projectiles, projectile)
			if index then
				table.remove(run.projectiles, index)
			end
		end
	end
end

return Projectiles
