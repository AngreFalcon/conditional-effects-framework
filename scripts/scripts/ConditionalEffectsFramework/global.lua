local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local core = require("openmw.core")
local world = require("openmw.world")
local storage = require("openmw.storage")
local vfs = require('openmw.vfs')
local json = require('scripts.lib.json')
local types = require('openmw.types')
local async = require('openmw.async')

local cef_utils = require('scripts.ConditionalEffectsFramework.cef-utils')


local settings = storage.globalSection("SettingsGeneralConditionalEffectsFramework")
local cefSettings = {
   cefEnable = true,
   cefLiteMode = false,
   cefTickDelay = 0.5,
   cefMWVarsUpdateDelay = 1.5,
   cefEnableMenuUpdates = true,
   cefMenuTickDelay = 1.0,
   cefPollRange = 2000.0,
}
local parsedConfigData
local timerRunning = false
local menuTimer = {
   realTime = core.getRealTime(),
   elapsedTime = 0,
}
local actorsInMenu = {}



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

local function MWVarsUpdateCallback(actor)
   syncMWVars(actor)
   async:newUnsavableSimulationTimer(cefSettings.cefMWVarsUpdateDelay, function()
      MWVarsUpdateCallback(actor)
   end)

end

local function sendUpdateEvent(actor)
   if types.NPC.objectIsInstance(actor) == true and cefSettings.cefEnable == true then
      actor:sendEvent("cefUpdate", { cefSettings = cefSettings, configData = parsedConfigData })
   end
end

local function performPausedUpdate()
   if core.isWorldPaused() == true and ((menuTimer.realTime - menuTimer.elapsedTime) >= cefSettings.cefMenuTickDelay) then
      if cefSettings.cefEnableMenuUpdates == true then
         for _, actors in pairs(actorsInMenu) do
            sendUpdateEvent(actors.player)
            if actors.actor ~= nil then
               sendUpdateEvent(actors.actor)
            end
         end
      end
      menuTimer.elapsedTime = menuTimer.realTime
   end
end

local function performConditionUpdate()
   for _, actor in ipairs(world.activeActors) do
      sendUpdateEvent(actor)
   end
end

local function regenerateUpdateTimer()
   if cefSettings.cefEnable == true and cefSettings.cefLiteMode == false then
      performConditionUpdate()
      async:newUnsavableSimulationTimer(cefSettings.cefTickDelay, regenerateUpdateTimer)
   else
      timerRunning = false
   end
end

local function createUpdateTimer()
   if timerRunning == false then
      async:newUnsavableSimulationTimer(cefSettings.cefTickDelay, regenerateUpdateTimer)
      timerRunning = true
   end
end

local function handleActiveActor(actor)
   if types.NPC.objectIsInstance(actor) == false and types.Player.objectIsInstance(actor) == false then
      return
   end
   storage.globalSection(actor.id):setLifeTime(storage.LIFE_TIME.GameSession)
   async:newUnsavableSimulationTimer(cefSettings.cefMWVarsUpdateDelay, function()
      MWVarsUpdateCallback(actor)
   end)

   createUpdateTimer()
end

local function sendDisableEvent(actor)
   if types.NPC.objectIsInstance(actor) == true then
      actor:sendEvent("cefDisable", {})
   end
end

local function disableAllEffects()
   for _, actor in ipairs(world.activeActors) do
      sendDisableEvent(actor)
   end
end

local function validateSpellId(spellId)
   for _, spell in ipairs(core.magic.spells.records) do
      if spell.id == spellId then
         return true
      end
   end
   return false
end

local function validateItemId(itemId)
   for _, itemType in ipairs(cef_utils.ITEM_INTERFACES) do
      if (itemType.records)[itemId] ~= nil then
         return true
      end
   end
   return false
end

local function validateEffectIDs()
   for fileName, contents in pairs(parsedConfigData) do
      for effectId, effect in pairs(contents) do
         if effect.spells ~= nil then
            for _, spell in ipairs(effect.spells) do
               if validateSpellId(spell.spellId) == false then
                  print("Spell could not be found by ID: " .. spell.spellId .. " in file: " .. fileName .. " for effect: " .. effectId)
               end
            end
         end
         if effect.items ~= nil then
            for _, itemPool in ipairs(effect.items) do
               for _, item in ipairs(itemPool.itemPool) do
                  if item.itemId ~= "nil" and validateItemId(item.itemId) == false then
                     print("Item could not be found by ID: " .. item.itemId .. " in file: " .. fileName .. " for effect: " .. effectId)
                  end
               end
            end
         end
      end
   end
end

local function storeConfigFiles()
   local configSection = storage.globalSection("CEF_ConfigData")
   configSection:reset({})
   configSection:setLifeTime(storage.LIFE_TIME.GameSession)
   for k, v in pairs(parsedConfigData) do
      configSection:set(k, v)
   end
end

local function parseConfigFiles(configData)
   local tempConfigData = {}
   for k, v in pairs(configData) do
      tempConfigData[k] = json.decode(v)
   end
   return tempConfigData
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
   parsedConfigData = parseConfigFiles(configData)
   storeConfigFiles()
end

local function settingsUpdated(sectionName, key)
   if sectionName ~= "SettingsGeneralConditionalEffectsFramework" then
      return
   end
   if key == nil then
      for k in pairs(cefSettings) do
         (cefSettings)[k] = settings:asTable()[k]
      end
   else
      (cefSettings)[key] = settings:asTable()[key]
   end

   if key == "cefEnable" then
      if cefSettings.cefEnable == true then
         createUpdateTimer()
      else
         disableAllEffects()
      end
   end
end

local function loadSettings()
   local settingsSectionName = "SettingsGeneralConditionalEffectsFramework"
   if settings == nil then
      settings = storage.globalSection(settingsSectionName)
      async:newUnsavableSimulationTimer(cef_utils.LOAD_SETTINGS_TICK_DELAY, loadSettings)
   else
      settingsUpdated(settingsSectionName)
      settings:subscribe(async:callback(settingsUpdated))
   end
end

local function cefInit()
   if #world.players == 1 then
      loadSettings()
      loadConfigFiles()
      validateEffectIDs()
   end
end


return {
   engineHandlers = {
      onPlayerAdded = function(player)
         cefInit()
         handleActiveActor(player)
      end,
      onActorActive = function(actor)
         handleActiveActor(actor)
      end,
      onActivate = function(object, actor)
         if cefSettings.cefEnable == false or cefSettings.cefLiteMode == true or types.Player.objectIsInstance(actor) ~= true or types.NPC.objectIsInstance(object) ~= true then
            return
         end
         actorsInMenu[actor.id] = { player = actor, actor = object }
      end,
      onUpdate = function()
         if cef_utils.checkSizeOfTable(actorsInMenu) > 0 then
            menuTimer.realTime = core.getRealTime()
            performPausedUpdate()
         end
      end,
   },
   eventHandlers = {
      cefAddItem = function(data)
         local item = world.createObject(data[2].itemId, data[2].quantity)
         item:moveInto(types.Actor.inventory(data[1]))
      end,
      cefRemoveItem = function(data)
         local inventory = types.Actor.inventory(data[1])
         local item = inventory:find(data[2].itemId)
         item:remove(data[2].quantity)
      end,
      cefMenuOpened = function(data)
         if actorsInMenu[data.actor.id] == nil then
            actorsInMenu[data.actor.id] = { player = data.actor }
         end
      end,
      cefUpdateVfx = function()
         for _, actor in ipairs(world.activeActors) do
            if types.NPC.objectIsInstance(actor) == true then
               actor:sendEvent("cefClearVfx", {})
            end
         end
      end,
      cefMenuClosed = function(data)
         actorsInMenu[data.actor.id] = nil
      end,
   },
}
