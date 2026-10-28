--!strict
-- What every enemy does in one step (ADR-0004, ADR-0014): walk at the nearest
-- hero around the obstacles, hit on contact (grunts) or wind up an attack the
-- players can read, land it and recover (elites and bosses), then push apart
-- from the crowd. Enemies are plain data; nothing here moves a Humanoid.

local Arena = require("./Arena")
local Damage = require("./Damage")
local Geometry = require("./Geometry")
local Hero = require("./Hero")
local Horde = require("./Horde")
local State = require("./State")
local Types = require("./Types")

local Enemies = {}

-- A grunt touches a hero within the two radii and this margin.
-- Draws a leap spends looking for free ground at its aim.
local FREE_SPOT_TRIES = 8
-- How far ahead of a feared or backing-off enemy its walk aims.
local AWAY_LOOK = 10

-- Per-step lookups shared by every enemy: the alive heroes by ascending id.
type Context = {
	players: { Types.Player },
}

local function face(enemy: Types.Enemy, x: number, z: number)
	local dx, dz = x - enemy.x, z - enemy.z
	if dx ~= 0 or dz ~= 0 then
		enemy.facing = Geometry.angle(dx, dz)
	end
end

local function nearestPlayer(enemy: Types.Enemy, context: Context): Types.Player?
	local best: Types.Player? = nil
	local bestDistance = math.huge
	for _, player in context.players do
		if player.state == "alive" then
			local distance = Geometry.distance(enemy.x, enemy.z, player.x, player.z)
			if distance < bestDistance then
				best, bestDistance = player, distance
			end
		end
	end
	return best
end

local function buffed(run: Types.Run, enemy: Types.Enemy): boolean
	return enemy.buffedUntil > run.time
end

-- `base` damage after the horde's growth, a weaken and a shaman's buff.
local function scaled(run: Types.Run, enemy: Types.Enemy, base: number): number
	local buff = if buffed(run, enemy) then run.config.horde.buffDamageFactor else 1
	return base * enemy.damageFactor * enemy.weakenFactor * buff
end

local function speedOf(run: Types.Run, enemy: Types.Enemy, kind: Types.EnemyKindConfig): number
	local speed = kind.speed * enemy.slowFactor
	if buffed(run, enemy) then
		speed *= run.config.horde.buffSpeedFactor
	end
	if enemy.phase == 2 and kind.phaseSpeedFactor then
		speed *= kind.phaseSpeedFactor
	end
	return speed
end

-- The attacks the enemy may use now: before a boss's second phase, those
-- before phaseAttackIndex.
local function available(kind: Types.EnemyKindConfig, enemy: Types.Enemy): number
	if kind.phaseAttackIndex and enemy.phase == 1 then
		return math.min(kind.phaseAttackIndex - 1, #kind.attacks)
	end
	return #kind.attacks
end

local function nextAttack(kind: Types.EnemyKindConfig, enemy: Types.Enemy)
	enemy.attack = enemy.attack % available(kind, enemy) + 1
end

-- Hurts a hero; thorns on the hero return their damage to the enemy.
local function hurt(run: Types.Run, enemy: Types.Enemy, player: Types.Player, amount: number)
	local result = Hero.damage(run, player, amount, enemy.id)
	if result.reflected > 0 and enemy.health > 0 then
		local hit: Damage.Hit = {
			source = player.id,
			skill = "thorns",
			amount = result.reflected,
			tags = { "physical" },
			effect = nil,
			critChance = 0,
			knockback = 0,
			fromX = player.x,
			fromZ = player.z,
		}
		Damage.hit(run, enemy, hit)
	end
end

-- Pushes a hero `studs` away from (fromX, fromZ), or along (dirX, dirZ)
-- when standing on it. A dashing hero is not pushed off their dash.
local function knock(
	run: Types.Run,
	player: Types.Player,
	fromX: number,
	fromZ: number,
	studs: number,
	dirX: number?,
	dirZ: number?
)
	if studs <= 0 or Hero.untouchable(run, player) then
		return
	end
	local dx, dz = player.x - fromX, player.z - fromZ
	if dx * dx + dz * dz < 1e-9 then
		dx, dz = dirX or 1, dirZ or 0
	end
	local nx, nz = Geometry.normalize(dx, dz)
	Hero.knock(run, player, nx * studs, nz * studs)
end

-- Walks up to `step` studs toward (toX, toZ), steering round obstacles and
-- stopped by them and the edge.
local function walk(
	run: Types.Run,
	enemy: Types.Enemy,
	kind: Types.EnemyKindConfig,
	toX: number,
	toZ: number,
	step: number
)
	if step <= 0 then
		return
	end
	local dx, dz = Arena.steer(
		run.arena,
		enemy.x,
		enemy.z,
		toX,
		toZ,
		kind.radius,
		run.config.horde.steerMargin,
		step + kind.radius + 2
	)
	local reach = Arena.reach(
		run.arena,
		enemy.x,
		enemy.z,
		enemy.x + dx * step,
		enemy.z + dz * step,
		kind.radius
	)
	local move = math.min(step, reach)
	enemy.x += dx * move
	enemy.z += dz * move
end

-- Walks `step` studs directly away from (fromX, fromZ).
local function walkAway(
	run: Types.Run,
	enemy: Types.Enemy,
	kind: Types.EnemyKindConfig,
	fromX: number,
	fromZ: number,
	step: number
)
	local nx, nz = Geometry.normalize(enemy.x - fromX, enemy.z - fromZ)
	face(enemy, enemy.x + nx, enemy.z + nz)
	walk(run, enemy, kind, enemy.x + nx * AWAY_LOOK, enemy.z + nz * AWAY_LOOK, step)
end

local function hurtNeighbour(run: Types.Run, enemy: Types.Enemy, radius: number): boolean
	for _, other in run.enemies do
		if
			other.health < other.maxHealth
			and Geometry.distance(enemy.x, enemy.z, other.x, other.z) <= radius
		then
			return true
		end
	end
	return false
end

-- Whether the attack's condition holds: a heal needs someone hurt, a summon
-- room under the cap, everything else the target within range.
local function canStart(
	run: Types.Run,
	enemy: Types.Enemy,
	attack: Types.AttackConfig,
	distance: number
): boolean
	if attack.kind == "heal" then
		return hurtNeighbour(run, enemy, attack.radius)
	elseif attack.kind == "summon" then
		return Horde.aliveCount(run) < run.config.horde.maxAlive
	end
	return distance <= attack.range
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
	local endX: number?, endZ: number? = nil, nil
	if attack.kind == "projectile" then
		x, z, radius = enemy.aimX, enemy.aimZ, math.max(attack.radius, 1)
	elseif attack.kind == "leap" or attack.kind == "ground" then
		x, z = enemy.aimX, enemy.aimZ
	elseif attack.kind == "charge" then
		local nx, nz = Geometry.normalize(enemy.aimX - enemy.x, enemy.aimZ - enemy.z)
		local overshoot = attack.chargeOvershoot or 0
		enemy.chargeEndX = enemy.aimX + nx * overshoot
		enemy.chargeEndZ = enemy.aimZ + nz * overshoot
		endX, endZ = enemy.chargeEndX, enemy.chargeEndZ
	end
	table.insert(run.events, {
		kind = "telegraph",
		enemyId = enemy.id,
		attackKind = attack.kind,
		x = x,
		z = z,
		radius = radius,
		seconds = attack.telegraphSeconds,
		endX = endX,
		endZ = endZ,
	})
end

-- Every alive hero within `radius` (plus the hero's own) of (x, z).
local function burstAt(
	run: Types.Run,
	enemy: Types.Enemy,
	attack: Types.AttackConfig,
	x: number,
	z: number,
	context: Context
)
	local reach = attack.radius + run.config.player.radius
	local damage = scaled(run, enemy, attack.damage)
	for _, player in context.players do
		if player.state == "alive" and Geometry.distance(x, z, player.x, player.z) <= reach then
			hurt(run, enemy, player, damage)
			knock(run, player, x, z, attack.knockback)
		end
	end
end

local function shoot(run: Types.Run, enemy: Types.Enemy, attack: Types.AttackConfig)
	local dx, dz = enemy.aimX - enemy.x, enemy.aimZ - enemy.z
	-- Aimed at its own feet, it shoots the way it faces.
	local base = if dx * dx + dz * dz < 1e-6 then enemy.facing else Geometry.angle(dx, dz)
	local count = attack.projectileCount or 1
	local spread = math.rad(attack.spreadDegrees or 0)
	-- A full circle spaces its shots evenly without doubling the last on the first.
	local gaps = if spread >= 2 * math.pi - 1e-6 then count else count - 1
	local damage = scaled(run, enemy, attack.damage)
	for index = 1, count do
		local offset = 0
		if count > 1 then
			offset = -spread / 2 + (index - 1) * spread / gaps
		end
		local angle = base + offset
		table.insert(run.projectiles, {
			id = State.nextId(run),
			owner = "enemy",
			source = enemy.id,
			kind = enemy.kind,
			x = enemy.x,
			z = enemy.z,
			dirX = math.cos(angle),
			dirZ = math.sin(angle),
			speed = attack.projectileSpeed or 0,
			-- Flies on past a miss, then lands.
			remaining = attack.range * run.config.projectiles.overshoot,
			damage = damage,
			radius = attack.radius,
			knockback = attack.knockback,
			tags = {},
			effect = nil,
			targetId = nil,
			critChance = 0,
		})
	end
end

local function summon(run: Types.Run, enemy: Types.Enemy, attack: Types.AttackConfig)
	-- A summon fills the horde at most up to its cap.
	local count =
		math.min(attack.summonCount or 0, run.config.horde.maxAlive - Horde.aliveCount(run))
	local kindId = Horde.windowKinds(run)[1]
	for index = 1, count do
		local angle = enemy.facing + (index - 1) * 2 * math.pi / count
		Horde.spawnKind(
			run,
			kindId,
			enemy.x + math.cos(angle) * attack.radius,
			enemy.z + math.sin(angle) * attack.radius
		)
	end
end

local function placeGround(run: Types.Run, enemy: Types.Enemy, attack: Types.AttackConfig)
	local seconds = attack.groundSeconds or 0
	local tick = attack.groundTickSeconds or seconds
	local area: Types.Area = {
		id = State.nextId(run),
		owner = "enemy",
		source = enemy.id,
		kind = enemy.kind,
		x = enemy.aimX,
		z = enemy.aimZ,
		radius = attack.radius,
		damage = scaled(run, enemy, attack.damage),
		until_ = run.time + seconds,
		nextTickAt = run.time + tick,
		tickSeconds = tick,
		tags = {},
		effect = nil,
		critChance = 0,
		knockback = attack.knockback,
	}
	table.insert(run.areas, area)
	table.insert(run.events, {
		kind = "areaPlaced",
		id = area.id,
		owner = "enemy",
		areaKind = enemy.kind,
		x = area.x,
		z = area.z,
		radius = area.radius,
		seconds = seconds,
	})
end

local function heal(run: Types.Run, enemy: Types.Enemy, attack: Types.AttackConfig)
	for _, other in run.enemies do
		if Geometry.distance(enemy.x, enemy.z, other.x, other.z) <= attack.radius then
			local gained = math.min(other.maxHealth - other.health, attack.heal or 0)
			other.health += gained
			other.buffedUntil = run.time + (attack.buffSeconds or 0)
			table.insert(
				run.events,
				{ kind = "enemyHealed", enemyId = other.id, by = enemy.id, amount = gained }
			)
		end
	end
end

-- Lands the current attack. Returns whether the enemy is gone (it exploded,
-- or thorns killed it).
local function land(
	run: Types.Run,
	enemy: Types.Enemy,
	kind: Types.EnemyKindConfig,
	attack: Types.AttackConfig,
	context: Context
): boolean
	if attack.kind == "leap" then
		enemy.x, enemy.z =
			Arena.freeSpot(run.arena, enemy.aimX, enemy.aimZ, kind.radius, run.rng, FREE_SPOT_TRIES)
	end
	table.insert(run.events, {
		kind = "enemyAttack",
		enemyId = enemy.id,
		enemyKind = enemy.kind,
		attackKind = attack.kind,
		x = enemy.x,
		z = enemy.z,
		radius = attack.radius,
	})

	if attack.kind == "melee" then
		local reach = attack.radius + run.config.player.radius
		local damage = scaled(run, enemy, attack.damage)
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
				hurt(run, enemy, player, damage)
				knock(run, player, enemy.x, enemy.z, attack.knockback)
			end
		end
	elseif attack.kind == "projectile" then
		shoot(run, enemy, attack)
	elseif attack.kind == "burst" or attack.kind == "leap" then
		burstAt(run, enemy, attack, enemy.x, enemy.z, context)
		if kind.diesOnAttack then
			table.insert(run.events, {
				kind = "exploded",
				enemyId = enemy.id,
				x = enemy.x,
				z = enemy.z,
				radius = attack.radius,
			})
			-- Nobody killed it: no kill event, no experience.
			State.removeEnemy(run, enemy)
			return true
		end
	elseif attack.kind == "heal" then
		heal(run, enemy, attack)
	elseif attack.kind == "summon" then
		summon(run, enemy, attack)
	elseif attack.kind == "ground" then
		placeGround(run, enemy, attack)
	elseif attack.kind == "charge" then
		enemy.chargedPlayers = {}
	end
	return enemy.health <= 0
end

local function cooldownOf(
	kind: Types.EnemyKindConfig,
	enemy: Types.Enemy,
	attack: Types.AttackConfig
): number
	if enemy.phase == 2 and kind.phaseCooldownFactor then
		return attack.cooldownSeconds * kind.phaseCooldownFactor
	end
	return attack.cooldownSeconds
end

local function recover(run: Types.Run, enemy: Types.Enemy, attack: Types.AttackConfig)
	if attack.recoverSeconds > 0 then
		enemy.state = "recover"
		enemy.stateUntil = run.time + attack.recoverSeconds
	else
		enemy.state = "chase"
	end
end

-- The telegraph is over: land the attack, start the cooldown, then recover
-- (a charge rushes first).
local function finishTelegraph(
	run: Types.Run,
	enemy: Types.Enemy,
	kind: Types.EnemyKindConfig,
	context: Context
)
	local attack = kind.attacks[enemy.attack]
	if land(run, enemy, kind, attack, context) then
		return
	end
	enemy.attackReadyAt = run.time + cooldownOf(kind, enemy, attack)
	if attack.kind == "charge" then
		-- The index moves on when the rush ends.
		enemy.state = "charge"
		return
	end
	nextAttack(kind, enemy)
	recover(run, enemy, attack)
end

-- The distance from (px, pz) to the segment from (ax, az) to (bx, bz).
local function segmentDistance(
	px: number,
	pz: number,
	ax: number,
	az: number,
	bx: number,
	bz: number
): number
	local dx, dz = bx - ax, bz - az
	local length2 = dx * dx + dz * dz
	local t = 0
	if length2 > 1e-12 then
		t = math.clamp(((px - ax) * dx + (pz - az) * dz) / length2, 0, 1)
	end
	return Geometry.distance(px, pz, ax + dx * t, az + dz * t)
end

-- One step of a rush along the locked line: hits every hero it passes once,
-- and ends at the end point or against an obstacle or the edge.
local function stepCharge(
	run: Types.Run,
	enemy: Types.Enemy,
	kind: Types.EnemyKindConfig,
	dt: number,
	context: Context
)
	local attack = kind.attacks[enemy.attack]
	local left = Geometry.distance(enemy.x, enemy.z, enemy.chargeEndX, enemy.chargeEndZ)
	local step = math.min((attack.chargeSpeed or 0) * dt, left)
	local reach =
		Arena.reach(run.arena, enemy.x, enemy.z, enemy.chargeEndX, enemy.chargeEndZ, kind.radius)
	local move = math.min(step, reach)
	local nx, nz = Geometry.normalize(enemy.chargeEndX - enemy.x, enemy.chargeEndZ - enemy.z)
	local fromX, fromZ = enemy.x, enemy.z
	enemy.x += nx * move
	enemy.z += nz * move
	face(enemy, enemy.chargeEndX, enemy.chargeEndZ)

	local width = attack.radius + run.config.player.radius
	local damage = scaled(run, enemy, attack.damage)
	for _, player in context.players do
		if
			player.state == "alive"
			and not enemy.chargedPlayers[player.id]
			-- A rush through a dashing hero misses them and may still catch them after.
			and not Hero.untouchable(run, player)
			and segmentDistance(player.x, player.z, fromX, fromZ, enemy.x, enemy.z) <= width
		then
			enemy.chargedPlayers[player.id] = true
			hurt(run, enemy, player, damage)
			knock(run, player, enemy.x, enemy.z, attack.knockback, nx, nz)
			if enemy.health <= 0 then
				return
			end
		end
	end

	local arrived = left - move <= 1e-6
	local blocked = move < step - 1e-6 or (step > 0 and reach <= 1e-6)
	if arrived or blocked or (attack.chargeSpeed or 0) <= 0 then
		nextAttack(kind, enemy)
		recover(run, enemy, attack)
	end
end

-- A telegraph or rush in progress stops: the attack is not spent.
local function interrupt(enemy: Types.Enemy)
	if enemy.state == "telegraph" or enemy.state == "charge" then
		enemy.state = "chase"
	end
end

-- A grunt walks straight at the hero, stops at contact and hits on contact.
local function stepGrunt(
	run: Types.Run,
	enemy: Types.Enemy,
	kind: Types.EnemyKindConfig,
	target: Types.Player,
	dt: number,
	rooted: boolean
)
	local touching = run.config.player.radius + kind.radius
	local distance = Geometry.distance(enemy.x, enemy.z, target.x, target.z)
	face(enemy, target.x, target.z)
	if not rooted and distance > touching + run.config.horde.contactMargin then
		local step = math.min(speedOf(run, enemy, kind) * dt, distance - touching)
		walk(run, enemy, kind, target.x, target.z, step)
		distance = Geometry.distance(enemy.x, enemy.z, target.x, target.z)
	end
	if
		distance <= touching + run.config.horde.contactMargin
		and enemy.contactReadyAt <= run.time
		-- Contact against a dashing hero is not spent: it lands when the dash ends.
		and not Hero.untouchable(run, target)
	then
		enemy.contactReadyAt = run.time + run.config.horde.contactSeconds
		hurt(run, enemy, target, scaled(run, enemy, kind.damage))
	end
end

-- An elite or boss closes to its attack's range (backing off inside its
-- preferred range) and starts the attack when its condition holds.
local function chase(
	run: Types.Run,
	enemy: Types.Enemy,
	kind: Types.EnemyKindConfig,
	target: Types.Player,
	dt: number,
	rooted: boolean
)
	if enemy.attack > available(kind, enemy) then
		enemy.attack = 1
	end
	face(enemy, target.x, target.z)
	local distance = Geometry.distance(enemy.x, enemy.z, target.x, target.z)
	local attack = kind.attacks[enemy.attack]
	if run.time >= enemy.attackReadyAt then
		if canStart(run, enemy, attack, distance) then
			beginTelegraph(run, enemy, attack, target)
			return
		elseif
			(attack.kind == "heal" or attack.kind == "summon") and available(kind, enemy) > 1
		then
			-- A heal or summon with nothing to do does not hold up the others.
			nextAttack(kind, enemy)
			attack = kind.attacks[enemy.attack]
		end
	end
	if rooted then
		return
	end

	local step = speedOf(run, enemy, kind) * dt
	if kind.preferredRange and distance < kind.preferredRange then
		walkAway(run, enemy, kind, target.x, target.z, step)
		face(enemy, target.x, target.z)
	elseif distance > attack.range * run.config.horde.approachFactor then
		-- Never closer than touching.
		local gap = kind.radius + run.config.player.radius
		walk(run, enemy, kind, target.x, target.z, math.min(step, math.max(0, distance - gap)))
	end
end

local function enterPhase(run: Types.Run, enemy: Types.Enemy, kind: Types.EnemyKindConfig)
	if
		kind.phaseHealthShare
		and enemy.phase == 1
		and enemy.health <= kind.phaseHealthShare * enemy.maxHealth
	then
		enemy.phase = 2
		table.insert(run.events, { kind = "bossPhase", enemyId = enemy.id, phase = 2 })
	end
end

local function stepEnemy(run: Types.Run, enemy: Types.Enemy, dt: number, context: Context)
	local kind = State.kind(run, enemy)
	local time = run.time
	enterPhase(run, enemy, kind)

	-- The last step of a knockback covers only what is left of it.
	local knockLeft = math.clamp(enemy.knockUntil - (time - dt), 0, dt)
	if enemy.knockUntil > time or knockLeft > 0 then
		local toX = enemy.x + enemy.knockX * knockLeft
		local toZ = enemy.z + enemy.knockZ * knockLeft
		local reach = Arena.reach(run.arena, enemy.x, enemy.z, toX, toZ, kind.radius)
		local x, z = Geometry.stepToward(enemy.x, enemy.z, toX, toZ, reach)
		enemy.x, enemy.z = Arena.clamp(run.arena, x, z, kind.radius)
		-- A telegraph in progress still lands on time; nothing else is decided.
		if enemy.state == "telegraph" and time >= enemy.stateUntil then
			finishTelegraph(run, enemy, kind, context)
		end
		return
	end

	local stunned = enemy.stunnedUntil > time
	local feared = enemy.fearedUntil > time
	local rooted = stunned or enemy.rootedUntil > time
	if stunned or feared then
		interrupt(enemy)
	elseif rooted and enemy.state == "charge" then
		local attack = kind.attacks[enemy.attack]
		nextAttack(kind, enemy)
		recover(run, enemy, attack)
	end

	local target = nearestPlayer(enemy, context)
	enemy.target = if target then target.id else nil

	if stunned then
		return
	end
	if feared then
		if target and not rooted then
			walkAway(run, enemy, kind, target.x, target.z, speedOf(run, enemy, kind) * dt)
		end
		return
	end

	if #kind.attacks == 0 then
		if target then
			stepGrunt(run, enemy, kind, target, dt, rooted)
		end
		return
	end

	local state = enemy.state
	if state == "telegraph" then
		face(enemy, enemy.aimX, enemy.aimZ)
		if time >= enemy.stateUntil then
			finishTelegraph(run, enemy, kind, context)
		end
	elseif state == "charge" then
		stepCharge(run, enemy, kind, dt, context)
	elseif state == "recover" then
		if time >= enemy.stateUntil then
			enemy.state = "chase"
		end
	elseif target then
		chase(run, enemy, kind, target, dt, rooted)
	end
end

-- Pushes overlapping enemies apart, half the overlap each. Neighbours come from
-- a grid of separationRadius cells, so the cost stays near linear.
local function separate(run: Types.Run)
	local enemies = run.enemies
	local radius = run.config.horde.separationRadius
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

-- Keeps an enemy inside the edge and out of the obstacles: one pushed into
-- an obstacle leaves it along the obstacle's normal.
local function settle(run: Types.Run, enemy: Types.Enemy)
	local radius = State.kind(run, enemy).radius
	enemy.x, enemy.z = Arena.clamp(run.arena, enemy.x, enemy.z, radius)
	local blocker = Arena.blocking(run.arena, enemy.x, enemy.z, radius)
	if blocker then
		local nx, nz = Geometry.normalize(enemy.x - blocker.x, enemy.z - blocker.z)
		local push = blocker.radius + radius + 1e-3
		enemy.x, enemy.z =
			Arena.clamp(run.arena, blocker.x + nx * push, blocker.z + nz * push, radius)
	end
end

-- Advances every enemy by `dt` seconds: knockback, statuses, movement,
-- contact hits and attacks, then separation and back onto free ground.
function Enemies.step(run: Types.Run, dt: number)
	local context: Context = { players = State.alivePlayers(run) }
	-- An exploder or an attacker killed by thorns leaves run.enemies mid-pass,
	-- only ever itself; a summon adds to it.
	for _, enemy in table.clone(run.enemies) do
		if enemy.health > 0 then
			stepEnemy(run, enemy, dt, context)
		end
	end

	separate(run)
	for _, enemy in run.enemies do
		settle(run, enemy)
	end
end

return Enemies
