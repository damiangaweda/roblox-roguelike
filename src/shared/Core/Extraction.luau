--!strict
-- Extraction zones and the flood at the end of the run.

local Types = require("./Types")

local Extraction = {}

-- Opens the zones when their time comes and advances players extracting in them.
function Extraction.update(run: Types.Run, dt: number)
	error("not implemented")
end

-- Floods the map when the run's time is up: everyone not extracted dies.
function Extraction.flood(run: Types.Run)
	error("not implemented")
end

return Extraction
