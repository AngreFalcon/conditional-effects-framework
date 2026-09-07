local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local core = require("openmw.core")
local world = require("openmw.world")
local storage = require("openmw.storage")
local vfs = require('openmw.vfs')
local json = require('scripts.lib.json')
local types = require('openmw.types')
local async = require('openmw.async')

local ITEM_INTERFACES = {
   types.Apparatus,
   types.Armor,
   types.Book,
   types.Clothing,
   types.Ingredient,
   types.Light,
   types.Lockpick,
   types.Miscellaneous,
   types.Potion,
   types.Probe,
   types.Repair,
   types.Weapon,
}

local settings = storage.globalSection("SettingsGeneralConditionalEffectsFramework")
local loadSettingsTickDelay = 0.5
local timerRunning = false
local realTime = core.getRealTime()
local elapsedTime = 0
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

local function findSpellByID(spellId)
   local foundSpell = nil
   for _, spell in ipairs(core.magic.spells.records) do
      if spell.id == spellId then
         foundSpell = spell
         break
      end
   end
   return foundSpell
end

local function validateItemId(itemId)
   for _, itemRecord in ipairs(ITEM_INTERFACES) do
      if (itemRecord.records)[itemId] ~= nil then
         return true
      end
   end
   return false
end

local function validateEffectIDs()
   local configData = storage.globalSection("CEF_ConfigData")
   for fileName, contents in pairs(configData:asTable()) do
      for effectId, effect in pairs(contents) do
         if effect.spells ~= nil then
            for _, spell in ipairs(effect.spells) do
               local foundSpell = findSpellByID(spell.spellId)
               if foundSpell == nil then
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

local function sendUpdateEvent(actor)
   if types.NPC.objectIsInstance(actor) == true then
      syncMWVars(actor)
      actor:sendEvent("cefUpdate", {})
   end
end

local function performConditionUpdate()
   for _, actor in ipairs(world.activeActors) do
      sendUpdateEvent(actor)
   end
end

local function regenerateUpdateTimer()
   if settings:asTable().cefEnable == true and settings:asTable().cefLiteMode == false then
      performConditionUpdate()
      async:newUnsavableSimulationTimer((settings:asTable().cefTickDelay), regenerateUpdateTimer)
   else
      timerRunning = false
   end
end

local function createUpdateTimer()
   if timerRunning == false then
      async:newUnsavableSimulationTimer((settings:asTable().cefTickDelay), regenerateUpdateTimer)
      timerRunning = true
   end
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

local function clearVfx()
   for _, actor in ipairs(world.activeActors) do
      if types.NPC.objectIsInstance(actor) == true then
         actor:sendEvent("cefClearVfx", {})
      end
   end
end

local function loadSettings()
   if settings == nil then
      async:newUnsavableSimulationTimer(loadSettingsTickDelay, loadSettings)
      settings = storage.globalSection("SettingsGeneralConditionalEffectsFramework")
   end
end







return {
   engineHandlers = {
      onInit = function()
         local configData = loadConfigFiles()
         local parsedConfigData = parseConfigFiles(configData)
         storeConfigFiles(parsedConfigData)
         loadSettings()
         validateEffectIDs()
      end,
      onActorActive = function(actor)
         if types.NPC.objectIsInstance(actor) == false then
            return
         end
         storage.globalSection(actor.id):setLifeTime(storage.LIFE_TIME.GameSession)
         createUpdateTimer()
      end,
      onActivate = function(object, actor)
         if settings:asTable().cefEnable == false or settings:asTable().cefLiteMode == true or types.Player.objectIsInstance(actor) ~= true or types.NPC.objectIsInstance(object) ~= true then
            return
         end
         table.insert(actorsInMenu, { player = actor, actor = object })
      end,
      onUpdate = function()
         if next(actorsInMenu) ~= nil then
            return
         else
            realTime = core.getRealTime()
         end
         if core.isWorldPaused() == true and ((realTime - elapsedTime) >= (settings:asTable().cefMenuTickDelay)) then
            if settings:asTable().cefEnableMenuUpdates == true then
               for _, v in ipairs(actorsInMenu) do
                  v.player:sendEvent("cefUpdate", {})
                  if v.actor ~= nil then
                     v.actor:sendEvent("cefUpdate", {})
                  end
               end
            end
            elapsedTime = realTime
         end
      end,
   },
   eventHandlers = {
      cefAddItem = function(data)
         local item = world.createObject(data.itemId, data.quantity)
         item:moveInto(types.Actor.inventory(data.actor))
      end,
      cefRemoveItem = function(data)
         local inventory = types.Actor.inventory(data.actor)
         local item = inventory:find(data.itemId)
         item:remove(data.quantity)
      end,
      cefMenuOpened = function(data)
         table.insert(actorsInMenu, { player = data.actor })
      end,
      cefUpdateVfx = function()
         clearVfx()
      end,
      cefMainMenuClosed = function()
         if settings:asTable().cefEnable == true then
            createUpdateTimer()
         else
            disableAllEffects()
         end
      end,
      cefInventoryClosed = function(data)
         for i, actors in ipairs(actorsInMenu) do
            if actors.player == data.actor then
               table.remove(actorsInMenu, i)
               break
            end
         end
      end,
      cefMenuClosed = function(data)
         for i, actors in ipairs(actorsInMenu) do
            if actors.player == data.actor then
               table.remove(actorsInMenu, i)
               break
            end
         end
      end,
   },
}
