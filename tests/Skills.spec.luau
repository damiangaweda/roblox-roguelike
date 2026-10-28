--!strict
local Assert = require("./Assert")
local Fixtures = require("./Fixtures")
local Skills = require("../src/shared/Core/Skills")
local Types = require("../src/shared/Core/Types")

-- A hero with no passives.
local function baseStats(): Types.HeroStats
	return {
		damage = 1,
		maxHealth = 120,
		speed = 17,
		regeneration = 0,
		haste = 0,
		area = 1,
		pickupRange = 10,
		experience = 1,
		armour = 0,
		critChance = 0.05,
	}
end

return {
	["rank 1 is the configuration with the hero's crit chance"] = function()
		local config = Fixtures.config()
		local skill = Skills.effective(config, config.skills.sleetfall, 1, baseStats())
		Assert.near(skill.damage, 7)
		Assert.near(skill.cooldownSeconds, 9)
		Assert.near(skill.radius, 16)
		Assert.near(skill.durationSeconds, 6)
		Assert.near(skill.range, 45)
		Assert.near(skill.critChance, 0.05)
		Assert.equal(skill.targeting, "ground")
	end,

	["rank 8 scales damage, cooldown, radius and duration but not range"] = function()
		local config = Fixtures.config()
		local skill = Skills.effective(config, config.skills.sleetfall, 8, baseStats())
		Assert.near(skill.damage, 7 * (1 + 0.3 * 7))
		Assert.near(skill.cooldownSeconds, 9 * 0.93 ^ 7)
		Assert.near(skill.radius, 16 * (1 + 0.08 * 7))
		Assert.near(skill.durationSeconds, 6 * (1 + 0.1 * 7))
		Assert.near(skill.range, 45)
	end,

	["ranks 3, 5 and 7 add a target"] = function()
		local config = Fixtures.config()
		local expected = { [1] = 1, [2] = 1, [3] = 2, [4] = 2, [5] = 3, [6] = 3, [7] = 4, [8] = 4 }
		for rank, count in expected do
			local skill = Skills.effective(config, config.skills.rimeDart, rank, baseStats())
			Assert.equal(skill.count, count, "rank " .. rank)
		end
		Assert.equal(Skills.effective(config, config.skills.glintVolley, 7, baseStats()).count, 6)
	end,

	["the hero's damage and area scale a skill"] = function()
		local config = Fixtures.config()
		local stats = baseStats()
		stats.damage = 1.5
		stats.area = 1.2
		stats.critChance = 0.15
		local skill = Skills.effective(config, config.skills.pulseBurst, 2, stats)
		Assert.near(skill.damage, 10 * 1.3 * 1.5)
		Assert.near(skill.radius, 16 * 1.08 * 1.2)
		Assert.near(skill.critChance, 0.15)
	end,

	["haste cuts a cooldown down to its share and the floor"] = function()
		local config = Fixtures.config()
		local stats = baseStats()
		stats.haste = 0.2
		Assert.near(
			Skills.effective(config, config.skills.rimeDart, 1, stats).cooldownSeconds,
			1.3 * 0.8
		)
		stats.haste = 0.9
		Assert.near(
			Skills.effective(config, config.skills.rimeDart, 1, stats).cooldownSeconds,
			1.3 * 0.35
		)
		Assert.near(
			Skills.effective(config, config.skills.relentlessEdge, 8, stats).cooldownSeconds,
			0.2
		)
	end,

	["damage over time scales like the hit and leaves the configuration alone"] = function()
		local config = Fixtures.config()
		local stats = baseStats()
		stats.damage = 1.5
		local skill = Skills.effective(config, config.skills.emberOrb, 3, stats)
		local effect = skill.effect :: Types.EffectConfig
		Assert.near(effect.dps :: number, 3 * 1.6 * 1.5)
		Assert.near(effect.seconds :: number, 3)
		Assert.near((config.skills.emberOrb.effect :: Types.EffectConfig).dps :: number, 3)
	end,
}
