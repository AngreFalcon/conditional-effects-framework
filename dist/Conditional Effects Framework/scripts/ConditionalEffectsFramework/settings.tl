local I = require('openmw.interfaces')
local storage = require('openmw.storage')
local core = require('openmw.core')

local l10n = core.l10n("ConditionalEffectsFramework", "en")

local cefConfigData = storage.globalSection("CEF_ConfigData"):asTable()
local cafConfigs: { string } = {}
for _, fileContents in pairs(cefConfigData) do
    for configName in pairs(fileContents as { string: any }) do
        cafConfigs[#cafConfigs + 1] = configName
    end
end

local function genConfigToggles(fileName: string): I.Settings.SettingOptions
    local settings: I.Settings.SettingOptions = {}
    settings.renderer = "multiselect"
    settings.key = "configToggle" .. fileName
    settings.name = (l10n("config_toggle_name") as string) .. fileName
    settings.description = (l10n("config_toggle_desc") as string) .. fileName
    settings.default = {}
    settings.argument = {}
    (settings.argument as { string: any }).keys = {}
    for configName in pairs(cefConfigData[fileName] as { string: any }) do
        (settings.default as { string: boolean })[configName] = true
        (settings.argument as { string: { string } }).keys[#(settings.argument as { string: { string } }).keys + 1] = configName
    end
    return settings
end

local function getToggleSettings(): { I.Settings.SettingOptions }
    local settingsList: { I.Settings.SettingOptions } = {}
    for fileName in pairs(cefConfigData as { string: any }) do
        settingsList[#settingsList + 1] = genConfigToggles(fileName)
    end
    table.sort(settingsList, (function(first: I.Settings.SettingOptions, second: I.Settings.SettingOptions): boolean
        if first.name < second.name then
            return true
        else
            return false
        end
    end))
    return settingsList
end

I.Settings.registerGroup {
    key = 'SettingsConditionalEffectsFrameworkConfigs',
    l10n = 'ConditionalEffectsFramework',
    page = 'ConditionalEffectsFrameworkPage',
    name = 'toggle_settings_group_name',
    description = 'toggle_settings_group_desc',
    permanentStorage = false,
    settings = getToggleSettings(),
}

I.Settings.registerGroup {
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
            }
        },
		{
			renderer = "number",
			key = "cefTickDelay",
			name = "tick_rate_name",
			description = "tick_rate_desc",
			default = 0.2,
			argument = {
				min = 0.05,
				max = 10,
			},
		},
	} as {I.Settings.SettingOptions},
}