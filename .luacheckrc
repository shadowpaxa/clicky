-- luacheck config (https://luacheck.readthedocs.io). WoW runs Lua 5.1.
std = "lua51"
max_line_length = false
codes = true
exclude_files = {
	"tests/.cache",
	".claude",
	".lua", -- CI's LuaJIT and LuaRocks installs
	".luarocks",
}
ignore = {
	"212/self", -- methods that don't use self
}

-- Globals Clicky sets: its slash command, and entries in Blizzard's tables.
globals = {
	"SLASH_CLICKY1",
	"SlashCmdList",
	"StaticPopupDialogs",
}

-- WoW API and Blizzard UI globals Clicky reads.
read_globals = {
	"BaseScrollBoxEvents",
	"BATTLE_PET_FAVORITE",
	"BATTLE_PET_UNFAVORITE",
	"ButtonFrameTemplate_HideAttic",
	"ButtonFrameTemplate_HideButtonBar",
	"ButtonFrameTemplate_HidePortrait",
	"C_AddOns",
	"C_Container",
	"C_Item",
	"C_Spell",
	"C_SpellBook",
	"C_Timer",
	"C_ToyBox",
	"C_ToyBoxInfo",
	"ChatFrameUtil",
	"COLLECTED",
	"CANCEL",
	"COLLECTIONS_JOURNAL_TAB_INDEX_TOYS",
	"CollectionsJournal",
	"Constants",
	"CooldownFrame_Set",
	"CopyTable",
	"CreateDataProvider",
	"CreateFrame",
	"CreateMacro",
	"CreateScrollBoxListLinearView",
	"DELETE",
	"DeleteMacro",
	"EditMacro",
	"Enum",
	"EventRegistry",
	"EventUtil",
	"GameTooltip",
	"GameTooltip_Hide",
	"GetFlyoutInfo",
	"GetFlyoutSlotInfo",
	"geterrorhandler",
	"GetInventoryItemID",
	"GetMacroInfo",
	"GetNumMacros",
	"InCombatLockdown",
	"INVSLOT_FIRST_EQUIPPED",
	"INVSLOT_LAST_EQUIPPED",
	"IsModifiedClick",
	"issecretvalue",
	"IsMouseButtonDown",
	"IsShiftKeyDown",
	"IsControlKeyDown",
	"IsAltKeyDown",
	"MenuUtil",
	"NEW_CAPS",
	"NORMAL_FONT_COLOR",
	"NUM_TOTAL_EQUIPPED_BAG_SLOTS",
	"NOT_COLLECTED",
	"PanelTemplates_GetSelectedTab",
	"PanelTemplates_SetNumTabs",
	"PanelTemplates_SetTab",
	"PanelTemplates_TabResize",
	"PET_JOURNAL_FILTER_USABLE_ONLY",
	"PickupMacro",
	"PlayerHasToy",
	"ScrollBoxConstants",
	"ScrollUtil",
	"SecureHandlerSetFrameRef",
	"SecureHandlerWrapScript",
	"SetCollectionsJournalShown",
	"SetUIPanelAttribute",
	"StaticPopup_Show",
	"StaticPopup_StandardEditBoxOnEscapePressed",
	"StaticPopup_StandardNonEmptyTextHandler",
	"strtrim",
	"tCompare",
	"tostringall",
	"ToyBox",
	"UIErrorsFrame",
	"UIParent",
	"UpdateUIPanelPositions",
	"wipe",
}

files["tests"] = {
	std = "+busted",
}
