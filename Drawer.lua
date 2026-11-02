-- Every macro's drawer: its /click line sends a right-click to ClickyP<id> (ClickyPFVRT,
-- ClickyPFVMT and ClickyPFVPT for the built-in macros), which opens a grid of the macro's entries
-- (any kind; Entries.lua) the player has, at the mouse, in the panel's order, an item with how many
-- the player carries when more than one. Clicking one uses it. The drawer closes when an entry is
-- chosen, on Escape, on a second right-click, and when the mouse leaves it.
--   ns.SetUpDrawer(m)   makes m's opener and drawer if they don't exist yet (out of combat only)
--   ns.FillDrawer(m)    fills m's drawer with its entries, once SetUpDrawer has made it (out of
--                       combat only)
--   ns.QueueDrawer(m)   fills m's drawer soon, one drawer every FILL_DELAY
--   ns.EmptyDrawer(id)  empties a deleted macro's drawer (out of combat only)
--   ns.GetDrawer(id)    { frame, opener, buttons } for an id's drawer, or nil; for tests and
--                       /clicky debug (frame's "count" attribute is how many entries it holds)
--
-- It all works in combat, so it's secure: the opener's _onclick and each entry button's wrapped
-- OnClick run in WoW's restricted environment, which may show and hide protected frames and set
-- their attributes in combat. Each button's secure action is set when it is filled, out of combat
-- or on PLAYER_REGEN_DISABLED, whatever the entry's kind. Protected frames can't be created in
-- combat or destroyed, so openers and drawers are made with the macro's button and their entry
-- buttons are reused. Drawers are filled one at a time after login and combat, when opened out of
-- combat, and all on PLAYER_REGEN_DISABLED, the last chance before combat.

local _, ns = ...

local BUTTON_SIZE = 36
local GAP = 2
local PADDING = 6
local AUTO_HIDE = 0.5 -- seconds the mouse can be off the drawer before it closes
local FILL_DELAY = 0.1 -- seconds between drawers filled in the background (after login, after combat)

-- $cursor puts the drawer's bottom just under the mouse, so the mouse starts over it.
local OPEN = [[
	if down then
		return
	end
	local drawer = self:GetFrameRef("drawer")
	if drawer:IsShown() then
		drawer:Hide()
		return
	end
	if (drawer:GetAttribute("count") or 0) == 0 then
		return
	end
	drawer:ClearAllPoints()
	drawer:SetPoint("BOTTOM", "$cursor", 0, -4)
	drawer:Show()
	drawer:RegisterAutoHide(]] .. AUTO_HIDE .. [[)
]]

-- Closes the drawer: wrapped before an entry button's own click, which uses the entry, and run by the
-- close button. Escape closes the open drawer, in combat too: while it's shown, an override
-- binding sends Escape to the hidden close button, and the drawer clears it when it hides (HIDDEN).
local CLOSE = [[ self:GetFrameRef("drawer"):Hide() ]]
local SHOWN = [[ self:SetBindingClick(true, "ESCAPE", self:GetFrameRef("close")) ]]
local HIDDEN = [[ self:ClearBindings() ]]

local drawers = {} -- id -> { frame, opener, buttons }
local queue = {} -- ids waiting to be filled

-- How many entries the drawer holds is the frame's "count" attribute, which OPEN reads in secure code.
local function Count(drawer)
	return drawer.frame:GetAttribute("count") or 0
end

-- How many the player carries, when more than one, as Select's flyout buttons show it (its
-- secure/button.lua) and the bags do (SetItemButtonCount, ItemButtonTemplate.lua).
local function UpdateItemCount(button)
	local count = button.entry and ns.EntryCount(button.entry)
	button.count:SetText(count and count > 1 and tostring(count) or "")
end

-- Cooldowns and counts change while the drawer is closed. Shown by secure code, so this only reads.
local function Drawer_OnShow(frame)
	for i = 1, Count(frame.drawer) do
		local button = frame.drawer.buttons[i]
		ns.UpdateEntryCooldown(button.cooldown, button.entry)
		UpdateItemCount(button)
	end
end

local function CreateDrawerButton(drawer)
	local button = ns.CreateEntryButton(drawer.frame, BUTTON_SIZE, "ANCHOR_LEFT")
	-- An action button's count, on a frame above the cooldown so its swipe and countdown don't cover
	-- it (ActionButtonTemplate.xml: TextOverlayContainer, frameLevel 500, and Count).
	local overlay = CreateFrame("Frame", nil, button)
	overlay:SetAllPoints()
	overlay:SetFrameLevel(500)
	button.count = overlay:CreateFontString(nil, "OVERLAY", "NumberFontNormal")
	button.count:SetJustifyH("RIGHT")
	button.count:SetPoint("BOTTOMRIGHT", -3, 3)
	SecureHandlerSetFrameRef(button, "drawer", drawer.frame)
	SecureHandlerWrapScript(button, "OnClick", button, CLOSE)
	return button
end

function ns.SetUpDrawer(m)
	if InCombatLockdown() or not m.button or drawers[m.id] then
		return
	end
	local id = m.id
	local frame = CreateFrame("Frame", nil, UIParent, "SecureHandlerShowHideTemplate")
	frame:Hide()
	frame:SetFrameStrata("DIALOG")
	frame:SetClampedToScreen(true)
	frame:EnableMouse(true)
	frame.background = frame:CreateTexture(nil, "BACKGROUND")
	frame.background:SetAllPoints()
	frame.background:SetColorTexture(0, 0, 0, 0.85)
	frame:HookScript("OnShow", Drawer_OnShow)
	-- SetBindingClick needs the close button's name.
	local close = CreateFrame("Button", ns.DRAWER_BUTTON_PREFIX .. id .. "Close", frame, "SecureHandlerClickTemplate")
	close:RegisterForClicks("AnyDown")
	SecureHandlerSetFrameRef(close, "drawer", frame)
	close:SetAttribute("_onclick", CLOSE)
	SecureHandlerSetFrameRef(frame, "close", close)
	frame:SetAttribute("_onshow", SHOWN)
	frame:SetAttribute("_onhide", HIDDEN)

	local opener = CreateFrame("Button", ns.DRAWER_BUTTON_PREFIX .. id, UIParent, "SecureHandlerClickTemplate")
	opener:RegisterForClicks("AnyUp", "AnyDown")
	SecureHandlerSetFrameRef(opener, "drawer", frame)
	opener:SetAttribute("_onclick", OPEN)
	opener:SetScript("PreClick", function()
		local current = ns.GetMacro(id)
		if current then
			ns.FillDrawer(current)
		end
	end)
	-- OPEN shows nothing for an empty drawer; say why, as a left-click does.
	opener:SetScript("PostClick", function(_, _, down)
		local current = ns.GetMacro(id)
		if current and not down and Count(drawers[id]) == 0 then
			ns.ShowError(ns.NoEntriesMessage(current))
		end
	end)
	local drawer = { frame = frame, opener = opener, buttons = {} }
	frame.drawer = drawer
	drawers[id] = drawer
	ns.Trace("[drawer] created %s%s", ns.DRAWER_BUTTON_PREFIX, id)
end

function ns.FillDrawer(m)
	local drawer = drawers[m.id]
	if InCombatLockdown() or not drawer then
		return
	end
	local entries = ns.GetMacroEntries(m)
	local columns = math.max(1, math.ceil(math.sqrt(#entries)))
	local step = BUTTON_SIZE + GAP
	for i, key in ipairs(entries) do
		local button = drawer.buttons[i]
		if not button then
			button = CreateDrawerButton(drawer)
			drawer.buttons[i] = button
		end
		ns.SetEntryButton(button, key)
		UpdateItemCount(button)
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", PADDING + (i - 1) % columns * step, -(PADDING + math.floor((i - 1) / columns) * step))
		button:Show()
	end
	for i = #entries + 1, #drawer.buttons do
		ns.EmptyEntryButton(drawer.buttons[i])
	end
	local rows = math.max(1, math.ceil(#entries / columns))
	drawer.frame:SetSize(PADDING * 2 + columns * step - GAP, PADDING * 2 + rows * step - GAP)
	drawer.frame:SetAttribute("count", #entries)
	ns.Trace("[%s] drawer filled with %d entries", m.name, #entries)
end

-- A deleted macro's drawer, like its button, can't be destroyed: it's emptied.
function ns.EmptyDrawer(id)
	local drawer = drawers[id]
	if not drawer or InCombatLockdown() then
		return
	end
	for i = 1, #drawer.buttons do
		ns.EmptyEntryButton(drawer.buttons[i])
	end
	drawer.frame:Hide()
	drawer.frame:SetAttribute("count", 0)
	ns.Trace("[drawer] emptied %s%s", ns.DRAWER_BUTTON_PREFIX, id)
end

function ns.GetDrawer(id)
	return drawers[id]
end

-- One drawer per FILL_DELAY, skipping combat (PLAYER_REGEN_DISABLED fills them all).
local filling = false

local function FillNext()
	local id = table.remove(queue, 1)
	filling = id ~= nil
	if not filling then
		return
	end
	local m = ns.GetMacro(id)
	if m and not InCombatLockdown() then
		ns.FillDrawer(m)
	end
	C_Timer.After(FILL_DELAY, FillNext)
end

function ns.QueueDrawer(m)
	for _, id in ipairs(queue) do
		if id == m.id then
			return
		end
	end
	queue[#queue + 1] = m.id
	if not filling then
		filling = true
		C_Timer.After(FILL_DELAY, FillNext)
	end
end
