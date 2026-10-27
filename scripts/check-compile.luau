--!strict
-- Compiles every .luau source with Luau's own compiler, which is what Studio
-- runs: the type checker and the linter miss its limits (such as the 200
-- local registers of one function). Exits 1 when any file fails.
--   lune run scripts/check-compile src

local fs = require("@lune/fs")
local luau = require("@lune/luau")
local process = require("@lune/process")

local function collect(dir: string, into: { string })
	for _, name in fs.readDir(dir) do
		local path = dir .. "/" .. name
		if fs.isDir(path) then
			collect(path, into)
		elseif string.sub(name, -5) == ".luau" then
			table.insert(into, path)
		end
	end
end

local files = {}
for _, root in process.args do
	collect(root, files)
end
table.sort(files)

local failed = 0
for _, file in files do
	local ok, err = pcall(luau.compile, fs.readFile(file))
	if not ok then
		failed += 1
		print("FAIL " .. file .. "\n     " .. tostring(err))
	end
end
print(string.format("%d files compiled, %d failed", #files - failed, failed))
process.exit(if failed == 0 then 0 else 1)
