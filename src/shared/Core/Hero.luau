--!strict
-- The hero's body: stats from the class and passives, damage taken through
-- the barrier and armour, heals, knockback and the three utility skills.

local Arena = require("./Arena")
local Geometry = require("./Geometry")
local State = require("./State")
local Types = require("./Types")

local Hero = {}

-- The class's numbers with the player's passives applied.
function Hero.stats(run: Types.Run, player: Types.Player): Types.HeroStats
	local config = run.config
	local class = config.classes[player.class]

	-- Each stat's sum of perRank × rank over the passives that raise it.
	local sums: { [Types.Stat]: number } = {}
	for id, rank in player.passives do
		local passive = config.passives[id]
		if passive ~= nil and rank > 0 then
			sums[passive.stat] = (sums[passive.stat] or 0) + passive.perRank * rank
		end
	end
	-- Boons and pacts add to the same shares (GLOSSARY: boon, pact).
	local function sum(stat: Types.Stat): number
		return (sums[stat] or 0) + (player.shrineShares[stat] or 0)
	end

	return {
		damage = 1 + sum("damage"),
		maxHealth = class.maxHealth * (1 + sum("maxHealth")),
		speed = class.walkSpeed * (1 + sum("speed")),
		regeneration = sum("regeneration"),
		haste = sum("haste"),
		area = 1 + sum("area"),
		pickupRange = config.player.pickupRange * (1 + sum("pickupRange")),
		experience = 1 + sum("experience"),
		armour = sum("armour"),
		critChance = config.player.baseCritChance + sum("critChance"),
	}
end

-- Studs per second the hero may walk now, with a sprint running and slowed
-- in the shallows (ADR-0023): by `slow`, else by the slow factor where the
-- hero stands.
function Hero.walkSpeed(run: Types.Run, player: Types.Player, slow: number?): number
	local speed = Hero.stats(run, player).speed
	if player.sprintUntil > run.time then
		speed *= player.sprintFactor
	end
	return speed * (slow or Arena.slowFactor(run.arena, run.config.terrain, player.x, player.z))
end

-- Whether nothing can hurt the hero now: a dash is under way (GLOSSARY: dash).
function Hero.untouchable(run: Types.Run, player: Types.Player): boolean
	return player.dashUntil > run.time
end

-- Dashes in direction (dx, dz): config.player.dashDistance over dashSeconds,
-- carried like a knockback and stopped by obstacles and the wall, untouchable
-- for the dash. Returns false with no charge, while dead, or with no direction
-- (one too short, or too long, to normalise).
function Hero.dash(run: Types.Run, player: Types.Player, dx: number, dz: number): boolean
	local config = run.config.player
	if player.state ~= "alive" or player.dashCharges < 1 then
		return false
	end
	local length = math.sqrt(dx * dx + dz * dz)
	if not (length >= 1e-9 and length < math.huge) then
		return false
	end
	local nx, nz = dx / length, dz / length
	if player.dashCharges == config.dashCharges then
		player.dashReadyAt = run.time + config.dashCooldownSeconds
	end
	player.dashCharges -= 1
	player.dashUntil = run.time + config.dashSeconds
	player.facing = math.atan2(nz, nx)
	player.knockX = nx * config.dashDistance / config.dashSeconds
	player.knockZ = nz * config.dashDistance / config.dashSeconds
	player.knockUntil = player.dashUntil
	table.insert(run.events, {
		kind = "dash",
		player = player.id,
		dx = nx * config.dashDistance,
		dz = nz * config.dashDistance,
	})
	return true
end

-- Damages an alive hero by `amount` (the attacker's multipliers already in):
-- the barrier absorbs first, armour cuts what is left down to minDamage. A hit
-- interrupts the extraction spell's cast and a shrine's hold, not the chest
-- opening (the horde made the chest unopenable; decided on 2026-10-28).
-- Nothing lands on an untouchable hero. `reflected` is the thorns the
-- caller returns to the attacker.
function Hero.damage(
	run: Types.Run,
	player: Types.Player,
	amount: number,
	enemyId: number?
): { taken: number, reflected: number }
	if player.state ~= "alive" or amount <= 0 or Hero.untouchable(run, player) then
		return { taken = 0, reflected = 0 }
	end

	local absorbed = 0
	if player.barrierUntil > run.time and player.barrier > 0 then
		absorbed = math.min(player.barrier, amount)
		player.barrier -= absorbed
	end
	local left = amount - absorbed
	local taken = 0
	if left > 0 then
		taken = math.max(left - Hero.stats(run, player).armour, run.config.player.minDamage)
		player.health -= taken
	end
	player.hurtAt = run.time
	table.insert(run.events, {
		kind = "playerHurt",
		player = player.id,
		amount = taken,
		enemyId = enemyId,
		absorbed = absorbed,
	})

	if player.castingUntil ~= nil then
		player.castingUntil = nil
		table.insert(run.events, { kind = "castInterrupted", player = player.id })
	end
	player.shrineProgress = 0

	local reflected = if player.thornsUntil > run.time then player.thorns else 0

	if player.health <= 0 then
		player.health = 0
		player.state = "dead"
		table.insert(run.events, { kind = "died", player = player.id })
	end
	return { taken = taken, reflected = reflected }
end

-- Heals an alive hero by up to `amount`, never above max health.
function Hero.heal(run: Types.Run, player: Types.Player, amount: number)
	if player.state ~= "alive" or amount <= 0 then
		return
	end
	local maxHealth = Hero.stats(run, player).maxHealth
	local healed = math.min(amount, maxHealth - player.health)
	if healed <= 0 then
		return
	end
	player.health += healed
	table.insert(run.events, { kind = "healed", player = player.id, amount = healed })
end

-- Pushes an alive hero by (dx, dz) studs over config.player.knockbackSeconds.
function Hero.knock(run: Types.Run, player: Types.Player, dx: number, dz: number)
	if player.state ~= "alive" or (dx == 0 and dz == 0) then
		return
	end
	local seconds = run.config.player.knockbackSeconds
	player.knockX = dx / seconds
	player.knockZ = dz / seconds
	player.knockUntil = run.time + seconds
	table.insert(run.events, { kind = "knockback", player = player.id, dx = dx, dz = dz })
end

-- Fires utility button `index`. Returns false when the player cannot use it now.
-- Raises a barrier of `amount` for `seconds`: a barrier already up keeps
-- whatever is larger, its absorb and its time, so a utility and a shield
-- skill never cut each other down.
function Hero.raiseBarrier(run: Types.Run, player: Types.Player, amount: number, seconds: number)
	local active = player.barrierUntil > run.time and player.barrier > 0
	player.barrier = if active then math.max(player.barrier, amount) else amount
	player.barrierUntil = math.max(if active then player.barrierUntil else 0, run.time + seconds)
end

function Hero.useUtility(run: Types.Run, playerId: number, index: number): boolean
	local player = run.players[playerId]
	local utility = run.config.utilities[index]
	if
		player == nil
		or player.state ~= "alive"
		or utility == nil
		or (player.utilityReadyAt[index] or 0) > run.time
	then
		return false
	end

	if utility.kind == "sprint" then
		player.sprintUntil = run.time + (utility.seconds or 0)
		player.sprintFactor = utility.factor or 1
	elseif utility.kind == "barrier" then
		Hero.raiseBarrier(run, player, utility.amount or 0, utility.seconds or 0)
	elseif utility.kind == "heal" then
		Hero.heal(run, player, utility.amount or 0)
	end
	player.utilityReadyAt[index] = run.time + utility.cooldownSeconds
	table.insert(run.events, { kind = "utility", player = player.id, utility = utility.id })
	return true
end

-- Regeneration and heals over time, the barrier's end and knockback, once a step.
function Hero.update(run: Types.Run, dt: number)
	local radius = run.config.player.radius
	for _, player in State.sortedPlayers(run) do
		if player.state ~= "alive" then
			continue
		end

		-- Regeneration and a heal skill's pending health, as one heal a step.
		local amount = Hero.stats(run, player).regeneration * dt
		if player.healPending > 0 then
			local drained = math.min(player.healPending, player.healRate * dt)
			player.healPending -= drained
			amount += drained
			if player.healPending <= 0 then
				player.healPending = 0
				player.healRate = 0
			end
		end
		if amount > 0 then
			Hero.heal(run, player, amount)
		end

		if player.barrier > 0 and player.barrierUntil <= run.time then
			player.barrier = 0
		end

		-- One dash charge back per cooldown, the next cooldown from then.
		local dashConfig = run.config.player
		while player.dashCharges < dashConfig.dashCharges and player.dashReadyAt <= run.time do
			player.dashCharges += 1
			player.dashReadyAt += dashConfig.dashCooldownSeconds
		end

		-- The last step of a knockback covers only what is left of it; an
		-- obstacle on the way stops the push there.
		local knockLeft = math.clamp(player.knockUntil - (run.time - dt), 0, dt)
		if knockLeft > 0 then
			local toX = player.x + player.knockX * knockLeft
			local toZ = player.z + player.knockZ * knockLeft
			local reach = Arena.reach(run.arena, player.x, player.z, toX, toZ, radius)
			local x, z = Geometry.stepToward(player.x, player.z, toX, toZ, reach)
			player.x, player.z = Arena.clamp(run.arena, x, z, radius)
		end
	end
end

return Hero
