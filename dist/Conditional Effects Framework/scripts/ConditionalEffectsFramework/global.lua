local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local core = require("openmw.core")
local world = require("openmw.world")
local storage = require("openmw.storage")
local vfs = require('openmw.vfs')
local time = require('openmw_aux.time')
local json = require('scripts.lib.json')
local types = require('openmw.types')

local timerDelay = (0.1 * time.second)
local realTime = core.getRealTime()
local elapsedTime = 0

local function syncMWVars(actor)
   if actor ~= nil then
      local localScript = world.mwscript.getLocalScript(actor, nil)
      if localScript ~= nil then
         local varTable = storage.globalSection(actor.id)
         for k, v in pairs((localScript.variables)) do
            varTable:set(k, v)
         end
      end
   end
end

local function loadConfigFiles()
   local configData = {}
   local configPath = "/scripts/ConditionalEffectsFramework/configs/"
   for fileName in vfs.pathsWithPrefix(configPath) do
      local file = vfs.open(fileName)
      if file ~= nil then
         local configId = string.match(file.fileName, "([^/\\]+)%..+$")
         configData[configId] = file:read("*all")
      end
   end
   return configData
end

local function parseConfigFiles(configData)
   local parsedConfigData = {}
   for k, v in pairs(configData) do
      parsedConfigData[k] = json.decode(v)
   end
   return parsedConfigData
end

local function storeConfigFiles(parsedConfigData)
   local configSection = storage.globalSection("CEF_ConfigData")
   configSection:setLifeTime(storage.LIFE_TIME.GameSession)
   for k, v in pairs(parsedConfigData) do
      configSection:set(k, v)
   end
end







return {
   engineHandlers = {
      onInit = function()
         local configData = loadConfigFiles()
         local parsedConfigData = parseConfigFiles(configData)
         storeConfigFiles(parsedConfigData)
      end,
      onActorActive = function(actor)
         syncMWVars(actor)
         storage.globalSection(actor.id):setLifeTime(storage.LIFE_TIME.GameSession)
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
      addItem = function(data)
         local item = world.createObject(data.itemId, data.quantity)
         item:moveInto(types.Actor.inventory(data.actor))
      end,
      removeItem = function(data)
         local inventory = types.Actor.inventory(data.actor)
         local item = inventory:find(data.itemId)
         item:remove(data.quantity)
      end,
   },
}
