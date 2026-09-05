local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local ipairs = _tl_compat and _tl_compat.ipairs or ipairs; local math = _tl_compat and _tl_compat.math or math; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local core = require('openmw.core')
local types = require('openmw.types')
local anim = require('openmw.animation')
local this = require('openmw.self')
local storage = require('openmw.storage')
local nearby = require('openmw.nearby')
local async = require('openmw.async')




































































local DYNAMIC_STATS = {
   ["health"] = types.Actor.stats.dynamic.health,
   ["fatigue"] = types.Actor.stats.dynamic.fatigue,
   ["magicka"] = types.Actor.stats.dynamic.magicka,
}

local ATTRIBUTES = {
   ["agility"] = types.Actor.stats.attributes.agility,
   ["endurance"] = types.Actor.stats.attributes.endurance,
   ["intelligence"] = types.Actor.stats.attributes.intelligence,
   ["luck"] = types.Actor.stats.attributes.luck,
   ["personality"] = types.Actor.stats.attributes.personality,
   ["speed"] = types.Actor.stats.attributes.speed,
   ["strength"] = types.Actor.stats.attributes.strength,
   ["willpower"] = types.Actor.stats.attributes.willpower,
}

local SKILLS = {
   ["acrobatics"] = types.NPC.stats.skills.acrobatics,
   ["alchemy"] = types.NPC.stats.skills.alchemy,
   ["alteration"] = types.NPC.stats.skills.alteration,
   ["armorer"] = types.NPC.stats.skills.armorer,
   ["athletics"] = types.NPC.stats.skills.athletics,
   ["axe"] = types.NPC.stats.skills.axe,
   ["block"] = types.NPC.stats.skills.block,
   ["bluntweapon"] = types.NPC.stats.skills.bluntweapon,
   ["conjuration"] = types.NPC.stats.skills.conjuration,
   ["destruction"] = types.NPC.stats.skills.destruction,
   ["enchant"] = types.NPC.stats.skills.enchant,
   ["handtohand"] = types.NPC.stats.skills.handtohand,
   ["heavyarmor"] = types.NPC.stats.skills.heavyarmor,
   ["illusion"] = types.NPC.stats.skills.illusion,
   ["lightarmor"] = types.NPC.stats.skills.lightarmor,
   ["longblade"] = types.NPC.stats.skills.longblade,
   ["marksman"] = types.NPC.stats.skills.marksman,
   ["mediumarmor"] = types.NPC.stats.skills.mediumarmor,
   ["mercantile"] = types.NPC.stats.skills.mercantile,
   ["mysticism"] = types.NPC.stats.skills.mysticism,
   ["restoration"] = types.NPC.stats.skills.restoration,
   ["security"] = types.NPC.stats.skills.security,
   ["shortblade"] = types.NPC.stats.skills.shortblade,
   ["sneak"] = types.NPC.stats.skills.sneak,
   ["spear"] = types.NPC.stats.skills.spear,
   ["speechcraft"] = types.NPC.stats.skills.speechcraft,
   ["unarmored"] = types.NPC.stats.skills.unarmored,
}

local EQUIP_SLOTS = {
   ["helmet"] = 0,
   ["cuirass"] = 1,
   ["greaves"] = 2,
   ["leftpauldron"] = 3,
   ["rightpauldron"] = 4,
   ["leftgauntlet"] = 5,
   ["rightgauntlet"] = 6,
   ["boots"] = 7,
   ["shirt"] = 8,
   ["pants"] = 9,
   ["skirt"] = 10,
   ["robe"] = 11,
   ["leftring"] = 12,
   ["rightring"] = 13,
   ["amulet"] = 14,
   ["belt"] = 15,
   ["carriedright"] = 16,
   ["carriedleft"] = 17,
   ["ammunition"] = 18,
}



local configData
local varsTable
local configSettings
local settings
local distTable = {}
local effectWhitelist



local function tableHasElement(array, element)
   for _, item in ipairs(array) do
      if item == element then
         return true
      end
   end
   return false
end

local function compareRange(value, r, valueMax)
   if not r.percent then
      if ((r.min > r.max) and (value < r.min) and (value > r.max)) or ((value < r.min) or (value > r.max)) then
         return false
      end
   elseif valueMax ~= nil and valueMax ~= 0 then
      local ratio = (value / valueMax * 100)
      if ((r.min > r.max) and (ratio < r.min) and (ratio > r.max)) or ((ratio < r.min) or (ratio > r.max)) then
         return false
      end
   else
      return false
   end
   return true
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
   core.sendGlobalEvent("addItem", { actor = this.object, itemId = itemId, quantity = quantity })
end

local function removeItemFromActor(itemId, quantity)
   core.sendGlobalEvent("removeItem", { actor = this.object, itemId = itemId, quantity = quantity })
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

local function applyItemDistribution(fileName, effectId, items)
   distTable[fileName .. effectId].items = {}
   local actorInventory = types.Actor.inventory(this)
   for _, item in ipairs(items) do
      local itemIdType = type(item.itemId)
      if itemIdType == "string" then
         if item.remove == true and (item.random == nil or item.random == false) then
            local inventoryCount = itemQuantity(item.itemId, actorInventory)
            local removeQuantity = item.quantity
            if item.quantity > inventoryCount then
               removeQuantity = inventoryCount
            end
            distTable[fileName .. effectId].items[#distTable[fileName .. effectId].items + 1] = { itemId = item.itemId, remove = item.remove, quantity = removeQuantity }
            removeItemFromActor(item.itemId, removeQuantity)
         elseif item.remove == false then
            addItemToActor(item.itemId, item.quantity)
            distTable[fileName .. effectId].items[#distTable[fileName .. effectId].items + 1] = { itemId = item.itemId, remove = item.remove, quantity = item.quantity }
         end
      elseif itemIdType == "table" then
         if #(item.itemId) > 0 then

         else

         end
      end
   end
end

local function undoItemDistribution(fileName, effectId)
   local actorInventory = types.Actor.inventory(this)
   for _, item in ipairs(distTable[fileName .. effectId].items) do
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
   distTable[fileName .. effectId].items = nil
end

local STATIC_CONDITIONS = {
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

   { "isMale",
   function(_, isMale)
      return types.NPC.record(this.object).isMale == isMale
   end,
   },

   { "classes",
   function(_, classes)
      local class = types.NPC.record(this.object).class
      return classes[string.lower(class)]
   end,
   },
}

local CONDITIONS = {
   { "level",
   function(_, level)
      local actorLevel = types.Actor.stats.level(this.object)
      return compareRange(actorLevel.current, level)
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
      local leftBracer = (types.Actor.getEquipment(this.object, EQUIP_SLOTS["leftgauntlet"]))
      local rightBracer = (types.Actor.getEquipment(this.object, EQUIP_SLOTS["rightgauntlet"]))
      local hasLeftBracer = leftBracer ~= nil and leftBracer.recordId == "slave_bracer_left"
      local hasRightBracer = rightBracer ~= nil and rightBracer.recordId == "slave_bracer_right"
      return (types.NPC.record(this.object).class == "slave" and (hasRightBracer or hasLeftBracer)) == isSlave
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

   { "vars",
   function(_, vars)
      if varsTable == nil then
         return false
      end
      for k, range in pairs(vars) do
         local value = varsTable:get(k)
         if value == nil or compareRange(value, range, range.maxValue) == false then
            return false
         end
      end
      return true
   end,
   },

   { "dynStats",
   function(_, dynStats)
      for k, range in pairs(dynStats) do
         local getStat = DYNAMIC_STATS[k];
         local dynStat = getStat and getStat(this.object)
         if dynStat == nil or compareRange(dynStat.current, range, dynStat.base + dynStat.modifier) == false then
            return false
         end
      end
      return true
   end,
   },

   { "attributes",
   function(_, attributes)
      for k, range in pairs(attributes) do
         local getAttr = ATTRIBUTES[k]
         local attr = getAttr and getAttr(this.object)
         if attr == nil or compareRange(attr.modified, range, attr.base + attr.modifier) == false then
            return false
         end
      end
      return true
   end,
   },

   { "skills",
   function(_, skills)
      for k, range in pairs(skills) do
         local getSkill = SKILLS[k]
         local skill = getSkill and getSkill(this.object)
         if skill == nil or compareRange(skill.modified, range, skill.base + skill.modifier) == false then
            return false
         end
      end
      return true
   end,
   },

   { "equipment",
   function(_, equipment)
      for k, v in pairs(equipment) do
         local equipped = types.Actor.getEquipment(this.object, EQUIP_SLOTS[string.lower(k)])
         local dataType = type(v)
         if (dataType == "boolean" and v == (equipped == nil)) or
            (dataType ~= "boolean" and equipped == nil) or
            (dataType == "string" and (equipped).recordId ~= string.lower(v)) or
            (dataType == "table" and tableHasElement(v, (equipped).recordId) == false) then
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
            if v.rank and compareRange(rank, v.rank) == false then
               return false
            end
            local reputation = types.NPC.getFactionReputation(this.object, k)
            if v.reputation and compareRange(reputation, v.reputation) == false then
               return false
            end
         end
      end
      return true
   end,
   },
}

local function checkStaticConditions(effectId, conditions)
   local result = true
   for _, v1 in ipairs(conditions) do
      result = true
      for _, v2 in ipairs(STATIC_CONDITIONS) do
         local condition = (v1)[v2[1]]
         if condition ~= nil and v2[2](effectId, condition) == false then
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

local function checkConditions(effectId, conditions)
   local result = true
   for _, v1 in ipairs(conditions) do
      result = true
      for _, v2 in ipairs(CONDITIONS) do
         local condition = (v1)[v2[1]]
         if condition ~= nil and v2[2](effectId, condition) == false then
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
   if checkConditions(effectId, effect.conditions) == false then
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

local function checkEffect(fileName, effectId, effect)
   if settings:asTable().cefEnable == true and ((configSettings:asTable()["configToggle" .. fileName])[effectId] == true) then
      checkEffectConditions(fileName, effectId, effect)
   elseif distTable[fileName .. effectId] ~= nil then
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
end

local function loopThroughEffects()
   for fileName, contents in pairs(effectWhitelist) do
      for effectId, effect in pairs(contents) do
         checkEffect(fileName, effectId, effect)
      end
   end
end

local function checkNearby()
   for _, player in ipairs(nearby.players) do
      if types.Actor.isInActorsProcessingRange(player) == true then
         nearby.asyncCastRenderingRay(async:callback(
         function(result)
            if result.hit == false then
               loopThroughEffects()
            end
         end),
         player.position, (this).position, { ignore = player })

      end
   end
end

local function removeEffects()
   for k, _ in pairs(distTable) do
      distTable[k].effects = nil
   end
end

local function buildEffectWhitelist()
   for fileName, contents in pairs(configData:asTable()) do
      for effectId, effect in pairs(contents) do
         if effectWhitelist[fileName] == nil then
            effectWhitelist[fileName] = {}
         end
         if checkStaticConditions(effectId, effect.conditions) == true then
            effectWhitelist[fileName][effectId] = effect
         end
      end
   end
end

return {
   engineHandlers = {
      onSave = function()
         local saveData = {}
         saveData.distTable = distTable
         return saveData
      end,
      onLoad = function(saveData)
         distTable = saveData.distTable
      end,
      onInactive = function()
         removeEffects()
      end,
      onActive = function()
         configData = storage.globalSection("CEF_ConfigData")
         varsTable = storage.globalSection(this.object.id)
         configSettings = storage.globalSection("SettingsConditionalEffectsFrameworkConfigs")
         settings = storage.globalSection("SettingsGeneralConditionalEffectsFramework")
         if effectWhitelist == nil then
            effectWhitelist = {}
            buildEffectWhitelist()
         end
         loopThroughEffects()
      end,
      onUpdate = function()
      end,
   },
   eventHandlers = {
      cefUpdate = function()
         if next(distTable) == nil and settings:asTable().cefEnable == false then
            return
         end
         checkNearby()
      end,
   },
}
