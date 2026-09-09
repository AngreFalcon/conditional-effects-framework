local core = require('openmw.core')
local this = require('openmw.self')

local cef_utils = require('scripts.ConditionalEffectsFramework.cef-utils')

-- variables
local activatedBed: number = 0
-- end variables

return {
	eventHandlers = {
	-- full credit to Ihyacinth and their mod, Sun's Dusk, which served as an example and inspiration for the logic checking if a player has slept
	["UiModeChanged"] = function(data: { string: any })
		if data.newMode ~= nil and data.oldMode == nil then
			core.sendGlobalEvent("cefMenuOpened", { actor = this.object })

			if data.newMode == cef_utils.MENU_MODES.Rest then -- player opened rest menu
				activatedBed = core.getGameTime()
			end
		elseif data.newMode == nil and data.oldMode ~= nil then
			core.sendGlobalEvent("cefMenuClosed", { actor = this.object })

			if data.oldMode == cef_utils.MENU_MODES.Rest then -- player closed rest menu
				if core.getGameTime() > activatedBed then -- will only be true if player has activated a bed to open the rest menu and has also passed time by sleeping. otherwise, will be false
					core.sendGlobalEvent("cefUpdateVfx", {})
				end
			end
		end
	end
	},
}