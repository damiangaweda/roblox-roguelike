--!strict
-- Player health: damage, downed, revive and death.

local Types = require("./Types")

local Life = {}

-- Players by ascending id: `pairs` order over the map is not stable between runs.
local function sortedPlayers(run: Types.Run): { Types.Player }
	local list = {}
	for _, player in run.players do
		table.insert(list, player)
	end
	table.sort(list, function(a, b)
		return a.id < b.id
	end)
	return list
end

-- Stage 1: anyone alive may revive anyone downed. Stage 2 restricts it to allies.
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
	for _, other in sortedPlayers(run) do
		if other.state == "alive" and other.interacting and canRevive(run, other, downed) then
			local distance = math.sqrt((other.x - downed.x) ^ 2 + (other.z - downed.z) ^ 2)
			if distance <= radius and distance < bestDistance then
				best = other
				bestDistance = distance
			end
		end
	end
	return best
end

-- Damages an alive player; at zero health the player is downed.
function Life.damage(run: Types.Run, player: Types.Player, amount: number)
	if player.state ~= "alive" or amount <= 0 then
		return
	end
	player.health -= amount
	-- Damage interrupts extraction.
	player.extractProgress = 0
	table.insert(run.events, { kind = "playerHurt", player = player.id, amount = amount })

	if player.health <= 0 then
		player.health = 0
		player.state = "downed"
		player.downedAt = run.time
		player.reviveProgress = 0
		table.insert(run.events, { kind = "downed", player = player.id })
	end
end

-- Advances revives and bleeding out of downed players by `dt`.
function Life.update(run: Types.Run, dt: number)
	local config = run.config.player
	for _, player in sortedPlayers(run) do
		local downedAt = player.downedAt
		if player.state == "downed" and downedAt then
			local reviver = findReviver(run, player)
			if reviver then
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

return Life
