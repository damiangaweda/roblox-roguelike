--!strict
-- What a skill lands on (ADR-0013; GLOSSARY: targeting): pure queries over
-- run.enemies. Distances are flat; an enemy's body (its kind's radius) counts
-- toward reach. Ties in distance go to the lower id, so a seed replays.

local Geometry = require("./Geometry")
local State = require("./State")
local Types = require("./Types")

local Targeting = {}

type Candidate = { enemy: Types.Enemy, distance: number }

local function byDistance(a: Candidate, b: Candidate): boolean
	if a.distance ~= b.distance then
		return a.distance < b.distance
	end
	return a.enemy.id < b.enemy.id
end

local function radiusOf(run: Types.Run, enemy: Types.Enemy): number
	return State.kind(run, enemy).radius
end

-- Enemies whose distance from (x, z) is within `reach` plus `bodyShare` of
-- their radius, nearest first.
local function candidates(
	run: Types.Run,
	x: number,
	z: number,
	reach: number,
	bodyShare: number
): { Candidate }
	local found: { Candidate } = {}
	for _, enemy in run.enemies do
		local distance = Geometry.distance(x, z, enemy.x, enemy.z)
		if distance <= reach + bodyShare * radiusOf(run, enemy) then
			table.insert(found, { enemy = enemy, distance = distance })
		end
	end
	table.sort(found, byDistance)
	return found
end

local function enemiesOf(found: { Candidate }, count: number): { Types.Enemy }
	local enemies = {}
	for index = 1, math.min(count, #found) do
		table.insert(enemies, found[index].enemy)
	end
	return enemies
end

-- The `count` nearest enemies within `range` (or, `toughest`, the `count`
-- with the most health among them).
function Targeting.nearest(
	run: Types.Run,
	x: number,
	z: number,
	range: number,
	count: number,
	toughest: boolean
): { Types.Enemy }
	local found = candidates(run, x, z, range, 1)
	if toughest then
		table.sort(found, function(a, b)
			if a.enemy.health ~= b.enemy.health then
				return a.enemy.health > b.enemy.health
			end
			return byDistance(a, b)
		end)
	end
	return enemiesOf(found, count)
end

-- Everything within `radius` of (x, z), half an enemy's body counting, nearest first.
function Targeting.within(run: Types.Run, x: number, z: number, radius: number): { Types.Enemy }
	local found = candidates(run, x, z, radius, 0.5)
	return enemiesOf(found, #found)
end

-- The `within` set inside a cone aimed at its nearest member. An enemy
-- touching the hero is always inside.
function Targeting.cone(
	run: Types.Run,
	x: number,
	z: number,
	radius: number,
	halfAngleDegrees: number
): { Types.Enemy }
	local found = Targeting.within(run, x, z, radius)
	if #found == 0 then
		return found
	end
	local aim = Geometry.angle(found[1].x - x, found[1].z - z)
	local half = math.rad(halfAngleDegrees)
	local kept = {}
	for _, enemy in found do
		local distance = Geometry.distance(x, z, enemy.x, enemy.z)
		local touching = distance < run.config.player.radius + radiusOf(run, enemy)
		local angle = Geometry.angle(enemy.x - x, enemy.z - z)
		if touching or Geometry.angleBetween(aim, angle) <= half then
			table.insert(kept, enemy)
		end
	end
	return kept
end

-- Where to put an area of `radius`: the position of the enemy, among the
-- `candidates` nearest within `range`, with the most of those candidates
-- within `radius` of it (ties go to the later, farther one). Nil when none is
-- in range.
function Targeting.cluster(
	run: Types.Run,
	x: number,
	z: number,
	range: number,
	radius: number,
	candidateCount: number
): Types.Point?
	local found = Targeting.nearest(run, x, z, range, candidateCount, false)
	local best: Types.Enemy? = nil
	local bestCount = -1
	for _, enemy in found do
		local count = 0
		for _, other in found do
			if
				other ~= enemy
				and Geometry.distance(enemy.x, enemy.z, other.x, other.z) <= radius
			then
				count += 1
			end
		end
		if count >= bestCount then
			best = enemy
			bestCount = count
		end
	end
	if best == nil then
		return nil
	end
	return { x = best.x, z = best.z }
end

-- A chain: the nearest within `range`, then each time the nearest not yet
-- struck within `jumpRadius` of the last, up to `maxTargets` in all.
function Targeting.chain(
	run: Types.Run,
	x: number,
	z: number,
	range: number,
	jumpRadius: number,
	maxTargets: number
): { Types.Enemy }
	local path: { Types.Enemy } = {}
	local struck: { [Types.Enemy]: boolean } = {}
	local fromX, fromZ, reach = x, z, range
	while #path < maxTargets do
		local nextTarget: Types.Enemy? = nil
		for _, candidate in candidates(run, fromX, fromZ, reach, 1) do
			if not struck[candidate.enemy] then
				nextTarget = candidate.enemy
				break
			end
		end
		if nextTarget == nil then
			break
		end
		table.insert(path, nextTarget)
		struck[nextTarget] = true
		fromX, fromZ, reach = nextTarget.x, nextTarget.z, jumpRadius
	end
	return path
end

-- `count` enemies drawn at random from the count × 3 nearest within `range`.
function Targeting.scatter(
	run: Types.Run,
	x: number,
	z: number,
	range: number,
	count: number,
	rng: Types.Rng
): { Types.Enemy }
	local pool = Targeting.nearest(run, x, z, range, count * 3, false)
	local picked = {}
	for index = 1, math.min(count, #pool) do
		local chosen = rng:integer(index, #pool)
		pool[index], pool[chosen] = pool[chosen], pool[index]
		table.insert(picked, pool[index])
	end
	return picked
end

return Targeting
