--!strict
-- Damage to enemies: the basic attack, the skill, burning and the synergy.

local Progression = require("./Progression")
local Types = require("./Types")

local Combat = {}

local function hasTag(tags: { Types.Tag }, tag: Types.Tag): boolean
	return table.find(tags, tag) ~= nil
end

local function distance(ax: number, az: number, bx: number, bz: number): number
	return math.sqrt((ax - bx) ^ 2 + (az - bz) ^ 2)
end

-- The enemy closest to (x, z) within `range`, or nil. Ties go to the oldest.
local function nearestEnemy(run: Types.Run, x: number, z: number, range: number): Types.Enemy?
	local best: Types.Enemy? = nil
	local bestDistance = range
	for _, enemy in run.enemies do
		local d = distance(x, z, enemy.x, enemy.z)
		if d <= bestDistance and (best == nil or d < bestDistance) then
			best = enemy
			bestDistance = d
		end
	end
	return best
end

local function stacks(player: Types.Player, perk: string): number
	return player.perks[perk] or 0
end

local function tagsFor(player: Types.Player, fire: string, ice: string): { Types.Tag }
	local tags: { Types.Tag } = {}
	if stacks(player, fire) > 0 then
		table.insert(tags, "fire")
	end
	if stacks(player, ice) > 0 then
		table.insert(tags, "ice")
	end
	return tags
end

-- The one place enemies lose health. `source` is the player credited with the
-- damage and any kill. A burn tick (`isBurn`) neither emits a hit nor applies
-- statuses, so burning cannot renew itself.
local function damage(
	run: Types.Run,
	enemy: Types.Enemy,
	source: number?,
	amount: number,
	tags: { Types.Tag },
	isActiveSkill: boolean,
	isBurn: boolean
)
	local config = run.config

	-- Checked before this hit's own statuses apply, so a bolt that is both fire
	-- and ice does not shatter its own chill.
	local synergy = hasTag(tags, "fire") and run.time < enemy.chilledUntil
	if synergy then
		amount *= config.synergy.shatterMultiplier
	end
	enemy.health -= amount

	if not isBurn then
		if source then
			table.insert(run.events, {
				kind = "hit",
				source = source,
				enemyId = enemy.id,
				amount = amount,
				synergy = synergy,
				activeSkill = isActiveSkill,
			})
		end
		if hasTag(tags, "fire") then
			enemy.burningUntil = run.time + config.statuses.burnSeconds
			enemy.burnSource = source
		end
		if hasTag(tags, "ice") then
			enemy.chilledUntil = run.time + config.statuses.chillSeconds
		end
	end

	if enemy.health > 0 then
		return
	end
	local index = table.find(run.enemies, enemy)
	if index then
		table.remove(run.enemies, index)
	end
	if source == nil then
		return
	end
	table.insert(run.events, { kind = "kill", source = source, enemyId = enemy.id })
	local player = run.players[source]
	if player then
		player.kills += 1
		Progression.grantXp(run, player, config.horde.kinds[enemy.kind].xp)
	end
end

-- Fires the basic attack of every alive player whose attack is ready.
function Combat.basicAttacks(run: Types.Run)
	local config = run.config
	local ids: { number } = {}
	for id in run.players do
		table.insert(ids, id)
	end
	table.sort(ids)

	for _, id in ids do
		local player = run.players[id]
		if player.state == "alive" and run.time >= player.basicReadyAt then
			local target = nearestEnemy(run, player.x, player.z, config.basicAttack.range)
			if target then
				damage(
					run,
					target,
					id,
					config.basicAttack.damage,
					tagsFor(player, "searingBolts", "frostBolts"),
					false,
					false
				)
				player.basicReadyAt = run.time
					+ config.basicAttack.intervalSeconds
						* config.perks.quickHandsIntervalFactor ^ stacks(player, "quickHands")
			end
		end
	end
end

-- Fires a player's skill at `aim`, or at the nearest enemy in range when
-- `aim` is nil. Returns false when the player cannot use it now.
function Combat.useActiveSkill(
	run: Types.Run,
	playerId: number,
	aim: { x: number, z: number }?
): boolean
	local player = run.players[playerId]
	if player == nil or player.state ~= "alive" or run.time < player.activeSkillReadyAt then
		return false
	end
	local activeSkill = run.config.activeSkill

	local aimX, aimZ
	if aim then
		aimX, aimZ = aim.x, aim.z
		local d = distance(player.x, player.z, aimX, aimZ)
		if d > activeSkill.range then
			local scale = activeSkill.range / d
			aimX = player.x + (aimX - player.x) * scale
			aimZ = player.z + (aimZ - player.z) * scale
		end
	else
		local target = nearestEnemy(run, player.x, player.z, activeSkill.range)
		if target == nil then
			return false
		end
		aimX, aimZ = target.x, target.z
	end

	local tags = tagsFor(player, "fireBlast", "iceBlast")
	-- Damage can remove enemies, so walk a snapshot.
	for _, enemy in table.clone(run.enemies) do
		if distance(aimX, aimZ, enemy.x, enemy.z) <= activeSkill.radius then
			damage(run, enemy, playerId, activeSkill.damage, tags, true, false)
		end
	end
	player.activeSkillReadyAt = run.time + activeSkill.cooldownSeconds
	return true
end

-- Applies burning damage for `dt` seconds.
function Combat.burn(run: Types.Run, dt: number)
	local amount = run.config.statuses.burnDps * dt
	local tags: { Types.Tag } = { "fire" }
	for _, enemy in table.clone(run.enemies) do
		if run.time < enemy.burningUntil then
			damage(run, enemy, enemy.burnSource, amount, tags, false, true)
		end
	end
end

return Combat
