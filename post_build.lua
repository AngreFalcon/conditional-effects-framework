local lfs = require("lfs")

local projDir = lfs.currentdir()
local src = {
	"scripts",
	"meshes",
	"textures",
	"l10n",
}
local dest = projDir .. "\\dist\\Conditional Effects Framework"

os.execute("rmdir /s \"" .. dest .. "\"") -- delete current dist directory, removing all old build files
os.execute("mkdir \"" .. dest .. "\"") -- create empty dist directory to store build files in for publication

for _, dir in ipairs(src) do
	if dir == ("scripts") then
		for file in lfs.dir(projDir .. "\\" .. dir) do
			if file ~= nil and file ~= "scripts" and file ~= "." and file ~= ".." then
				print(file)
				os.execute("xcopy /v /e \"" .. projDir .. "\\" .. dir .. "\\" .. file .. "\" \"" .. dest .. "\\" .. dir .. "\\" .. file .. "\"\\")
			end
		end
	else
		os.execute("xcopy /v /e \"" .. projDir .. "\\" .. dir .. "\" \"" .. dest .. "\\" .. dir .. "\"\\")
	end
end
