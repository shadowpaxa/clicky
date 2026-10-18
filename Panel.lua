-- The Clicky panel, docked to the right edge of the Toy Box: one scrolling list of macros, each
-- collapsed by default. Click a macro to show or hide its toys. Drag a macro's icon to put it
-- on a bar; right-click a macro to rename or delete it; right-click
-- a toy for the same menu as the Toy Box. It's parented to the Toy Box, so it shows only on the
-- Toy Box tab. A macro whose toys can't be read has a greyed icon with a warning mark and "?" for
-- its count; hovering over it says why, and clicking it shows the same message as an error.
--   ns.OnMacrosChanged()   refreshes the panel next frame, if it's shown
--   ns.PanelRows()         the rows the panel lists (see Rows below); for tests

local _, ns = ...

local PANEL_WIDTH = 260
local MACRO_ROW_HEIGHT = 30
local TOY_ROW_HEIGHT = 24
local TOY_INDENT = 34
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local WARNING = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"

local panel, list
local refreshPending = false

local function IconTexture(icon)
	if type(icon) == "string" then
		return "Interface\\Icons\\" .. icon
	end
	return icon
end

local Refresh

-- After a macro opens, scroll just enough to show its toys, keeping the macro's own row in view
-- when there are more toys than fit.
local function ScrollToMacro(id)
	local macroIndex = list:FindElementDataIndexByPredicate(function(data)
		return data.kind == "macro" and data.macro.id == id
	end)
	if not macroIndex then
		return
	end
	local lastIndex = macroIndex
	while true do
		local data = list:FindElementData(lastIndex + 1)
		if not data or data.kind == "macro" then
			break
		end
		lastIndex = lastIndex + 1
	end
	list:ScrollToNearest(lastIndex, 0, true)
	list:ScrollToNearest(macroIndex, 0, true)
end

------------------------------------------------------------------------------------------
-- Rows. The list holds three kinds of element, all drawn by the same pooled button:
--   { kind = "macro", macro = m, count = n,   a macro, with its expand arrow, drag icon and toy
--     unreadable = why }                      count; why is ns.Unreadable(m), and the count "?"
--   { kind = "toy", itemID = itemID,          a toy in an expanded macro, greyed if the player
--     owned = bool }                          doesn't own it
--   { kind = "note", text = text }            a line of help text

local function Row_OnClick(row, mouseButton)
	local data = row.data
	if data.kind == "macro" then
		if mouseButton == "RightButton" then
			ns.OpenMacroMenu(row, data.macro)
		elseif data.unreadable then
			ns.ShowError(data.unreadable)
		else
			local id = data.macro.id
			ns.expanded[id] = not ns.expanded[id] or nil
			Refresh()
			if ns.expanded[id] then
				ScrollToMacro(id)
			end
		end
	elseif data.kind == "toy" and mouseButton == "RightButton" then
		ns.OpenToyMenu(row, data.itemID)
	end
end

local function ShowMacroTooltip(owner, data)
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	GameTooltip:SetText(data.macro.name)
	if data.unreadable then
		GameTooltip:AddLine(data.unreadable, 1, 0.82, 0, true)
	end
	GameTooltip:AddLine("Drag to an action bar.", 1, 1, 1)
	if not data.unreadable then
		GameTooltip:AddLine("On the bar, right-click it to choose a toy.", 1, 1, 1)
	end
	GameTooltip:Show()
end

local function Row_OnEnter(row)
	if row.data.kind == "toy" then
		GameTooltip:SetOwner(row, "ANCHOR_RIGHT")
		GameTooltip:SetToyByItemID(row.data.itemID)
		GameTooltip:Show()
	elseif row.data.kind == "macro" and row.data.unreadable then
		ShowMacroTooltip(row, row.data)
	end
end

local function MacroIcon_OnEnter(icon)
	ShowMacroTooltip(icon, icon:GetParent().data)
end

local function BuildRow(row)
	row:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	row:SetScript("OnClick", Row_OnClick)
	row:SetScript("OnEnter", Row_OnEnter)
	row:SetScript("OnLeave", GameTooltip_Hide)
	row:SetHighlightTexture(HIGHLIGHT, "ADD")

	row.arrow = row:CreateTexture(nil, "ARTWORK")
	row.arrow:SetSize(14, 14)
	row.arrow:SetPoint("LEFT", 2, 0)

	local macroIcon = CreateFrame("Button", nil, row)
	macroIcon:SetSize(24, 24)
	macroIcon:SetPoint("LEFT", row.arrow, "RIGHT", 4, 0)
	macroIcon:RegisterForDrag("LeftButton")
	macroIcon:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	macroIcon:SetScript("OnDragStart", function()
		ns.PickupMacro(row.data.macro)
	end)
	macroIcon:SetScript("OnClick", function(_, mouseButton)
		Row_OnClick(row, mouseButton)
	end)
	macroIcon:SetScript("OnEnter", MacroIcon_OnEnter)
	macroIcon:SetScript("OnLeave", GameTooltip_Hide)
	macroIcon.texture = macroIcon:CreateTexture(nil, "ARTWORK")
	macroIcon.texture:SetAllPoints()
	macroIcon:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	macroIcon.warning = macroIcon:CreateTexture(nil, "OVERLAY")
	macroIcon.warning:SetSize(14, 14)
	macroIcon.warning:SetPoint("BOTTOMRIGHT", 3, -3)
	macroIcon.warning:SetTexture(WARNING)
	row.macroIcon = macroIcon

	row.toyIcon = row:CreateTexture(nil, "ARTWORK")
	row.toyIcon:SetSize(20, 20)
	row.toyIcon:SetPoint("LEFT", TOY_INDENT, 0)

	row.count = row:CreateFontString(nil, "ARTWORK", "GameFontDisable")
	row.count:SetPoint("RIGHT", -4, 0)

	row.name = row:CreateFontString(nil, "ARTWORK", "GameFontHighlight")
	row.name:SetJustifyH("LEFT")
	row.name:SetWordWrap(false)
end

local function InitRow(row, data)
	if not row.name then
		BuildRow(row)
	end
	row.data = data
	local kind = data.kind
	row.arrow:SetShown(kind == "macro")
	row.macroIcon:SetShown(kind == "macro")
	row.count:SetShown(kind == "macro")
	row.toyIcon:SetShown(kind == "toy")
	row:GetHighlightTexture():SetAlpha(kind == "note" and 0 or 1)
	row.name:ClearAllPoints()

	if kind == "macro" then
		local m = data.macro
		row.arrow:SetTexture(ns.expanded[m.id] and "Interface\\Buttons\\UI-MinusButton-Up"
			or "Interface\\Buttons\\UI-PlusButton-Up")
		row.macroIcon.texture:SetTexture(IconTexture(m.icon))
		row.macroIcon.texture:SetDesaturated(data.unreadable ~= nil)
		row.macroIcon.warning:SetShown(data.unreadable ~= nil)
		row.count:SetText(data.count)
		row.name:SetFontObject("GameFontHighlight")
		row.name:SetPoint("LEFT", row.macroIcon, "RIGHT", 8, 0)
		row.name:SetPoint("RIGHT", row.count, "LEFT", -6, 0)
		row.name:SetText(m.name)
	elseif kind == "toy" then
		local _, name, icon = C_ToyBox.GetToyInfo(data.itemID)
		row.toyIcon:SetTexture(icon)
		row.toyIcon:SetDesaturated(not data.owned)
		row.name:SetFontObject(data.owned and "GameFontNormal" or "GameFontDisable")
		row.name:SetPoint("LEFT", row.toyIcon, "RIGHT", 8, 0)
		row.name:SetPoint("RIGHT", -4, 0)
		row.name:SetText(name or "")
	else
		row.name:SetFontObject("GameFontDisable")
		row.name:SetPoint("LEFT", TOY_INDENT, 0)
		row.name:SetPoint("RIGHT", -4, 0)
		row.name:SetText(data.text)
	end
end

------------------------------------------------------------------------------------------

local function PanelRows()
	local data = {}
	for _, m in ipairs(ns.GetMacros()) do
		local unreadable = ns.Unreadable(m)
		local toys = unreadable and {} or ns.GetMacroToys(m, true)
		data[#data + 1] = { kind = "macro", macro = m, count = unreadable and "?" or #toys, unreadable = unreadable }
		if ns.expanded[m.id] and not unreadable then
			for _, itemID in ipairs(toys) do
				data[#data + 1] = { kind = "toy", itemID = itemID, owned = PlayerHasToy(itemID) }
			end
			if #toys == 0 then
				data[#data + 1] = { kind = "note", text = m.builtin and "Star toys to add them."
					or "Right-click toys to add them." }
			end
		end
	end
	if not ns.HasOwnMacros() then
		data[#data + 1] = { kind = "note", text = "Right-click a toy to make one." }
	end
	return data
end
ns.PanelRows = PanelRows

function Refresh()
	local data = PanelRows()
	ns.Trace("[panel] refresh, %d rows", #data)
	list:SetDataProvider(CreateDataProvider(data), ScrollBoxConstants.RetainScrollPosition)
end

-- Changes can arrive in bursts, so refresh once, next frame.
function ns.OnMacrosChanged()
	if not panel or not panel:IsVisible() or refreshPending then
		return
	end
	refreshPending = true
	C_Timer.After(0, function()
		refreshPending = false
		if panel:IsVisible() then
			Refresh()
		end
	end)
end

local function CreatePanel()
	panel = CreateFrame("Frame", "ClickyPanel", ToyBox, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(panel)
	ButtonFrameTemplate_HideButtonBar(panel)
	panel.CloseButton:Hide()
	panel:SetTitle("Clicky")
	panel:SetWidth(PANEL_WIDTH)
	panel:SetPoint("TOPLEFT", ToyBox, "TOPRIGHT", 2, 0)
	panel:SetPoint("BOTTOMLEFT", ToyBox, "BOTTOMRIGHT", 2, 0)

	list = CreateFrame("Frame", nil, panel.Inset, "WowScrollBoxList")
	list:SetPoint("TOPLEFT", 6, -6)
	list:SetPoint("BOTTOMRIGHT", -20, 6)
	local scrollBar = CreateFrame("EventFrame", nil, panel.Inset, "MinimalScrollBar")
	scrollBar:SetPoint("TOPLEFT", list, "TOPRIGHT", 6, 0)
	scrollBar:SetPoint("BOTTOMLEFT", list, "BOTTOMRIGHT", 6, 0)
	local view = CreateScrollBoxListLinearView()
	view:SetElementExtentCalculator(function(_, data)
		return data.kind == "macro" and MACRO_ROW_HEIGHT or TOY_ROW_HEIGHT
	end)
	view:SetElementInitializer("Button", InitRow)
	ScrollUtil.InitScrollBoxListWithScrollBar(list, scrollBar, view)

	-- WoW places windows such as /macro beside the Collections window by its layout width, which
	-- doesn't include this panel; while it shows, widen that width, as the Calendar does for its
	-- side panel (Blizzard_Calendar.lua, CalendarCreateEventFrame_OnShow).
	panel:SetScript("OnShow", function()
		SetUIPanelAttribute(CollectionsJournal, "extraWidth", panel:GetWidth() + 2)
		UpdateUIPanelPositions(CollectionsJournal)
		Refresh()
	end)
	panel:SetScript("OnHide", function()
		SetUIPanelAttribute(CollectionsJournal, "extraWidth", nil)
		UpdateUIPanelPositions(CollectionsJournal)
	end)
	if panel:IsVisible() then
		panel:GetScript("OnShow")()
	end
end

-- The Collections window is load-on-demand.
if C_AddOns.IsAddOnLoaded("Blizzard_Collections") then
	CreatePanel()
else
	local loader = CreateFrame("Frame")
	loader:RegisterEvent("ADDON_LOADED")
	loader:SetScript("OnEvent", function(self, _, name)
		if name == "Blizzard_Collections" then
			self:UnregisterEvent("ADDON_LOADED")
			CreatePanel()
		end
	end)
end
