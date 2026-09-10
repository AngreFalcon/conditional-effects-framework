local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local coroutine = _tl_compat and _tl_compat.coroutine or coroutine; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local core = require('openmw.core')
local types = require('openmw.types')
local anim = require('openmw.animation')
local this = require('openmw.self')
local storage = require('openmw.storage')
local nearby = require('openmw.nearby')
local async = require('openmw.async')
local util = require('openmw.util')

local cef_utils = require('scripts.ConditionalEffectsFramework.cef-utils')


local varsTable
local configSettings = storage.globalSection("SettingsConditionalEffectsFrameworkConfigs")
local cefConfigSettings = {}
local effectWhitelist
local distTable = {}
local cefBuildWhitelistThread



local function isWithinPollingRange(pollRange)
   for _, player in ipairs(nearby.players) do
      local distance = util.vector3(
      player.position.x - this.object.position.x,
      player.position.y - this.object.position.y,
      player.position.z - this.object.position.z)

      if distance:length() <= pollRange then
         return player
      end
   end
   return nil
end

local function hasSpell(spellId, spellList)
   for _, spell in ipairs(spellList) do
      if spell.id == spellId then
         return true
      end
   end
   return false
end

local function itemQuantity(itemId, actorInventory)
   if actorInventory:find(itemId) ~= nil then
      return actorInventory:countOf(itemId)
   else
      return nil
   end
end

local function addItemToActor(itemId, quantity)
   core.sendGlobalEvent("cefAddItem", { actor = this.object, itemId = itemId, quantity = quantity })
end

local function removeItemFromActor(itemId, quantity)
   core.sendGlobalEvent("cefRemoveItem", { actor = this.object, itemId = itemId, quantity = quantity })
end

local function applyCosmetics(fileName, effectId, effects)
   distTable[fileName .. effectId].effects = {}
   for _, effectData in ipairs(effects) do
      local vfxId = fileName .. effectId .. effectData.mesh
      if vfxId == nil or anim.hasBone(this.object, effectData.node) == false then
         return
      end
      distTable[fileName .. effectId].effects[#distTable[fileName .. effectId].effects + 1] = vfxId
      anim.addVfx(this, effectData.mesh, {
         loop = true,
         boneName = effectData.node,
         vfxId = vfxId,
         useAmbientLight = false,
      })
   end
end

local function removeCosmetics(fileName, effectId)
   for _, vfxId in ipairs(distTable[fileName .. effectId].effects) do
      anim.removeVfx(this, vfxId)
   end
   distTable[fileName .. effectId].effects = nil
end

local function applySpellDistribution(fileName, effectId, spells)
   distTable[fileName .. effectId].spells = {}
   local actorSpells = types.Actor.spells(this)
   for _, spell in ipairs(spells) do
      if spell.remove == true and hasSpell(spell.spellId, actorSpells) == true then
         distTable[fileName .. effectId].spells[#distTable[fileName .. effectId].spells + 1] = { spellId = spell.spellId, remove = spell.remove };
         (actorSpells):remove(spell.spellId)
      elseif spell.remove == false and hasSpell(spell.spellId, actorSpells) == false then
         distTable[fileName .. effectId].spells[#distTable[fileName .. effectId].spells + 1] = { spellId = spell.spellId, remove = spell.remove };
         (actorSpells):add(spell.spellId)
      end
   end
end

local function undoSpellDistribution(fileName, effectId)
   local actorSpells = types.Actor.spells(this)
   for _, spell in ipairs(distTable[fileName .. effectId].spells) do
      if spell.remove == true then
         (actorSpells):add(spell.spellId)
      else
         (actorSpells):remove(spell.spellId)
      end
   end
   distTable[fileName .. effectId].spells = nil
end

local function applyItemEffect(item, dist, actorInventory)
   if item.itemId == "nil" then
      dist.itemPool[#dist.itemPool + 1] = { itemId = item.itemId, remove = nil, quantity = nil }
      return
   end
   if item.remove == true then
      local inventoryCount = itemQuantity(item.itemId, actorInventory)
      if inventoryCount ~= nil then
         local removeQuantity = item.quantity or 1
         if removeQuantity > inventoryCount then
            removeQuantity = inventoryCount
         end
         dist.itemPool[#dist.itemPool + 1] = { itemId = item.itemId, remove = item.remove, quantity = removeQuantity }
         removeItemFromActor(item.itemId, removeQuantity)
      end
   else
      local addQuantity = item.quantity or 1
      addItemToActor(item.itemId, addQuantity)
      dist.itemPool[#dist.itemPool + 1] = { itemId = item.itemId, remove = item.remove, quantity = addQuantity }
   end
end

local function applyItemDistribution(fileName, effectId, items)
   distTable[fileName .. effectId].items = {}
   local actorInventory = types.Actor.inventory(this)
   for _, itemPool in ipairs(items) do
      distTable[fileName .. effectId].items[#distTable[fileName .. effectId].items + 1] = { random = itemPool.random, itemPool = {} }
      local distTableElement = distTable[fileName .. effectId].items[#distTable[fileName .. effectId].items]
      if itemPool.random == true then
         if distTableElement.randomSeed == nil then
            distTableElement.randomSeed = math.random()
         end
         math.randomseed(distTableElement.randomSeed)
         local randomInd = math.floor(math.random(1, #itemPool.itemPool))
         local item = itemPool.itemPool[randomInd]
         applyItemEffect(item, distTableElement, actorInventory)
      else
         for _, item in ipairs(itemPool.itemPool) do
            applyItemEffect(item, distTableElement, actorInventory)
         end
      end
   end
end

local function undoItemDistribution(fileName, effectId)
   local actorInventory = types.Actor.inventory(this)
   for _, itemPool in ipairs(distTable[fileName .. effectId].items) do
      for _, item in ipairs(itemPool.itemPool) do
         if item.itemId ~= "nil" then
            if item.remove == true then
               addItemToActor(item.itemId, item.quantity)
            else
               local removeQuantity = itemQuantity(item.itemId, actorInventory)
               if removeQuantity > item.quantity then
                  removeQuantity = item.quantity
               end
               removeItemFromActor(item.itemId, removeQuantity)
            end
         end
      end
   end
   distTable[fileName .. effectId].items = nil
end

local STATIC_CONDITIONS = {
   { "isMale",
   function(_, isMale)
      return types.NPC.record(this.object).isMale == isMale
   end,
   },

   { "isPlayer",
   function(_, isPlayer)
      return types.Player.objectIsInstance(this.object) == isPlayer
   end,
   },

   { "isBeastRace",
   function(_, isBeastRace)
      local race = types.NPC.record(this.object).id
      return types.NPC.races.record(race).isBeast == isBeastRace
   end,
   },

   { "charId",
   function(_, condId)
      local charId = types.NPC.record(this.object).id
      for i = 1, #condId do
         if charId == condId[i] then
            return true
         end
      end
      return false
   end,
   },

   { "race",
   function(_, race)
      local actorRace = types.NPC.record(this.object).race
      for i = 1, #race do
         if actorRace == race[i] then
            return true
         end
      end
      return false
   end,
   },

   { "classes",
   function(_, classes)
      local class = types.NPC.record(this.object).class
      return classes[string.lower(class)]
   end,
   },

   { "getRandom",
   function(effectId, chance)
      if chance == 1 then
         return true
      elseif chance < 1 then
         return false
      end
      local seed = 0
      local seedString = this.object.id .. effectId
      for i = 1, #seedString do
         seed = seed + seedString:byte(i)
      end
      math.randomseed(seed)
      local random = math.random(1, math.floor(chance))
      return math.floor((chance / 2) + 0.5) == random
   end,
   },
}

local CONDITIONS = {
   { "level",
   function(_, level)
      local actorLevel = types.Actor.stats.level(this.object)
      return cef_utils.compareRange(actorLevel.current, level)
   end,
   },

   { "isWerewolf",
   function(_, isWerewolf)
      return types.NPC.isWerewolf(this.object) == isWerewolf
   end,
   },

   { "isDead",
   function(_, isDead)
      return types.Actor.isDead(this.object) == isDead
   end,
   },

   { "hasEffects",
   function(_, fileEffects)
      for fileName, effects in pairs(fileEffects) do
         for effectId, value in pairs(effects) do
            if (distTable[fileName .. effectId] == nil) == value then
               return false
            end
         end
      end
      return true
   end,
   },

   { "isSlave",
   function(_, isSlave)
      local leftBracer = (types.Actor.getEquipment(this.object, cef_utils.EQUIP_SLOTS["leftgauntlet"]))
      local rightBracer = (types.Actor.getEquipment(this.object, cef_utils.EQUIP_SLOTS["rightgauntlet"]))
      local hasLeftBracer = leftBracer ~= nil and leftBracer.recordId == "slave_bracer_left"
      local hasRightBracer = rightBracer ~= nil and rightBracer.recordId == "slave_bracer_right"
      return (types.NPC.record(this.object).class == "slave" and (hasRightBracer or hasLeftBracer)) == isSlave
   end,
   },

   { "vars",
   function(_, vars)
      if varsTable == nil then
         return false
      end
      for k, range in pairs(vars) do
         local value = varsTable:get(k)
         if value == nil or cef_utils.compareRange(value, range, range.maxValue) == false then
            return false
         end
      end
      return true
   end,
   },

   { "dynStats",
   function(_, dynStats)
      for k, range in pairs(dynStats) do
         local getStat = cef_utils.DYNAMIC_STATS[k];
         local dynStat = getStat and getStat(this.object)
         if dynStat == nil or cef_utils.compareRange(dynStat.current, range, dynStat.base + dynStat.modifier) == false then
            return false
         end
      end
      return true
   end,
   },

   { "attributes",
   function(_, attributes)
      for k, range in pairs(attributes) do
         local getAttr = cef_utils.ATTRIBUTES[k]
         local attr = getAttr and getAttr(this.object)
         if attr == nil or cef_utils.compareRange(attr.modified, range, attr.base + attr.modifier) == false then
            return false
         end
      end
      return true
   end,
   },

   { "skills",
   function(_, skills)
      for k, range in pairs(skills) do
         local getSkill = cef_utils.SKILLS[k]
         local skill = getSkill and getSkill(this.object)
         if skill == nil or cef_utils.compareRange(skill.modified, range, skill.base + skill.modifier) == false then
            return false
         end
      end
      return true
   end,
   },

   { "equipment",
   function(_, equipment)
      for k, v in pairs(equipment) do
         local equipped = types.Actor.getEquipment(this.object, cef_utils.EQUIP_SLOTS[string.lower(k)])
         local dataType = type(v)
         if (dataType == "boolean" and v == (equipped == nil)) or
            (dataType ~= "boolean" and equipped == nil) or
            (dataType == "string" and (equipped).recordId ~= string.lower(v)) or
            (dataType == "table" and cef_utils.tableHasElement(v, (equipped).recordId) == false) then
            return false
         end
      end
      return true
   end,
   },

   { "guilds",
   function(_, guilds)
      local actorGuilds = {}
      for _, v in ipairs(types.NPC.getFactions(this.object)) do
         actorGuilds[v] = true
      end
      for k, v in pairs(guilds) do
         if actorGuilds[k] == nil then
            return false
         else
            local rank = types.NPC.getFactionRank(this.object, k)
            if v.rank and cef_utils.compareRange(rank, v.rank) == false then
               return false
            end
            local reputation = types.NPC.getFactionReputation(this.object, k)
            if v.reputation and cef_utils.compareRange(reputation, v.reputation) == false then
               return false
            end
         end
      end
      return true
   end,
   },
}

local function checkConditions(effectId, conditionList, conditionEvalList)
   local result = true
   for _, conditionListItem in ipairs(conditionList) do
      result = true
      for _, conditionEval in ipairs(conditionEvalList) do
         local condition = (conditionListItem)[conditionEval[1]]
         if condition ~= nil and conditionEval[2](effectId, condition) == false then
            result = false
            break
         end
      end
      if result == true then
         return result
      end
   end
   return result
end

local function checkEffectConditions(fileName, effectId, effect)
   if distTable[fileName .. effectId] == nil then
      distTable[fileName .. effectId] = {}
   end
   if checkConditions(effectId, effect.conditions, CONDITIONS) == false then
      if effect.effects ~= nil and distTable[fileName .. effectId].effects ~= nil then
         removeCosmetics(fileName, effectId)
      end
      return
   end
   if effect.effects ~= nil then
      if distTable[fileName .. effectId].effects == nil then
         applyCosmetics(fileName, effectId, effect.effects)
      end
   else
      effectWhitelist[fileName][effectId] = nil
   end
   if effect.spells ~= nil and distTable[fileName .. effectId].spells == nil then
      applySpellDistribution(fileName, effectId, effect.spells)
   end
   if effect.items ~= nil and distTable[fileName .. effectId].items == nil then
      applyItemDistribution(fileName, effectId, effect.items)
   end
end

local function removeEffects(fileName, effectId, effect)
   if effectWhitelist[fileName][effectId] == nil then
      effectWhitelist[fileName][effectId] = effect
   end
   if effect.effects ~= nil and distTable[fileName .. effectId].effects ~= nil then
      removeCosmetics(fileName, effectId)
   end
   if effect.spells ~= nil and distTable[fileName .. effectId].spells ~= nil then
      undoSpellDistribution(fileName, effectId)
   end
   if effect.items ~= nil and distTable[fileName .. effectId].items ~= nil then
      undoItemDistribution(fileName, effectId)
   end
   distTable[fileName .. effectId] = nil
end

local function loopThroughEffects()
   for fileName, contents in pairs(effectWhitelist) do
      if cefConfigSettings["configToggle" .. fileName] ~= nil then
         for effectId, effect in pairs(contents) do
            if cefConfigSettings["configToggle" .. fileName][effectId] == true then
               checkEffectConditions(fileName, effectId, effect)
            end
         end
      end
   end
end

local function checkNearby(pollRange, func)
   if types.Player.objectIsInstance(this.object) == true then
      func()
   else
      local player = isWithinPollingRange(pollRange)
      if player ~= nil then
         nearby.asyncCastRenderingRay(async:callback(
         function(result)
            if result.hit == false then
               func()
            end
         end),
         player.position, (this).position, { ignore = player })

      end
   end
end

local function disableFramework()
   for fileName, contents in pairs(effectWhitelist) do
      for effectId, effect in pairs(contents) do
         if distTable[fileName .. effectId] ~= nil then
            removeEffects(fileName, effectId, effect)
         end
      end
   end
end

local function clearVfx()
   for k, _ in pairs(distTable) do
      distTable[k].effects = nil
   end
end

local function buildEffectWhitelist(configData)
   local newWhitelist = {}

   local workingConfigData
   if workingConfigData == nil then
      workingConfigData = configData
   end

   for fileName, contents in pairs(configData) do
      for effectId, effect in pairs(contents) do
         if newWhitelist[fileName] == nil then
            newWhitelist[fileName] = {}
         end
         if checkConditions(effectId, effect.conditions, STATIC_CONDITIONS) == true then
            newWhitelist[fileName][effectId] = effect
         end
      end
   end
   effectWhitelist = newWhitelist
   cef_utils.debugPrint(this.object, "Finished building whitelist for: " .. types.NPC.record(this.object).id)
   cefBuildWhitelistThread = nil
end

local function resumeBuildingWhitelist(pollingRange, configData)
   if cefBuildWhitelistThread ~= nil then
      local status = coroutine.status(cefBuildWhitelistThread)
      if status == "suspended" then
         checkNearby(pollingRange, function()
            cef_utils.debugPrint(this.object, "Resuming building whitelist for: " .. types.NPC.record(this.object).id)
            coroutine.resume(cefBuildWhitelistThread, configData)
         end)

      end
   end
end

local function configSettingsUpdated(sectionName, key)
   if sectionName ~= "SettingsConditionalEffectsFrameworkConfigs" then
      return
   end
   if key == nil then
      for fileName, contents in pairs(configSettings:asTable()) do
         if cefConfigSettings[fileName] == nil then
            cefConfigSettings[fileName] = {}
         end
         for effectId, toggle in pairs(contents) do
            cefConfigSettings[fileName][effectId] = toggle
         end
      end
   else
      for effectId, toggle in pairs((configSettings:asTable())[key]) do
         if cefConfigSettings[key][effectId] ~= toggle then
            cefConfigSettings[key][effectId] = toggle
            if toggle == false then
               local fileName = key:sub(#"configToggle" + 1)
               if distTable[fileName .. effectId] ~= nil then
                  removeEffects(fileName, effectId, effectWhitelist[fileName][effectId])
               end
            end
         end
      end
   end
end

local function loadConfigSettings()
   local sectionName = "SettingsConditionalEffectsFrameworkConfigs"
   if configSettings == nil then
      configSettings = storage.globalSection(sectionName)
      async:newUnsavableSimulationTimer(cef_utils.LOAD_SETTINGS_TICK_DELAY, loadConfigSettings)
   else
      configSettingsUpdated(sectionName, nil)
      configSettings:subscribe(async:callback(configSettingsUpdated))
   end
end


return {
   engineHandlers = {
      onInit = function()
         if effectWhitelist == nil and cefBuildWhitelistThread == nil then
            cef_utils.debugPrint(this.object, "Building whitelist for: " .. types.NPC.record(this.object).id)
            cefBuildWhitelistThread = coroutine.create(buildEffectWhitelist)
         end
         loadConfigSettings()
      end,
      onSave = function()
         local saveData = {}
         saveData.distTable = distTable
         saveData.effectWhitelist = effectWhitelist
         return saveData
      end,
      onLoad = function(saveData)
         distTable = saveData.distTable
         effectWhitelist = saveData.effectWhitelist
      end,
      onActive = function()
         varsTable = storage.globalSection(this.object.id)
      end,
      onInactive = function()
         if cefBuildWhitelistThread ~= nil then
            local status = coroutine.status(cefBuildWhitelistThread)
            if status == "running" then
               coroutine.yield(cefBuildWhitelistThread)
            end
         end
         clearVfx()
      end,
   },
   eventHandlers = {
      cefUpdate = function(data)
         local cefSettings = data.cefSettings
         if effectWhitelist ~= nil then
            checkNearby(cefSettings.cefPollRange, loopThroughEffects)
         else
            resumeBuildingWhitelist(cefSettings.cefPollRange, data.configData)
         end
      end,
      cefDisable = function()
         if next(distTable) == nil then
            return
         end
         disableFramework()
      end,
      cefRemoveEffects = function()
         clearVfx()
      end,
   },
}
