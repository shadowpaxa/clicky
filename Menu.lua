-- Right-click menus: macro entries on the Toy Box's own toy menu, the same menu for toys in the
-- Clicky panel, the macro menu (Rename, Delete, Copy /click line), and the dialogs they open.
--   ns.OpenToyMenu(owner, itemID), ns.OpenMacroMenu(owner, m)
--   ns.ToyMenuEntries(itemID)   { macro, label } per macro the toy can be added to or removed
--                               from, as the toy menus list them; for tests

local _, ns = ...

local COMBAT_ERROR = "Can't change macros in combat."

local function EntryLabel(m, itemID)
	return (ns.HasToy(m, itemID) and "Remove from %s" or "Add to %s"):format(m.name)
end

local function ShowNewMacroDialog(itemID)
	if InCombatLockdown() then
		ns.ShowError(COMBAT_ERROR)
		return
	end
	StaticPopup_Show("CLICKY_NEW_MACRO", nil, nil, { itemID = itemID })
end

-- One entry per macro whose toys can be changed ("Add to Illusion" / "Remove from Illusion").
local function ToyMenuEntries(itemID)
	local entries = {}
	for _, m in ipairs(ns.GetMacros()) do
		if not m.builtin and not ns.Unreadable(m) then
			entries[#entries + 1] = { macro = m, label = EntryLabel(m, itemID) }
		end
	end
	return entries
end
ns.ToyMenuEntries = ToyMenuEntries

-- The macro entries, then "Add to new macro...". Choosing one keeps the menu open; the
-- initializer re-reads the label on refresh, so the entry flips in place and a toy can be put in
-- several macros in one go. A refused change (combat, a full macro) shows why and leaves the
-- entry as it was.
local function AddMacroEntries(rootDescription, itemID)
	rootDescription:CreateDivider()
	for _, entry in ipairs(ToyMenuEntries(itemID)) do
		local m = entry.macro
		local button = rootDescription:CreateButton(entry.label, function()
			local ok, err = ns.SetToy(m, itemID, not ns.HasToy(m, itemID))
			if not ok then
				ns.ShowError(err)
			end
			return MenuResponse.Refresh
		end)
		button:AddInitializer(function(frame)
			frame.fontString:SetTextToFit(EntryLabel(m, itemID))
		end)
	end
	rootDescription:CreateButton("Add to new macro...", function()
		ShowNewMacroDialog(itemID)
	end)
end

Menu.ModifyMenu("MENU_TOYBOX_FAVORITE", function(owner, rootDescription)
	---@diagnostic disable-next-line: undefined-field -- the owner is the Toy Box's toy button
	local itemID = owner and owner.itemID
	if itemID then
		AddMacroEntries(rootDescription, itemID)
	end
end)

-- The same menu as the Toy Box's, for a toy listed in the panel.
function ns.OpenToyMenu(owner, itemID)
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		if C_ToyBox.GetIsFavorite(itemID) then
			rootDescription:CreateButton(BATTLE_PET_UNFAVORITE, function()
				C_ToyBox.SetIsFavorite(itemID, false)
				ns.Changed()
			end)
		else
			rootDescription:CreateButton(BATTLE_PET_FAVORITE, function()
				C_ToyBox.SetIsFavorite(itemID, true)
				ns.Changed()
			end)
		end
		AddMacroEntries(rootDescription, itemID)
	end)
end

function ns.OpenMacroMenu(owner, m)
	MenuUtil.CreateContextMenu(owner, function(_, rootDescription)
		rootDescription:CreateTitle(m.name)
		rootDescription:CreateButton("Rename", function()
			if InCombatLockdown() then
				ns.ShowError(COMBAT_ERROR)
				return
			end
			StaticPopup_Show("CLICKY_RENAME_MACRO", m.name, nil, { macro = m })
		end)
		rootDescription:CreateButton(DELETE, function()
			if InCombatLockdown() then
				ns.ShowError(COMBAT_ERROR)
				return
			end
			StaticPopup_Show("CLICKY_DELETE_MACRO", m.name, nil, { macro = m })
		end)
		rootDescription:CreateButton("Copy /click line", function()
			StaticPopup_Show("CLICKY_COPY_LINE", nil, nil, { line = "/click " .. m.buttonName })
		end)
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
	function(data, name) return ns.MakeMacro(name, data.itemID) end)

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
