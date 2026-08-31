local lfs = require("lfs")

local projDir = lfs.currentdir()
local dest = projDir .. "\\dist\\Conditional Effects Framework"
local src = {
	"scripts",
	"meshes",
	"textures",
	"l10n",
}
local plugins = {
	"conditional_effects_framework.omwscripts",
}

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

for _, plugin in ipairs(plugins) do
	os.execute("echo F|xcopy /v \"" .. projDir .. "\\" .. plugin .. "\" \"" .. dest .. "\\" .. plugin .. "\"")
end

os.execute("7z a \"".. dest .. ".7z\" \"" .. dest .. "\\*\"")