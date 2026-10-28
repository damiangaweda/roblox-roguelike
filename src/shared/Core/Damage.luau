--!strict
-- Hits on enemies and what they leave: crits, statuses, damage-over-time
-- stacks, the class synergies, the shieldbearer's block, and kills with their
-- crystal and food (stage 3; ADR-0013). Damage to an asleep boss or guard
-- wakes its lair, and a lair's boss's death silences it (ADR-0021). A wraith
-- takes damage over time but no control, knockback or execute, and leaves
-- nothing. Every number comes
-- from run.config.

local Geometry = require("./Geometry")
local Hero = require("./Hero")
local Lairs = require("./Lairs")
local Progression = require("./Progression")
local State = require("./State")
local Targeting = require("./Targeting")
local Types = require("./Types")

local Damage = {}

-- One hit by a player's skill. (fromX, fromZ) is where it comes from, which
-- decides a block and the knockback; a hit from the enemy's own position (a
-- ground area beneath it) has no direction and is never blocked.
-- `allowSynergy` false keeps the class synergies out (nil allows them).
export type Hit = {
	source: number,
	skill: string,
	amount: number,
	tags: { Types.Tag },
	effect: Types.EffectConfig?,
	critChance: number,
	knockback: number,
	fromX: number,
	fromZ: number,
	allowSynergy: boolean?,
}

type DotStatus = "burning" | "bleeding" | "poisoned"

local function hasTag(tags: { Types.Tag }, tag: Types.Tag): boolean
	return table.find(tags, tag) ~= nil
end

-- Whether the enemy has `status` now.
function Damage.hasStatus(run: Types.Run, enemy: Types.Enemy, status: Types.Status): boolean
	local time = run.time
	if status == "slowed" then
		return enemy.slowUntil > time and enemy.slowFactor < 1
	elseif status == "chilled" then
		return enemy.chilledUntil > time
	elseif status == "rooted" then
		return enemy.rootedUntil > time
	elseif status == "stunned" then
		return enemy.stunnedUntil > time
	elseif status == "feared" then
		return enemy.fearedUntil > time
	elseif status == "weakened" then
		return enemy.weakenUntil > time
	end
	for _, dot in enemy.dots do
		if dot.status == status and dot.until_ > time then
			return true
		end
	end
	return false
end

local function isWraith(run: Types.Run, enemy: Types.Enemy): boolean
	return State.kind(run, enemy).role == "wraith"
end

-- Takes `amount` off the enemy, announces it and credits the player; a kill
-- follows at zero health. A lair's boss or guard hurt keeps its lair awake;
-- an asleep lair wakes (and grows) before the damage is taken.
local function deal(
	run: Types.Run,
	enemy: Types.Enemy,
	source: number,
	amount: number,
	skill: string,
	crit: boolean,
	synergy: string?
)
	if enemy.lairId and amount > 0 then
		Lairs.hurt(run, enemy)
	end
	enemy.health -= amount
	table.insert(run.events, {
		kind = "hit",
		source = source,
		enemyId = enemy.id,
		amount = amount,
		skill = skill,
		crit = crit,
		synergy = synergy,
		blocked = false,
	})
	local player = run.players[source]
	if player then
		player.damageDone += amount
	end
end

-- A damage-over-time stack; past the cap the oldest goes.
local function addDot(
	run: Types.Run,
	enemy: Types.Enemy,
	status: DotStatus,
	dps: number,
	seconds: number,
	source: number,
	tags: { Types.Tag }
)
	table.insert(enemy.dots, {
		dps = dps,
		until_ = run.time + seconds,
		nextTickAt = run.time + run.config.statuses.dotTickSeconds,
		status = status,
		source = source,
		tags = tags,
	})
	while #enemy.dots > run.config.statuses.maxDotStacks do
		table.remove(enemy.dots, 1)
	end
	table.insert(run.events, {
		kind = "statusApplied",
		enemyId = enemy.id,
		status = status,
		seconds = seconds,
	})
end

-- Puts a control status on the enemy, with the boss's resistances: a slow
-- never below bossSlowFloor, roots and stuns cut to bossControlShare, no fear.
-- A slow keeps the strongest factor and the longest duration; weaken
-- overwrites. A damage-over-time status goes through an effect instead.
function Damage.applyStatus(
	run: Types.Run,
	enemy: Types.Enemy,
	status: Types.Status,
	seconds: number,
	factor: number?
)
	local horde = run.config.horde
	local boss = State.isBoss(State.kind(run, enemy))
	local time = run.time
	if isWraith(run, enemy) then
		return
	end
	if status == "slowed" or status == "chilled" then
		local slow = factor or 1
		if boss then
			slow = math.max(slow, horde.bossSlowFloor)
		end
		enemy.slowFactor = if enemy.slowUntil > time then math.min(enemy.slowFactor, slow) else slow
		enemy.slowUntil = math.max(enemy.slowUntil, time + seconds)
		if status == "chilled" then
			enemy.chilledUntil = math.max(enemy.chilledUntil, time + seconds)
		end
	elseif status == "rooted" or status == "stunned" then
		if boss then
			seconds *= horde.bossControlShare
		end
		if status == "rooted" then
			enemy.rootedUntil = math.max(enemy.rootedUntil, time + seconds)
		else
			enemy.stunnedUntil = math.max(enemy.stunnedUntil, time + seconds)
		end
	elseif status == "feared" then
		if boss then
			return
		end
		enemy.fearedUntil = math.max(enemy.fearedUntil, time + seconds)
	elseif status == "weakened" then
		enemy.weakenFactor = factor or 1
		enemy.weakenUntil = time + seconds
	else
		return
	end
	table.insert(run.events, {
		kind = "statusApplied",
		enemyId = enemy.id,
		status = status,
		seconds = seconds,
	})
end

-- Applies a hit's lasting effect. Drain and execute act on the hit itself
-- (Damage.hit), so they do nothing here.
function Damage.applyEffect(
	run: Types.Run,
	enemy: Types.Enemy,
	effect: Types.EffectConfig,
	source: number,
	tags: { Types.Tag }
)
	local seconds = effect.seconds or 0
	if effect.kind == "slow" then
		Damage.applyStatus(run, enemy, "slowed", seconds, effect.factor)
	elseif effect.kind == "root" then
		Damage.applyStatus(run, enemy, "rooted", seconds)
	elseif effect.kind == "stun" then
		Damage.applyStatus(run, enemy, "stunned", seconds)
	elseif effect.kind == "fear" then
		Damage.applyStatus(run, enemy, "feared", seconds)
	elseif effect.kind == "weaken" then
		Damage.applyStatus(run, enemy, "weakened", seconds, effect.factor)
	elseif effect.kind == "dot" and effect.status and effect.dps then
		addDot(run, enemy, effect.status, effect.dps, seconds, source, tags)
	end
end

-- The enemy dies: its crystal drops, maybe food (a boss always drops a full
-- heal), and the player credited counts the kill; a wraith leaves nothing. A
-- lair's boss silences its lair, its killer getting the great offer.
function Damage.kill(run: Types.Run, enemy: Types.Enemy, source: number)
	local kind = State.kind(run, enemy)
	local horde = run.config.horde
	table.insert(run.events, {
		kind = "kill",
		source = source,
		enemyId = enemy.id,
		enemyKind = enemy.kind,
		x = enemy.x,
		z = enemy.z,
	})
	local player = run.players[source]
	if player then
		player.kills += 1
	end
	State.removeEnemy(run, enemy)
	if kind.role == "wraith" then
		return
	end
	Progression.dropCrystal(run, enemy.x, enemy.z, kind.xp)
	if State.isBoss(kind) then
		-- Hero.heal caps it at the eater's max health.
		Progression.dropFood(run, enemy.x, enemy.z, math.huge)
	elseif run.rng:next() < horde.foodChance then
		Progression.dropFood(run, enemy.x, enemy.z, horde.foodHeal)
	end
	local lairId = enemy.lairId
	if lairId and kind.role == "boss" then
		local lair = State.lairById(run, lairId)
		if lair and lair.bossId == enemy.id then
			Lairs.silence(run, lair, source)
		end
	end
end

-- The synergies of the source's class that the enemy's statuses (as they
-- were before this hit) set off: the multiplier on the hit and the first
-- synergy's id; spreads happen here.
local function synergies(run: Types.Run, enemy: Types.Enemy, hit: Hit): (number, string?)
	local player = run.players[hit.source]
	if player == nil or hit.allowSynergy == false then
		return 1, nil
	end
	local multiplier = 1
	local fired: string? = nil
	for _, synergy in run.config.classes[player.class].synergies do
		if hasTag(hit.tags, synergy.tag) and Damage.hasStatus(run, enemy, synergy.status) then
			fired = fired or synergy.id
			if synergy.kind == "multiply" then
				multiplier *= synergy.multiplier or 1
			elseif synergy.spreadStatus then
				local status: DotStatus = synergy.spreadStatus :: any
				local radius = synergy.radius or 0
				for _, other in table.clone(run.enemies) do
					if
						other ~= enemy
						and Geometry.distance(enemy.x, enemy.z, other.x, other.z) <= radius
					then
						addDot(
							run,
							other,
							status,
							synergy.spreadDps or 0,
							synergy.spreadSeconds or 0,
							hit.source,
							hit.tags
						)
					end
				end
			end
		end
	end
	return multiplier, fired
end

-- Lands a hit on the enemy. Returns the damage dealt: 0 when blocked or when
-- the enemy is already dead.
function Damage.hit(run: Types.Run, enemy: Types.Enemy, hit: Hit): number
	if enemy.health <= 0 then
		return 0
	end
	local config = run.config
	local kind = State.kind(run, enemy)

	local blockArc = kind.blockArcDegrees
	local directed = Geometry.distance(hit.fromX, hit.fromZ, enemy.x, enemy.z) > 1e-9
	if
		blockArc
		and directed
		and Geometry.inArc(enemy.x, enemy.z, enemy.facing, blockArc, hit.fromX, hit.fromZ)
	then
		table.insert(run.events, {
			kind = "hit",
			source = hit.source,
			enemyId = enemy.id,
			amount = 0,
			skill = hit.skill,
			crit = false,
			synergy = nil,
			blocked = true,
		})
		return 0
	end

	local amount = hit.amount
	local crit = hit.critChance > 0 and run.rng:next() < hit.critChance
	if crit then
		amount *= config.ranks.critMultiplier
	end
	local multiplier, synergy = synergies(run, enemy, hit)
	amount *= multiplier

	local effect = hit.effect
	if
		effect
		and effect.kind == "execute"
		and not State.isBoss(kind)
		and kind.role ~= "wraith"
		and enemy.health - amount <= (effect.factor or 0) * enemy.maxHealth
	then
		amount = math.max(amount, enemy.health)
	end

	deal(run, enemy, hit.source, amount, hit.skill, crit, synergy)

	local player = run.players[hit.source]
	if effect and effect.kind == "drain" and player then
		Hero.heal(run, player, amount * (effect.factor or 0))
	end

	if enemy.health <= 0 then
		Damage.kill(run, enemy, hit.source)
		return amount
	end

	if effect then
		Damage.applyEffect(run, enemy, effect, hit.source, hit.tags)
	end
	if hasTag(hit.tags, "ice") then
		local statuses = config.statuses
		Damage.applyStatus(run, enemy, "chilled", statuses.chillSeconds, statuses.chillFactor)
	end
	-- Bosses and wraiths stand their ground.
	if hit.knockback > 0 and not State.isBoss(kind) and kind.role ~= "wraith" then
		local seconds = config.player.knockbackSeconds
		local dx, dz = Geometry.normalize(enemy.x - hit.fromX, enemy.z - hit.fromZ)
		enemy.knockX = dx * hit.knockback / seconds
		enemy.knockZ = dz * hit.knockback / seconds
		enemy.knockUntil = run.time + seconds
	end
	return amount
end

-- Lands `hit` on `target` and its splash: every other enemy within `radius`
-- of it takes splashShare of the hit, from the target's position. Returns the
-- target's damage.
function Damage.splash(run: Types.Run, target: Types.Enemy, hit: Hit, radius: number): number
	local x, z = target.x, target.z
	local others: { Types.Enemy } = {}
	if radius > 0 then
		for _, enemy in Targeting.within(run, x, z, radius) do
			if enemy ~= target then
				table.insert(others, enemy)
			end
		end
	end
	local dealt = Damage.hit(run, target, hit)
	if #others == 0 then
		return dealt
	end
	local share = table.clone(hit)
	share.amount = hit.amount * run.config.ranks.splashShare
	share.fromX, share.fromZ = x, z
	for _, enemy in others do
		Damage.hit(run, enemy, share)
	end
	return dealt
end

-- Damage over time ticks every dotTickSeconds (never a crit; the kill goes to
-- the stack's source); expired stacks, slows and weakens end.
function Damage.update(run: Types.Run, _dt: number)
	local time = run.time
	local tick = run.config.statuses.dotTickSeconds
	for _, enemy in table.clone(run.enemies) do
		for _, dot in table.clone(enemy.dots) do
			while enemy.health > 0 and dot.nextTickAt <= time and dot.nextTickAt <= dot.until_ do
				deal(run, enemy, dot.source, dot.dps * tick, dot.status, false, nil)
				dot.nextTickAt += tick
				if enemy.health <= 0 then
					Damage.kill(run, enemy, dot.source)
				end
			end
		end
		if enemy.health <= 0 then
			continue
		end
		for index = #enemy.dots, 1, -1 do
			if enemy.dots[index].until_ <= time then
				table.remove(enemy.dots, index)
			end
		end
		if enemy.slowUntil <= time then
			enemy.slowFactor = 1
		end
		if enemy.weakenUntil <= time then
			enemy.weakenFactor = 1
		end
	end
end

return Damage
