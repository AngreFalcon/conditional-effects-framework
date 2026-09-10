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
local parsedConfigData: { string: { string: CEFConfig } }
local timerRunning: boolean = false
local menuTimer: CEFTimer = {
	realTime = core.getRealTime(),
	elapsedTime = 0
}
local actorsInMenu: { string: { string: core.GameObject } } = {}
local cefLoadConfigDataThread: thread
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

local function storeConfigFiles()
	local configSection = storage.globalSection("CEF_ConfigData")
	configSection:reset({})
	configSection:setLifeTime(storage.LIFE_TIME.GameSession as storage.LifeTime)
	for k, v in pairs(parsedConfigData) do
		configSection:set(k, v)
	end
end

local function parseConfigFiles(configData: { string: string }): { string: { string: CEFConfig } }
	local tempConfigData: { string: { string: CEFConfig } } = {}
	for k, v in pairs(configData) do
		tempConfigData[k] = json.decode(v) as { string: CEFConfig }
	end
	return tempConfigData
end

local function loadConfigFiles()
	local configData: { string: string } = {}
	local configPath = "/scripts/ConditionalEffectsFramework/configs/"
	for fileName in vfs.pathsWithPrefix(configPath) do
		local file = vfs.open(fileName as string)
		if file ~= nil then
			local configId = string.match(file.fileName, "([^/\\]+)%..+$")
			configData[configId] = file:read("*all")
		end
	end
	parsedConfigData = parseConfigFiles(configData)
	storeConfigFiles()
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
		actor:sendEvent("cefUpdate", cefSettings)
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
	if parsedConfigData == nil then
		return
	end
	if timerRunning == false then
		async:newUnsavableSimulationTimer(cefSettings.cefTickDelay, regenerateUpdateTimer)
		timerRunning = true
	end
end

local function sendDisableEvent(actor: core.GameObject)
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

local function settingsUpdated(sectionName: string, key?: string)
	if sectionName ~= "SettingsGeneralConditionalEffectsFramework" then
		return
	end
	if key == nil then
		for k in pairs(cefSettings as { string: any }) do
			(cefSettings as { string: any })[k] = settings:asTable()[k]
		end
	else
		(cefSettings as { string: any })[key] = settings:asTable()[key]
	end

	if key == "cefEnable" then
		if cefSettings.cefEnable == false then
			disableAllEffects()
		else
			createUpdateTimer()
		end
	end
end

local function loadSettings()
	local settingsSectionName = "SettingsGeneralConditionalEffectsFramework"
	if settings == nil then
		settings = storage.globalSection(settingsSectionName)
		async:newUnsavableSimulationTimer(cef_utils.LOAD_SETTINGS_TICK_DELAY, loadSettings)
	else -- once settings have loaded, store them and send new settings to all active actors
		settingsUpdated(settingsSectionName)
		settings:subscribe(async:callback(settingsUpdated))
	end
end

local function passConfigDataToActor(actor: core.GameObject)
	if parsedConfigData == nil and cefLoadConfigDataThread ~= nil and coroutine.status(cefLoadConfigDataThread) ~= "dead" then
		async:newUnsavableSimulationTimer(cef_utils.LOAD_SETTINGS_TICK_DELAY, function()
			passConfigDataToActor(actor)
		end
	)
	elseif parsedConfigData == nil and (cefLoadConfigDataThread == nil or coroutine.status(cefLoadConfigDataThread) == "dead") then
		print("Error: Config data failed to load.")
	else
		actor:sendEvent("cefResumeBuildingWhitelist", { configData = parsedConfigData, pollingRange = cefSettings.cefPollRange })
	end
end

local function handleActiveActor(actor: core.GameObject)
	if types.NPC.objectIsInstance(actor) == false and types.Player.objectIsInstance(actor) == false then
		return
	end
	if cefLoadConfigDataThread == nil then
		cefLoadConfigDataThread = coroutine.create(loadConfigFiles)
		coroutine.resume(cefLoadConfigDataThread)
	end
	storage.globalSection(actor.id):setLifeTime(storage.LIFE_TIME.GameSession as storage.LifeTime)
	passConfigDataToActor(actor)
	createUpdateTimer()
end
-- end functions

return {
   	engineHandlers = {
		onInit = function()
			loadSettings()
			validateEffectIDs()
		end,
		onPlayerAdded = function(player: core.GameObject)
			handleActiveActor(player)
		end,
      	onActorActive = function(actor: core.GameObject)
			handleActiveActor(actor)
      	end,
		onActivate = function(object: core.GameObject, actor: core.GameObject)
			if cefSettings.cefEnable == false or cefSettings.cefLiteMode == true or types.Player.objectIsInstance(actor) ~= true or types.NPC.objectIsInstance(object) ~= true then
				return
			end
			actorsInMenu[actor.id] = { player = actor, actor = object}
		end,
		onUpdate = function()
			if cef_utils.checkSizeOfTable(actorsInMenu) > 0 and parsedConfigData ~= nil then
				menuTimer.realTime = core.getRealTime()
				performPausedUpdate()
			end
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
		cefMenuClosed = function(data: { string: core.GameObject })
			actorsInMenu[data.actor.id] = nil
		end,
	},
}
