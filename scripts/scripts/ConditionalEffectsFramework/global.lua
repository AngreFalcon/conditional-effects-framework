local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local core = require("openmw.core")
local world = require("openmw.world")
local storage = require("openmw.storage")
local vfs = require('openmw.vfs')
local time = require('openmw_aux.time')
local json = require('scripts.lib.json')
local types = require('openmw.types')

local ITEM_INTERFACES = {
   types.Apparatus.records,
   types.Armor.records,
   types.Book.records,
   types.Clothing.records,
   types.Ingredient.records,
   types.Light.records,
   types.Lockpick.records,
   types.Miscellaneous.records,
   types.Potion.records,
   types.Probe.records,
   types.Repair.records,
   types.Weapon.records,
}

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
   for _, itemRecords in ipairs(ITEM_INTERFACES) do
      if (itemRecords)[itemId] ~= nil then
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
            for _, item in ipairs(effect.items) do
               local itemIdType = type(item.itemId)
               if itemIdType == "string" then
                  if validateItemId(item.itemId) == false then
                     print("Item could not be found by ID: " .. item.itemId .. " in file: " .. fileName .. " for effect: " .. effectId)
                  end
               elseif itemIdType == "table" then
                  if #item.itemId > 0 then
                     for _, v in ipairs(item.itemId) do
                        if v ~= "nil" and validateItemId(v) == false then
                           print("Item could not be found by ID: " .. v .. " in file: " .. fileName .. " for effect: " .. effectId)
                        end
                     end
                  else
                     for _, v in pairs(item.itemId) do
                        if v ~= "nil" and validateItemId(v) == false then
                           print("Item could not be found by ID: " .. v .. " in file: " .. fileName .. " for effect: " .. effectId)
                        end
                     end
                  end
               end
            end
         end
      end
   end
end







return {
   engineHandlers = {
      onInit = function()
         local configData = loadConfigFiles()
         local parsedConfigData = parseConfigFiles(configData)
         storeConfigFiles(parsedConfigData)
         validateEffectIDs()
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
