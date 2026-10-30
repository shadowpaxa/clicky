-- Clicky's grid in place of the Toy Box's (journey 15; docs/architecture.md, "The grid"), with
-- its own search and filters: the Toy Box's are the player's settings and are only hidden. It lists
-- entries (Entries.lua) in sections: toys, mounts and pets as each tab's filters let them through,
-- the spells the character knows, and the items carried or worn. A tab for each, with its count,
-- shows that section. A view (ns.RegisterView); its own redraws (search, filters, a tab, scrolling,
-- unwrap, held-mouse retry, the mount ridden or the pet out changing) skip ns.Changed. In combat the
-- buttons keep their entries until combat ends.
--   ns.GridSections(filters, text)   the sections listed, in order: { name ("toys", "mounts", "pets",
--                                    "spells" or "items"), keys }; filters is section name -> its
--                                    filters (GridFilters.lua), its defaults for one not given; for tests
--   ns.GridRows(section, columns)    the grid's rows of a section's keys, { keys }; for tests
--   ns.GridView(rows, from)          the rows in view from `from` (kept between 1 and the highest
--                                    first row), each { index, row, offset }; then the first row
--                                    used and the highest first row; for tests
--   ns.GetGridFilters()              the grid's filters now, section name -> filters; for tests
--   ns.GetGridState()                for /clicky debug: whether the grid is made, the tab shown,
--                                    where it is scrolled to, its search and the shown tab's filters

local _, ns = ...

-- 12 x 8 icons of the Toy Box's size (Blizzard_CollectionTemplates.xml), 6 apart across
-- (12 * 48 - 6 = 570) and 14 down (8 * 56 - 14 = 434): a star rises 13 above its icon
-- (slotFavorite, Blizzard_CollectionTemplates.xml:118), so 14 keeps it off the row above, as the
-- Toy Box's 16 between rows does for its 50-wide buttons (Blizzard_ToyBox.xml:67). Centered with
-- the scroll bar (8 from it, 8 wide, MinimalScrollBar.xml) in the icons frame: 693 x 541, the
-- 703 x 606 Collections window (Blizzard_Collections.xml:15) less its insets
-- (SharedCollectionTemplates.xml:57-60); down, the first row's stars are counted, so there are 47
-- above them and 47 below the last row ((541 - 13 - 434) / 2). That keeps clear of the frame's
-- corners as the Toy Box's own buttons do (its first at 40, 53, Blizzard_ToyBox.xml:52).
local VIEW_WIDTH, VIEW_HEIGHT = 570, 434
local VIEW_X, VIEW_Y = 53, 60
local COLUMNS, ROWS = 12, 8
local ICON_SIZE = 42
local COLUMN_STEP = ICON_SIZE + 6 -- from one entry to the next across
local ROW_STEP = ICON_SIZE + 14 -- and down
local TITLE = "Clicky" -- the Collections window's, on the Toy Box tab
-- The Toy Box's parts Clicky's grid takes the place of (Blizzard_ToyBox.xml).
local TOY_BOX_PARTS = { "iconsFrame", "PagingFrame", "searchBox", "FilterDropdown" }
-- The sections, in the order of their tabs, with their titles.
local SECTIONS = {
	{ name = "toys", title = "Toys" },
	{ name = "mounts", title = "Mounts" },
	{ name = "pets", title = "Pets" },
	{ name = "spells", title = "Spells" },
	{ name = "items", title = "Items" },
}
-- The search box: its width and its distance from the window's right edge.
local SEARCH_WIDTH, SEARCH_RIGHT = 115, 12
local TABS_X = 58 -- the first tab, from the window's left edge
-- Every tab's width together, as Appearances fits its own tabs to WARDROBE_TABS_MAX_WIDTH
-- (Blizzard_Wardrobe.lua:3, 9, 133): from the first tab to the search box in the 703-wide window
-- (Blizzard_Collections.xml:15), less the 3 between tabs (PanelTemplates_AnchorTabs,
-- SharedUIPanelTemplates.lua:479).
local TABS_WIDTH = 703 - SEARCH_RIGHT - SEARCH_WIDTH - TABS_X - (#SECTIONS - 1) * 3
local WHEEL_ROWS = 3 -- as one notch scrolls a message frame's three (ScrollUtil.lua:198-203)
local CHECK = "Interface\\Buttons\\UI-CheckBox-Check"
-- Toy names arrive one event at a time (GET_ITEM_INFO_RECEIVED) and drawing the grid is costlier
-- than the panel, so refreshes wait this long and run once.
local REFRESH_DELAY = 0.2

-- The filters each session starts with: Clicky has no saved settings.

-- Toys, Mounts and Pets each have their own filters, as the Toy Box, the Mount Journal and the Pet
-- Journal each keep their own; Spells and Items have none.
local filters = { toys = ns.DefaultGridFilters("toys"), mounts = ns.DefaultGridFilters("mounts"),
	pets = ns.DefaultGridFilters("pets") }
local grid -- with fields board (its buttons), buttons, scrollBar, search, filterButton, Tabs (in
-- SECTIONS' order)
local waiting = false -- the Collections window loaded in combat: the grid is made when it ends
local retrying = false -- a redraw is queued for after the held mouse button is released
local rows = {} -- GridRows' rows, as of the last refresh
local first = 1 -- the row at the top of the view
local maxFirst = 1 -- the highest row the view can start at
local listed = { 0, 0, 0, 0, 0 } -- how many of each section the last refresh listed, in SECTIONS' order
local inMacro = {} -- key -> true for the entries in a Clicky macro, as of the last refresh

------------------------------------------------------------------------------------------
-- What's listed.

-- Keeps an entry's name, which is "" while it loads; true if the entry matches the search (Search.lua).
local function Matches(names, key, name, text)
	names[key] = name
	return ns.EntryMatches(key, name, text)
end

-- Starred, then the rest the player has, then the rest, each by name (or as Pets' Sort by says), one
-- after the other as in the Toy Box, as the tab's filters let them through (GridFilters.lua); Spells
-- and Items (no tab filters) list what the player has. Only entries the filters let through are
-- named: an uncached name is loaded from the server.
local function ListedKeys(candidates, tab, gridFilters, text)
	local groups, names = { {}, {}, {} }, {}
	for _, key in ipairs(candidates) do
		local owned = ns.IsEntryOwned(key)
		if (gridFilters and ns.PassesGridFilters(tab, gridFilters, key, owned) or not gridFilters and owned)
			and Matches(names, key, ns.EntryName(key), text) then
			table.insert(groups[ns.IsEntryFavorite(key) and 1 or owned and 2 or 3], key)
		end
	end
	local keys = {}
	for _, group in ipairs(groups) do
		if gridFilters then
			ns.SortGridGroup(tab, gridFilters, group, names)
		else
			ns.SortEntries(group, names)
		end
		for _, key in ipairs(group) do
			keys[#keys + 1] = key
		end
	end
	return keys, names
end

local function Section(name, keys)
	return { name = name, keys = keys }
end

function ns.GridSections(gridFilters, text)
	text = strtrim(text or ""):lower()
	local function Filters(name)
		return gridFilters[name] or ns.DefaultGridFilters(name)
	end
	return {
		Section("toys", ListedKeys(ns.ListedToyEntries(Filters("toys").uncollected), "toys", Filters("toys"), text)),
		Section("mounts", ListedKeys(ns.ListedMountEntries(Filters("mounts").uncollected), "mounts", Filters("mounts"), text)),
		Section("pets", ListedKeys(ns.ListedPetEntries(Filters("pets").uncollected), "pets", Filters("pets"), text)),
		Section("spells", ListedKeys(ns.KnownSpellEntries(), "spells", nil, text)),
		Section("items", ListedKeys(ns.CarriedItemEntries(), "items", nil, text)),
	}
end

function ns.GridRows(section, columns)
	local result = {}
	for at = 1, #section.keys, columns do
		local row = {}
		for i = at, math.min(at + columns - 1, #section.keys) do
			row[#row + 1] = section.keys[i]
		end
		result[#result + 1] = { keys = row }
	end
	return result
end

-- Whole rows, so none is cut off.
function ns.GridView(allRows, from)
	local highest = math.max(1, #allRows - ROWS + 1)
	from = math.max(1, math.min(from, highest))
	local view = {}
	for i = from, math.min(#allRows, from + ROWS - 1) do
		view[#view + 1] = { index = i, row = allRows[i], offset = (i - from) * ROW_STEP }
	end
	return view, from, highest
end

-- A toy still in its gift wrap, or learned this session and not hovered over yet: only toys have
-- either (Toys.lua).
local function IsWrapped(key)
	return ns.EntryKind(key) == "toy" and ns.IsWrapped(key)
end

local function IsNew(key)
	return ns.EntryKind(key) == "toy" and ns.IsNewToy(key)
end

-- As on the Toy Box's buttons (Blizzard_ToyBox.xml OnClick, ToySpellButton_OnClick/OnModifiedClick).
-- "Modified" is shift, ctrl or alt, the keys the secure action reads (SecureTemplates.lua:70-90).
local function GridClick(key, mouseButton, modified, chatLink)
	if modified then
		return chatLink and "link" or nil
	elseif mouseButton == "RightButton" then
		return ns.IsEntryOwned(key) and "menu" or nil
	elseif mouseButton == "LeftButton" then
		if IsWrapped(key) then
			return "unwrap"
		elseif ns.IsEntryOwned(key) then
			return "use"
		end
	end
end

-- "3 toys, 0 mounts, ...": what the last refresh listed.
local function Counts()
	local counts = {}
	for i, section in ipairs(SECTIONS) do
		counts[i] = ("%d %s"):format(listed[i], section.name)
	end
	return table.concat(counts, ", ")
end

function ns.GetGridState()
	if not grid then
		return waiting and "waiting for combat to end" or "not made"
	end
	local name = SECTIONS[PanelTemplates_GetSelectedTab(grid)].name
	local shown = filters[name]
	return ("made, showing %s, top row %d of %d (%s), %ssearch %q%s%s"):format(name, first, #rows, Counts(),
		shown and (ns.DescribeGridFilters(shown) .. ", ") or "",
		grid.search:GetText(), InCombatLockdown() and ", in combat: redrawing waits for it to end" or "",
		retrying and ", redrawing waits for the mouse button" or "")
end

function ns.GetGridFilters()
	return filters
end

------------------------------------------------------------------------------------------
-- Buttons: secure entry buttons (EntryButton.lua), made once and re-pointed as the grid scrolls. In
-- combat nothing here sets a button's entry or moves, shows or hides a button, the board or the grid
-- (CLAUDE.md, WoW constraints). Their cooldown swipes and NEW labels still change: Cooldown frames
-- aren't protected (Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3), and SetCooldown's
-- IsProtectedFunction (FrameAPICooldownDocumentation.lua) applies only to protected frames.
-- PostClick's menu, link and unwrap are unrestricted in combat (MenuUtil.lua:151-167,
-- ChatFrameUtilOverrides.lua:14-77, ToyBoxInfoDocumentation.lua).

-- Out of combat only (its callers check).
local function ShowFrom(from)
	local view
	view, first, maxFirst = ns.GridView(rows, from)
	local shown = 0
	for _, entry in ipairs(view) do
		for column, key in ipairs(entry.row.keys) do
			shown = shown + 1
			local button = grid.buttons[shown]
			button:ClearAllPoints()
			button:SetPoint("TOPLEFT", grid.board, "TOPLEFT", (column - 1) * COLUMN_STEP, -entry.offset)
			ns.SetEntryButton(button, key, GridClick(key, "LeftButton") ~= "use")
			button.icon:SetAlpha(ns.IsEntryOwned(key) and 1 or 0.5)
			button.check:SetShown(inMacro[key] == true)
			button.star:SetShown(ns.IsEntryFavorite(key))
			button.new:SetShown(IsNew(key))
			button:Show()
		end
	end
	for i = shown + 1, #grid.buttons do
		ns.EmptyEntryButton(grid.buttons[i])
	end
end

local function ScrollPosition()
	return maxFirst > 1 and (first - 1) / (maxFirst - 1) or 0
end

-- The bar reports a wheel step twice (ScrollBar.lua:105-111, 173-179).
local function ScrollBar_OnScroll(_, percentage)
	if InCombatLockdown() then
		return
	end
	local row = 1 + math.floor(percentage * (maxFirst - 1) + 0.5)
	if row ~= first then
		ShowFrom(row)
		ns.Trace("[grid] scrolled to row %d of %d", first, #rows)
	end
end

-- Only when they'd reach the search box: the selected tab keeps its label and the rest share what's
-- left (SharedUIPanelTemplates.lua:439-468).
local function FitTabs(frame)
	PanelTemplates_ResizeTabsToFit(frame, TABS_WIDTH)
end

local Refresh

local function RefreshIfShown()
	if grid:IsVisible() then
		Refresh()
	end
end

function Refresh()
	if InCombatLockdown() then
		ns.Trace("[grid] refresh waits for combat to end")
		return
	end
	-- A button re-pointed between press and release would use the new toy, so wait while any mouse
	-- button is held (no argument: any, ModelControlButtonMixin.lua:167).
	if IsMouseButtonDown() then
		ns.Trace("[grid] refresh waits for the mouse button to be released")
		if not retrying then
			retrying = true
			C_Timer.After(REFRESH_DELAY, function()
				retrying = false
				RefreshIfShown()
			end)
		end
		return
	end
	-- A name still loading sorts first, and its entry moves when it arrives (each arrival refreshes
	-- the grid: Toys.lua, Spells.lua, Items.lua). Timed when tracing: a search can read thousands of
	-- tooltips (Search.lua).
	local started = ns.IsTracing() and debugprofilestop()
	local sections = ns.GridSections(filters, grid.search:GetText())
	local took = started and debugprofilestop() - started
	local shown = PanelTemplates_GetSelectedTab(grid)
	for i, section in ipairs(sections) do
		listed[i] = #section.keys
		grid.Tabs[i]:SetText(("%s (%d)"):format(SECTIONS[i].title, #section.keys))
		PanelTemplates_TabResize(grid.Tabs[i], grid.tabPadding)
	end
	-- The counts change the labels, so the tabs are fitted after every resize (FitTabs).
	FitTabs(grid)
	rows = ns.GridRows(sections[shown], COLUMNS)
	grid.filterButton:SetShown(filters[SECTIONS[shown].name] ~= nil)
	-- Favorites isn't counted: its toys are the favorites, which have their star.
	inMacro = {}
	for _, m in ipairs(ns.GetMacros()) do
		if not m.builtin then
			for key in pairs(ns.MacroEntries(m)) do
				inMacro[key] = true
			end
		end
	end
	ShowFrom(first)
	-- One snap position per first row, from the visible share (ScrollController.lua:105-116,
	-- ScrollUtil.lua:187-191).
	local bar = grid.scrollBar
	bar:SetVisibleExtentPercentage(1 / maxFirst)
	bar:SetPanExtentPercentage(maxFirst > 1 and WHEEL_ROWS / (maxFirst - 1) or 0)
	bar:SetScrollPercentage(ScrollPosition(), ScrollBoxConstants.NoScrollInterpolation)
	ns.Trace("[grid] refresh, %s, showing %s, top row %d of %d, listed in %.1f ms", Counts(), SECTIONS[shown].name,
		first, #rows, took or 0)
end

-- A search or filter change: only the grid shows it; back to the top.
local function ChangedList()
	first = 1
	RefreshIfShown()
end

-- A tab: its section, from the top. Not in combat, when nothing moves the grid's buttons (see Buttons).
local function ShowSection(index)
	if InCombatLockdown() then
		ns.Trace("[grid] %s tab: not in combat", SECTIONS[index].name)
		return
	end
	PanelTemplates_SetTab(grid, index)
	ns.Trace("[grid] showing %s", SECTIONS[index].name)
	-- At once, not in the redraw, which can wait for a mouse button (Refresh): the filter button is
	-- this tab's, and its reset button shows whether this tab's filters are the defaults, checked again
	-- as filters changed outside the menu are (Blizzard_Menu/11_0_0_MenuImplementationGuide.lua:230).
	grid.filterButton:SetShown(filters[SECTIONS[index].name] ~= nil)
	grid.filterButton:ValidateResetState()
	ChangedList()
end

ns.RegisterView("grid", function()
	return grid ~= nil and grid:IsVisible()
end, Refresh, REFRESH_DELAY)

-- The Toy Box's buttons redraw cooldowns on SPELL_UPDATE_COOLDOWN only (CollectionsSpellButton_OnShow,
-- Blizzard_CollectionTemplates.lua); an item's cooldown also has its own event
-- (ContainerDocumentation.lua). Also in combat (see Buttons).
local function UpdateCooldowns()
	if not grid or not grid:IsVisible() then
		return
	end
	for _, button in ipairs(grid.buttons) do
		if button:IsShown() then
			ns.UpdateEntryCooldown(button.cooldown, button.entry)
		end
	end
end
ns.RegisterEvent("SPELL_UPDATE_COOLDOWN", UpdateCooldowns)
ns.RegisterEvent("BAG_UPDATE_COOLDOWN", UpdateCooldowns)

-- The mount ridden or the pet that's out changed: the Mount Journal redraws its list and the mount
-- it marks on it, whatever its argument (Blizzard_MountCollection.lua:140, 353-357, 414); the Pet
-- Journal on "CRITTER" (Blizzard_PetCollection.lua:98, 271-275). What's listed doesn't change, so
-- only the buttons in view are redrawn, at once: their marks, and which of a look's pets a click
-- summons (one that isn't out). Going through ns.Changed rebuilt the whole list after its wait,
-- which made the mark lag (seen in play). In combat, or with a mouse button held, the marks change
-- at once (they're textures, which aren't protected) and the rest waits: Refresh for the button's
-- release, combat's end for its redraw.
ns.RegisterEvent("COMPANION_UPDATE", function(companionType)
	ns.Trace("[grid] COMPANION_UPDATE %s", tostring(companionType))
	if not grid or not grid:IsVisible() then
		return
	end
	if InCombatLockdown() or IsMouseButtonDown() then
		for _, button in ipairs(grid.buttons) do
			if button:IsShown() and button.entry then
				button.active:SetShown(ns.IsEntryActive(button.entry))
			end
		end
		if not InCombatLockdown() then
			Refresh()
		end
		return
	end
	ShowFrom(first)
end)

------------------------------------------------------------------------------------------
-- The filter menu of the tab shown: the Toy Box's, the Mount Journal's or the Pet Journal's
-- (GridFilters.lua).

-- The grid's frame is the filter button's parent. The menu reads it, not `grid`: SetupMenu builds the
-- menu at once, asking each checkbox whether it's ticked and whether the filters are the defaults
-- (DropdownButton.lua:240-247, 284-307; MenuTemplates.lua:924-927), while the grid is being built,
-- before `grid` is set. The frame has its tabs by then.
local function ShownName(frame)
	return SECTIONS[PanelTemplates_GetSelectedTab(frame)].name
end

local function SetUpFilters(filterButton)
	local frame = filterButton:GetParent()
	local function ShownFilters()
		return filters[ShownName(frame)]
	end
	-- Off as on the Toy Box's (Blizzard_ToyBox.xml:41; MenuTemplates.xml:74-75).
	filterButton.resizeToText = false
	filterButton:SetWidth(90)
	filterButton:SetIsDefaultCallback(function()
		local shown = ShownFilters()
		return shown == nil or ns.GridFiltersAreDefault(ShownName(frame), shown) -- Spells and Items have none
	end)
	filterButton:SetDefaultCallback(function()
		local name = ShownName(frame)
		filters[name] = ns.DefaultGridFilters(name)
		ns.Trace("[grid] %s filters reset", name)
		ChangedList()
	end)
	-- Spells and Items have no filters, and their tabs hide the button.
	filterButton:SetupMenu(function(_, rootDescription)
		local shown = ShownFilters()
		if shown then
			ns.AddGridFilterMenu(ShownName(frame), shown, rootDescription, ChangedList)
		end
	end)
end

------------------------------------------------------------------------------------------
-- Building the grid.

local function CreateButton(board)
	local button = ns.CreateEntryButton(board, ICON_SIZE, nil, true)
	button:RegisterForDrag("LeftButton")
	-- The Toy Box's drag for a toy (Blizzard_ToyBox.lua, ToySpellButton_OnDrag); the others are
	-- picked up the same way, with their own calls (Entries.lua).
	button:SetScript("OnDragStart", function(self)
		ns.PickupEntry(self.entry)
	end)
	button:SetScript("PostClick", function(self, mouseButton)
		local key = self.entry
		local modified = IsShiftKeyDown() or IsControlKeyDown() or IsAltKeyDown()
		local click = GridClick(key, mouseButton, modified, IsModifiedClick("CHATLINK"))
		if click == "menu" then
			ns.OpenEntryMenu(self, key)
		elseif click == "link" then
			local link = ns.EntryLink(key)
			if link then
				ChatFrameUtil.InsertLink(link)
			end
		elseif click == "unwrap" then
			ns.Unwrap(key)
			Refresh() -- the next click on it uses it
		end
		ns.Trace("[grid] %s on %s: %s", mouseButton, key, click)
	end)
	-- Also UpdateTooltip, as in the Toy Box (Blizzard_ToyBox.lua:213-226): a NEW toy scrolled under
	-- the mouse is seen.
	local ShowTooltip = button:GetScript("OnEnter")
	local function OnEnter(self)
		-- A button emptied while the mouse is over it holds no entry.
		if self.entry and ns.EntryKind(self.entry) == "toy" then
			ns.SeeToy(self.entry)
		end
		self.new:SetShown(self.entry ~= nil and IsNew(self.entry))
		ShowTooltip(self)
	end
	button:SetScript("OnEnter", OnEnter)
	button.UpdateTooltip = OnEnter
	-- Above the cooldown swipe.
	local marks = CreateFrame("Frame", nil, button)
	marks:SetAllPoints()
	marks:SetFrameLevel(button.cooldown:GetFrameLevel() + 1)
	button.check = marks:CreateTexture(nil, "OVERLAY")
	button.check:SetSize(18, 18)
	button.check:SetPoint("BOTTOMRIGHT", 4, -4)
	button.check:SetTexture(CHECK)
	-- The Toy Box's favorite star, where it has it (Blizzard_CollectionTemplates.xml:116-119).
	button.star = marks:CreateTexture(nil, "OVERLAY")
	button.star:SetAtlas("collections-icon-favorites", true)
	button.star:SetPoint("TOPLEFT", -12, 13)
	button.star:Hide()
	-- The Toy Box's label (Blizzard_CollectionTemplates.xml).
	button.new = marks:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
	button.new:SetPoint("TOP", 0, -2)
	button.new:SetText(NEW_CAPS)
	button.new:SetShadowOffset(1, -1)
	return button
end

-- Built hidden and kept only when whole, so a failure leaves the Toy Box's own grid. Out of combat.
local function CreateGrid()
	for _, part in ipairs(TOY_BOX_PARTS) do
		if not ToyBox[part] then
			ns.Trace("[grid] not made: the Toy Box lacks its %s", part)
			return
		end
	end
	-- The icons frame's own template (Blizzard_ToyBox.xml:47): its border, background and shadows,
	-- which the tabs stand on, in its place (SharedCollectionTemplates.xml:56-60).
	local frame = CreateFrame("Frame", "ClickyGrid", ToyBox, "CollectionsBackgroundTemplate")
	frame:Hide()
	-- Its top corners hidden under the tabs, as Appearances hides its own (Blizzard_Wardrobe.lua:137-138).
	frame.BGCornerTopLeft:Hide()
	frame.BGCornerTopRight:Hide()

	-- The tabs, Blizzard's top tabs where the Appearances tab has its Items and Sets
	-- (Blizzard_Wardrobe.xml:198-216; WardrobeCollectionFrame fills the window as the Toy Box does),
	-- on the edge of the grid's frame. PanelTemplates_SetTab shows the selected one
	-- (SharedUIPanelTemplates.lua:369-400).
	frame.Tabs = {}
	-- More than the template's 20 in all, which looked cramped, and a fifth less than 20 more,
	-- which looked too wide with five tabs (seen in play); a tab's OnShow resizes it with its
	-- parent's tabPadding too (SharedUIPanelTemplates.lua:256-258, 405-413).
	frame.tabPadding = 16
	for i, section in ipairs(SECTIONS) do
		local tab = CreateFrame("Button", nil, frame, "PanelTopTabButtonTemplate")
		tab:SetID(i)
		tab:SetText(section.title)
		-- A tab resizes itself to its full label when shown and when the screen size changes
		-- (PanelTabButtonMixin, SharedUIPanelTemplates.lua:249-258), which would undo the fit; a hook
		-- runs after the tab's own script, so the tabs are fitted again after it.
		tab:HookScript("OnShow", function() FitTabs(frame) end)
		tab:HookScript("OnEvent", function() FitTabs(frame) end)
		tab:SetScript("OnClick", function()
			ShowSection(i)
		end)
		frame.Tabs[i] = tab
	end
	frame.Tabs[1]:SetPoint("TOPLEFT", ToyBox, "TOPLEFT", TABS_X, -28)
	-- As Appearances sets its own up (Blizzard_Wardrobe.lua:131-132): SetNumTabs anchors each after the
	-- one before, and SetTab keeps the selected one on the frame (SharedUIPanelTemplates.lua:369-376).
	-- Each session starts with the toys.
	PanelTemplates_SetNumTabs(frame, #frame.Tabs)
	PanelTemplates_SetTab(frame, 1)

	local board = CreateFrame("Frame", "ClickyGridBoard", frame)
	frame.board = board
	board:SetPoint("TOPLEFT", frame, "TOPLEFT", VIEW_X, -VIEW_Y)
	board:SetSize(VIEW_WIDTH, VIEW_HEIGHT)
	frame.buttons = {}
	for i = 1, ROWS * COLUMNS do
		frame.buttons[i] = CreateButton(board)
		ns.EmptyEntryButton(frame.buttons[i])
	end

	-- Driven as Blizzard drives a message frame's (InitScrollingMessageFrameWithScrollBar, ScrollUtil.lua).
	local scrollBar = CreateFrame("EventFrame", "ClickyGridScrollBar", frame, "MinimalScrollBar")
	frame.scrollBar = scrollBar
	scrollBar:SetPoint("TOPLEFT", board, "TOPRIGHT", 8, 0)
	scrollBar:SetPoint("BOTTOMLEFT", board, "BOTTOMRIGHT", 8, 0)
	scrollBar:Init(1, 0)
	scrollBar:EnableSnapToInterval()
	-- The annotations type a MinimalScrollBar as a plain EventFrame, not as the callback registry it is.
	---@diagnostic disable-next-line: param-type-mismatch
	scrollBar:RegisterCallback(BaseScrollBoxEvents.OnScroll, ScrollBar_OnScroll, frame)
	-- As a scroll frame's wheel (ScrollUtil.lua:261-263); not while a mouse button is held (see Refresh).
	frame:EnableMouseWheel(true)
	frame:SetScript("OnMouseWheel", function(_, delta)
		if not IsMouseButtonDown() then
			scrollBar:ScrollStepInDirection(-delta)
		end
	end)

	-- The search, for every tab, where the Toy Box's filter button is (Blizzard_ToyBox.xml:39-45),
	-- leaving the tabs room.
	frame.search = CreateFrame("EditBox", "ClickyGridSearch", frame, "SearchBoxTemplate")
	frame.search:SetSize(SEARCH_WIDTH, 20)
	frame.search:SetPoint("TOPRIGHT", ToyBox, "TOPRIGHT", -SEARCH_RIGHT, -35)
	frame.search:SetAutoFocus(false)
	frame.search:HookScript("OnTextChanged", function(self)
		ns.Trace("[grid] search %q", self:GetText())
		ChangedList()
	end)
	-- The filters, on the Toys, Mounts and Pets tabs, above the grid's top right, which is free with its
	-- corner hidden: 18 high (MenuTemplates.xml:67), centered between the edge and the first row's
	-- icons ((VIEW_Y - 18) / 2 = 21 from each; a star there comes within 8, centering on the stars
	-- looked high over the usual icon without one, seen in play); its right edge lines up with the
	-- scroll bar's, at the grid's right (693 - VIEW_X - VIEW_WIDTH - 16 = 54).
	frame.filterButton = CreateFrame("DropdownButton", "ClickyGridFilter", frame, "WowStyle1FilterDropdownTemplate")
	frame.filterButton:SetPoint("TOPRIGHT", frame, "TOPRIGHT", -(693 - VIEW_X - VIEW_WIDTH - 16), -(VIEW_Y - 18) / 2)
	SetUpFilters(frame.filterButton)
	-- The Macros panel's arrow, right of the Filter button, in the room left to the window's edge. It
	-- stays there on the tabs without a Filter button.
	frame.panelToggle = ns.CreatePanelToggle(frame)
	frame.panelToggle:SetPoint("LEFT", frame.filterButton, "RIGHT", 4, 0)

	frame:SetScript("OnShow", Refresh)
	grid = frame
	-- Drawn now, not only when shown: the Toy Box tab can first be shown in combat, when a redraw waits.
	Refresh()
	-- Hidden once: nothing in Blizzard's UI source shows these again.
	for _, part in ipairs(TOY_BOX_PARTS) do
		ToyBox[part]:Hide()
	end
	-- Toys (n) says it. Blizzard only sets its value (Blizzard_ToyBox.lua:445-448), so it stays
	-- hidden; a patch without it leaves nothing to hide.
	if ToyBox.progressBar then
		ToyBox.progressBar:Hide()
	end
	-- Else its wheel turns the hidden pages, with a sound (Blizzard_ToyBox.lua:20-22, 195-198).
	ToyBox:EnableMouseWheel(false)
	-- The window's title is its tab's: CollectionsJournal_UpdateSelectedTab sets it after showing the
	-- tab, then triggers CollectionsJournal.TabSet (Blizzard_Collections.lua:35-53), whose callbacks
	-- get their owner first (CallbackRegistry.lua:135). On the Toy Box tab, which Clicky's grid and
	-- panel fill, it says Clicky; another tab sets its own again.
	EventRegistry:RegisterCallback("CollectionsJournal.TabSet", function(_, journal, tab)
		if tab == COLLECTIONS_JOURNAL_TAB_INDEX_TOYS then
			journal:SetTitle(TITLE)
		end
	end, frame)
	if ToyBox:IsShown() then
		CollectionsJournal:SetTitle(TITLE)
	end
	frame:Show()
	ns.Trace("[grid] made")
end

local function CreateGridWhenAllowed()
	if InCombatLockdown() then
		waiting = true
		ns.Trace("[grid] waiting for combat to end")
		return
	end
	waiting = false
	CreateGrid()
end

-- The last moment to stop a thumb drag, an OnUpdate (ScrollBar.lua:296-299).
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	if grid then
		grid.scrollBar:SetScrollAllowed(false)
		grid.scrollBar:UnregisterUpdate()
		ns.Trace("[grid] scrolling off for combat")
	end
end)

ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	if waiting then
		CreateGridWhenAllowed()
	elseif grid then
		grid.scrollBar:SetScrollAllowed(true)
		ns.Trace("[grid] scrolling on")
		-- What combat held back (a hidden grid redraws on OnShow).
		ns.Changed()
	end
end)

-- The Collections window is load-on-demand.
EventUtil.ContinueOnAddOnLoaded("Blizzard_Collections", CreateGridWhenAllowed)
