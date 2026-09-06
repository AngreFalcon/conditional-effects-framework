local core = require('openmw.core')

local activatedBed: number = 0

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

return {
	eventHandlers = {
		-- full credit to Ihyacinth and their mod, Sun's Dusk, which served as an example and inspiration for the logic checking if a player has slept
		["UiModeChanged"] = function(data: { string: any })
			if data.newMode == MENU_MODES.Rest and data.oldMode == nil then -- player opened rest menu
				activatedBed = core.getGameTime()
			elseif data.newMode == nil and data.oldMode == MENU_MODES.Rest then -- player closed rest menu
				if core.getGameTime() > activatedBed then -- will only be true if player has activated a bed to open the rest menu and has also passed time by sleeping. otherwise, will be false
					core.sendGlobalEvent("updateVfx", {})
				end
			elseif data.oldMode == MENU_MODES.MainMenu and data.newMode == nil then -- player closed main menu
				core.sendGlobalEvent("settingsChanged", {})
			elseif data.newMode == MENU_MODES.MainMenu then -- player opened main menu
			end
		end
	},
}