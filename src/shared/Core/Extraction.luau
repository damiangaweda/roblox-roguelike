--!strict
-- Extraction zones, open for the whole run, and the flood at its end.

local State = require("./State")
local Types = require("./Types")

local Extraction = {}

local function inAnyZone(run: Types.Run, player: Types.Player): boolean
	for _, zone in run.zones do
		local dx, dz = player.x - zone.x, player.z - zone.z
		if dx * dx + dz * dz <= zone.radius * zone.radius then
			return true
		end
	end
	return false
end

-- Advances players extracting in a zone while they hold the interact button.
function Extraction.update(run: Types.Run, dt: number)
	for _, player in State.sortedPlayers(run) do
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

	for _, player in State.sortedPlayers(run) do
		if player.state == "alive" or player.state == "downed" then
			player.state = "dead"
			table.insert(run.events, { kind = "died", player = player.id })
		end
	end
end

return Extraction
