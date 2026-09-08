local core = require('openmw.core')
local this = require('openmw.self')

local cef_utils = require('scripts.ConditionalEffectsFramework.cef-utils')


local activatedBed = 0


return {
   eventHandlers = {

      ["UiModeChanged"] = function(data)
         if data.newMode ~= nil and data.oldMode == nil then
            core.sendGlobalEvent("cefMenuOpened", { actor = this.object })

            if data.newMode == cef_utils.MENU_MODES.Rest then
               activatedBed = core.getGameTime()
            end
         elseif data.newMode == nil and data.oldMode ~= nil then
            core.sendGlobalEvent("cefMenuClosed", { actor = this.object })

            if data.oldMode == cef_utils.MENU_MODES.Rest then
               if core.getGameTime() > activatedBed then
                  core.sendGlobalEvent("cefUpdateVfx", {})
               end
            elseif data.oldMode == cef_utils.MENU_MODES.MainMenu then
               core.sendGlobalEvent("cefMainMenuClosed", {})
            end
         end
      end,
   },
}
