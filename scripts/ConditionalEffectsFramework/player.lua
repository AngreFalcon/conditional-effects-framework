local core = require('openmw.core')

local activatedBed = 0

local MENU_MODES = {
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

return {
   eventHandlers = {

      ["UiModeChanged"] = function(data)
         if data.newMode == MENU_MODES.Rest and data.oldMode == nil then
            activatedBed = core.getGameTime()
         elseif data.newMode == nil and data.oldMode == MENU_MODES.Rest then
            if core.getGameTime() > activatedBed then
               core.sendGlobalEvent("updateVfx", {})
            end
         elseif data.oldMode == MENU_MODES.MainMenu and data.newMode == nil then
            core.sendGlobalEvent("settingsChanged", {})
         elseif data.newMode == MENU_MODES.MainMenu then
         end
      end,
   },
}
