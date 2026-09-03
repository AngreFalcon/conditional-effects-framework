local core = require('openmw.core')
local types = require('openmw.types')
local anim = require('openmw.animation')
local this = require('openmw.self')
local storage = require('openmw.storage')
local time = require('openmw_aux.time')
local nearby = require('openmw.nearby')

-- interfaces
local interface CEFRange 
	min: number
	max: number
	percent: boolean
	maxValue: number
end

local interface CEFGuild
	rank: CEFRange
	reputation: CEFRange
end

local interface CEFCondition
	charId: { string }
	race: { string }
	level: CEFRange
	isMale: boolean
	isWerewolf: boolean
	isDead: boolean
	isSlave: boolean
	vars: { string: CEFRange }
	dynStats: { string: CEFRange }
	attributes: { string: CEFRange }
	skills: { string: CEFRange }
	equipment: { string: boolean }
	classes: { string: boolean }
	guilds: { string: CEFGuild }
	effects: { string: { string: boolean } }
end

local interface CEFEffect
	mesh: string
	node: string
end

local interface CEFSpell
	spellId: string
	remove: boolean
end

local interface CEFItem
	itemId: string
	quantity: number
	remove: boolean
	random: boolean
end

local interface CEFConfig
	conditions: { CEFCondition }
	effects: { CEFEffect }
	spells: { CEFSpell }
	items: { CEFItem }
end

local interface DistributionTable
	effects: { string }
	spells: { CEFSpell }
	items: { CEFItem }
end

local interface SaveData
	distTable: { string: DistributionTable }
end
-- end interfaces

-- constants
local DYNAMIC_STATS <const>: { string: function(core.GameObject): types.DynamicStat } = {
	["health"] = types.Actor.stats.dynamic.health,
	["fatigue"] = types.Actor.stats.dynamic.fatigue,
	["magicka"] = types.Actor.stats.dynamic.magicka,
}

local ATTRIBUTES <const>: { string: function(core.GameObject): types.AttributeStat } = {
	["agility"] = types.Actor.stats.attributes.agility,
	["endurance"] = types.Actor.stats.attributes.endurance,
	["intelligence"] = types.Actor.stats.attributes.intelligence,
	["luck"] = types.Actor.stats.attributes.luck,
	["personality"] = types.Actor.stats.attributes.personality,
	["speed"] = types.Actor.stats.attributes.speed,
	["strength"] = types.Actor.stats.attributes.strength,
	["willpower"] = types.Actor.stats.attributes.willpower,
}

local SKILLS <const>: { string: function(core.GameObject): types.SkillStat } = {
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

local EQUIP_SLOTS <const>: { string: number } = {
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
-- end constants

-- variables
local realTime: number = core.getRealTime()
local elapsedTime: number = 0
local configData: storage.StorageSection
local varsTable: storage.StorageSection
local configSettings: storage.StorageSection
local settings: storage.StorageSection
local distTable: { string: DistributionTable } = {} -- effectId.spell/item = true/false
local effectWhitelist: { string: { string: CEFConfig } }
-- end variables

-- functions
local function tableHasElement(array: { any }, element: any): boolean
	for _, item in ipairs(array) do
		if item == element then
			return true
		end
	end
	return false
end

local function compareRange(value: number, r: CEFRange, valueMax?: number): boolean
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
	core.sendGlobalEvent("addItem", { actor = this.object, itemId = itemId, quantity = quantity })
end

local function removeItemFromActor(itemId: string, quantity: number)
	core.sendGlobalEvent("removeItem", { actor = this.object, itemId = itemId, quantity = quantity })
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

local function applyItemDistribution(fileName: string, effectId: string, items: { CEFItem })
	distTable[fileName .. effectId].items = {}
	local actorInventory = types.Actor.inventory(this as core.GameObject)
	for _, item in ipairs(items) do
		local itemIdType = type(item.itemId)
		if itemIdType == "string" then
			if item.remove == true and (item.random == nil or item.random == false) then
				local inventoryCount = itemQuantity(item.itemId, actorInventory)
				local removeQuantity: number = item.quantity
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
			if #(item.itemId as { any }) > 0 then -- itemId is a list of items
			
			else -- itemId is a table of items, whose keys should be numerical and represent the random chance of that particular item being selected from the item pool

			end
		end
	end
end

local function undoItemDistribution(fileName: string, effectId: string)
	local actorInventory = types.Actor.inventory(this as core.GameObject)
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

local STATIC_CONDITIONS <const>: { { string, function(string, any) } } = {
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

	{ "isMale",
		function(_, isMale: boolean): boolean
			return types.NPC.record(this.object as types.Actor).isMale == isMale
		end
	},

	{ "classes",
		function(_, classes: { string: boolean }): boolean
			local class = types.NPC.record(this.object).class
			return classes[string.lower(class)]
		end
	},
}

local CONDITIONS <const>: { { string, function(string, any) } } = {
	{ "level", 
		function(_, level: CEFRange): boolean
			local actorLevel = types.Actor.stats.level(this.object)
			return compareRange(actorLevel.current, level)
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

	{ "isPlayer",
		function(_, isPlayer: boolean): boolean
			return types.Player.objectIsInstance(this.object) == isPlayer
		end
	},

	{ "isSlave",
		function(_, isSlave: boolean): boolean
			local leftBracer = (types.Actor.getEquipment(this.object, EQUIP_SLOTS["leftgauntlet"]) as core.GameObject)
			local rightBracer = (types.Actor.getEquipment(this.object, EQUIP_SLOTS["rightgauntlet"]) as core.GameObject)
			local hasLeftBracer: boolean = leftBracer ~= nil and leftBracer.recordId == "slave_bracer_left"
			local hasRightBracer: boolean = rightBracer ~= nil and rightBracer.recordId == "slave_bracer_right"
			return (types.NPC.record(this.object).class == "slave" and (hasRightBracer or hasLeftBracer)) == isSlave
		end
	},

	{ "isBeastRace",
		function(_, isBeastRace: boolean): boolean
			local race: string = types.NPC.record(this.object).id
			return types.NPC.races.record(race).isBeast == isBeastRace
		end
	},

	{ "vars",
		function(_, vars: { string: CEFRange }): boolean
			if varsTable == nil then
				return false
			end
			for k, range in pairs(vars) do
				local value = varsTable:get(k)
				if value == nil or compareRange(value as integer, range, range.maxValue) == false then
					return false
				end
			end
			return true
		end
	},

	{ "dynStats",
		function(_, dynStats: { string: CEFRange }): boolean
			for k, range in pairs(dynStats) do
				local getStat = DYNAMIC_STATS[k];
				local dynStat = getStat and getStat(this.object)
				if dynStat == nil or compareRange(dynStat.current, range, dynStat.base + dynStat.modifier) == false then
					return false
				end
			end
			return true
		end
	},

	{ "attributes",
		function(_, attributes: { string: CEFRange }): boolean
			for k, range in pairs(attributes) do
				local getAttr = ATTRIBUTES[k]
				local attr = getAttr and getAttr(this.object)
				if attr == nil or compareRange(attr.modified, range, attr.base + attr.modifier) == false then
					return false
				end
			end
			return true
		end
	},

	{ "skills",
		function(_, skills: { string: CEFRange }): boolean
			for k, range in pairs(skills) do
				local getSkill = SKILLS[k]
				local skill = getSkill and getSkill(this.object)
				if skill == nil or compareRange(skill.modified, range, skill.base + skill.modifier) == false then
					return false
				end
			end
			return true
		end
	},

	{ "equipment",
		function(_, equipment: { string: boolean }): boolean
			for k, v in pairs(equipment) do
				local equipped = types.Actor.getEquipment(this.object, EQUIP_SLOTS[string.lower(k)])
				local dataType = type(v)
				if (dataType == "boolean" and v == (equipped == nil))
				or (dataType ~= "boolean" and equipped == nil)
				or (dataType == "string" and (equipped as core.GameObject).recordId ~= string.lower(v as string))
				or (dataType == "table" and tableHasElement(v as { string }, (equipped as core.GameObject).recordId) == false) then
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
	if effect.effects ~= nil and distTable[fileName .. effectId].effects == nil then
		applyCosmetics(fileName, effectId, effect.effects)
	end
	if effect.spells ~= nil and distTable[fileName .. effectId].spells == nil then
		applySpellDistribution(fileName, effectId, effect.spells)
	end
	if effect.items ~= nil and distTable[fileName .. effectId].items == nil then
		applyItemDistribution(fileName, effectId, effect.items)
	end
end

local function checkEffect(fileName: string, effectId: string, effect: CEFConfig)
	if settings:asTable().cefEnable == true and ((configSettings:asTable()["configToggle" .. fileName] as { string: boolean })[effectId] == true) then
		checkEffectConditions(fileName, effectId, effect)
	elseif distTable[fileName .. effectId] ~= nil then
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
		for effectId, effect in pairs(contents as { string: CEFConfig }) do
			checkEffect(fileName, effectId, effect)
		end
	end
end

local function checkNearby()
	if next(distTable) == nil and settings:asTable().cefEnable == false then
		return
	end
	for _, v in ipairs(nearby.players) do
		if v ~= nil and types.Actor.isInActorsProcessingRange(v) == true then
			loopThroughEffects()
			break
		end
	end
end

local function removeEffects()
	if next(distTable) == nil then
		return
	end
	for fileName, contents in pairs(configData:asTable() as { string: any }) do
		for effectId, effect in pairs(contents as { string: CEFConfig }) do
			if distTable[fileName .. effectId] ~= nil then
				if effect.effects ~= nil and distTable[fileName .. effectId].effects ~= nil then
					distTable[fileName .. effectId].effects = nil
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
	end
end

local function buildEffectWhitelist()
	for fileName, contents in pairs(configData:asTable() as { string: { string: CEFConfig } }) do
		for effectId, effect in pairs(contents as { string: CEFConfig }) do
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
		onSave = function(): SaveData
			local saveData: SaveData = {}
			saveData.distTable = distTable
			return saveData
		end,
		onLoad = function(saveData: SaveData)
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
			time.runRepeatedly(checkNearby, (settings:asTable().cefTickDelay as number), {})
		end,
		onUpdate = function()
			if core.isWorldPaused() and settings:asTable().cefEnableMenuUpdates == true and ((realTime - elapsedTime) >= (settings:asTable().cefMenuTickDelay as number)) then
				checkNearby()
				elapsedTime = realTime
			end
			realTime = core.getRealTime()
		end,
   	},
}