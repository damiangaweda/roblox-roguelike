--!strict
-- What the held interact button does at a player's spot: extracting in an
-- open zone, else reading a clue, else opening a chest (stage 2d), and the
-- flood's end, when it meets at the centre.

local Arc = require("./Arc")
local State = require("./State")
local Types = require("./Types")

local Extraction = {}

local function inOpenZone(run: Types.Run, player: Types.Player): boolean
	for _, zone in run.zones do
		local dx, dz = player.x - zone.x, player.z - zone.z
		if zone.open and dx * dx + dz * dz <= zone.radius * zone.radius then
			return true
		end
	end
	return false
end

-- Advances what each alive player holding the interact button does, the first
-- that applies: extracting in an open zone, reading the nearest clue, opening
-- the nearest chest. Every other progress, and all of it once the button is
-- let go, starts over.
function Extraction.update(run: Types.Run, dt: number)
	local arc = run.config.run.arc
	for _, player in State.sortedPlayers(run) do
		if player.state ~= "alive" then
			continue
		end
		local extracting = player.interacting and inOpenZone(run, player)
		local clue = if player.interacting and not extracting
			then Arc.clueNear(run, player)
			else nil
		local chest = if player.interacting
				and not extracting
				and clue == nil
			then Arc.chestNear(run, player)
			else nil

		if extracting then
			player.extractProgress += dt
		else
			player.extractProgress = 0
		end
		if clue then
			player.clueProgress += dt
		else
			player.clueProgress = 0
		end
		if chest then
			player.chestProgress += dt
		else
			player.chestProgress = 0
		end

		if extracting and player.extractProgress >= run.config.run.extractSeconds then
			player.state = "extracted"
			table.insert(run.events, { kind = "extracted", player = player.id })
		elseif clue and player.clueProgress >= arc.clues.readSeconds then
			player.clueProgress = 0
			Arc.readClue(run, clue, player)
		elseif chest and player.chestProgress >= arc.events.chest.openSeconds then
			player.chestProgress = 0
			Arc.openChest(run, chest, player)
		end
	end
end

-- Floods the map when the flood meets at the centre: everyone not extracted
-- dies.
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
