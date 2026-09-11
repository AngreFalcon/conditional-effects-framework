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
local configSettings: storage.StorageSection = storage.globalSection("SettingsConditionalEffectsFrameworkConfigs")
local cefConfigSettings: { string: { string: boolean } } = {}
local effectWhitelist: { string: { string: CEFConfig } }
local distTable: { string: CEFDistributionTable } = {}
local conditionState: { string: { string: { number: { string: boolean } } } } = {} -- fileName -> effectId -> condition list index -> condition type
local cefBuildWhitelistThread: thread
-- end variables

-- functions
local function isWithinPollingRange(pollRange: number): core.GameObject
	for _, player in ipairs(nearby.players) do
		local distance: util.Vector3 = util.vector3(
			player.position.x - this.object.position.x,
			player.position.y - this.object.position.y,
			player.position.z - this.object.position.z
		)
		if distance:length() <= pollRange then
			return player
		end
	end
	return nil
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

local STATIC_CONDITIONS <const>: { CEFConditionEval } = {
	{ 
		conditionType = "isMale",
		eventDriven = false,
		conditionEval = function(_, isMale: boolean): boolean
			return types.NPC.record(this.object as types.Actor).isMale == isMale
		end,
	},

	{
		conditionType = "isPlayer",
		eventDriven = false,
		conditionEval = function(_, isPlayer: boolean): boolean
			return types.Player.objectIsInstance(this.object) == isPlayer
		end
	},

	{
		conditionType = "isBeastRace",
		eventDriven = false,
		conditionEval = function(_, isBeastRace: boolean): boolean
			local race: string = types.NPC.record(this.object).id
			return types.NPC.races.record(race).isBeast == isBeastRace
		end
	},

	{
		conditionType = "charId",
		eventDriven = false,
		conditionEval = function(_, condId: { string }): boolean
			local charId = types.NPC.record(this.object as types.Actor).id
			for i = 1, #condId do
				if charId == condId[i] then
					return true
				end
			end
			return false
		end
	},

	{
		conditionType = "race",
		eventDriven = false,
		conditionEval = function(_, race: { string }): boolean
			local actorRace = types.NPC.record(this.object as types.Actor).race
			for i = 1, #race do
				if actorRace == race[i] then
					return true
				end
			end
			return false
		end
	},

	{
		conditionType = "classes",
		eventDriven = false,
		conditionEval = function(_, classes: { string: boolean }): boolean
			local class = types.NPC.record(this.object).class
			return classes[string.lower(class)]
		end
	},

	{
		conditionType = "getRandom",
		eventDriven = false,
		conditionEval = function(effectId: string, chance: number): boolean
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

local CONDITIONS <const>: { CEFConditionEval } = {
	{
		conditionType = "level",
		eventDriven = false,
		conditionEval = function(_, level: CEFRange): boolean
			local actorLevel = types.Actor.stats.level(this.object)
			return cef_utils.compareRange(actorLevel.current, level)
		end
	},

	{
		conditionType = "isWerewolf",
		eventDriven = false,
		conditionEval = function(_, isWerewolf: boolean): boolean
			return types.NPC.isWerewolf(this.object) == isWerewolf
		end
	},

	{
		conditionType = "isDead",
		eventDriven = false,
		conditionEval = function(_, isDead: boolean): boolean
			return types.Actor.isDead(this.object) == isDead
		end
	},

	{
		conditionType = "hasEffects",
		eventDriven = true,
		conditionEval = function(_, fileEffects: { string: { string: boolean } }): boolean
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

	{
		conditionType = "isSlave",
		eventDriven = false,
		conditionEval = function(_, isSlave: boolean): boolean
			local leftBracer = (types.Actor.getEquipment(this.object, cef_utils.EQUIP_SLOTS["leftgauntlet"]) as core.GameObject)
			local rightBracer = (types.Actor.getEquipment(this.object, cef_utils.EQUIP_SLOTS["rightgauntlet"]) as core.GameObject)
			local hasLeftBracer: boolean = leftBracer ~= nil and leftBracer.recordId == "slave_bracer_left"
			local hasRightBracer: boolean = rightBracer ~= nil and rightBracer.recordId == "slave_bracer_right"
			return (types.NPC.record(this.object).class == "slave" and (hasRightBracer or hasLeftBracer)) == isSlave
		end
	},

	{
		conditionType = "vars",
		eventDriven = false,
		conditionEval = function(_, vars: { string: CEFRange }): boolean
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

	{
		conditionType = "dynStats",
		eventDriven = false,
		conditionEval = function(_, dynStats: { string: CEFRange }): boolean
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

	{
		conditionType = "attributes",
		eventDriven = false,
		conditionEval = function(_, attributes: { string: CEFRange }): boolean
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

	{
		conditionType = "skills",
		eventDriven = false,
		conditionEval = function(_, skills: { string: CEFRange }): boolean
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

	{
		conditionType = "equipment",
		eventDriven = false,
		conditionEval = function(_, equipment: { string: boolean }): boolean
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

	{
		conditionType = "guilds",
		eventDriven = false,
		conditionEval = function(_, guilds: { string: CEFGuild }): boolean
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

local function checkCondition(effectId: string, conditionListItem: CEFCondition, conditionEvalList: { CEFConditionEval }, fileName?: string, conditionInd?: number): boolean
	for _, conditionType in ipairs(conditionEvalList) do
		local condition = (conditionListItem as { string: any })[conditionType.conditionType]

		if condition ~= nil then
			if conditionInd == nil or conditionType.eventDriven == false then
				if conditionType.conditionEval(effectId, condition) == false then
					return false
				end
			else
				if conditionState[fileName][effectId][conditionInd][conditionType.conditionType] == nil then
					conditionState[fileName][effectId][conditionInd][conditionType.conditionType] = conditionType.conditionEval(effectId, condition) as boolean
				end
				
				if conditionState[fileName][effectId][conditionInd][conditionType.conditionType] == false then
					return false
				end
			end
		end
	end
	return true
end

local function checkEffectConditions(fileName: string, effectId: string, effect: CEFConfig)
	if distTable[fileName .. effectId] == nil then
		distTable[fileName .. effectId] = {}
	end
	for conditionInd, condition in ipairs(effect.conditions) do
		if checkCondition(effectId, condition, CONDITIONS, fileName, conditionInd) == true then
			--this.object:sendEvent("cefEffectAdded", { fileName = fileName, effectId = effectId, conditionInd = conditionInd })
			break
		end
		if conditionInd == #effect.conditions then
			if effect.effects ~= nil and distTable[fileName .. effectId].effects ~= nil then
				removeCosmetics(fileName, effectId)
			end
			return
		end
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

local function loopThroughEffects()
	for fileName, contents in pairs(effectWhitelist) do
		if cefConfigSettings["configToggle" .. fileName] ~= nil then
			for effectId, effect in pairs(contents as { string: CEFConfig }) do
				if cefConfigSettings["configToggle" .. fileName][effectId] == true then
					checkEffectConditions(fileName, effectId, effect)
				end
			end
		end
	end
end

local function checkNearby(pollRange: number, func: function())
	if types.Player.objectIsInstance(this.object) == true then
		func()
	else
		local player: core.GameObject = isWithinPollingRange(pollRange)
		if player ~= nil then
			nearby.asyncCastRenderingRay(async:callback(
				function(result: nearby.RayCastingResult)
					if result.hit == false then
						func()
					end
				end),
				player.position, (this as core.GameObject).position, { ignore = player }
			)
		end
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

local function disableFramework()
	for fileName, contents in pairs(effectWhitelist) do
		for effectId, effect in pairs(contents as { string: CEFConfig }) do
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

local function buildEffectWhitelist(configData: { string: { string: CEFConfig } })
	local newWhitelist: { string: { string: CEFConfig } } = {}
	
	local workingConfigData: { string: { string: CEFConfig } }
	if workingConfigData == nil then
		workingConfigData = configData
	end

	for fileName, contents in pairs(configData) do
		for effectId, effect in pairs(contents as { string: CEFConfig }) do
			for _, condition in ipairs(effect.conditions) do
				if checkCondition(effectId, condition, STATIC_CONDITIONS) == true then
					if newWhitelist[fileName] == nil then
						newWhitelist[fileName] = {}
						conditionState[fileName] = {}
					end
					if newWhitelist[fileName][effectId] == nil then
						newWhitelist[fileName][effectId] = {
							effects = effect.effects,
							spells = effect.spells,
							items = effect.items,
							conditions = {},
						}
						conditionState[fileName][effectId] = {}
					end
					table.insert(newWhitelist[fileName][effectId].conditions, condition)
					table.insert(conditionState[fileName][effectId], {})
				end
			end
		end
	end
	effectWhitelist = newWhitelist
	cef_utils.debugPrint(this.object, "Finished building whitelist for: " .. types.NPC.record(this.object).id)
	cefBuildWhitelistThread = nil
end

local function resumeBuildingWhitelist(pollingRange: number, configData?: { string: { string: CEFConfig } })
	if cefBuildWhitelistThread ~= nil then
		local status: string = coroutine.status(cefBuildWhitelistThread)
		if status == "suspended" then
			checkNearby(pollingRange, function()
					cef_utils.debugPrint(this.object, "Resuming building whitelist for: " .. types.NPC.record(this.object).id)
					coroutine.resume(cefBuildWhitelistThread, configData)
				end
			)
		end
	end
end

local function configSettingsUpdated(sectionName: string, key?: string)
	if sectionName ~= "SettingsConditionalEffectsFrameworkConfigs" then
		return
	end
	if key == nil then
		for fileName, contents in pairs(configSettings:asTable() as { string: { string: boolean } }) do
			if cefConfigSettings[fileName] == nil then
				cefConfigSettings[fileName] = {}
			end
			for effectId, toggle in pairs(contents) do
				cefConfigSettings[fileName][effectId] = toggle
			end
		end
	else
		for effectId, toggle in pairs((configSettings:asTable() as { string: { string: boolean } })[key]) do
			if cefConfigSettings[key][effectId] ~= toggle then
				cefConfigSettings[key][effectId] = toggle
				if toggle == false then
					local fileName: string = key:sub(#"configToggle" + 1)
					if distTable[fileName .. effectId] ~= nil then -- only executes if the effect is disabled, and the effect is still applied
						removeEffects(fileName, effectId, effectWhitelist[fileName][effectId])
					end
				end
			end
		end
	end
end

local function loadConfigSettings()
	local sectionName: string = "SettingsConditionalEffectsFrameworkConfigs"
	if configSettings == nil then
		configSettings = storage.globalSection(sectionName)
		async:newUnsavableSimulationTimer(cef_utils.LOAD_SETTINGS_TICK_DELAY, loadConfigSettings)
	else
		configSettingsUpdated(sectionName, nil)
		configSettings:subscribe(async:callback(configSettingsUpdated))
	end
end
-- end functions

return {
   	engineHandlers = {
		onInit = function()
			if effectWhitelist == nil and cefBuildWhitelistThread == nil then
				cef_utils.debugPrint(this.object, "Building whitelist for: " .. types.NPC.record(this.object).id)
				cefBuildWhitelistThread = coroutine.create(buildEffectWhitelist)
			end
			loadConfigSettings()
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
		end,
		onInactive = function()
			if cefBuildWhitelistThread ~= nil then
				local status: string = coroutine.status(cefBuildWhitelistThread)
				if status == "running" then
					coroutine.yield(cefBuildWhitelistThread)
				end
			end
			clearVfx()
		end,
   	},
	eventHandlers = {
		cefUpdate = function(data: { string: any })
			local cefSettings = data.cefSettings as CEFSettings
			if effectWhitelist ~= nil then
				checkNearby(cefSettings.cefPollRange, loopThroughEffects)
			else
				resumeBuildingWhitelist(cefSettings.cefPollRange, data.configData as { string: { string: CEFConfig } })
			end
		end,
		cefDisable = function()
			if next(distTable) == nil then -- no effects to remove
				return
			end
			disableFramework()
		end,
		cefRemoveEffects = function()
			clearVfx()
		end,
		cefEffectAdded = function()

		end,
	},
}