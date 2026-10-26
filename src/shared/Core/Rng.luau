--!strict
-- A seeded xorshift32 generator, so a run replays exactly in tests (ADR-0002).

local Types = require("./Types")

local Rng = {}

local function step(state: number): number
	state = bit32.bxor(state, bit32.lshift(state, 13))
	state = bit32.bxor(state, bit32.rshift(state, 17))
	state = bit32.bxor(state, bit32.lshift(state, 5))
	return state
end

function Rng.new(seed: number): Types.Rng
	-- Xorshift needs a non-zero state.
	local state = bit32.band(math.floor(seed), 0xFFFFFFFF)
	if state == 0 then
		state = 0x9E3779B9
	end

	local rng = {}

	function rng.next(_self: Types.Rng): number
		state = step(state)
		return state / 0x100000000
	end

	function rng.integer(self: Types.Rng, min: number, max: number): number
		return min + math.floor(self:next() * (max - min + 1))
	end

	return rng :: Types.Rng
end

return Rng
