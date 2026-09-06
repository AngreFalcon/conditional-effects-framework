local core = require("openmw.core")
local world = require("openmw.world")
local storage = require("openmw.storage")
local vfs = require('openmw.vfs')
local json = require('scripts.lib.json')
local types = require('openmw.types')
local async = require('openmw.async')

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

local settings: storage.StorageSection
local timerRunning: boolean = false
local realTime: number = core.getRealTime()
local elapsedTime: number = 0
local actorInteracted: core.GameObject = nil

local function syncMWVars(actor: core.GameObject) -- Get the current state of all local mwscript variables associated with the provided actor
	if actor ~= nil then
		local localScript: world.MWScript = world.mwscript.getLocalScript(actor, nil)
		if localScript ~= nil then
            local varTable = storage.globalSection(actor.id)
            for k, v in pairs((localScript.variables as {string: number})) do
                varTable:set(k, v)
			end
		end
	end
end

local function loadConfigFiles(): { string: string }
	local configData: { string: string } = {}
	local configPath = "/scripts/ConditionalEffectsFramework/configs/"
	for fileName in vfs.pathsWithPrefix(configPath) do
		local file = vfs.open(fileName as string)
		if file ~= nil then
			local configId = string.match(file.fileName, "([^/\\]+)%..+$")
			configData[configId] = file:read("*all")
		end
	end
	return configData
end

local function parseConfigFiles(configData: { string: string}): { string: any }
	local parsedConfigData: { string: any } = {}
	for k, v in pairs(configData) do
		parsedConfigData[k] = json.decode(v)
	end
	return parsedConfigData
end

local function storeConfigFiles(parsedConfigData: { string: any })
	local configSection = storage.globalSection("CEF_ConfigData")
	configSection:setLifeTime(storage.LIFE_TIME.GameSession as storage.LifeTime)
	for k, v in pairs(parsedConfigData) do
		configSection:set(k, v)
	end
end

local function findSpellByID(spellId: string): core.Spell
	local foundSpell: core.Spell = nil
	for _, spell in ipairs(core.magic.spells.records) do
		if spell.id == spellId then
			foundSpell = spell
			break
		end
	end
	return foundSpell
end

local function validateItemId(itemId: string): boolean
	for _, itemRecord in ipairs(ITEM_INTERFACES as { { string: any } }) do
		if (itemRecord.records as { string: any })[itemId] ~= nil then
			return true
		end
	end
	return false
end

local function validateEffectIDs()
	local configData = storage.globalSection("CEF_ConfigData")
	for fileName, contents in pairs(configData:asTable() as { string: { string: any } }) do
		for effectId, effect in pairs(contents as { string: { string: any } }) do
			if effect.spells ~= nil then
				for _, spell in ipairs(effect.spells as { { string: string } }) do
					local foundSpell = findSpellByID(spell.spellId)
					if foundSpell == nil then
						print("Spell could not be found by ID: " .. spell.spellId .. " in file: " .. fileName .. " for effect: " .. effectId)
					end
				end
			end
			if effect.items ~= nil then
				for _, itemPool in ipairs(effect.items as { { string: { { string: string } } } }) do
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

local function sendUpdateEvent(actor: core.GameObject)
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

local function createUpdateTimer()
	if settings:asTable().cefEnable == false then
		return
	end

	if timerRunning == true then
		performConditionUpdate()
		timerRunning = false
	end

	if timerRunning == false and settings:asTable().cefLiteMode == false then
		async:newUnsavableSimulationTimer((settings:asTable().cefTickDelay as number), createUpdateTimer)
		timerRunning = true
	end
end

local function clearEffects()
	for _, actor in ipairs(world.activeActors) do
		if types.NPC.objectIsInstance(actor) == true then
			actor:sendEvent("cefRemoveEffects", {})
		end
	end
end

local interface ItemData
	actor: core.GameObject
	itemId: string
	quantity: number
end

return {
   	engineHandlers = {
		onInit = function()
			local configData = loadConfigFiles()
			local parsedConfigData = parseConfigFiles(configData)
			storeConfigFiles(parsedConfigData)
			settings = storage.globalSection("SettingsGeneralConditionalEffectsFramework")
			validateEffectIDs()
			createUpdateTimer()
		end,
      	onActorActive = function(actor: core.GameObject)
			if types.NPC.objectIsInstance(actor) == false then
				return
			end
			syncMWVars(actor)
			storage.globalSection(actor.id):setLifeTime(storage.LIFE_TIME.GameSession as storage.LifeTime)
      	end,
		onActivate = function(object: core.GameObject, actor: core.GameObject)
			if types.Player.objectIsInstance(actor) ~= true or types.NPC.objectIsInstance(object) ~= true then
				return
			end
			actorInteracted = object
		end,
		onUpdate = function()
			if actorInteracted == nil then
				return
			else
				realTime = core.getRealTime()
			end
			if ((realTime - elapsedTime) >= (settings:asTable().cefMenuTickDelay as number)) then
				if core.isWorldPaused() == true and settings:asTable().cefEnable == true and settings:asTable().cefLiteMode == false and settings:asTable().cefEnableMenuUpdates == true then
					actorInteracted:sendEvent("cefUpdate", {})
				end
				elapsedTime = realTime
			end
		end,
   	},
	eventHandlers = {
		cefAddItem = function(data: ItemData)
			local item = world.createObject(data.itemId, data.quantity)
			item:moveInto(types.Actor.inventory(data.actor))
		end,
		cefRemoveItem = function(data: ItemData)
			local inventory = types.Actor.inventory(data.actor)
			local item = inventory:find(data.itemId)
			item:remove(data.quantity)
		end,
		cefMenuOpened = function()
			
		end,
		cefUpdateVfx = function()
			clearEffects()
		end,
		cefMainMenuClosed = function()
			createUpdateTimer()
		end,
		cefMenuClosed = function()
			actorInteracted = nil
		end,
	},
}

