--!strict
-- A skill's numbers at a rank, after the hero's stats (ADR-0013): what
-- Casting fires. Each rank above 1 raises damage, shortens the cooldown and
-- grows the radius and the duration; the configured ranks add a target.
-- Range and an effect's own duration do not scale.

local Types = require("./Types")

local Skills = {}

-- Targets added by the ranks up to `rank`.
function Skills.extraTargets(config: Types.Config, rank: number): number
	local extra = 0
	for _, threshold in config.ranks.extraTargetRanks do
		if threshold <= rank then
			extra += 1
		end
	end
	return extra
end

function Skills.effective(
	config: Types.Config,
	skill: Types.SkillConfig,
	rank: number,
	stats: Types.HeroStats
): Types.EffectiveSkill
	local ranks = config.ranks
	local above = rank - 1
	local damageFactor = (1 + ranks.damagePerRank * above) * stats.damage
	local cooldown = skill.cooldownSeconds
		* ranks.cooldownFactorPerRank ^ above
		* math.max(1 - stats.haste, ranks.minCooldownShare)

	-- Damage over time scales like the hit.
	local effect = skill.effect
	if effect and effect.kind == "dot" and effect.dps then
		local scaled = table.clone(effect)
		scaled.dps = effect.dps * damageFactor
		effect = scaled
	end

	return {
		id = skill.id,
		targeting = skill.targeting,
		toughest = skill.toughest == true,
		damage = skill.damage * damageFactor,
		cooldownSeconds = math.max(ranks.minCooldownSeconds, cooldown),
		range = skill.range,
		radius = skill.radius * (1 + ranks.radiusPerRank * above) * stats.area,
		-- Area kinds (count 0) gain no targets.
		count = if skill.count > 0
			then skill.count + Skills.extraTargets(config, rank)
			else skill.count,
		durationSeconds = skill.durationSeconds * (1 + ranks.durationPerRank * above),
		speed = skill.speed,
		knockback = skill.knockback,
		tags = skill.tags,
		effect = effect,
		critChance = stats.critChance,
	}
end

return Skills
