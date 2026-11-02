-- Right-click menus: an entry's menu (a toy's, mount's, pet's, spell's or item's, in Clicky's grid
-- and its panel), the macro menu, and the dialogs they open.
--   ns.OpenEntryMenu(owner, key), ns.OpenMacroEntryMenu(owner, m, key), ns.OpenMacroMenu(owner, m)
--                                 key is an entry's key (Entries.lua). The grid's entry menu: the
--                                 star and a checkbox per macro. The panel's menu for an entry
--                                 listed under macro m is about that item in m only: "Use as icon
--                                 for <m>" (once m exists in /macro and the icon is loaded) and
--                                 "Remove from <m>";
--                                 a macro's menu: Rename, Delete, Copy /click line, and Open in
--                                 /macro once the macro exists there (a built-in one's may not
--                                 yet). Only toys, mounts and pets have the star (Entries.lua), and
--                                 the built-in macros are those stars

local _, ns = ...

-- Shows a dialog, unless in combat: what it does to a macro is refused then.
local function ShowDialog(which, text, data)
	if InCombatLockdown() then
		ns.ShowError(ns.COMBAT_ERROR)
		return
	end
	StaticPopup_Show(which, text, nil, data)
end

-- Under a "Clicky macros" title, a checkbox per macro whose entries can be changed, ticked if the
-- entry is in it, then "Add to new macro...". A checkbox keeps the menu open and re-reads whether
-- the entry is in its macro (CreateCheckbox's response is MenuResponse.Refresh,
-- Blizzard_Menu/MenuTemplates.lua), so an entry can be put in several macros in one go. A refused
-- change (combat, a full macro) shows why and leaves the checkbox as it was.
local function AddMacroEntries(rootDescription, key)
	rootDescription:CreateDivider()
	rootDescription:CreateTitle("Clicky macros")
	for _, m in ipairs(ns.GetMacros()) do
		if not m.builtin and not ns.Unreadable(m) then
			rootDescription:CreateCheckbox(m.name, function()
				return ns.HasEntry(m, key)
			end, function()
				local ok, err = ns.SetEntry(m, key, not ns.HasEntry(m, key))
				if not ok then
					ns.ShowError(err)
				end
			end)
		end
	end
	rootDescription:CreateButton("Add to new macro...", function()
		ShowDialog("CLICKY_NEW_MACRO", nil, { key = key })
	end)
end

-- The star, as the Toy Box's and the Mount Journal's own menus have it (Blizzard_ToyBox.lua,
-- ToySpellButton_CreateContextMenu; Blizzard_MountCollection.lua), then the macros, for every kind
-- of entry.
function ns.OpenEntryMenu(owner, key)
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		if ns.CanFavoriteEntry(key) then
			local favorite = ns.IsEntryFavorite(key)
			rootDescription:CreateButton(favorite and BATTLE_PET_UNFAVORITE or BATTLE_PET_FAVORITE, function()
				ns.SetEntryFavorite(key, not favorite)
			end)
		end
		AddMacroEntries(rootDescription, key)
	end)
end

-- The menu of an item listed under macro m in the panel. For a built-in macro, SetEntry takes the
-- star off.
function ns.OpenMacroEntryMenu(owner, m, key)
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		if ns.InMacroUI(m) and ns.EntryIcon(key) then
			rootDescription:CreateButton("Use as icon for " .. m.name, function()
				local ok, err = ns.SetMacroIcon(m, key)
				if not ok then
					ns.ShowError(err)
				end
			end)
		end
		rootDescription:CreateButton("Remove from " .. m.name, function()
			local ok, err = ns.SetEntry(m, key, false)
			if not ok then
				ns.ShowError(err)
			end
		end)
	end)
end

function ns.OpenMacroMenu(owner, m)
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:CreateTitle(m.name)
		rootDescription:CreateButton("Rename", function()
			ShowDialog("CLICKY_RENAME_MACRO", m.name, { macro = m })
		end)
		rootDescription:CreateButton(DELETE, function()
			ShowDialog("CLICKY_DELETE_MACRO", m.name, { macro = m })
		end)
		rootDescription:CreateButton("Copy /click line", function()
			StaticPopup_Show("CLICKY_COPY_LINE", nil, nil, { line = "/click " .. ns.ButtonName(m.id) })
		end)
		if ns.InMacroUI(m) then
			rootDescription:CreateButton("Open in /macro", function()
				ns.OpenMacroInUI(m)
			end)
		end
	end)
end

------------------------------------------------------------------------------------------
-- Dialogs. Returning true from OnAccept keeps the dialog open, so a refused name can be fixed.

local function ClickAccept(editBox)
	local button1 = editBox:GetParent():GetButton1()
	if button1:IsEnabled() then
		button1:Click()
	end
end

local function NameDialog(text, button1, initialText, accept)
	return {
		text = text,
		button1 = button1,
		button2 = CANCEL,
		hasEditBox = true,
		maxLetters = 16, -- WoW's macro name limit
		OnShow = function(dialog, data)
			local editBox = dialog:GetEditBox()
			editBox:SetText(initialText(data))
			editBox:HighlightText()
			dialog:GetButton1():SetEnabled(strtrim(editBox:GetText()) ~= "")
		end,
		EditBoxOnTextChanged = StaticPopup_StandardNonEmptyTextHandler,
		EditBoxOnEnterPressed = ClickAccept,
		EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
		OnAccept = function(dialog, data)
			local ok, err = accept(data, dialog:GetEditBox():GetText())
			if not ok then
				ns.ShowError(err)
				return true
			end
		end,
		timeout = 0,
		whileDead = true,
		hideOnEscape = true,
	}
end

StaticPopupDialogs.CLICKY_NEW_MACRO = NameDialog("Name the new macro:", "Create",
	function() return "" end,
	function(data, name) return ns.MakeMacro(name, data.key) end)

StaticPopupDialogs.CLICKY_RENAME_MACRO = NameDialog("Rename %s to:", "Rename",
	function(data) return data.macro.name end,
	function(data, name) return ns.RenameMacro(data.macro, name) end)

-- CopyToClipboard is restricted (OsDocumentation.lua: HasRestrictions), so the line is shown
-- selected for the player to copy.
StaticPopupDialogs.CLICKY_COPY_LINE = {
	text = "Copy this line, then paste it into a macro of your own:",
	button1 = "Close",
	hasEditBox = true,
	-- Popup frames keep the last dialog's letter limit (GameDialog.lua), and the name dialogs set 16.
	maxLetters = 64,
	OnShow = function(dialog, data)
		local editBox = dialog:GetEditBox()
		editBox:SetText(data.line)
		editBox:HighlightText()
	end,
	EditBoxOnEscapePressed = StaticPopup_StandardEditBoxOnEscapePressed,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}

StaticPopupDialogs.CLICKY_DELETE_MACRO = {
	text = "Delete the macro %s? It will be removed from your bars.",
	button1 = DELETE,
	button2 = CANCEL,
	showAlert = true,
	OnAccept = function(_, data)
		local ok, err = ns.DeleteMacro(data.macro)
		if not ok then
			ns.ShowError(err)
		end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
}
