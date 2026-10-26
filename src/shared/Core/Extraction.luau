--!strict
-- Extraction zones and the flood at the end of the run.

local Types = require("./Types")

local Extraction = {}

-- Players by ascending id, so events come in the same order on every run.
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

-- Picks `zoneCount` distinct zone points with the run's generator.
local function openZones(run: Types.Run)
	local config = run.config.run
	local points = table.clone(config.zonePoints)
	local count = math.min(config.zoneCount, #points)
	for i = 1, count do
		-- Partial Fisher-Yates: the first `count` entries end up chosen.
		local j = run.rng:integer(i, #points)
		points[i], points[j] = points[j], points[i]
		table.insert(run.zones, { x = points[i].x, z = points[i].z, radius = config.zoneRadius })
	end
	run.zonesOpen = true
	table.insert(run.events, { kind = "zonesOpened" })
end

local function inAnyZone(run: Types.Run, player: Types.Player): boolean
	for _, zone in run.zones do
		local dx, dz = player.x - zone.x, player.z - zone.z
		if dx * dx + dz * dz <= zone.radius * zone.radius then
			return true
		end
	end
	return false
end

-- Opens the zones when their time comes and advances players extracting in them.
function Extraction.update(run: Types.Run, dt: number)
	if not run.zonesOpen and run.time >= run.config.run.zonesOpenAtSeconds then
		openZones(run)
	end
	if not run.zonesOpen then
		return
	end

	for _, player in sortedPlayers(run) do
		if player.state == "alive" then
			if player.interacting and inAnyZone(run, player) then
				player.extractProgress += dt
				if player.extractProgress >= run.config.run.extractSeconds then
					player.state = "extracted"
					table.insert(run.events, { kind = "extracted", player = player.id })
				end
			else
				player.extractProgress = 0
			end
		end
	end
end

-- Floods the map when the run's time is up: everyone not extracted dies.
function Extraction.flood(run: Types.Run)
	if run.flooded then
		return
	end
	run.flooded = true
	table.insert(run.events, { kind = "flood" })

	for _, player in sortedPlayers(run) do
		if player.state == "alive" or player.state == "downed" then
			player.state = "dead"
			table.insert(run.events, { kind = "died", player = player.id })
		end
	end
end

return Extraction
