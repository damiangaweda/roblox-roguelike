--!strict
-- What every enemy does in one step (ADR-0004): notice players, chase them,
-- wind up an attack the players can read, land it, recover, and walk home when
-- the chase ends. Enemies are plain data; nothing here moves a Humanoid.

local Geometry = require("./Geometry")
local Life = require("./Life")
local Map = require("./Map")
local State = require("./State")
local Types = require("./Types")

local Enemies = {}

-- Spots a wanderer draws before it waits for the next draw.
local WANDER_DRAWS = 8

-- Per-step lookups shared by every enemy: the alive players by ascending id,
-- and the enemies by id (a heal reaches its camp through camp.members).
type Context = {
	players: { Types.Player },
	byId: { [number]: Types.Enemy },
}

-- Faces (x, z); an enemy standing on it keeps its facing.
local function face(enemy: Types.Enemy, x: number, z: number)
	local dx, dz = x - enemy.x, z - enemy.z
	if dx ~= 0 or dz ~= 0 then
		enemy.facing = Geometry.angle(dx, dz)
	end
end

-- Whether `enemy` notices `player`: alive and within the detection range,
-- which cover halves. The map is open: nothing else hides a player.
function Enemies.detects(run: Types.Run, enemy: Types.Enemy, player: Types.Player): boolean
	if player.state ~= "alive" then
		return false
	end
	local range = State.archetype(run, enemy).detectionRange
	if player.inCover then
		range *= run.config.enemies.coverDetectionFactor
	end
	return Geometry.distance(enemy.x, enemy.z, player.x, player.z) <= range
end

-- The nearest alive player the enemy notices; a tie goes to the lowest id.
local function nearestDetected(run: Types.Run, enemy: Types.Enemy, context: Context): Types.Player?
	local best: Types.Player? = nil
	local bestDistance = math.huge
	for _, player in context.players do
		if Enemies.detects(run, enemy, player) then
			local distance = Geometry.distance(enemy.x, enemy.z, player.x, player.z)
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

-- Wakes the camp's idle members against `targetId`; the event fires only the
-- first time, until the camp calms down.
function Enemies.alertCamp(run: Types.Run, camp: Types.Camp, targetId: number)
	for _, id in table.clone(camp.members) do
		local member = State.enemyById(run, id)
		if member and member.state == "idle" then
			member.state = "chase"
			member.target = targetId
		end
	end
	if not camp.alerted then
		camp.alerted = true
		table.insert(run.events, { kind = "campAlerted", campId = camp.id })
	end
end

-- A hit wakes the enemy against whoever dealt it, and its camp with it: an
-- enemy shot from beyond its detection range still reacts. A returning enemy
-- turns back; a telegraph or recovery in progress is not interrupted.
function Enemies.provoke(run: Types.Run, enemy: Types.Enemy, playerId: number)
	local player = run.players[playerId]
	if player == nil or player.state ~= "alive" then
		return
	end
	local state = enemy.state
	if state == "idle" or state == "patrol" or state == "return" then
		if state ~= "return" and enemy.patrolId then
			enemy.homeX, enemy.homeZ = enemy.x, enemy.z
		end
		enemy.state = "chase"
		enemy.target = playerId
		enemy.stuckSince = nil
	end
	local camp = if enemy.campId then State.campById(run, enemy.campId) else nil
	if camp and run.config.enemies.campAlerts then
		Enemies.alertCamp(run, camp, playerId)
	end
end

-- The camp is quiet again once every living member stands idle at home.
local function calmCamp(run: Types.Run, enemy: Types.Enemy, context: Context)
	local camp = if enemy.campId then State.campById(run, enemy.campId) else nil
	if camp == nil or not camp.alerted then
		return
	end
	for _, id in camp.members do
		local member = context.byId[id]
		if member and member.state ~= "idle" then
			return
		end
	end
	camp.alerted = false
end

-- The enemy a heal reaches: its camp's living members, or itself alone.
local function campMembers(run: Types.Run, enemy: Types.Enemy, context: Context): { Types.Enemy }
	local camp = if enemy.campId then State.campById(run, enemy.campId) else nil
	if camp == nil then
		return { enemy }
	end
	local members: { Types.Enemy } = {}
	for _, id in camp.members do
		local member = context.byId[id]
		if member then
			table.insert(members, member)
		end
	end
	return members
end

local function hurtMemberInRadius(
	run: Types.Run,
	enemy: Types.Enemy,
	attack: Types.AttackConfig,
	context: Context
): boolean
	for _, member in campMembers(run, enemy, context) do
		if
			member.health < member.maxHealth
			and Geometry.distance(enemy.x, enemy.z, member.x, member.z) <= attack.radius
		then
			return true
		end
	end
	return false
end

-- Moves one step toward (toX, toZ) along the map's paths or around what
-- blocks the way, kept on walkable ground. Returns whether the map found a
-- way on; when it does not, the enemy stays.
local function walkToward(
	run: Types.Run,
	enemy: Types.Enemy,
	toX: number,
	toZ: number,
	step: number
): boolean
	local wx, wz = Map.waypointToward(run.map, enemy.x, enemy.z, toX, toZ)
	if wx == enemy.x and wz == enemy.z then
		return false
	end
	local x, z = Geometry.stepToward(enemy.x, enemy.z, wx, wz, step)
	enemy.x, enemy.z = Map.clamp(run.map, x, z)
	return true
end

-- Whether an enemy that found no way on has been stuck for giveUpSeconds;
-- records when it got stuck, and forgets it once a way is found.
local function givesUp(run: Types.Run, enemy: Types.Enemy, found: boolean): boolean
	if found then
		enemy.stuckSince = nil
		return false
	end
	local since = enemy.stuckSince or run.time
	enemy.stuckSince = since
	return run.time - since >= run.config.enemies.giveUpSeconds
end

-- Ends a chase: the enemy walks home.
local function giveUpChase(enemy: Types.Enemy)
	enemy.state = "return"
	enemy.target = nil
	enemy.stuckSince = nil
end

-- Starts the telegraph of the current attack: the aim is locked now, so a
-- player can leave the marked area before the attack lands.
local function beginTelegraph(
	run: Types.Run,
	enemy: Types.Enemy,
	attack: Types.AttackConfig,
	target: Types.Player
)
	enemy.state = "telegraph"
	enemy.stateUntil = run.time + attack.telegraphSeconds
	enemy.aimX, enemy.aimZ = target.x, target.z
	face(enemy, target.x, target.z)

	local x, z, radius = enemy.x, enemy.z, attack.radius
	if attack.kind == "projectile" then
		x, z, radius = enemy.aimX, enemy.aimZ, math.max(attack.radius, 1)
	end
	table.insert(run.events, {
		kind = "telegraph",
		enemyId = enemy.id,
		attack = enemy.attack,
		x = x,
		z = z,
		radius = radius,
		seconds = attack.telegraphSeconds,
	})
end

-- Lands the current attack. Returns whether the attack removed the enemy.
local function land(run: Types.Run, enemy: Types.Enemy, context: Context): boolean
	local config = run.config
	local archetype = State.archetype(run, enemy)
	local attack = archetype.attacks[enemy.attack]
	local damage = attack.damage
	if run.time < enemy.buffedUntil then
		damage *= config.enemies.buffDamageFactor
	end
	local reach = attack.radius + config.player.radius

	if attack.kind == "melee" then
		table.insert(run.events, {
			kind = "enemyAttack",
			enemyId = enemy.id,
			archetype = enemy.archetype,
			attack = enemy.attack,
			x = enemy.x,
			z = enemy.z,
		})
		for _, player in context.players do
			if
				player.state == "alive"
				and Geometry.distance(enemy.x, enemy.z, player.x, player.z) <= reach
				and Geometry.inArc(
					enemy.x,
					enemy.z,
					enemy.facing,
					attack.arcDegrees or 360,
					player.x,
					player.z
				)
			then
				Life.damage(run, player, damage, enemy.id)
				Life.knockPlayer(run, player, enemy.x, enemy.z, attack.knockback)
			end
		end
	elseif attack.kind == "projectile" then
		table.insert(run.events, {
			kind = "enemyAttack",
			enemyId = enemy.id,
			archetype = enemy.archetype,
			attack = enemy.attack,
			x = enemy.x,
			z = enemy.z,
		})
		local dx, dz = enemy.aimX - enemy.x, enemy.aimZ - enemy.z
		-- Aimed at its own feet, it shoots the way it faces.
		local base = if dx * dx + dz * dz < 1e-6 then enemy.facing else Geometry.angle(dx, dz)
		local count = attack.projectileCount or 1
		local spread = math.rad(attack.spreadDegrees or 0)
		for index = 1, count do
			local offset = 0
			if count > 1 then
				offset = -spread / 2 + (index - 1) * spread / (count - 1)
			end
			local angle = base + offset
			table.insert(run.projectiles, {
				id = run.nextProjectileId,
				owner = "enemy",
				source = enemy.id,
				kind = enemy.archetype,
				x = enemy.x,
				z = enemy.z,
				dirX = math.cos(angle),
				dirZ = math.sin(angle),
				speed = attack.projectileSpeed or 0,
				-- Flies on past a miss, then lands.
				remaining = attack.range * config.projectiles.overshoot,
				damage = damage,
				radius = attack.radius,
				knockback = attack.knockback,
				tags = {},
				statusFactor = 1,
			})
			run.nextProjectileId += 1
		end
	elseif attack.kind == "burst" then
		table.insert(run.events, {
			kind = "exploded",
			enemyId = enemy.id,
			x = enemy.x,
			z = enemy.z,
			radius = attack.radius,
		})
		for _, player in context.players do
			if
				player.state == "alive"
				and Geometry.distance(enemy.x, enemy.z, player.x, player.z) <= reach
			then
				Life.damage(run, player, damage, enemy.id)
				Life.knockPlayer(run, player, enemy.x, enemy.z, attack.knockback)
			end
		end
		if archetype.diesOnAttack then
			-- Nobody killed it: no kill event, no experience.
			State.removeEnemy(run, enemy)
			return true
		end
	else
		for _, member in campMembers(run, enemy, context) do
			if Geometry.distance(enemy.x, enemy.z, member.x, member.z) <= attack.radius then
				local gained = math.min(member.maxHealth - member.health, attack.heal or 0)
				member.health += gained
				member.buffedUntil = run.time + (attack.buffSeconds or 0)
				table.insert(
					run.events,
					{ kind = "healed", enemyId = member.id, by = enemy.id, amount = gained }
				)
			end
		end
	end
	return false
end

-- The telegraph is over: land the attack, then start the cooldown and recovery.
local function finishTelegraph(run: Types.Run, enemy: Types.Enemy, context: Context)
	local archetype = State.archetype(run, enemy)
	local attack = archetype.attacks[enemy.attack]
	if land(run, enemy, context) then
		return
	end
	enemy.attackReadyAt = run.time + attack.cooldownSeconds
	enemy.attack = enemy.attack % #archetype.attacks + 1
	if attack.recoverSeconds > 0 then
		enemy.state = "recover"
		enemy.stateUntil = run.time + attack.recoverSeconds
	else
		enemy.state = "chase"
	end
end

-- The player chased: the current target while alive, else the nearest noticed.
local function resolveTarget(run: Types.Run, enemy: Types.Enemy, context: Context): Types.Player?
	local current = if enemy.target then run.players[enemy.target] else nil
	if current and current.state == "alive" then
		return current
	end
	return nearestDetected(run, enemy, context)
end

local function chase(
	run: Types.Run,
	enemy: Types.Enemy,
	dt: number,
	speed: number,
	context: Context
)
	local archetype = State.archetype(run, enemy)
	local target = resolveTarget(run, enemy, context)
	if
		target == nil
		or Geometry.distance(enemy.x, enemy.z, enemy.homeX, enemy.homeZ) > archetype.leash
	then
		giveUpChase(enemy)
		return
	end
	enemy.target = target.id
	face(enemy, target.x, target.z)

	local attack = archetype.attacks[enemy.attack]
	local distance = Geometry.distance(enemy.x, enemy.z, target.x, target.z)
	if run.time >= enemy.attackReadyAt then
		-- A shaman starts its heal only when someone needs it.
		local ready = if attack.kind == "heal"
			then hurtMemberInRadius(run, enemy, attack, context)
			else distance <= attack.range
		if ready then
			beginTelegraph(run, enemy, attack, target)
			return
		end
	end

	local step = speed * dt
	local found = true
	if archetype.preferredRange and distance < archetype.preferredRange then
		local nx, nz = Geometry.normalize(enemy.x - target.x, enemy.z - target.z)
		enemy.x, enemy.z = Map.clamp(run.map, enemy.x + nx * step, enemy.z + nz * step)
	elseif distance > attack.range * run.config.enemies.approachFactor then
		-- Never closer than touching.
		local gap = archetype.radius + run.config.player.radius
		local allowed = math.min(step, math.max(0, distance - gap))
		if allowed > 0 then
			found = walkToward(run, enemy, target.x, target.z, allowed)
		end
	end
	-- A target the map finds no way to (across water) ends the chase as the
	-- leash does.
	if givesUp(run, enemy, found) then
		giveUpChase(enemy)
	end
end

local function walkHome(
	run: Types.Run,
	enemy: Types.Enemy,
	speed: number,
	dt: number,
	context: Context
)
	local config = run.config.enemies
	if Geometry.distance(enemy.x, enemy.z, enemy.homeX, enemy.homeZ) <= config.arriveDistance then
		-- Back in formation, healed, and ready to notice again.
		enemy.x, enemy.z = enemy.homeX, enemy.homeZ
		enemy.health = math.max(enemy.health, enemy.maxHealth * config.returnHealFraction)
		enemy.target = nil
		enemy.stuckSince = nil
		enemy.state = if enemy.patrolId then "patrol" else "idle"
		calmCamp(run, enemy, context)
		return
	end
	face(enemy, enemy.homeX, enemy.homeZ)
	-- With no way home for giveUpSeconds, where it stands becomes its home,
	-- so it does not stand in the return forever, blind to players.
	if givesUp(run, enemy, walkToward(run, enemy, enemy.homeX, enemy.homeZ, speed * dt)) then
		enemy.homeX, enemy.homeZ = enemy.x, enemy.z
	end
end

-- Sends the patrol on to a neighbour of its point, not back where it came
-- from unless the point is a dead end.
local function advancePatrol(run: Types.Run, patrol: Types.Patrol)
	local point = run.map.points[patrol.routePoint]
	local options: { number } = {}
	for _, neighbour in point.neighbours do
		if neighbour ~= patrol.previousPoint then
			table.insert(options, neighbour)
		end
	end
	if #options == 0 then
		options = point.neighbours
	end
	if #options == 0 then
		return
	end
	local next = if #options > 1 then options[run.rng:integer(1, #options)] else options[1]
	patrol.previousPoint = patrol.routePoint
	patrol.routePoint = next
end

-- Sends a wanderer to a walkable spot drawn within wanderRadius of (x, z),
-- or keeps it where it stands when no draw is walkable, until wanderSeconds
-- pass.
local function drawWanderSpot(run: Types.Run, patrol: Types.Patrol, x: number, z: number)
	local patrols = run.config.enemies.patrols
	patrol.wanderX, patrol.wanderZ = x, z
	patrol.wanderUntil = run.time + patrols.wanderSeconds
	for _ = 1, WANDER_DRAWS do
		local angle = run.rng:next() * 2 * math.pi
		-- Uniform over the disc, not bunched at its centre.
		local radius = patrols.wanderRadius * math.sqrt(run.rng:next())
		local sx, sz = x + math.cos(angle) * radius, z + math.sin(angle) * radius
		if Map.walkable(run.map, sx, sz) then
			patrol.wanderX, patrol.wanderZ = sx, sz
			return
		end
	end
end

-- A wanderer roams the open ground: to its spot, then to a new one drawn
-- where it arrived, or drawn where it stands once wanderSeconds pass.
local function wanderWalk(
	run: Types.Run,
	enemy: Types.Enemy,
	patrol: Types.Patrol,
	speed: number,
	dt: number,
	arriveDistance: number
)
	local arrived = Geometry.distance(enemy.x, enemy.z, patrol.wanderX, patrol.wanderZ)
		<= arriveDistance
	if patrol.members[1] == enemy.id and (arrived or run.time >= patrol.wanderUntil) then
		drawWanderSpot(run, patrol, enemy.x, enemy.z)
	end
	if Geometry.distance(enemy.x, enemy.z, patrol.wanderX, patrol.wanderZ) > arriveDistance then
		face(enemy, patrol.wanderX, patrol.wanderZ)
		walkToward(run, enemy, patrol.wanderX, patrol.wanderZ, speed * dt)
	end
end

local function patrolWalk(
	run: Types.Run,
	enemy: Types.Enemy,
	speed: number,
	dt: number,
	arriveDistance: number
)
	local patrol = if enemy.patrolId then State.patrolById(run, enemy.patrolId) else nil
	if patrol == nil then
		return
	end
	if patrol.wanders then
		wanderWalk(run, enemy, patrol, speed, dt, arriveDistance)
		return
	end
	local point = run.map.points[patrol.routePoint]
	-- One member decides where the patrol goes next, so it stays together.
	if
		patrol.members[1] == enemy.id
		and Geometry.distance(enemy.x, enemy.z, point.x, point.z) <= arriveDistance
	then
		advancePatrol(run, patrol)
		point = run.map.points[patrol.routePoint]
	end
	enemy.routePoint = patrol.routePoint
	if Geometry.distance(enemy.x, enemy.z, point.x, point.z) > arriveDistance then
		face(enemy, point.x, point.z)
		walkToward(run, enemy, point.x, point.z, speed * dt)
	end
end

local function stepEnemy(run: Types.Run, enemy: Types.Enemy, dt: number, context: Context)
	local config = run.config

	-- The last step of a knockback covers only what is left of it.
	local knockLeft = math.clamp(enemy.knockUntil - (run.time - dt), 0, dt)
	if knockLeft > 0 then
		-- Water or a prop on the way stops the push there.
		local toX = enemy.x + enemy.knockX * knockLeft
		local toZ = enemy.z + enemy.knockZ * knockLeft
		local reach = Map.reach(run.map, enemy.x, enemy.z, toX, toZ)
		local x, z = Geometry.stepToward(enemy.x, enemy.z, toX, toZ, reach)
		enemy.x, enemy.z = Map.clamp(run.map, x, z)
		-- A telegraph in progress still lands on time; nothing else is decided.
		if enemy.state == "telegraph" and run.time >= enemy.stateUntil then
			finishTelegraph(run, enemy, context)
		end
		return
	end

	local speed = State.archetype(run, enemy).speed
	if run.time < enemy.chilledUntil then
		speed *= 1 - config.statuses.chillSlow
	end
	if run.time < enemy.buffedUntil then
		speed *= config.enemies.buffSpeedFactor
	end

	local state = enemy.state
	if state == "idle" or state == "patrol" then
		local found = nearestDetected(run, enemy, context)
		if found then
			enemy.state = "chase"
			enemy.target = found.id
			-- A patrol member's or a wanderer's leash starts where it noticed
			-- the player.
			if enemy.patrolId then
				enemy.homeX, enemy.homeZ = enemy.x, enemy.z
			end
			local camp = if enemy.campId then State.campById(run, enemy.campId) else nil
			if camp and config.enemies.campAlerts then
				Enemies.alertCamp(run, camp, found.id)
			end
		elseif state == "patrol" then
			patrolWalk(run, enemy, speed, dt, config.enemies.arriveDistance)
		end
	elseif state == "chase" then
		chase(run, enemy, dt, speed, context)
	elseif state == "telegraph" then
		face(enemy, enemy.aimX, enemy.aimZ)
		if run.time >= enemy.stateUntil then
			finishTelegraph(run, enemy, context)
		end
	elseif state == "recover" then
		if run.time >= enemy.stateUntil then
			enemy.state = "chase"
		end
	else
		walkHome(run, enemy, speed, dt, context)
	end
end

-- Pushes overlapping enemies apart, half the overlap each. Neighbours come from
-- a grid of separationRadius cells, so the cost stays near linear.
local function separate(run: Types.Run)
	local enemies = run.enemies
	local radius = run.config.enemies.separationRadius
	if #enemies < 2 or radius <= 0 then
		return
	end

	local cells: { [number]: { number } } = {}
	local cellX: { number } = {}
	local cellZ: { number } = {}
	for index, enemy in enemies do
		local cx, cz = math.floor(enemy.x / radius), math.floor(enemy.z / radius)
		cellX[index], cellZ[index] = cx, cz
		local key = cx * 100003 + cz
		local cell = cells[key]
		if cell == nil then
			cell = {}
			cells[key] = cell
		end
		table.insert(cell, index)
	end

	-- Displacements are summed from the positions at the start of the pass.
	local pushX: { number } = table.create(#enemies, 0)
	local pushZ: { number } = table.create(#enemies, 0)
	for i, enemy in enemies do
		for ox = -1, 1 do
			for oz = -1, 1 do
				local cell = cells[(cellX[i] + ox) * 100003 + (cellZ[i] + oz)]
				if cell == nil then
					continue
				end
				for _, j in cell do
					if j <= i then
						continue
					end
					local other = enemies[j]
					local dx, dz = enemy.x - other.x, enemy.z - other.z
					local distance = math.sqrt(dx * dx + dz * dz)
					if distance >= radius then
						continue
					end
					-- Enemies on the same spot split along x.
					local nx, nz = 1, 0
					if distance > 1e-9 then
						nx, nz = dx / distance, dz / distance
					end
					local half = (radius - distance) / 2
					pushX[i] += nx * half
					pushZ[i] += nz * half
					pushX[j] -= nx * half
					pushZ[j] -= nz * half
				end
			end
		end
	end

	-- A crowd must not fling one enemy far: cap each push at the radius.
	for index, enemy in enemies do
		local px, pz = pushX[index], pushZ[index]
		local length = math.sqrt(px * px + pz * pz)
		if length > radius then
			px, pz = px / length * radius, pz / length * radius
		end
		enemy.x += px
		enemy.z += pz
	end
end

-- Advances every enemy by `dt` seconds: knockback, behaviour, separation, and
-- back onto walkable ground.
function Enemies.step(run: Types.Run, dt: number)
	local players: { Types.Player } = {}
	for _, player in State.sortedPlayers(run) do
		if player.state == "alive" then
			table.insert(players, player)
		end
	end
	local byId: { [number]: Types.Enemy } = {}
	for _, enemy in run.enemies do
		byId[enemy.id] = enemy
	end
	local context: Context = { players = players, byId = byId }

	-- An exploder removes itself from run.enemies mid-pass.
	for _, enemy in table.clone(run.enemies) do
		stepEnemy(run, enemy, dt, context)
	end

	separate(run)
	for _, enemy in run.enemies do
		enemy.x, enemy.z = Map.clamp(run.map, enemy.x, enemy.z)
	end
end

return Enemies
