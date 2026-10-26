--!strict
-- A skill's effective numbers: its configuration with the player's perks
-- applied to the properties the skill carries (plan, stage 2a). A perk for a
-- property the skill lacks changes nothing.

local Perks = require("./Perks")
local Types = require("./Types")

local Skills = {}

-- The properties each shape carries, beyond damage and its interval.
local SHAPE_PROPERTIES: { [Types.SkillShape]: { Types.Property } } = {
	line = { "range", "pierce" },
	projectile = { "range", "area", "projectileSplit", "knockback" },
	ring = { "area", "knockback" },
	chain = { "range", "chainJumps" },
}

-- Whether a perk on `property` changes the skill. The basic attack's interval
-- is attackSpeed, an active skill's is cooldown.
function Skills.carries(
	skill: Types.SkillConfig,
	isBasic: boolean,
	property: Types.Property
): boolean
	if property == "damage" then
		return true
	elseif property == "cooldown" then
		return not isBasic
	elseif property == "attackSpeed" then
		return isBasic
	elseif property == "statusDuration" then
		return #skill.tags > 0
	end
	return table.find(SHAPE_PROPERTIES[skill.shape], property) ~= nil
end

-- The skill with the player's perks applied.
function Skills.effective(
	config: Types.Config,
	player: Types.Player,
	skill: Types.SkillConfig,
	isBasic: boolean
): Types.EffectiveSkill
	local modifiers = Perks.modifiers(config, player)
	local function value(property: Types.Property, base: number): number
		if Skills.carries(skill, isBasic, property) then
			return Perks.value(modifiers, property, base)
		end
		return base
	end

	return {
		id = skill.id,
		name = skill.name,
		shape = skill.shape,
		damage = value("damage", skill.damage),
		cooldownSeconds = if isBasic
			then value("attackSpeed", skill.cooldownSeconds)
			else value("cooldown", skill.cooldownSeconds),
		range = value("range", skill.range),
		radius = value("area", skill.radius),
		width = skill.width,
		pierce = value("pierce", skill.pierce),
		count = value("projectileSplit", 1),
		jumps = value("chainJumps", skill.jumps),
		jumpRange = skill.jumpRange,
		coneDegrees = skill.coneDegrees,
		speed = skill.speed,
		knockback = value("knockback", skill.knockback),
		tags = skill.tags,
		statusFactor = value("statusDuration", 1),
	}
end

return Skills
