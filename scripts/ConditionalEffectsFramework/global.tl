local core = require("openmw.core")
local world = require("openmw.world")
local storage = require("openmw.storage")
local vfs = require('openmw.vfs')
local json = require('scripts.lib.json')
local types = require('openmw.types')
local async = require('openmw.async')

local cef_utils = require('scripts.ConditionalEffectsFramework.cef-utils')

-- variables
local settings: storage.StorageSection = storage.globalSection("SettingsGeneralConditionalEffectsFramework")
local cefSettings: CEFSettings = {
		cefEnable = true,
		cefLiteMode = false,
		cefTickDelay = 0.5,
		cefEnableMenuUpdates = true,
		cefMenuTickDelay = 1.0,
		cefPollRange = 2000.0,
}
local cefConfigData: { string: { string: CEFConfig } }
local loadSettingsTickDelay: number = 0.5
local timerRunning: boolean = false
local menuTimer: CEFTimer = {
	realTime = core.getRealTime(),
	elapsedTime = 0
}
local actorsInMenu: { string: { string: core.GameObject } } = {}
-- end variables

-- functions
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

local function parseConfigFiles(configData: { string: string}): { string: { string: CEFConfig } }
	local parsedConfigData: { string: any } = {}
	for k, v in pairs(configData) do
		parsedConfigData[k] = json.decode(v)
	end
	return parsedConfigData as { string: { string: CEFConfig } }
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
	for _, itemRecord in ipairs(cef_utils.ITEM_INTERFACES as { { string: any } }) do
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
	if types.NPC.objectIsInstance(actor) == true and cefSettings.cefEnable == true then
		syncMWVars(actor)
		actor:sendEvent("cefUpdate", { settings = cefSettings, configData = cefConfigData })
	end
end

local function performConditionUpdate()
	for _, actor in ipairs(world.activeActors) do
		sendUpdateEvent(actor)
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

local function sendDisableEvent(actor: core.GameObject)
	if types.NPC.objectIsInstance(actor) == true then
		actor:sendEvent("cefDisable", { settings = cefSettings, configData = cefConfigData })
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

local function updateSettings(section: string, key: string)
	if section ~= "SettingsGeneralConditionalEffectsFramework" then
		return
	end
	if key == nil then
		for k in pairs(cefSettings as { string: any }) do
			(cefSettings as { string: any })[k] = settings:asTable()[k]
		end
	else
		(cefSettings as { string: any })[key] = settings:asTable()[key]
	end
end

local function loadSettings()
	local settingsSectionName = "SettingsGeneralConditionalEffectsFramework"
	if settings == nil then
		settings = storage.globalSection(settingsSectionName)
		async:newUnsavableSimulationTimer(loadSettingsTickDelay, loadSettings)
	else -- once settings have loaded, store them and send new settings to all active actors
		updateSettings(settingsSectionName, nil)
		settings:subscribe(async:callback(updateSettings))
	end
end
-- end functions

return {
   	engineHandlers = {
		onInit = function()
			local configData = loadConfigFiles()
			cefConfigData = parseConfigFiles(configData)
			loadSettings()
			validateEffectIDs()
		end,
      	onActorActive = function(actor: core.GameObject)
			if types.NPC.objectIsInstance(actor) == false then
				return
			end
			storage.globalSection(actor.id):setLifeTime(storage.LIFE_TIME.GameSession as storage.LifeTime)
			createUpdateTimer()
      	end,
		onActivate = function(object: core.GameObject, actor: core.GameObject)
			if cefSettings.cefEnable == false or cefSettings.cefLiteMode == true or types.Player.objectIsInstance(actor) ~= true or types.NPC.objectIsInstance(object) ~= true then
				return
			end
			actorsInMenu[actor.id] = { player = actor, actor = object}
		end,
		onUpdate = function()
			if cef_utils.checkSizeOfTable(actorsInMenu) == 0 then
				return
			else
				menuTimer.realTime = core.getRealTime()
			end
			performPausedUpdate()
		end,
   	},
	eventHandlers = {
		cefAddItem = function(data: { core.GameObject, CEFItem })
			local item = world.createObject(data[2].itemId, data[2].quantity)
			item:moveInto(types.Actor.inventory(data[1]))
		end,
		cefRemoveItem = function(data: { core.GameObject, CEFItem })
			local inventory = types.Actor.inventory(data[1])
			local item = inventory:find(data[2].itemId)
			item:remove(data[2].quantity)
		end,
		cefMenuOpened = function(data: { string: core.GameObject })
			if actorsInMenu[data.actor.id] == nil then
				actorsInMenu[data.actor.id] = { player = data.actor }
			end
		end,
		cefUpdateVfx = function()
			clearVfx()
		end,
		cefMainMenuClosed = function()
			if cefSettings.cefEnable == true then
				createUpdateTimer()
			else
				disableAllEffects()
			end
		end,
		cefMenuClosed = function(data: { string: core.GameObject })
			actorsInMenu[data.actor.id] = nil
		end,
	},
}
