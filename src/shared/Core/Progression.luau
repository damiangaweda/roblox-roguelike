--!strict
-- Experience, crystals, food and levels (GLOSSARY: crystal, level).

local Cards = require("./Cards")
local Geometry = require("./Geometry")
local Hero = require("./Hero")
local State = require("./State")
local Types = require("./Types")

local Progression = {}

-- Experience needed to go from `level` to the next one: the last band that
-- starts at or below the level.
function Progression.xpToNext(config: Types.Config, level: number): number
	local band = config.progression.bands[1]
	for _, candidate in config.progression.bands do
		if candidate.fromLevel <= level and candidate.fromLevel >= band.fromLevel then
			band = candidate
		end
	end
	return band.base + band.perLevel * (level - band.fromLevel)
end

-- Adds experience after the hero's multiplier, levelling up and offering
-- cards as many times as it covers.
function Progression.grantXp(run: Types.Run, player: Types.Player, xp: number)
	player.xp += xp * Hero.stats(run, player).experience
	while player.xp >= Progression.xpToNext(run.config, player.level) do
		player.xp -= Progression.xpToNext(run.config, player.level)
		player.level += 1
		table.insert(run.events, { kind = "levelUp", player = player.id, level = player.level })
		Cards.offer(run, player)
	end
end

-- Drops a crystal worth the enemy's `xp` times crystalFactor; past
-- maxCrystals its experience joins the nearest crystal on the ground.
function Progression.dropCrystal(run: Types.Run, x: number, z: number, xp: number)
	local progression = run.config.progression
	local value = xp * progression.crystalFactor
	if #run.crystals >= progression.maxCrystals and #run.crystals > 0 then
		local nearest = run.crystals[1]
		local nearestDistance = math.huge
		for _, crystal in run.crystals do
			local distance = Geometry.distance(x, z, crystal.x, crystal.z)
			if distance < nearestDistance then
				nearest = crystal
				nearestDistance = distance
			end
		end
		nearest.xp += value
		return
	end
	local crystal: Types.Crystal = { id = State.nextId(run), x = x, z = z, xp = value }
	table.insert(run.crystals, crystal)
	table.insert(run.events, { kind = "crystalDropped", id = crystal.id, x = x, z = z, xp = value })
end

-- Drops food that heals `heal` (math.huge for a boss's full heal).
function Progression.dropFood(run: Types.Run, x: number, z: number, heal: number)
	local food: Types.Food = { id = State.nextId(run), x = x, z = z, heal = heal }
	table.insert(run.foods, food)
	table.insert(run.events, { kind = "foodDropped", id = food.id, x = x, z = z })
end

-- Each alive hero collects the crystals within its pickup range and eats the
-- food it stands on.
function Progression.update(run: Types.Run, _dt: number)
	local eatRadius = run.config.player.radius + 1
	for _, player in State.alivePlayers(run) do
		local pickupRange = Hero.stats(run, player).pickupRange
		for index = #run.crystals, 1, -1 do
			local crystal = run.crystals[index]
			if Geometry.distance(player.x, player.z, crystal.x, crystal.z) <= pickupRange then
				table.remove(run.crystals, index)
				table.insert(run.events, {
					kind = "crystalCollected",
					id = crystal.id,
					player = player.id,
					xp = crystal.xp,
				})
				Progression.grantXp(run, player, crystal.xp)
			end
		end
		for index = #run.foods, 1, -1 do
			local food = run.foods[index]
			if Geometry.distance(player.x, player.z, food.x, food.z) <= eatRadius then
				table.remove(run.foods, index)
				local before = player.health
				Hero.heal(run, player, food.heal)
				table.insert(run.events, {
					kind = "foodEaten",
					id = food.id,
					player = player.id,
					amount = player.health - before,
				})
			end
		end
	end
end

return Progression
