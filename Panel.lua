-- The Clicky panel, docked to the right edge of the Toy Box: one scrolling list of macros, each
-- collapsed by default. Click a macro to show or hide its entries. Drag a macro's icon to put it
-- on a bar; right-click a macro to rename or delete it; right-click an entry for the same menu as
-- in the grid (Menu.lua). It's parented to the Toy Box, so it shows only on the Toy Box tab. A
-- macro whose entries can't be read has a greyed icon with a warning mark and "?" for its count;
-- hovering over it says why, and clicking it shows the same message as an error.
--   ns.PanelRows()         the rows the panel lists (see Rows below); for tests
--   ns.GetPanelState()     for /clicky debug: whether the panel is made and shown, and the macro the
--                          next refresh scrolls to
--   ns.CreatePanelToggle(parent)   the arrow that hides the panel and shows it again, as the world
--                          map's arrow does its quest log (WorldMapSidePanelToggleMixin,
--                          Blizzard_WorldMapTemplates.lua:644-659): the button showing is the one
--                          that does what it shows. Its art is the Calendar's page arrows
--                          (Blizzard_Calendar.xml:267-280): the world map's has a quest mark. The
--                          grid places it beside its Filter button (Grid.lua). The panel starts
--                          shown each session: Clicky saves nothing.
--
-- The panel is a view (ns.RegisterView, Core.lua): ns.Changed refreshes it next frame, if it's shown.

local _, ns = ...

local PANEL_WIDTH = 260
local TITLE = "Macros" -- the panel's, in its top bar
local MACRO_ROW_HEIGHT = 30
local TOY_ROW_HEIGHT = 24
local TOY_INDENT = 34
local HIGHLIGHT = "Interface\\QuestFrame\\UI-QuestTitleHighlight"
local WARNING = "Interface\\DialogFrame\\UI-Dialog-Icon-AlertNew"

local panel, list
local toggle -- the arrow that hides and shows the panel (ns.CreatePanelToggle)
local scrollTo -- the id of a macro just opened: the next refresh scrolls to show its entries

local function IconTexture(icon)
	if type(icon) == "string" then
		return "Interface\\Icons\\" .. icon
	end
	return icon
end

-- After a macro opens, scroll just enough to show its entries, keeping the macro's own row in view
-- when there are more entries than fit.
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
--   { kind = "macro", macro = m, count = n,   a macro, with its expand arrow, drag icon and entry
--     unreadable = why }                      count; why is ns.Unreadable(m), and the count "?"
--   { kind = "entry", key = key,              an entry (any kind, Entries.lua) in an
--     macro = m, owned = bool }               expanded macro m, greyed if the player doesn't have it
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
			scrollTo = ns.expanded[id] and id or nil
			ns.Trace("[panel] %s %s, scroll to it: %s", id, ns.expanded[id] and "opened" or "closed", scrollTo ~= nil)
			ns.Changed()
		end
	elseif data.kind == "entry" and mouseButton == "RightButton" then
		ns.OpenMacroEntryMenu(row, data.macro, data.key)
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
		-- A built-in macro holds one kind (ns.MacroNoun).
		GameTooltip:AddLine(("On the bar, right-click it to choose %s."):format(data.macro.builtin
			and data.macro.one or "an item"), 1, 1, 1)
		if ns.InMacroUI(data.macro) and #ns.GetMacroEntries(data.macro, true) > 0 then
			GameTooltip:AddLine(("To change this icon, right-click one of its %s."):format(ns.MacroNoun(data.macro)),
				1, 1, 1)
		end
	end
	GameTooltip:Show()
end

local function Row_OnEnter(row)
	if row.data.kind == "entry" then
		ns.ShowEntryTooltip(row, row.data.key)
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
	row.toyIcon:SetShown(kind == "entry")
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
	elseif kind == "entry" then
		ns.SetEntryTexture(row.toyIcon, data.key, data.owned)
		row.name:SetFontObject(data.owned and "GameFontNormal" or "GameFontDisable")
		row.name:SetPoint("LEFT", row.toyIcon, "RIGHT", 8, 0)
		row.name:SetPoint("RIGHT", -4, 0)
		row.name:SetText(ns.EntryName(data.key))
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
	local macros = ns.GetMacros()
	for _, m in ipairs(macros) do
		local unreadable = ns.Unreadable(m)
		local entries = ns.GetMacroEntries(m, true)
		data[#data + 1] = { kind = "macro", macro = m, count = unreadable and "?" or #entries, unreadable = unreadable }
		if ns.expanded[m.id] and not unreadable then
			for _, key in ipairs(entries) do
				data[#data + 1] = { kind = "entry", key = key, macro = m, owned = ns.IsEntryOwned(key) }
			end
			if #entries == 0 then
				data[#data + 1] = { kind = "note", text = m.builtin and ("Star %s to add them."):format(m.noun)
					or "Right-click a toy, mount, pet, spell or item to add it." }
			end
		end
	end
	if #macros == #ns.BUILTINS then
		data[#data + 1] = { kind = "note", text = "Right-click a toy, mount, pet, spell or item to make one." }
	end
	return data
end
ns.PanelRows = PanelRows

function ns.GetPanelState()
	if not panel then
		return "not made"
	end
	return ("made, %s, next refresh scrolls to %s"):format(panel:IsShown() and "shown" or "hidden", tostring(scrollTo or "nothing"))
end

local function Refresh()
	local data = PanelRows()
	ns.Trace("[panel] refresh, %d rows", #data)
	list:SetDataProvider(CreateDataProvider(data), ScrollBoxConstants.RetainScrollPosition)
	if scrollTo then
		ns.Trace("[panel] scrolling to show %s's entries", scrollTo)
		ScrollToMacro(scrollTo)
		scrollTo = nil
	end
end

-- Next frame: changes arrive in bursts, and the panel is small enough not to wait longer.
ns.RegisterView("panel", function()
	return panel ~= nil and panel:IsVisible()
end, Refresh, 0)

-- The window manager doesn't take addon calls in combat (UIParentPanelManager.lua:840-864), so the
-- window keeps its width until the panel is next shown or hidden out of combat.
local function SetExtraWidth(width)
	if not InCombatLockdown() then
		SetUIPanelAttribute(CollectionsJournal, "extraWidth", width)
		UpdateUIPanelPositions(CollectionsJournal)
	end
end

-- The arrow showing is the one that does what it shows: hide the panel while it's shown.
local function UpdateToggle()
	if toggle then
		local shown = panel == nil or panel:IsShown()
		toggle.OpenButton:SetShown(not shown)
		toggle.CloseButton:SetShown(shown)
	end
end

local function CreatePanel()
	panel = CreateFrame("Frame", "ClickyPanel", ToyBox, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(panel)
	ButtonFrameTemplate_HideButtonBar(panel)
	-- What it lists, in its top bar, as the Event Trace window titles its own ButtonFrameTemplate
	-- (Blizzard_EventTrace.lua:80, 111; TitledPanelMixin:SetTitle, PortraitFrame.lua:12). The window
	-- beside it says Clicky (Grid.lua). The list starts under the top edge.
	panel:SetTitle(TITLE)
	ButtonFrameTemplate_HideAttic(panel)
	panel.CloseButton:Hide()
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
	-- side panel (Blizzard_Calendar.lua, CalendarCreateEventFrame_OnShow). The panel is filled
	-- first: an error in the UI panel calls must not leave it empty.
	panel:SetScript("OnShow", function()
		Refresh()
		UpdateToggle()
		SetExtraWidth(panel:GetWidth() + 2)
	end)
	panel:SetScript("OnHide", function()
		scrollTo = nil
		UpdateToggle()
		SetExtraWidth(nil)
	end)
	if panel:IsVisible() then
		panel:GetScript("OnShow")()
	end
end

-- The window's width, as the panel's OnShow and OnHide set it, once a fight ends: in it they can't
-- (SetExtraWidth).
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if panel then
		SetExtraWidth(panel:IsVisible() and panel:GetWidth() + 2 or nil)
	end
end)

-- The panel isn't protected, so the arrow works in combat; the window's width follows it once
-- combat ends. The grid may make the arrow before the panel is made: until then it
-- shows the arrow that hides it, as the panel starts shown.
function ns.CreatePanelToggle(parent)
	toggle = CreateFrame("Frame", "ClickyPanelToggle", parent)
	toggle:SetSize(24, 24)
	for key, art in pairs({ OpenButton = "NextPage", CloseButton = "PrevPage" }) do
		local button = CreateFrame("Button", nil, toggle)
		button:SetAllPoints()
		button:SetNormalTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "-Up")
		button:SetPushedTexture("Interface\\Buttons\\UI-SpellbookIcon-" .. art .. "-Down")
		button:SetHighlightTexture("Interface\\Buttons\\UI-Common-MouseHilight", "ADD")
		button:SetScript("OnClick", function()
			if panel then
				panel:SetShown(not panel:IsShown())
				ns.Trace("[panel] %s by its arrow", panel:IsShown() and "shown" or "hidden")
			end
		end)
		toggle[key] = button
	end
	UpdateToggle()
	return toggle
end

-- The Collections window is load-on-demand.
EventUtil.ContinueOnAddOnLoaded("Blizzard_Collections", CreatePanel)
