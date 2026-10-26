--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Skills = require("../src/shared/Core/Skills")
local Types = require("../src/shared/Core/Types")

type Entry = { skill: Types.SkillConfig, isBasic: boolean }

-- A configuration in which every skill has a non-zero range, area, pierce,
-- jump count and knockback, so a perk that wrongly reaches a skill shows.
local function busyConfig(): Types.Config
	local config = Fixtures.config()
	local class = config.classes.elementalist
	local skills = { class.basic }
	for _, active in class.actives do
		table.insert(skills, active)
	end
	for _, skill in skills do
		skill.range = math.max(skill.range, 5)
		skill.radius = math.max(skill.radius, 5)
		skill.pierce = math.max(skill.pierce, 1)
		skill.jumps = math.max(skill.jumps, 2)
		skill.knockback = math.max(skill.knockback, 5)
	end
	return config
end

local function entries(config: Types.Config): { Entry }
	local class = config.classes.elementalist
	local list: { Entry } = { { skill = class.basic, isBasic = true } }
	for _, active in class.actives do
		table.insert(list, { skill = active, isBasic = false })
	end
	return list
end

-- The skills of the busy configuration by id.
local function byId(config: Types.Config): { [string]: Entry }
	local map = {}
	for _, entry in entries(config) do
		map[entry.skill.id] = entry
	end
	return map
end

-- A player with `perks` (perk id to stacks).
local function playerWith(config: Types.Config, perks: { [string]: number }): Types.Player
	local run = Fixtures.run(1, config)
	run.players[1].perks = perks
	return run.players[1]
end

local function effective(
	config: Types.Config,
	perks: { [string]: number },
	entry: Entry
): Types.EffectiveSkill
	return Skills.effective(config, playerWith(config, perks), entry.skill, entry.isBasic)
end

return {
	["without perks the numbers equal the configuration"] = function()
		local config = busyConfig()
		for _, entry in entries(config) do
			local skill, result = entry.skill, effective(config, {}, entry)
			Assert.equal(result.id, skill.id)
			Assert.equal(result.name, skill.name)
			Assert.equal(result.shape, skill.shape)
			Assert.equal(result.damage, skill.damage)
			Assert.equal(result.cooldownSeconds, skill.cooldownSeconds)
			Assert.equal(result.range, skill.range)
			Assert.equal(result.radius, skill.radius)
			Assert.equal(result.width, skill.width)
			Assert.equal(result.pierce, skill.pierce)
			Assert.equal(result.count, 1)
			Assert.equal(result.jumps, skill.jumps)
			Assert.equal(result.jumpRange, skill.jumpRange)
			Assert.equal(result.speed, skill.speed)
			Assert.equal(result.knockback, skill.knockback)
			Assert.equal(result.statusFactor, 1)
			Assert.equal(table.concat(result.tags, ","), table.concat(skill.tags, ","))
		end
	end,

	["the real configuration also comes through unchanged"] = function()
		local config = Fixtures.config()
		for _, entry in entries(config) do
			local result = effective(config, {}, entry)
			Assert.equal(result.damage, entry.skill.damage)
			Assert.equal(result.range, entry.skill.range)
			Assert.equal(result.radius, entry.skill.radius)
			Assert.equal(result.cooldownSeconds, entry.skill.cooldownSeconds)
		end
	end,

	["Power raises the damage of every skill"] = function()
		local config = busyConfig()
		for _, entry in entries(config) do
			Assert.near(effective(config, { power = 1 }, entry).damage, entry.skill.damage * 1.15)
			Assert.near(
				effective(config, { power = 2 }, entry).damage,
				entry.skill.damage * 1.15 ^ 2
			)
		end
	end,

	["Quick Hands shortens the cooldown of actives and not the basic attack"] = function()
		local config = busyConfig()
		local skills = byId(config)
		for id, entry in skills do
			local result = effective(config, { quickHands = 1 }, entry)
			if id == "arcaneBolt" then
				Assert.equal(result.cooldownSeconds, entry.skill.cooldownSeconds)
			else
				Assert.near(result.cooldownSeconds, entry.skill.cooldownSeconds * 0.85)
			end
		end
		Assert.near(
			effective(config, { quickHands = 2 }, skills.fireball).cooldownSeconds,
			5 * 0.85 ^ 2
		)
	end,

	["Rapid Fire shortens the interval of the basic attack and not the cooldowns"] = function()
		local config = busyConfig()
		for _, entry in entries(config) do
			local result = effective(config, { rapidFire = 1 }, entry)
			if entry.isBasic then
				Assert.near(result.cooldownSeconds, entry.skill.cooldownSeconds * 0.85)
			else
				Assert.equal(result.cooldownSeconds, entry.skill.cooldownSeconds)
			end
		end
	end,

	["Wide Reach grows the area of Fireball and Frost Nova only"] = function()
		local config = busyConfig()
		local skills = byId(config)
		Assert.near(effective(config, { wideReach = 1 }, skills.fireball).radius, 7 * 1.25)
		Assert.near(effective(config, { wideReach = 1 }, skills.frostNova).radius, 12 * 1.25)
		Assert.near(effective(config, { wideReach = 2 }, skills.frostNova).radius, 12 * 1.25 ^ 2)
		for _, id in { "chainLightning", "arcaneBolt" } do
			local entry = skills[id]
			Assert.equal(effective(config, { wideReach = 2 }, entry).radius, entry.skill.radius, id)
		end
	end,

	["Split Shot splits the projectile and nothing else"] = function()
		local config = busyConfig()
		local skills = byId(config)
		Assert.equal(effective(config, { splitShot = 1 }, skills.fireball).count, 3)
		for _, id in { "frostNova", "chainLightning", "arcaneBolt" } do
			Assert.equal(effective(config, { splitShot = 1 }, skills[id]).count, 1, id)
		end
	end,

	["Piercing adds pierce to Arcane Bolt only"] = function()
		local config = busyConfig()
		local skills = byId(config)
		Assert.equal(effective(config, { piercing = 1 }, skills.arcaneBolt).pierce, 2)
		Assert.equal(effective(config, { piercing = 2 }, skills.arcaneBolt).pierce, 3)
		for _, id in { "fireball", "frostNova", "chainLightning" } do
			local entry = skills[id]
			Assert.equal(effective(config, { piercing = 2 }, entry).pierce, entry.skill.pierce, id)
		end
	end,

	["Arcing adds jumps to Chain Lightning only"] = function()
		local config = busyConfig()
		local skills = byId(config)
		Assert.equal(effective(config, { arcing = 1 }, skills.chainLightning).jumps, 4 + 2)
		Assert.equal(effective(config, { arcing = 2 }, skills.chainLightning).jumps, 4 + 4)
		for _, id in { "arcaneBolt", "fireball", "frostNova" } do
			local entry = skills[id]
			Assert.equal(effective(config, { arcing = 2 }, entry).jumps, entry.skill.jumps, id)
		end
	end,

	["Lingering lengthens the statuses of tagged skills only"] = function()
		local config = busyConfig()
		local skills = byId(config)
		for _, id in { "fireball", "frostNova", "chainLightning" } do
			Assert.near(
				effective(config, { lingering = 1 }, skills[id]).statusFactor,
				1.3,
				1e-9,
				id
			)
			Assert.near(
				effective(config, { lingering = 2 }, skills[id]).statusFactor,
				1.69,
				1e-9,
				id
			)
		end
		Assert.equal(#skills.arcaneBolt.skill.tags, 0)
		Assert.equal(effective(config, { lingering = 2 }, skills.arcaneBolt).statusFactor, 1)
	end,

	["Long Arm lengthens the range of line, projectile and chain skills"] = function()
		local config = busyConfig()
		local skills = byId(config)
		for _, id in { "arcaneBolt", "fireball", "chainLightning" } do
			local entry = skills[id]
			Assert.near(
				effective(config, { longArm = 1 }, entry).range,
				entry.skill.range * 1.2,
				1e-9,
				id
			)
		end
		Assert.near(effective(config, { longArm = 2 }, skills.fireball).range, 45 * 1.2 ^ 2)
		Assert.equal(skills.frostNova.skill.shape, "ring")
		Assert.equal(
			effective(config, { longArm = 2 }, skills.frostNova).range,
			skills.frostNova.skill.range
		)
	end,

	["Impact scales the knockback of Fireball and Frost Nova only"] = function()
		local config = busyConfig()
		local skills = byId(config)
		for _, id in { "fireball", "frostNova" } do
			local base = skills[id].skill.knockback
			Assert.near(
				effective(config, { impact = 1 }, skills[id]).knockback,
				base * 1.5,
				1e-9,
				id
			)
			Assert.near(
				effective(config, { impact = 2 }, skills[id]).knockback,
				base * 1.5 ^ 2,
				1e-9,
				id
			)
		end
		for _, id in { "arcaneBolt", "chainLightning" } do
			local entry = skills[id]
			Assert.equal(
				effective(config, { impact = 2 }, entry).knockback,
				entry.skill.knockback,
				id
			)
		end
	end,

	["perks combine across properties"] = function()
		local config = busyConfig()
		local fireball = byId(config).fireball
		local result = effective(config, { power = 2, quickHands = 1, wideReach = 1 }, fireball)
		Assert.near(result.damage, 30 * 1.15 ^ 2)
		Assert.near(result.cooldownSeconds, 5 * 0.85)
		Assert.near(result.radius, 7 * 1.25)
		Assert.equal(result.range, 45)
	end,

	["perks that skills do not carry change nothing"] = function()
		local config = busyConfig()
		local perks = {
			toughness = 5,
			fleetFooted = 1,
			longBlink = 2,
			deepPockets = 2,
			strongBrew = 2,
			swift = 2,
			kindling = 2,
			deepFreeze = 2,
			resonance = 2,
			scholar = 2,
		}
		for _, entry in entries(config) do
			local skill, result = entry.skill, effective(config, perks, entry)
			Assert.equal(result.damage, skill.damage)
			Assert.equal(result.cooldownSeconds, skill.cooldownSeconds)
			Assert.equal(result.range, skill.range)
			Assert.equal(result.radius, skill.radius)
			Assert.equal(result.pierce, skill.pierce)
			Assert.equal(result.jumps, skill.jumps)
			Assert.equal(result.knockback, skill.knockback)
			Assert.equal(result.count, 1)
			Assert.equal(result.statusFactor, 1)
		end
	end,

	["numbers no perk touches stay as configured"] = function()
		local config = busyConfig()
		local perks: { [string]: number } = {}
		for id, perk in config.perks.pool do
			perks[id] = perk.maxStacks
		end
		for _, entry in entries(config) do
			local skill, result = entry.skill, effective(config, perks, entry)
			Assert.equal(result.width, skill.width)
			Assert.equal(result.jumpRange, skill.jumpRange)
			Assert.equal(result.speed, skill.speed)
			Assert.equal(result.shape, skill.shape)
		end
	end,

	["effective leaves the configuration alone"] = function()
		local config = busyConfig()
		local skills = byId(config)
		local before = skills.fireball.skill.damage
		effective(config, { power = 3, splitShot = 1 }, skills.fireball)
		Assert.equal(skills.fireball.skill.damage, before)
		Assert.equal(#skills.fireball.skill.tags, 1)
	end,

	["carries names the skills each property reaches"] = function()
		local config = busyConfig()
		local skills = byId(config)
		-- Property to the ids of the skills that carry it.
		local expected: { [string]: { string } } = {
			damage = { "arcaneBolt", "fireball", "frostNova", "chainLightning" },
			cooldown = { "fireball", "frostNova", "chainLightning" },
			attackSpeed = { "arcaneBolt" },
			range = { "arcaneBolt", "fireball", "chainLightning" },
			area = { "fireball", "frostNova" },
			statusDuration = { "fireball", "frostNova", "chainLightning" },
			projectileSplit = { "fireball" },
			pierce = { "arcaneBolt" },
			chainJumps = { "chainLightning" },
			knockback = { "fireball", "frostNova" },
			maxHealth = {},
			moveSpeed = {},
			dashCharges = {},
			dashDistance = {},
			potionCapacity = {},
			potionHeal = {},
			burnDamage = {},
			chillSlow = {},
			synergyBonus = {},
			xpGain = {},
		}
		for property, carriers in expected do
			for id, entry in skills do
				Assert.equal(
					Skills.carries(entry.skill, entry.isBasic, property :: Types.Property),
					table.find(carriers, id) ~= nil,
					id .. " / " .. property
				)
			end
		end
	end,

	["carries agrees with what a perk changes"] = function()
		local config = busyConfig()
		-- The effective number a property drives, and what it is without perks.
		local function field(result: Types.EffectiveSkill, property: Types.Property): number?
			if property == "damage" then
				return result.damage
			elseif property == "cooldown" or property == "attackSpeed" then
				return result.cooldownSeconds
			elseif property == "range" then
				return result.range
			elseif property == "area" then
				return result.radius
			elseif property == "statusDuration" then
				return result.statusFactor
			elseif property == "projectileSplit" then
				return result.count
			elseif property == "pierce" then
				return result.pierce
			elseif property == "chainJumps" then
				return result.jumps
			elseif property == "knockback" then
				return result.knockback
			end
			return nil
		end

		local tested = 0
		for id, perk in config.perks.pool do
			for _, entry in entries(config) do
				local before = field(effective(config, {}, entry), perk.property)
				local after = field(effective(config, { [id] = 1 }, entry), perk.property)
				if before == nil then
					-- A property of the player, not of skills.
					Assert.falsy(Skills.carries(entry.skill, entry.isBasic, perk.property))
				else
					tested += 1
					Assert.equal(
						after ~= before,
						Skills.carries(entry.skill, entry.isBasic, perk.property),
						id .. " on " .. entry.skill.id
					)
				end
			end
		end
		Assert.truthy(tested > 0)
	end,
}
