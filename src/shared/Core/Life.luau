--!strict
-- Player health and body: damage, knockback, downed, revive and death,
-- potions and pickups.

local Geometry = require("./Geometry")
local Map = require("./Map")
local Perks = require("./Perks")
local State = require("./State")
local Types = require("./Types")

local Life = {}

-- Stage 2a: anyone alive may revive anyone downed. Stage 3 restricts it to allies.
local function canRevive(_run: Types.Run, _reviver: Types.Player, _downed: Types.Player): boolean
	return true
end

-- The nearest alive player within revive range, holding the interact button,
-- who may revive `downed`.
local function findReviver(run: Types.Run, downed: Types.Player): Types.Player?
	local radius = run.config.player.reviveRadius
	local best: Types.Player? = nil
	local bestDistance = math.huge
	-- Ascending ids, so a tie goes to the lowest id on every run.
	for _, other in State.sortedPlayers(run) do
		if other.state == "alive" and other.interacting and canRevive(run, other, downed) then
			local distance = Geometry.distance(other.x, other.z, downed.x, downed.z)
			if distance <= radius and distance < bestDistance then
				best = other
				bestDistance = distance
			end
		end
	end
	return best
end

-- Damages an alive player; at zero health the player is downed. `enemyId`
-- names the attacker when one did it.
function Life.damage(run: Types.Run, player: Types.Player, amount: number, enemyId: number?)
	if player.state ~= "alive" or amount <= 0 then
		return
	end
	player.health -= amount
	-- Damage interrupts extraction, drinking, and reviving (see Life.update).
	player.extractProgress = 0
	player.hurtAt = run.time
	if player.drinkingUntil ~= nil then
		player.drinkingUntil = nil
		table.insert(run.events, { kind = "drinkInterrupted", player = player.id })
	end
	table.insert(
		run.events,
		{ kind = "playerHurt", player = player.id, amount = amount, enemyId = enemyId }
	)

	if player.health <= 0 then
		player.health = 0
		player.state = "downed"
		player.downedAt = run.time
		player.reviveProgress = 0
		table.insert(run.events, { kind = "downed", player = player.id })
	end
end

-- Pushes an alive player `studs` away from (fromX, fromZ), over
-- config.player.knockbackSeconds.
function Life.knockPlayer(
	run: Types.Run,
	player: Types.Player,
	fromX: number,
	fromZ: number,
	studs: number
)
	if player.state ~= "alive" or studs <= 0 then
		return
	end
	local seconds = run.config.player.knockbackSeconds
	local dx, dz = Geometry.normalize(player.x - fromX, player.z - fromZ)
	player.knockX = dx * studs / seconds
	player.knockZ = dz * studs / seconds
	player.knockUntil = run.time + seconds
	table.insert(
		run.events,
		{ kind = "knockback", player = player.id, dx = dx * studs, dz = dz * studs }
	)
end

-- The player's potion capacity after perks.
function Life.potionCapacity(run: Types.Run, player: Types.Player): number
	return math.floor(
		Perks.playerValue(run.config, player, "potionCapacity", run.config.player.potionCapacity)
	)
end

-- Starts drinking a potion. Returns false when the player cannot drink now.
function Life.drink(run: Types.Run, playerId: number): boolean
	local player = run.players[playerId]
	if
		player == nil
		or player.state ~= "alive"
		or player.potions <= 0
		or player.drinkingUntil ~= nil
	then
		return false
	end
	player.drinkingUntil = run.time + run.config.player.drinkSeconds
	table.insert(run.events, { kind = "drinking", player = player.id })
	return true
end

-- Moves knocked players, finishes drinks, takes pickups.
local function updateBodies(run: Types.Run, dt: number)
	local config = run.config.player
	for _, player in State.sortedPlayers(run) do
		if player.state ~= "alive" then
			continue
		end

		-- The last step of a knockback covers only what is left of it.
		local knockLeft = math.clamp(player.knockUntil - (run.time - dt), 0, dt)
		if knockLeft > 0 then
			-- Water or a prop on the way stops the push there.
			local toX = player.x + player.knockX * knockLeft
			local toZ = player.z + player.knockZ * knockLeft
			local reach = Map.reach(run.map, player.x, player.z, toX, toZ)
			local x, z = Geometry.stepToward(player.x, player.z, toX, toZ, reach)
			x, z = Map.clamp(run.map, x, z)
			-- The run carries the player; the character is pulled along by the
			-- server if the client does not move it itself.
			player.x, player.z = x, z
		end

		local drinkingUntil = player.drinkingUntil
		if drinkingUntil and run.time >= drinkingUntil then
			player.drinkingUntil = nil
			player.potions -= 1
			local amount = Perks.playerValue(run.config, player, "potionHeal", config.potionHeal)
			amount = math.min(amount, player.maxHealth - player.health)
			player.health += amount
			table.insert(run.events, { kind = "drank", player = player.id, amount = amount })
		end

		if player.potions < Life.potionCapacity(run, player) then
			for index, pickup in run.pickups do
				if
					Geometry.distance(player.x, player.z, pickup.x, pickup.z) <= config.pickupRadius
				then
					table.remove(run.pickups, index)
					player.potions += 1
					table.insert(
						run.events,
						{ kind = "pickedUp", player = player.id, pickup = pickup.kind }
					)
					break
				end
			end
		end
	end
end

-- Advances revives and bleeding out of downed players by `dt`.
local function updateDowned(run: Types.Run, dt: number)
	local config = run.config.player
	for _, player in State.sortedPlayers(run) do
		local downedAt = player.downedAt
		if player.state == "downed" and downedAt then
			local reviver = findReviver(run, player)
			-- A reviver hit this step starts the revive over.
			if reviver and reviver.hurtAt < run.time then
				player.reviveProgress += dt
				-- Bleeding out pauses while someone is reviving.
				player.downedAt = downedAt + dt
				if player.reviveProgress >= config.reviveSeconds then
					player.state = "alive"
					player.health = player.maxHealth * config.reviveHealthFraction
					player.downedAt = nil
					player.reviveProgress = 0
					table.insert(
						run.events,
						{ kind = "revived", player = player.id, by = reviver.id }
					)
				end
			else
				player.reviveProgress = 0
				if run.time - downedAt >= config.downedSeconds then
					player.state = "dead"
					table.insert(run.events, { kind = "died", player = player.id })
				end
			end
		end
	end
end

function Life.update(run: Types.Run, dt: number)
	updateBodies(run, dt)
	updateDowned(run, dt)
end

return Life
