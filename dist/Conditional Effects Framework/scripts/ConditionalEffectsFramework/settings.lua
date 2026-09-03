local _tl_compat; if (tonumber((_VERSION or ''):match('[%d.]*$')) or 0) < 5.3 then local p, m = pcall(require, 'compat53.module'); if p then _tl_compat = m end end; local pairs = _tl_compat and _tl_compat.pairs or pairs; local string = _tl_compat and _tl_compat.string or string; local table = _tl_compat and _tl_compat.table or table; local I = require('openmw.interfaces')
local storage = require('openmw.storage')
local core = require('openmw.core')

local l10n = core.l10n("ConditionalEffectsFramework", "en")

local cefConfigData = storage.globalSection("CEF_ConfigData"):asTable()
local cafConfigs = {}
for _, fileContents in pairs(cefConfigData) do
   for configName in pairs(fileContents) do
      cafConfigs[#cafConfigs + 1] = configName
   end
end

local function capitalizeText(text)
   local capitalizedText = ""
   local i = 1
   capitalizedText = text:sub(i, i):upper()
   i = i + 1
   while i <= #text do
      local j = text:find(" ", i)
      if j ~= nil then
         capitalizedText = capitalizedText .. text:sub(i, j) .. text:sub(j + 1, j + 1):upper()
         i = j + 2
      else
         break
      end
   end
   capitalizedText = capitalizedText .. text:sub(i, #text)
   return capitalizedText
end

local function genConfigToggles(fileName)
   local settings = {}
   settings.renderer = "multiselect"
   settings.key = "configToggle" .. fileName
   settings.name = (l10n("config_toggle_name")) .. capitalizeText(fileName)
   settings.description = (l10n("config_toggle_desc")) .. capitalizeText(fileName)
   settings.default = {}
   settings.argument = {};
   (settings.argument).keys = {};
   (settings.argument).aliases = {}
   for configName in pairs(cefConfigData[fileName]) do
      (settings.default)[configName] = true;
      (settings.argument).keys[#(settings.argument).keys + 1] = configName;
      (settings.argument).aliases[configName] = capitalizeText(configName)
   end
   (settings.argument).buttonWidth = 120
   return settings
end

local function getToggleSettings()
   local settingsList = {}
   for fileName in pairs(cefConfigData) do
      settingsList[#settingsList + 1] = genConfigToggles(fileName)
   end
   table.sort(settingsList, (function(first, second)
      if first.name < second.name then
         return true
      else
         return false
      end
   end))
   return settingsList
end

I.Settings.registerGroup({
   key = 'SettingsGeneralConditionalEffectsFramework',
   l10n = 'ConditionalEffectsFramework',
   page = 'ConditionalEffectsFrameworkPage',
   name = 'general_settings_group_name',
   description = 'general_settings_group_desc',
   permanentStorage = false,
   settings = {
      {
         renderer = "checkbox",
         key = "cefEnable",
         name = "cef_enable_name",
         description = "cef_enable_desc",
         default = true,
         argument = {
            l10n = "ConditionalEffectsFramework",
            trueLabel = "cef_enable_enabled",
            falseLabel = "cef_enable_disabled",
         },
      },
      {
         renderer = "number",
         key = "cefTickDelay",
         name = "tick_rate_name",
         description = "tick_rate_desc",
         default = 0.5,
         argument = {
            min = 0.05,
            max = 10,
         },
      },
      {
         renderer = "checkbox",
         key = "cefEnableMenuUpdates",
         name = "cef_enable_menu_updates_name",
         description = "cef_enable_menu_updates_desc",
         default = true,
         argument = {
            l10n = "ConditionalEffectsFramework",
            trueLabel = "cef_enable_menu_updates_enabled",
            falseLabel = "cef_enable_menu_updates_disabled",
         },
      },
      {
         renderer = "number",
         key = "cefMenuTickDelay",
         name = "menu_tick_rate_name",
         description = "menu_tick_rate_desc",
         default = 1.0,
         argument = {
            min = 0.05,
            max = 10,
         },
      },
   },
})

I.Settings.registerGroup({
   key = 'SettingsConditionalEffectsFrameworkConfigs',
   l10n = 'ConditionalEffectsFramework',
   page = 'ConditionalEffectsFrameworkPage',
   name = 'toggle_settings_group_name',
   description = 'toggle_settings_group_desc',
   permanentStorage = false,
   settings = getToggleSettings(),
   order = 10,
})
