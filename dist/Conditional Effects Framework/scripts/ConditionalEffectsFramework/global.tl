local core = require("openmw.core")
local world = require("openmw.world")
local storage = require("openmw.storage")
local vfs = require('openmw.vfs')
local time = require('openmw_aux.time')
local json = require('scripts.lib.json')
local types = require('openmw.types')

local timerDelay <const>: number = (0.1 * time.second)
local realTime: number = core.getRealTime()
local elapsedTime: number = 0

local function syncMWVars(actor: core.GameObject) -- Get the current state of all local mwscript variables associated with the provided actor
	if actor ~= nil then
		local localScript: world.MWScript = world.mwscript.getLocalScript(actor, nil)
		if localScript ~= nil then
            local varTable = storage.globalSection(actor.id)
            for k, v in pairs((localScript.variables as {string: number})) do
                varTable:set(k, v)
			end
		end
	end
end

local function loadConfigFiles(): { string: string }
	local configData: { string: string } = {}
	local configPath = "/scripts/ConditionalEffectsFramework/configs/"
	for fileName in vfs.pathsWithPrefix(configPath) do
		local file = vfs.open(fileName as string)
		if file ~= nil then
			local configId = string.match(file.fileName, "([^/\\]+)%..+$")
			configData[configId] = file:read("*all")
		end
	end
	return configData
end

local function parseConfigFiles(configData: { string: string}): { string: any }
	local parsedConfigData: { string: any } = {}
	for k, v in pairs(configData) do
		parsedConfigData[k] = json.decode(v)
	end
	return parsedConfigData
end

local function storeConfigFiles(parsedConfigData: { string: any })
	local configSection = storage.globalSection("CEF_ConfigData")
	configSection:setLifeTime(storage.LIFE_TIME.GameSession as storage.LifeTime)
	for k, v in pairs(parsedConfigData) do
		configSection:set(k, v)
	end
end

local interface ItemData
	actor: core.GameObject
	itemId: string
	quantity: number
end

return {
   	engineHandlers = {
		onInit = function()
			local configData = loadConfigFiles()
			local parsedConfigData = parseConfigFiles(configData)
			storeConfigFiles(parsedConfigData)
		end,
      	onActorActive = function(actor: core.GameObject)
			syncMWVars(actor)
			storage.globalSection(actor.id):setLifeTime(storage.LIFE_TIME.GameSession as storage.LifeTime)
      	end,
		onUpdate = function()
			if ((realTime - elapsedTime) >= (timerDelay)) then
				for i = 1, #world.activeActors do
					local actor = world.activeActors[i]
					syncMWVars(actor)
				end
				elapsedTime = realTime
			end
			realTime = core.getRealTime()
		end,
   	},
	eventHandlers = {
		addItem = function(data: ItemData)
			local item = world.createObject(data.itemId, data.quantity)
			item:moveInto(types.Actor.inventory(data.actor))
		end,
		removeItem = function(data: ItemData)
			local inventory = types.Actor.inventory(data.actor)
			local item = inventory:find(data.itemId)
			item:remove(data.quantity)
		end,
	},
}

