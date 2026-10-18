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
	"BATTLE_PET_FAVORITE",
	"BATTLE_PET_UNFAVORITE",
	"ButtonFrameTemplate_HideButtonBar",
	"ButtonFrameTemplate_HidePortrait",
	"C_AddOns",
	"C_Container",
	"C_Item",
	"C_Timer",
	"C_ToyBox",
	"CANCEL",
	"COLLECTIONS_JOURNAL_TAB_INDEX_TOYS",
	"CollectionsJournal",
	"Constants",
	"CooldownFrame_Set",
	"CreateDataProvider",
	"CreateFrame",
	"CreateMacro",
	"CreateScrollBoxListLinearView",
	"debugprofilestop",
	"DELETE",
	"DeleteMacro",
	"EditMacro",
	"GameTooltip",
	"GameTooltip_Hide",
	"GetMacroInfo",
	"GetNumMacros",
	"GetTime",
	"InCombatLockdown",
	"Menu",
	"MenuResponse",
	"MenuUtil",
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
	"ToyBox",
	"UIErrorsFrame",
	"UIParent",
	"UpdateUIPanelPositions",
	"wipe",
}

files["tests"] = {
	std = "+busted",
}
