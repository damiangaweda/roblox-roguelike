--!strict
local Assert = require("./Assert")
local Rng = require("../src/shared/Core/Rng")

return {
	["the same seed gives the same sequence"] = function()
		local a, b = Rng.new(42), Rng.new(42)
		for _ = 1, 100 do
			Assert.equal(a:next(), b:next())
		end
	end,

	["next stays in [0, 1)"] = function()
		local rng = Rng.new(7)
		for _ = 1, 1000 do
			local value = rng:next()
			Assert.truthy(value >= 0 and value < 1, "out of range: " .. value)
		end
	end,

	["integer covers both ends"] = function()
		local rng = Rng.new(3)
		local seen = {}
		for _ = 1, 1000 do
			local value = rng:integer(1, 3)
			Assert.truthy(value >= 1 and value <= 3)
			seen[value] = true
		end
		Assert.truthy(seen[1] and seen[2] and seen[3])
	end,

	["seed zero still works"] = function()
		local rng = Rng.new(0)
		Assert.truthy(rng:next() ~= rng:next())
	end,
}
