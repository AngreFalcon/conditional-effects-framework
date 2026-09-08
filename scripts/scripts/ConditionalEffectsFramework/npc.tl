local core = require('openmw.core')
local types = require('openmw.types')
local anim = require('openmw.animation')
local this = require('openmw.self')
local storage = require('openmw.storage')
local nearby = require('openmw.nearby')
local async = require('openmw.async')
local util = require('openmw.util')

local cef_utils = require('scripts.ConditionalEffectsFramework.cef-utils')

-- variables
local varsTable: storage.StorageSection
local configSettings: storage.StorageSection
local distTable: { string: CEFDistributionTable } = {}
local effectWhitelist: { string: { string: CEFConfig } }
local buildingWhitelist: thread
-- end variables

-- functions
local function isWithinPollingRange(player: util.Vector3, pollRange: number): boolean
	local distance: util.Vector3 = util.vector3(player.x - this.object.position.x, player.y - this.object.position.y, player.z - this.object.position.z)
	if distance:length() > pollRange then
		return false
	else
		return true
	end
end

local function hasSpell(spellId: string, spellList: { core.Spell }): boolean
	for _, spell in ipairs(spellList) do
		if spell.id == spellId then
			return true
		end
	end
	return false
end

local function itemQuantity(itemId: string, actorInventory: core.Inventory): number
	if actorInventory:find(itemId) ~= nil then
		return actorInventory:countOf(itemId)
	else
		return nil
	end
end

local function addItemToActor(itemId: string, quantity: number)
	core.sendGlobalEvent("cefAddItem", { actor = this.object, itemId = itemId, quantity = quantity })
end

local function removeItemFromActor(itemId: string, quantity: number)
	core.sendGlobalEvent("cefRemoveItem", { actor = this.object, itemId = itemId, quantity = quantity })
end

local function applyCosmetics(fileName: string, effectId: string, effects: { CEFEffect })
	distTable[fileName .. effectId].effects = {}
	for _, effectData in ipairs(effects) do
		local vfxId = fileName .. effectId .. effectData.mesh
		if vfxId == nil or anim.hasBone(this.object, effectData.node) == false then
			return
		end
		distTable[fileName .. effectId].effects[#distTable[fileName .. effectId].effects + 1] = vfxId
		anim.addVfx(this as core.GameObject, effectData.mesh, {
    		loop = true,
    		boneName = effectData.node,
			vfxId = vfxId,
			useAmbientLight = false,
  		})
	end
end

local function removeCosmetics(fileName: string, effectId: string)
	for _, vfxId in ipairs(distTable[fileName .. effectId].effects) do
		anim.removeVfx(this as core.GameObject, vfxId)
	end
	distTable[fileName .. effectId].effects = nil
end

local function applySpellDistribution(fileName: string, effectId: string, spells: { CEFSpell })
	distTable[fileName .. effectId].spells = {}
	local actorSpells = types.Actor.spells(this as core.GameObject) as { core.Spell }
	for _, spell in ipairs(spells) do
		if spell.remove == true and hasSpell(spell.spellId, actorSpells) == true then
			distTable[fileName .. effectId].spells[#distTable[fileName .. effectId].spells + 1] = { spellId = spell.spellId, remove = spell.remove }
			(actorSpells as types.ActorSpells):remove(spell.spellId)
		elseif spell.remove == false and hasSpell(spell.spellId, actorSpells) == false then
			distTable[fileName .. effectId].spells[#distTable[fileName .. effectId].spells + 1] = { spellId = spell.spellId, remove = spell.remove }
			(actorSpells as types.ActorSpells):add(spell.spellId)
		end
	end
end

local function undoSpellDistribution(fileName: string, effectId: string)
	local actorSpells = types.Actor.spells(this as core.GameObject) as { core.Spell }
	for _, spell in ipairs(distTable[fileName .. effectId].spells) do
		if spell.remove == true then
			(actorSpells as types.ActorSpells):add(spell.spellId)
		else
			(actorSpells as types.ActorSpells):remove(spell.spellId)
		end
	end
	distTable[fileName .. effectId].spells = nil
end

local function applyItemEffect(item: CEFItem, dist: CEFItemPool, actorInventory: core.Inventory)
	if item.itemId == "nil" then
		dist.itemPool[#dist.itemPool + 1] = { itemId = item.itemId, remove = nil, quantity = nil }
		return
	end
	if item.remove == true then
		local inventoryCount = itemQuantity(item.itemId, actorInventory)
		if inventoryCount ~= nil then
			local removeQuantity: number = item.quantity or 1
			if removeQuantity > inventoryCount then
				removeQuantity = inventoryCount
			end
			dist.itemPool[#dist.itemPool + 1] = { itemId = item.itemId, remove = item.remove, quantity = removeQuantity }
			removeItemFromActor(item.itemId, removeQuantity)
		end
	else
		local addQuantity: number = item.quantity or 1
		addItemToActor(item.itemId, addQuantity)
		dist.itemPool[#dist.itemPool + 1] = { itemId = item.itemId, remove = item.remove, quantity = addQuantity }
	end
end

local function applyItemDistribution(fileName: string, effectId: string, items: { CEFItemPool })
	distTable[fileName .. effectId].items = {}
	local actorInventory = types.Actor.inventory(this as core.GameObject)
	for _, itemPool in ipairs(items) do
		distTable[fileName .. effectId].items[#distTable[fileName .. effectId].items + 1] = { random = itemPool.random, itemPool = {}}
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

local function undoItemDistribution(fileName: string, effectId: string)
	local actorInventory = types.Actor.inventory(this as core.GameObject)
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

local STATIC_CONDITIONS <const>: { { string, function(string, any) } } = {
	{ "isMale",
		function(_, isMale: boolean): boolean
			return types.NPC.record(this.object as types.Actor).isMale == isMale
		end
	},

	{ "isPlayer",
		function(_, isPlayer: boolean): boolean
			return types.Player.objectIsInstance(this.object) == isPlayer
		end
	},

	{ "isBeastRace",
		function(_, isBeastRace: boolean): boolean
			local race: string = types.NPC.record(this.object).id
			return types.NPC.races.record(race).isBeast == isBeastRace
		end
	},

	{ "charId",
		function(_, condId: { string }): boolean
			local charId = types.NPC.record(this.object as types.Actor).id
			for i = 1, #condId do
				if charId == condId[i] then
					return true
				end
			end
			return false
		end
	},

	{ "race",
		function(_, race: { string }): boolean
			local actorRace = types.NPC.record(this.object as types.Actor).race
			for i = 1, #race do
				if actorRace == race[i] then
					return true
				end
			end
			return false
		end
	},

	{ "classes",
		function(_, classes: { string: boolean }): boolean
			local class = types.NPC.record(this.object).class
			return classes[string.lower(class)]
		end
	},

	{ "getRandom",
		function(effectId: string, chance: number): boolean
			if chance == 1 then
				return true
			elseif chance < 1 then
				return false
			end
			local seed: integer = 0
			local seedString: string = this.object.id .. effectId
			for i = 1, #seedString do
				seed = seed + seedString:byte(i)
			end
			math.randomseed(seed)
			local random = math.random(1, math.floor(chance))
			return math.floor((chance / 2) + 0.5) == random
		end
	},
}

local CONDITIONS <const>: { { string, function(string, any) } } = {
	{ "level", 
		function(_, level: CEFRange): boolean
			local actorLevel = types.Actor.stats.level(this.object)
			return cef_utils.compareRange(actorLevel.current, level)
		end
	},

	{ "isWerewolf",
		function(_, isWerewolf: boolean): boolean
			return types.NPC.isWerewolf(this.object) == isWerewolf
		end
	},

	{ "isDead",
		function(_, isDead: boolean): boolean
			return types.Actor.isDead(this.object) == isDead
		end
	},

	{ "hasEffects",
		function(_, fileEffects: { string: { string: boolean } }): boolean
			for fileName, effects in pairs(fileEffects) do
				for effectId, value in pairs(effects) do
					if (distTable[fileName .. effectId] == nil) == value then
						return false
					end
				end
			end
			return true
		end
	},

	{ "isSlave",
		function(_, isSlave: boolean): boolean
			local leftBracer = (types.Actor.getEquipment(this.object, cef_utils.EQUIP_SLOTS["leftgauntlet"]) as core.GameObject)
			local rightBracer = (types.Actor.getEquipment(this.object, cef_utils.EQUIP_SLOTS["rightgauntlet"]) as core.GameObject)
			local hasLeftBracer: boolean = leftBracer ~= nil and leftBracer.recordId == "slave_bracer_left"
			local hasRightBracer: boolean = rightBracer ~= nil and rightBracer.recordId == "slave_bracer_right"
			return (types.NPC.record(this.object).class == "slave" and (hasRightBracer or hasLeftBracer)) == isSlave
		end
	},

	{ "vars",
		function(_, vars: { string: CEFRange }): boolean
			if varsTable == nil then
				return false
			end
			for k, range in pairs(vars) do
				local value = varsTable:get(k)
				if value == nil or cef_utils.compareRange(value as integer, range, range.maxValue) == false then
					return false
				end
			end
			return true
		end
	},

	{ "dynStats",
		function(_, dynStats: { string: CEFRange }): boolean
			for k, range in pairs(dynStats) do
				local getStat = cef_utils.DYNAMIC_STATS[k];
				local dynStat = getStat and getStat(this.object)
				if dynStat == nil or cef_utils.compareRange(dynStat.current, range, dynStat.base + dynStat.modifier) == false then
					return false
				end
			end
			return true
		end
	},

	{ "attributes",
		function(_, attributes: { string: CEFRange }): boolean
			for k, range in pairs(attributes) do
				local getAttr = cef_utils.ATTRIBUTES[k]
				local attr = getAttr and getAttr(this.object)
				if attr == nil or cef_utils.compareRange(attr.modified, range, attr.base + attr.modifier) == false then
					return false
				end
			end
			return true
		end
	},

	{ "skills",
		function(_, skills: { string: CEFRange }): boolean
			for k, range in pairs(skills) do
				local getSkill = cef_utils.SKILLS[k]
				local skill = getSkill and getSkill(this.object)
				if skill == nil or cef_utils.compareRange(skill.modified, range, skill.base + skill.modifier) == false then
					return false
				end
			end
			return true
		end
	},

	{ "equipment",
		function(_, equipment: { string: boolean }): boolean
			for k, v in pairs(equipment) do
				local equipped = types.Actor.getEquipment(this.object, cef_utils.EQUIP_SLOTS[string.lower(k)])
				local dataType = type(v)
				if (dataType == "boolean" and v == (equipped == nil))
				or (dataType ~= "boolean" and equipped == nil)
				or (dataType == "string" and (equipped as core.GameObject).recordId ~= string.lower(v as string))
				or (dataType == "table" and cef_utils.tableHasElement(v as { string }, (equipped as core.GameObject).recordId) == false) then
					return false
				end
			end
			return true
		end
	},

	{ "guilds",
		function(_, guilds: { string: CEFGuild }): boolean
			local actorGuilds: { string: boolean } = {}
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
		end
	},
}

local function checkStaticConditions(effectId: string, conditions: { CEFCondition }): boolean
	local result: boolean = true
	for _, v1 in ipairs(conditions) do
		result = true
		for _, v2 in ipairs(STATIC_CONDITIONS) do
			local condition = (v1 as { string: any })[v2[1]]
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

local function buildEffectWhitelist(configData: { string: { string: CEFConfig } })
	local newWhitelist: { string: { string: CEFConfig } } = {}
	for fileName, contents in pairs(configData) do
		for effectId, effect in pairs(contents as { string: CEFConfig }) do
			if newWhitelist[fileName] == nil then
				newWhitelist[fileName] = {}
			end
			if checkStaticConditions(effectId, effect.conditions) == true then
				newWhitelist[fileName][effectId] = effect
			end
		end
	end
	effectWhitelist = newWhitelist
end

local function resumeBuildingWhitelist(configData: { string: { string: CEFConfig } })
	if buildingWhitelist ~= nil then
		local status: string = coroutine.status(buildingWhitelist)
		if status == "suspended" then
			coroutine.resume(buildingWhitelist, configData)
		elseif status == "dead" then
			buildingWhitelist = nil
		end
	end
end

local function checkConditions(effectId: string, conditions: { CEFCondition }): boolean
	local result: boolean = true
	for _, v1 in ipairs(conditions) do
		result = true
		for _, v2 in ipairs(CONDITIONS) do
			local condition = (v1 as { string: any })[v2[1]]
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

local function checkEffectConditions(fileName: string, effectId: string, effect: CEFConfig)
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
	else -- this effect contains no vfx. because items and spells are only applied once and never again, remove this effect from the whitelist; we no longer need to evaluate it for this actor
		effectWhitelist[fileName][effectId] = nil
	end
	if effect.spells ~= nil and distTable[fileName .. effectId].spells == nil then
		applySpellDistribution(fileName, effectId, effect.spells)
	end
	if effect.items ~= nil and distTable[fileName .. effectId].items == nil then
		applyItemDistribution(fileName, effectId, effect.items)
	end
end

local function removeEffects(fileName: string, effectId: string, effect: CEFConfig)
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

local function loopThroughEffects(cefSettings: CEFSettings)
	for fileName, contents in pairs(effectWhitelist) do
		for effectId, effect in pairs(contents as { string: CEFConfig }) do
			if cefSettings.cefEnable == true and (configSettings:asTable()["configToggle" .. fileName] as { string: boolean })[effectId] == true then
				checkEffectConditions(fileName, effectId, effect)
			elseif distTable[fileName .. effectId] ~= nil then -- only executes if the effect is disabled or cef is disabled, and the effect is still applied
				removeEffects(fileName, effectId, effect)
			end
		end
	end
end

local function checkNearby(cefSettings: CEFSettings)
	if effectWhitelist == nil then -- actor has no effects to poll for; don't bother doing any processing on them
		return
	end
	if types.Player.objectIsInstance(this.object) == true then
		loopThroughEffects(cefSettings)
	else
		for _, player in ipairs(nearby.players) do
			if isWithinPollingRange(player.position, cefSettings.cefPollRange) == true then
				nearby.asyncCastRenderingRay(async:callback(
					function(result: nearby.RayCastingResult)
						if result.hit == false then
							loopThroughEffects(cefSettings)
						end
					end),
					player.position, (this as core.GameObject).position, { ignore = player }
				)
			end
		end
	end
end

local function clearVfx()
	for k, _ in pairs(distTable) do
		distTable[k].effects = nil
	end
end
-- end functions

return {
   	engineHandlers = {
		onInit = function()
			if effectWhitelist == nil and buildingWhitelist == nil then
				buildingWhitelist = coroutine.create(buildEffectWhitelist)
			elseif buildingWhitelist ~= nil and coroutine.status(buildingWhitelist) == "dead" then
				buildingWhitelist = nil
			end
		end,
		onSave = function(): CEFSaveData
			local saveData: CEFSaveData = {}
			saveData.distTable = distTable
			saveData.effectWhitelist = effectWhitelist
			return saveData
		end,
		onLoad = function(saveData: CEFSaveData)
			distTable = saveData.distTable
			effectWhitelist = saveData.effectWhitelist
		end,
		onActive = function()
			varsTable = storage.globalSection(this.object.id)
			configSettings = storage.globalSection("SettingsConditionalEffectsFrameworkConfigs")
		end,
		onInactive = function()
			if buildingWhitelist ~= nil then
				local status: string = coroutine.status(buildingWhitelist)
				if status == "running" then
					coroutine.yield(buildingWhitelist)
				elseif status == "dead" then
					buildingWhitelist = nil
				end
			end
			clearVfx()
		end,
   	},
	eventHandlers = {
		cefUpdate = function(cefSettings: CEFSettings)
			checkNearby(cefSettings)
		end,
		cefDisable = function(cefSettings: CEFSettings)
			if next(distTable) == nil then -- no effects to remove
				return
			end
			checkNearby(cefSettings)
		end,
		cefRemoveEffects = function()
			clearVfx()
		end,
		cefResumeBuildingWhitelist = function(configData: { string: { string: CEFConfig } })
			resumeBuildingWhitelist(configData)
		end,
	},
}