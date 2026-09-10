local types = require('openmw.types')
local core = require('openmw.core')

-- interfaces below
global interface CEFSettings
	cefEnable: boolean
	cefLiteMode: boolean
	cefTickDelay: number
	cefMWVarsUpdateDelay: number
	cefEnableMenuUpdates: boolean
	cefMenuTickDelay: number
	cefPollRange: number
end

global interface CEFRange 
	min: number
	max: number
	percent: boolean
	maxValue: number
end

global interface CEFGuild
	rank: CEFRange
	reputation: CEFRange
end

global interface CEFCondition
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

global interface CEFEffect
	mesh: string
	node: string
end

global interface CEFSpell
	spellId: string
	remove: boolean
end

global interface CEFItem
	itemId: string
	quantity: number
	remove: boolean
end

global interface CEFItemPool
	itemPool: { CEFItem }
	random: boolean
	randomSeed: integer
end

global interface CEFConfig
	conditions: { CEFCondition }
	effects: { CEFEffect }
	spells: { CEFSpell }
	items: { CEFItemPool }
end

global interface CEFTimer
	realTime: number
	elapsedTime: number
end

global interface CEFDistributionTable
	effects: { string }
	spells: { CEFSpell }
	items: { CEFItemPool }
end

global interface CEFSaveData
	distTable: { string: CEFDistributionTable }
	effectWhitelist: { string: { string: CEFConfig } }
end
-- end interfaces


-- constants
local LOAD_SETTINGS_TICK_DELAY <const>: number = 1.0

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

local ITEM_INTERFACES <const>: { any } = {
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

local MENU_MODES <const>: { string: string } = {
	Loading = "Loading",
	LoadingWallpaper = "LoadingWallpaper",
	QuickKeysMenu = "QuickKeysMenu",
	SpellBuying = "SpellBuying",
	Rest = "Rest",
	Jail = "Jail",
	ChargenClassCreate = "ChargenClassCreate",
	Journal = "Journal",
	Repair = "Repair",
	Scroll = "Scroll",
	ChargenRace = "ChargenRace",
	Companion = "Companion",
	MainMenu = "MainMenu",
	Alchemy = "Alchemy",
	Dialogue = "Dialogue",
	Barter = "Barter",
	Container = "Container",
	Travel = "Travel",
	SpellCreation = "SpellCreation",
	Enchanting = "Enchanting",
	Recharge = "Recharge",
	Training = "Training",
	MerchantRepair = "MerchantRepair",
	LevelUp = "LevelUp",
	ChargenName = "ChargenName",
	Book = "Book",
	ChargenBirth = "ChargenBirth",
	ChargenClass = "ChargenClass",
	ChargenClassGenerate = "ChargenClassGenerate",
	ChargenClassPick = "ChargenClassPick",
	Interface = "Interface",
	ChargenClassReview = "ChargenClassReview",
}
-- end constants

-- utility functions below
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

local function checkSizeOfTable(t: { any: any }): number
	local size: number = 0
	local k, v = next(t)
	while v ~= nil do
		k, v = next(t, k)
		size = size + 1
	end
	return size
end

local function debugPrint(actor: core.GameObject, msg: string, actorIds?: { string })
	if types.NPC.objectIsInstance(actor) == false then
		return
	end
	if actorIds == nil then
		print(msg)
	else
		for _, actorId in ipairs(actorIds) do
			if types.NPC.record(actor).id == actorId then
				print(msg)
				break
			end
		end
	end
end
-- end functions

return {
	-- constants
	LOAD_SETTINGS_TICK_DELAY = LOAD_SETTINGS_TICK_DELAY,
	DYNAMIC_STATS = DYNAMIC_STATS,
	ATTRIBUTES = ATTRIBUTES,
	SKILLS = SKILLS,
	EQUIP_SLOTS = EQUIP_SLOTS,
	ITEM_INTERFACES = ITEM_INTERFACES,
	MENU_MODES = MENU_MODES,

	-- functions
	tableHasElement = tableHasElement,
	compareRange = compareRange,
	checkSizeOfTable = checkSizeOfTable,
	debugPrint = debugPrint,
}