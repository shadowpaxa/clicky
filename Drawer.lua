-- Every macro's drawer: its /click line sends a right-click to ClickyP<id> (ClickyPFVRT for
-- Favorites), which opens a grid of the macro's owned toys at the mouse, in the panel's order.
-- Clicking a toy uses it. The drawer closes when a toy is chosen, on Escape, on a second
-- right-click, and when the mouse leaves it.
--   ns.SetUpDrawer(m)   makes m's opener and drawer if they don't exist yet (out of combat only)
--   ns.FillDrawer(m)    fills m's drawer with its toys (out of combat only)
--   ns.QueueDrawer(m)   fills m's drawer soon, a few drawers at a time
--   ns.EmptyDrawer(id)  empties a deleted macro's drawer (out of combat only)
--   ns.GetDrawer(id)    { frame, opener, buttons, count } for an id's drawer, or nil; for tests
--                       and /clicky debug
--
-- All of it works in combat, so it's secure: the opener's _onclick and each toy button's wrapped
-- OnClick run in WoW's restricted environment, which may show and hide protected frames and set
-- their attributes in combat. Protected frames can't be created in combat and can't be destroyed,
-- so openers and drawers are made when the macro's button is, and their toy buttons are reused.
-- Filling a drawer makes a button per owned toy (up to 150; Favorites has no limit), so drawers
-- set up together (after login, after combat) are filled a few at a time; a drawer is also filled when it's opened out of combat, and every drawer on
-- PLAYER_REGEN_DISABLED, the last chance before combat.

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

-- Before the toy button's own click, which uses the toy.
local CHOOSE = [[ self:GetFrameRef("drawer"):Hide() ]]

-- Escape closes the open drawer, in combat too: while it's shown, an override binding sends
-- Escape to a hidden close button, and the drawer clears it when it hides (HIDDEN).
local SHOWN = [[ self:SetBindingClick(true, "ESCAPE", self:GetFrameRef("close")) ]]
local HIDDEN = [[ self:ClearBindings() ]]
local CLOSE = [[ self:GetFrameRef("drawer"):Hide() ]]

local drawers = {} -- id -> { frame, opener, buttons, count }
local queue = {} -- ids waiting to be filled

local function Button_OnEnter(button)
	GameTooltip:SetOwner(button, "ANCHOR_LEFT")
	GameTooltip:SetToyByItemID(button:GetAttribute("item"))
	GameTooltip:Show()
end

-- Cooldowns change while the drawer is closed. Shown by secure code, so this only reads.
local function Drawer_OnShow(frame)
	for i = 1, frame.drawer.count do
		local button = frame.drawer.buttons[i]
		CooldownFrame_Set(button.cooldown, C_Container.GetItemCooldown(button:GetAttribute("item")))
	end
end

local function CreateToyButton(drawer)
	local button = CreateFrame("Button", nil, drawer.frame, "SecureActionButtonTemplate")
	button:SetSize(BUTTON_SIZE, BUTTON_SIZE)
	-- Mouse clicks on secure buttons act on the up click (SecureActionButton_OnClick), and the
	-- wrapped snippet runs on every click it's registered for.
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	SecureHandlerSetFrameRef(button, "drawer", drawer.frame)
	SecureHandlerWrapScript(button, "OnClick", button, CHOOSE)
	button:SetScript("OnEnter", Button_OnEnter)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
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
		if current and not down and drawers[id].count == 0 then
			ns.ShowError(ns.NoToysMessage(current))
		end
	end)
	local drawer = { frame = frame, opener = opener, buttons = {}, count = 0 }
	frame.drawer = drawer
	drawers[id] = drawer
	ns.Trace("[drawer] created %s%s", ns.DRAWER_BUTTON_PREFIX, id)
end

function ns.FillDrawer(m)
	ns.SetUpDrawer(m)
	local drawer = drawers[m.id]
	if InCombatLockdown() or not drawer then
		return
	end
	local toys = ns.GetMacroToys(m)
	local columns = math.max(1, math.ceil(math.sqrt(#toys)))
	local step = BUTTON_SIZE + GAP
	for i, itemID in ipairs(toys) do
		local button = drawer.buttons[i]
		if not button then
			button = CreateToyButton(drawer)
			drawer.buttons[i] = button
		end
		button:SetAttribute("item", itemID)
		button:SetAttribute("type", "toy")
		button:SetAttribute("toy", itemID)
		button.icon:SetTexture(ns.ToyIcon(itemID))
		button:ClearAllPoints()
		button:SetPoint("TOPLEFT", PADDING + (i - 1) % columns * step, -(PADDING + math.floor((i - 1) / columns) * step))
		button:Show()
	end
	for i = #toys + 1, #drawer.buttons do
		local button = drawer.buttons[i]
		for _, key in ipairs({ "item", "type", "toy" }) do
			button:SetAttribute(key, nil)
		end
		button:Hide()
	end
	local rows = math.max(1, math.ceil(#toys / columns))
	drawer.frame:SetSize(PADDING * 2 + columns * step - GAP, PADDING * 2 + rows * step - GAP)
	drawer.frame:SetAttribute("count", #toys)
	drawer.count = #toys
	ns.Trace("[%s] drawer filled with %d toys", m.name, #toys)
end

-- A deleted macro's drawer, like its button, can't be destroyed: it's emptied.
function ns.EmptyDrawer(id)
	local drawer = drawers[id]
	if not drawer or InCombatLockdown() then
		return
	end
	for i = 1, #drawer.buttons do
		drawer.buttons[i]:Hide()
	end
	drawer.frame:Hide()
	drawer.frame:SetAttribute("count", 0)
	drawer.count = 0
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
