--!strict
-- Runs every `*.spec.luau` under tests/ with Lune (ADR-0001). A spec returns a
-- table of test functions keyed by name; a test fails by raising an error.
--   lune run tests/runner [filter]

local fs = require("@lune/fs")
local process = require("@lune/process")

local filter = process.args[1]

local function collect(dir: string, into: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			collect(path, into)
		elseif string.sub(name, -10) == ".spec.luau" then
			table.insert(into, path)
		end
	end
end

local files = {}
collect("tests", files)
table.sort(files)

local passed, failed = 0, 0
for _, file in files do
	-- Requires resolve relative to this script, which lives in tests/.
	local spec =
		require("./" .. string.sub(file, #"tests/" + 1, -#".luau" - 1)) :: { [string]: () -> () }
	local names = {}
	for name in spec do
		table.insert(names, name)
	end
	table.sort(names)
	for _, name in names do
		local label = file .. " > " .. name
		if filter == nil or string.find(label, filter, 1, true) then
			local ok, err = pcall(spec[name])
			if ok then
				passed += 1
			else
				failed += 1
				print("FAIL " .. label .. "\n     " .. tostring(err))
			end
		end
	end
end

print(string.format("%d passed, %d failed", passed, failed))
process.exit(if failed == 0 and passed > 0 then 0 else 1)
