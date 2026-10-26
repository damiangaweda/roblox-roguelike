--!strict
-- The horde: spawning, movement and contact with players.

local Types = require("./Types")

local Horde = {}

-- Ids of the alive players, ascending, so every pass visits them in one order.
local function aliveIds(run: Types.Run): { number }
	local ids = {}
	for id, player in run.players do
		if player.state == "alive" then
			table.insert(ids, id)
		end
	end
	table.sort(ids)
	return ids
end

local function clampToArena(run: Types.Run, value: number): number
	local half = run.config.arena.halfSize
	return math.clamp(value, -half, half)
end

-- Spawns enemies for `dt` seconds of the run's spawn rate, up to the alive cap.
function Horde.spawn(run: Types.Run, dt: number)
	local config = run.config.horde
	local ids = aliveIds(run)
	if #ids == 0 then
		run.spawnDebt = 0
		return
	end

	local minutes = run.time / 60
	local rate = config.spawnPerSecondAtStart + config.spawnPerSecondGrowthPerMinute * minutes
	run.spawnDebt += rate * dt

	local bruteShare = math.min(
		config.bruteShareMax,
		config.bruteShareAtStart + config.bruteShareGrowthPerMinute * minutes
	)

	while run.spawnDebt >= 1 do
		if #run.enemies >= config.maxAlive then
			-- Full: keep the fraction, so a freed slot does not release a burst.
			run.spawnDebt %= 1
			return
		end
		run.spawnDebt -= 1

		local kind = if run.rng:next() < bruteShare then "brute" else "grunt"
		local target = run.players[ids[run.rng:integer(1, #ids)]]
		local angle = run.rng:next() * 2 * math.pi
		local distance = config.spawnRingMin
			+ run.rng:next() * (config.spawnRingMax - config.spawnRingMin)

		local id = run.nextEnemyId
		run.nextEnemyId += 1
		table.insert(run.enemies, {
			id = id,
			kind = kind,
			x = clampToArena(run, target.x + math.cos(angle) * distance),
			z = clampToArena(run, target.z + math.sin(angle) * distance),
			health = config.kinds[kind].health,
			chilledUntil = 0,
			burningUntil = 0,
			burnSource = nil,
		})
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
		enemy.x = clampToArena(run, enemy.x + px)
		enemy.z = clampToArena(run, enemy.z + pz)
	end
end

-- Moves every enemy toward the nearest alive player, keeping enemies apart.
function Horde.move(run: Types.Run, dt: number)
	local config = run.config
	local ids = aliveIds(run)
	if #ids == 0 then
		return
	end

	for _, enemy in run.enemies do
		local kind = config.horde.kinds[enemy.kind]

		local nearest: Types.Player? = nil
		local nearestSquared = math.huge
		for _, id in ids do
			local player = run.players[id]
			local dx, dz = player.x - enemy.x, player.z - enemy.z
			local squared = dx * dx + dz * dz
			if squared < nearestSquared then
				nearest, nearestSquared = player, squared
			end
		end
		if nearest == nil then
			continue
		end

		local speed = kind.speed
		if run.time < enemy.chilledUntil then
			speed *= 1 - config.statuses.chillSlow
		end

		local distance = math.sqrt(nearestSquared)
		local step = math.min(speed * dt, distance - (kind.radius + run.config.player.radius))
		if step > 0 then
			enemy.x = clampToArena(run, enemy.x + (nearest.x - enemy.x) / distance * step)
			enemy.z = clampToArena(run, enemy.z + (nearest.z - enemy.z) / distance * step)
		end
	end

	separate(run)
end

-- Returns the contact damage each player takes during `dt`, by player id.
function Horde.contact(run: Types.Run, dt: number): { [number]: number }
	local damage: { [number]: number } = {}
	for _, id in aliveIds(run) do
		local player = run.players[id]
		local total = 0
		for _, enemy in run.enemies do
			local kind = run.config.horde.kinds[enemy.kind]
			local reach = kind.radius + run.config.player.radius
			local dx, dz = player.x - enemy.x, player.z - enemy.z
			-- The tolerance covers an enemy that stopped exactly at reach.
			if dx * dx + dz * dz <= reach * reach + 1e-6 then
				total += kind.contactDps * dt
			end
		end
		damage[id] = total
	end
	return damage
end

return Horde
