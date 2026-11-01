-- Stubs of the WoW API Clicky calls, for running its real files under LuaJIT (Lua 5.1, like WoW).
--
-- wow.New(options) builds a fresh, isolated world: one login on one computer, with its own
-- globals and events. What WoW keeps on its servers per account (toys, macros,
-- action bars) lives in world.account, which another world can share to play the same account on
-- a second computer: wow.New({ account = world.account }). It loads the files listed in
-- Clicky.toc as the game does (each file gets ("Clicky", ns)) and fires the login events.
--
-- Clicky's toy list (ToyList.lua) is shipped with Clicky, not read from the game, so a world has
-- its own: options.toyList, a list of entries (item IDs, "s<id>", "i<id>", "m<id>",
-- "p<species>:<display>"), stands in for
-- ToyList.lua's ns.TOY_IDS. Without it the list is the account's toys (account.toyOrder) as they
-- are when the world is made. A test that adds a toy to the game or takes one out passes the list
-- explicitly, so the toys' places don't move. A computer with an older or newer Clicky gets a
-- shorter or longer toyList.
--
-- Only game state is stubbed: toys, spells, items, mounts, pets, macros, action bars running /click
-- lines (with macro conditionals and the mouse button), secure buttons and their modified
-- attributes, secure snippets in a restricted-like environment, modifier keys, auto-hiding frames,
-- timers, combat lockdown and events, each following Blizzard's documentation or UI source (cited
-- where it matters), and the Blizzard frames and widgets Clicky relies on (the Toy Box's frames, a
-- scroll bar and list, a filter menu, tooltips, cooldown frames, the context menu's entries), as
-- far as Clicky uses them, each citing Blizzard's source. The mouse reaches a button as WoW sends
-- it: the clicks it registered for, the wheel and drags only if enabled (World:HoldMouse,
-- World:MouseWheel, World:Drag). UI behavior is shown by tests, or relies only on behavior
-- Blizzard's source shows. A context menu is kept as its generator builds it (world.menu) and a
-- dialog as StaticPopup_Show sets it up (world.dialog); what Blizzard draws for them isn't here.
--
-- A test changes the game with World:AddToy, AddSpell (on a skill line, in a flyout or a
-- profession's), AddItem (in a bag or worn), AddMount, AddPet and LearnPet, and with the options
-- below (toyList and toyHidden for Clicky's list); it answers the menu with World:ChooseMenuEntry
-- and a dialog with World:TypeInDialog, PressEnterInDialog and ClickDialogButton; to see which menu
-- opens, it can replace ns.OpenEntryMenu.
-- tests/check_api.py checks every API Clicky calls exists.

local wow = {}

local ADDON = "Clicky"
local ROOT = (debug.getinfo(1, "S").source:match("^@(.*)/tests/wow%.lua$") or ".")
local MAX_ACCOUNT = 120 -- MacroConstantsDocumentation.lua
local MAX_CHARACTER = 30

-- WoW's string.format is Lua 5.1's, where %s takes only a string or a number and anything else is
-- "bad argument" (Lua 5.1 reference manual, string.format; its C code checks the argument with
-- luaL_checklstring). LuaJIT's takes anything, so this makes it strict, to see code that would
-- fail in the game.
local formatLoose = string.format
rawset(string, "format", function(fmt, ...)
	local args, n = { ... }, 0
	for spec in tostring(fmt):gmatch("%%[-+ #0]*%d*%.?%d*([%a%%])") do
		if spec ~= "%" then
			n = n + 1
			if spec == "s" and type(args[n]) ~= "string" and type(args[n]) ~= "number" then
				error(("bad argument #%d to 'format' (string expected, got %s)"):format(n + 1, type(args[n])), 2)
			end
		end
	end
	return formatLoose(fmt, ...)
end)

local function strtrim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

------------------------------------------------------------------------------------------
-- Frames. Methods Clicky calls only for looks (SetAtlas, SetFrameStrata...) do nothing, on the
-- widget types that have them (LOOKS); a method no stub defines is missing, as in the game.

local Frame = {}

-- A widget's type (frame.kind: the type CreateFrame was given, or Texture or FontString) and the
-- types it inherits, as Ketho's annotations (Annotations/Core) and warcraft.wiki.gg Widget API have
-- them: CheckButton is a Button, every frame type is a Frame, and everything is a Region and a
-- ScriptRegion.
local function IsA(frame, class)
	local kind = frame.kind
	if class == "Region" or class == "ScriptRegion" then return true end
	if class == "Frame" then return kind ~= "Texture" and kind ~= "FontString" end
	if class == "Button" then return kind == "Button" or kind == "CheckButton" end
	return kind == class
end

-- Methods Clicky calls only for how a widget looks or sits: they do nothing here, and only the types
-- that have them have them (the class each is defined on in Ketho's annotations). Any other method
-- the stubs don't define is missing, so calling it is an error, as calling a method a widget lacks
-- is in the game.
local LOOKS = {
	EnableMouse = "ScriptRegion",
	SetAtlas = "Texture", SetBlendMode = "Texture", SetColorTexture = "Texture", -- TextureBase
	SetHighlightTexture = "Button", SetNormalTexture = "Button", SetPushedTexture = "Button",
	SetAutoFocus = "EditBox",
	SetClampedToScreen = "Frame", SetDontSavePosition = "Frame", SetFrameStrata = "Frame", SetID = "Frame",
	SetMovable = "Frame", SetToplevel = "Frame",
	SetFontObject = "FontString EditBox", SetJustifyH = "FontString EditBox", SetShadowOffset = "FontString EditBox",
	SetWordWrap = "FontString",
}

-- Methods with state that only some types have (TextureBase's SetTexture and SetDesaturated,
-- Button's GetHighlightTexture), filled in below.
local TYPED = {}

Frame.__index = function(self, key)
	local method = rawget(Frame, key)
	if method then
		return method
	end
	local typed = TYPED[key]
	if typed and IsA(self, typed.class) then
		return typed.fn
	end
	for class in (LOOKS[key] or ""):gmatch("%a+") do
		if IsA(self, class) then return function() return self end end
	end
end

-- Templates that make a frame protected: each inherits SecureFrameTemplate (protected="true",
-- SecureTemplatesBase.xml).
local PROTECTED = {
	SecureFrameTemplate = true,
	SecureActionButtonTemplate = true, -- SecureTemplates.xml
	SecureHandlerClickTemplate = true,
	SecureHandlerShowHideTemplate = true,
}

-- Characters in a UTF-8 string. Macro names hold 16 (the /macro name box has letters="16",
-- SharedUIPanelTemplates.xml), whatever their bytes.
local function Letters(s)
	return select(2, s:gsub("[^\128-\191]", ""))
end

-- The first n characters of a UTF-8 string. /macro's body box holds 255 characters, whatever their
-- bytes (MacroFrameText letters="255", Blizzard_MacroUI.xml; its counter is GetNumLetters).
local function FirstLetters(s, n)
	local letters = 0
	for at = 1, #s do
		local byte = s:byte(at)
		if byte < 0x80 or byte >= 0xC0 then
			letters = letters + 1
			if letters > n then
				return s:sub(1, at - 1)
			end
		end
	end
	return s
end

-- General macros are kept sorted by name, so creating or renaming one can move it and others
-- (warcraft.wiki.gg API_EditMacro: "as they are sorted alphabetically"). Returns m's new index.
local function SortMacros(macros, m)
	local sorted = {}
	for _, macro in ipairs(macros) do
		local at = #sorted + 1
		while at > 1 and macro.name < sorted[at - 1].name do
			at = at - 1
		end
		table.insert(sorted, at, macro)
	end
	local index
	for i, macro in ipairs(sorted) do
		macros[i] = macro
		if macro == m then index = i end
	end
	return index
end

local Cooldown, ScrollBar, ScrollList, FilterDropdown, ButtonFrame -- templates with methods of their own, below

local function NewFrame(world, name, parent, template, kind)
	local frame = setmetatable({ world = world, name = name, parent = parent, template = template, kind = kind or "Frame",
		scripts = {}, hooks = {}, attributes = {}, wraps = {}, shown = true, points = {}, width = 0,
		height = 0, level = 1 }, Frame)
	if PROTECTED[template] then
		if world.combat then
			error("ADDON_ACTION_BLOCKED: CreateFrame of a protected frame in combat", 3)
		end
		frame.protected = true
	end
	-- Blizzard's templates that Clicky's frames are made of, as far as Clicky uses them.
	local methods = template == "MinimalScrollBar" and ScrollBar
		or template == "WowScrollBoxList" and ScrollList
		or template == "WowStyle1FilterDropdownTemplate" and FilterDropdown
		or template == "CooldownFrameTemplate" and Cooldown
	for key, method in pairs(methods or {}) do
		frame[key] = method
	end
	if template == "WowStyle1FilterDropdownTemplate" then
		frame.resizeToText = true -- MenuTemplates.xml:74
	elseif template == "MinimalScrollBar" then
		frame.allowScroll, frame.panExtentPercentage, frame.visibleExtentPercentage = true, 0.1, 0
		frame.scrollPercentage, frame.callbacks = 0, {}
	elseif template == "WowScrollBoxList" then
		frame.rows, frame.elements, world.scrollList = {}, {}, frame
	elseif template == "ButtonFrameTemplate" then
		ButtonFrame(world, frame)
	elseif template == "PortraitFrameTemplate" then
		-- Its title (TitledPanelMixin, PortraitFrame.lua:4-14), as ButtonFrameTemplate's below.
		frame.TitleContainer = { TitleText = NewFrame(world, nil, frame, nil, "FontString") }
		function frame:SetTitle(title) self.TitleContainer.TitleText:SetText(title) end
	elseif template == "PanelTopTabButtonTemplate" then
		-- A tab resizes itself to its label with its parent's padding when shown
		-- (PanelTabButtonMixin:OnShow, SharedUIPanelTemplates.lua:256-258).
		frame.scripts.OnShow = function(tab)
			world.env.PanelTemplates_TabResize(tab, tab.parent.tabPadding, nil, tab.parent.minTabWidth, tab.parent.maxTabWidth)
		end
	elseif template == "ScrollingEditBoxTemplate" then
		-- Its ScrollBox and the multi-line EditBox in it, which doesn't take the keyboard when shown
		-- (autoFocus="false", ScrollTemplates.xml:21-44); SetText puts the text in the edit box
		-- (ScrollingEditBoxMixin:SetText, ScrollTemplates.lua:165-170). A click on it gives it the
		-- keyboard and runs OnEditFocusGained (warcraft.wiki.gg UIHANDLER OnEditFocusGained);
		-- HighlightText(0) selects from the start to the end (warcraft.wiki.gg API
		-- EditBox:HighlightText: end defaults to the end), kept as the text selected.
		frame.ScrollBox = NewFrame(world, nil, frame)
		frame.ScrollBox.EditBox = NewFrame(world, nil, frame.ScrollBox, nil, "EditBox")
		local editBox = frame.ScrollBox.EditBox
		function editBox:SetFocus()
			self.focused = true
			for _, fn in ipairs(self.hooks.OnEditFocusGained or {}) do fn(self) end
		end
		function editBox:HasFocus() return self.focused == true end
		function editBox:ClearFocus() self.focused = false end
		function editBox:HighlightText(start) self.selected = (self.text or ""):sub((start or 0) + 1) end
		function frame:GetScrollBox() return self.ScrollBox end
		function frame:GetEditBox() return self.ScrollBox.EditBox end
		function frame:SetText(text) self.ScrollBox.EditBox:SetText(text) end
		function frame:GetText() return self.ScrollBox.EditBox:GetText() end
	elseif template == "UICheckButtonTemplate" then
		-- Its label, parentKey Text (CheckButtonTemplates.xml:50-64). A click ticks or unticks it,
		-- then runs OnClick (warcraft.wiki.gg Widget API CheckButton).
		frame.Text = NewFrame(world, nil, frame, nil, "FontString")
		function frame:SetChecked(checked) self.checked = checked == true end
		function frame:GetChecked() return self.checked == true end
		function frame:Click()
			self.checked = not self.checked
			if self.scripts.OnClick then self.scripts.OnClick(self, "LeftButton", false) end
		end
	elseif template == "CollectionsBackgroundTemplate" then
		-- Its top corners (SharedCollectionTemplates.xml:177-186), shown.
		frame.BGCornerTopLeft, frame.BGCornerTopRight = frame:CreateTexture(), frame:CreateTexture()
		frame.BGCornerTopLeft.shown, frame.BGCornerTopRight.shown = true, true
	end
	if name then
		world.env[name] = frame
	end
	return frame
end

function Frame:SetScript(script, fn) self.scripts[script] = fn end
function Frame:GetScript(script) return self.scripts[script] end
function Frame:IsProtected() return self.protected or false, self.protected or false end

-- HookScript post-hooks: the hook runs after the frame's own script (warcraft.wiki.gg API
-- ScriptRegion:HookScript, "Securely post-hooks").
function Frame:HookScript(script, fn)
	self.hooks[script] = self.hooks[script] or {}
	table.insert(self.hooks[script], fn)
end

local function RunScripts(frame, script, ...)
	if frame.scripts[script] then frame.scripts[script](frame, ...) end
	for _, fn in ipairs(frame.hooks[script] or {}) do fn(frame, ...) end
end

-- A frame is visible when it and every parent are shown (warcraft.wiki.gg API
-- ScriptRegion:IsVisible).
local function Visible(frame)
	while frame do
		if not frame.shown then return false end
		frame = frame.parent
	end
	return true
end

function Frame:IsVisible() return Visible(self) end

-- In combat addon code can't set the attributes of a protected frame, or move, resize, re-parent,
-- show or hide it, and "control restrictions on protected frames are also applied to their parents
-- and any frames they are anchored to" (warcraft.wiki.gg Secure Execution and Tainting). A frame is
-- locked here if it is protected, the parent of a protected frame or something a protected frame is
-- anchored to. The page doesn't say whether this goes further up the chain.
local function Locked(frame)
	if frame.protected then return true end
	for _, other in ipairs(frame.world.frames) do
		if other.protected then
			if other.parent == frame then return true end
			for _, point in ipairs(other.points) do
				if point.relativeTo == frame then return true end
			end
		end
	end
	return false
end

local function CheckCombat(frame, what)
	if frame.world.combat and Locked(frame) then
		error(("ADDON_ACTION_BLOCKED: %s on %s, a protected frame or one tied to a protected frame, in combat")
			:format(what, tostring(frame.name or frame.template or "a frame")), 3)
	end
end

-- Cooldown frames (FrameAPICooldownDocumentation.lua): SetCooldown starts a swipe, Clear ends it.
-- Both carry IsProtectedFunction, the mark SetPoint carries
-- (SimpleScriptRegionResizingAPIDocumentation.lua), so they are blocked in combat on a locked frame
-- only. A cooldown isn't protected (CooldownFrameTemplate,
-- Blizzard_FrameXMLUtil/Mainline/Cooldown.xml:3).
Cooldown = {}
function Cooldown:SetCooldown(start, duration)
	CheckCombat(self, "SetCooldown")
	self.start, self.duration = start, duration
end
function Cooldown:Clear()
	CheckCombat(self, "Clear")
	self.start, self.duration = nil, nil
end

local RunSnippet

-- Showing or hiding: SecureHandlerShowHideTemplate's OnShow and OnHide run its _onshow and
-- _onhide snippets (SecureHandlerTemplates.xml, SecureHandler_OnSimpleEvent). A hidden frame
-- leaves auto-hide. A frame that becomes visible or invisible, itself or through a parent, runs its
-- OnShow or OnHide (warcraft.wiki.gg UIHANDLER OnShow: it runs when the frame is about to become
-- visible). Blizzard's code depends on the "through a parent" part: a Toy Box button registers for
-- TOYS_UPDATED in its OnShow and unregisters in its OnHide (Blizzard_ToyBox.lua:201-211), and stays
-- shown while the Toy Box page itself is closed and opened (it's hidden one by one only on a page
-- with fewer toys, Blizzard_ToyBox.lua:316-320).
local function SetShown(frame, shown)
	if frame.shown == shown then return end
	local before = {}
	for _, other in ipairs(frame.world.frames) do before[other] = Visible(other) end
	frame.shown = shown
	if not shown then frame.autoHide = nil end
	local snippet = frame.template == "SecureHandlerShowHideTemplate"
		and frame.attributes[shown and "_onshow" or "_onhide"]
	if snippet then RunSnippet(frame.world, frame, snippet) end
	local changed = {}
	for _, other in ipairs(frame.world.frames) do
		if Visible(other) ~= before[other] then changed[#changed + 1] = other end
	end
	for _, other in ipairs(changed) do RunScripts(other, Visible(other) and "OnShow" or "OnHide") end
end

-- Addon code can't show or hide a protected frame in combat; secure snippets can.
function Frame:Show()
	CheckCombat(self, "Show")
	SetShown(self, true)
end

function Frame:Hide()
	CheckCombat(self, "Hide")
	SetShown(self, false)
end

function Frame:IsShown() return self.shown end
function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end

function Frame:SetPoint(point, a, b, c, d)
	CheckCombat(self, "SetPoint")
	-- SetPoint(point [, relativeTo [, relativePoint]] [, x, y]): relativeTo defaults to the parent.
	local relativeTo, relativePoint, x, y
	if type(a) == "number" or a == nil then
		relativeTo, relativePoint, x, y = self.parent, point, a or 0, b or 0
	elseif type(b) == "number" then
		relativeTo, relativePoint, x, y = a, point, b, c or 0
	else
		relativeTo, relativePoint, x, y = a, b or point, c or 0, d or 0
	end
	table.insert(self.points, { point = point, relativeTo = relativeTo, relativePoint = relativePoint, x = x, y = y })
end

function Frame:SetAllPoints(relativeTo)
	CheckCombat(self, "SetAllPoints")
	relativeTo = relativeTo or self.parent
	self.points = {
		{ point = "TOPLEFT", relativeTo = relativeTo, relativePoint = "TOPLEFT", x = 0, y = 0 },
		{ point = "BOTTOMRIGHT", relativeTo = relativeTo, relativePoint = "BOTTOMRIGHT", x = 0, y = 0 },
	}
end

function Frame:ClearAllPoints()
	CheckCombat(self, "ClearAllPoints")
	self.points = {}
end

function Frame:GetPoint(i)
	local p = self.points[i or 1]
	if p then return p.point, p.relativeTo, p.relativePoint, p.x, p.y end
end

function Frame:SetSize(width, height)
	CheckCombat(self, "SetSize")
	self.width, self.height = width, height
end

function Frame:SetWidth(width)
	CheckCombat(self, "SetWidth")
	self.width = width
end

function Frame:GetWidth() return self.width end

function Frame:GetParent() return self.parent end
function Frame:SetFrameLevel(level) self.level = level end
function Frame:GetFrameLevel() return self.level end

-- Regions: textures and font strings are made by their frame, are never protected and have the
-- state Clicky sets on them.
local function NewRegion(frame, kind)
	local region = NewFrame(frame.world, nil, frame, nil, kind == "texture" and "Texture" or "FontString")
	region.region = kind
	return region
end

function Frame:CreateTexture() return NewRegion(self, "texture") end
function Frame:CreateFontString() return NewRegion(self, "fontstring") end
TYPED.SetTexture = { class = "Texture", fn = function(self, texture) self.texture = texture end }
TYPED.SetDesaturated = { class = "Texture", fn = function(self, desaturated) self.desaturated = desaturated end }
-- The texture SetHighlightTexture set, or one made for it (warcraft.wiki.gg API Button
-- GetHighlightTexture).
TYPED.GetHighlightTexture = { class = "Button", fn = function(self)
	self.highlight = self.highlight or NewRegion(self, "texture")
	return self.highlight
end }
function Frame:SetAlpha(alpha) self.alpha = alpha end

-- Text set by code runs OnTextChanged, with userInput false (warcraft.wiki.gg UIHANDLER OnTextChanged).
function Frame:SetText(text)
	local changed = self.text ~= text
	self.text = text
	if changed then RunScripts(self, "OnTextChanged", false) end
end

function Frame:GetText() return self.text or "" end

function Frame:RegisterEvent(event)
	self.world.eventFrames[self] = self.world.eventFrames[self] or {}
	self.world.eventFrames[self][event] = true
end

function Frame:UnregisterEvent(event)
	if self.world.eventFrames[self] then
		self.world.eventFrames[self][event] = nil
	end
end

-- Secure attributes are locked in combat for protected frames, for addon code.
function Frame:SetAttribute(key, value)
	if self.protected and self.world.combat then
		error("ADDON_ACTION_BLOCKED: SetAttribute on " .. tostring(self.name) .. " in combat", 2)
	end
	self.attributes[key] = value
end

function Frame:GetAttribute(key) return self.attributes[key] end

-- Which mouse clicks a button receives: "AnyUp", "AnyDown", or "LeftButtonUp", "RightButtonDown"...
-- A button that never registered gets a left button up click (warcraft.wiki.gg API Button
-- RegisterForClicks).
function Frame:RegisterForClicks(...) self.clicks = { ... } end

local function ReceivesClick(frame, button, down)
	local suffix = down and "Down" or "Up"
	for _, registered in ipairs(frame.clicks or { "LeftButtonUp" }) do
		if registered == "Any" .. suffix or registered == button .. suffix then return true end
	end
	return false
end

-- The mouse wheel reaches a frame only after EnableMouseWheel (enable defaults to false,
-- SimpleScriptRegionAPIDocumentation.lua:95-103), and a drag only after RegisterForDrag, which
-- "enables OnDragStart" (warcraft.wiki.gg API Frame RegisterForDrag).
function Frame:EnableMouseWheel(enable)
	CheckCombat(self, "EnableMouseWheel") -- IsProtectedFunction (SimpleScriptRegionAPIDocumentation.lua:94-96)
	self.mouseWheel = enable
end
function Frame:RegisterForDrag(...) self.drags = { ... } end

-- A modified attribute, as SecureButton_GetModifiedAttribute looks it up (SecureTemplates.lua):
-- modifier prefix ("alt-", "ctrl-", "shift-", from the keys held) and button suffix ("1" for
-- LeftButton, "2" for RightButton, "3" for MiddleButton), then GetAttribute(prefix, name,
-- suffix), which tries prefix..name..suffix, *name..suffix, prefix..name.."*", *name*, then name
-- (warcraft.wiki.gg SecureActionButtonTemplate, "Modified attributes").
local SUFFIX = { LeftButton = "1", RightButton = "2", MiddleButton = "3" }

local function ModifiedAttribute(frame, name, button)
	local keys, prefix = frame.world.keys, ""
	if keys.shift then prefix = "shift-" .. prefix end
	if keys.ctrl then prefix = "ctrl-" .. prefix end
	if keys.alt then prefix = "alt-" .. prefix end
	local suffix = SUFFIX[button] or ""
	local a = frame.attributes
	local value = a[prefix .. name .. suffix]
	if value == nil then value = a["*" .. name .. suffix] end
	if value == nil then value = a[prefix .. name .. "*"] end
	if value == nil then value = a["*" .. name .. "*"] end
	if value == nil then value = a[name] end
	return value
end

------------------------------------------------------------------------------------------
-- Secure snippets: run like WoW's restricted environment (RestrictedEnvironment.lua,
-- RestrictedFrames.lua), with only these functions, and frames reached through handles.

local Handle = {}
Handle.__index = Handle

local function HandleOf(frame)
	frame.handle = frame.handle or setmetatable({ frame = frame }, Handle)
	return frame.handle
end

-- HANDLE:GetAttribute and SetAttribute refuse names starting with "_"; SetAttribute takes
-- strings, numbers, booleans, nil and handles, and works in combat.
function Handle:GetAttribute(name)
	if type(name) ~= "string" or name:match("^_") then return nil end
	return self.frame.attributes[name]
end

function Handle:SetAttribute(name, value)
	assert(type(name) == "string" and not name:match("^_"), "Invalid attribute name")
	local tv = type(value)
	assert(tv == "string" or tv == "number" or tv == "boolean" or tv == "nil"
		or getmetatable(value) == Handle, "Invalid attribute value")
	self.frame.attributes[name] = value
end

function Handle:GetFrameRef(label)
	local value = self.frame.attributes["frameref-" .. label]
	if getmetatable(value) == Handle then return value end
end

function Handle:IsShown() return self.frame.shown end
function Handle:Show() SetShown(self.frame, true) end
function Handle:Hide() SetShown(self.frame, false) end

-- Override bindings (SetOverrideBindingClick, through HANDLE:SetBindingClick and ClearBindings):
-- owned by the frame, gone when it clears them, and never saved, unlike the player's own bindings.
-- The target is a frame handle or a name.
function Handle:SetBindingClick(priority, key, target, button)
	local name = getmetatable(target) == Handle and target.frame.name or target
	assert(type(name) == "string", "Invalid click target name")
	local world = self.frame.world
	world.overrides[self.frame] = world.overrides[self.frame] or {}
	world.overrides[self.frame][key] = { name = name, button = button, priority = priority }
end

function Handle:ClearBindings() self.frame.world.overrides[self.frame] = nil end
function Handle:ClearAllPoints() self.frame.point = nil end

-- relframe can be a handle, "$screen", "$cursor" or "$parent", nothing else.
function Handle:SetPoint(point, relframe, relpoint, x, y)
	assert(relframe == nil or relframe == "$screen" or relframe == "$cursor" or relframe == "$parent"
		or getmetatable(relframe) == Handle, "Invalid relative frame id")
	self.frame.point = { point, relframe, relpoint, x, y }
end

-- RegisterAutoHide hides the frame once the mouse has been off it for duration seconds.
function Handle:RegisterAutoHide(duration) self.frame.autoHide = tonumber(duration) end

function RunSnippet(world, frame, body, ...)
	local env = world.restricted
	local chunk = assert(loadstring("local self, button, down = ...\n" .. body))
	setfenv(chunk, env)
	return chunk(HandleOf(frame), ...)
end

-- A click: PreClick, the wrapped OnClick (each wrap's snippet first, Wrapped_Click in
-- SecureHandlers.lua; a snippet returning false stops the click), the template's OnClick (or a
-- plain button's own), PostClick. SecureActionButton_OnClick acts on the down click when
-- useOnKeyDown is on and the up click otherwise; with the attribute unset it follows the
-- ActionButtonUseKeyDown setting (SecureTemplates.lua, SecureActionButton_ShouldUseOnKeyDown), and
-- SECURE_ACTIONS.toy uses the modified "toy" attribute. SecureHandlerClickTemplate's OnClick runs
-- its _onclick snippet (SecureHandler_OnClick).
function Frame:Click(button, down)
	local world = self.world
	if self.scripts.PreClick then self.scripts.PreClick(self, button, down) end
	local wrap = self.wraps.OnClick
	if not wrap or RunSnippet(world, self, wrap, button, down) ~= false then
		if self.template == "SecureActionButtonTemplate" then
			local useOnKeyDown = self.attributes.useOnKeyDown
			if useOnKeyDown == nil then
				useOnKeyDown = world.cvars.ActionButtonUseKeyDown
			end
			if (down and useOnKeyDown) or (not down and not useOnKeyDown) then
				world:SecureAction(self, button)
			end
		elseif self.template == "SecureHandlerClickTemplate" and self.attributes._onclick then
			RunSnippet(world, self, self.attributes._onclick, button, down)
		else
			-- Any other button runs its own OnClick (warcraft.wiki.gg UIHANDLER OnClick).
			RunScripts(self, "OnClick", button, down)
		end
	end
	if self.scripts.PostClick then self.scripts.PostClick(self, button, down) end
end

------------------------------------------------------------------------------------------
-- Blizzard templates that Clicky's toy grid and panel are made of, as far as Clicky uses them.

local function Saturate(x) return math.max(0, math.min(1, x)) end

local function Trigger(frame, event, ...)
	for _, callback in ipairs(frame.callbacks[event] or {}) do
		callback.fn(callback.owner, ...)
	end
end

-- MinimalScrollBar (ScrollBar.lua, ScrollController.lua), driven by Clicky as Blizzard drives one
-- for a scroll frame (ScrollUtil.lua, InitScrollFrameWithScrollBar): it reports its position with
-- the OnScroll callback. The thumb and track are not here: a drag is the bar's SetScrollPercentage.
ScrollBar = {}

-- WowScrollBoxList (ScrollBox.lua) with a ScrollBoxListLinearView. SetDataProvider (ScrollBox.lua:703)
-- shows each element on a row, a frame of the view's type that is reused, and calls the view's
-- initializer(row, element) (ScrollBoxListView.lua:397-401, 487-). The real list makes rows only for
-- the elements in view; here every element has one, and the rows after the last are hidden.
ScrollList = {}

function ScrollList:SetDataProvider(elements)
	self.elements = elements
	for i, element in ipairs(elements) do
		local row = self.rows[i]
		if not row then
			row = self.world.env.CreateFrame(self.view.frameType, nil, self)
			self.rows[i] = row
		end
		row:Show()
		self.view.initializer(row, element)
	end
	for i = #elements + 1, #self.rows do self.rows[i]:Hide() end
end

-- ScrollBox.lua:638-650.
function ScrollList:FindElementData(index) return self.elements[index] end
function ScrollList:FindElementDataIndexByPredicate(predicate)
	for i, element in ipairs(self.elements) do
		if predicate(element) then return i end
	end
end

-- ScrollBox.lua:813.
function ScrollList:ScrollToNearest(index) self.scrolledTo = index end

-- ScrollBar.lua:67-71 (sets no OnScroll).
function ScrollBar:Init(visibleExtentPercentage, panExtentPercentage)
	self.scrollPercentage = 0
	self.panExtentPercentage = Saturate(panExtentPercentage)
	self.visibleExtentPercentage = Saturate(visibleExtentPercentage)
end

-- CallbackRegistryMixin: the function gets the owner, then the event's arguments.
function ScrollBar:RegisterCallback(event, fn, owner)
	self.callbacks[event] = self.callbacks[event] or {}
	table.insert(self.callbacks[event], { fn = fn, owner = owner })
end

function ScrollBar:GetScrollPercentage() return self.scrollPercentage end
function ScrollBar:GetVisibleExtentPercentage() return self.visibleExtentPercentage end
function ScrollBar:GetPanExtentPercentage() return self.panExtentPercentage end -- ScrollController.lua:144
function ScrollBar:SetVisibleExtentPercentage(p) self.visibleExtentPercentage = Saturate(p) end -- ScrollBar.lua:133
function ScrollBar:SetPanExtentPercentage(p) self.panExtentPercentage = Saturate(p) end -- ScrollController.lua:148
function ScrollBar:IsScrollAllowed() return self.allowScroll end

-- Snap to interval (ScrollController.lua:105-116): the bar has one position per 1 / visible
-- extent, less 1 for the range, and its position goes to the nearest.
function ScrollBar:EnableSnapToInterval() self.snapToInterval = true end

function ScrollBar:GetIntervalRange()
	if self.visibleExtentPercentage > 0 then
		return math.floor(1 / self.visibleExtentPercentage + 0.000001) - 1 -- MathUtil.lua:4
	end
	return 0
end

-- ScrollBar.lua:155-179 and ScrollController.lua:168-178: the position is set, snapped to the
-- nearest of the range's positions (Round is the game's, half up), and OnScroll is triggered
-- (SetScrollPercentage takes no check of IsScrollAllowed); there's no interpolation unless the bar
-- is set to (not by Clicky).
function ScrollBar:SetScrollPercentage(p)
	if self.snapToInterval then
		local range = self:GetIntervalRange()
		if range > 0 then p = math.floor(p * range + 0.5) / range end
	end
	self.scrollPercentage = Saturate(p)
	Trigger(self, "OnScroll", self.scrollPercentage)
end

-- ScrollBar.lua:185-193.
function ScrollBar:SetScrollAllowed(allow)
	if self.allowScroll ~= allow then
		self.allowScroll = allow
		Trigger(self, "OnAllowScrollChanged", allow)
	end
end

-- ScrollController.lua:128-142 moves the position unless scrolling is off (by at least one
-- position when snapping), then ScrollBar.lua:105-111 triggers OnScroll whether it moved or not, so
-- a wheel step reports twice.
function ScrollBar:ScrollInDirection(percentage, direction)
	if self.allowScroll then
		local range = self.snapToInterval and self:GetIntervalRange() or 0
		if range > 0 then percentage = math.max(1 / range, percentage) end
		self:SetScrollPercentage(self.scrollPercentage + percentage * direction)
	end
	Trigger(self, "OnScroll", self.scrollPercentage)
end

-- ScrollBar.lua:117-119: direction is 1 to scroll down, -1 up (ScrollController.lua:71-74).
function ScrollBar:ScrollStepInDirection(direction)
	self:ScrollInDirection(self.panExtentPercentage, direction)
end

-- ScrollBar.lua:296-299: a drag or a held track is an OnUpdate script.
function ScrollBar:UnregisterUpdate() self.scripts.OnUpdate = nil end

-- A dropdown button (Blizzard_Menu/MenuTemplates.lua). Its menu is built when it opens, and when set up
-- while shown (SetupMenu below); the world
-- opens it for a test (World:GridFilterMenu).
local MenuDescription -- a menu as its generator builds it, below World:GridFilterMenu
FilterDropdown = {}
-- A shown button builds its menu at once, asking each checkbox whether it's ticked, then checks its
-- reset state (DropdownButton.lua:240-247, 284-307; MenuTemplates.lua:924-927).
function FilterDropdown:SetupMenu(generator)
	self.menuGenerator = generator
	if self:IsShown() then
		local all = {}
		generator(self, MenuDescription(self, all))
		for _, entry in ipairs(all) do
			if entry.isSelected then entry.isSelected() end
		end
		self:ValidateResetState()
	end
end
function FilterDropdown:SetDefaultCallback(callback) self.defaultCallback = callback end -- MenuTemplates.lua:876
function FilterDropdown:SetIsDefaultCallback(callback) self.isDefaultCallback = callback end -- MenuTemplates.lua:881
-- The reset button shows when the filters aren't the defaults (MenuTemplates.lua:900-904).
function FilterDropdown:ValidateResetState() self.resetShown = not self.isDefaultCallback() end

-- ButtonFrameTemplate's children that the panel uses: parentKeys CloseButton and Inset
-- (Blizzard_SharedXML/SharedUIPanelTemplates.xml); and its title, which SetTitle puts in its top
-- bar's TitleText (TitledPanelMixin, PortraitFrame.lua:4-14).
ButtonFrame = function(world, frame)
	frame.CloseButton = NewFrame(world, nil, frame, nil, "Button")
	frame.Inset = NewFrame(world, nil, frame)
	frame.TitleContainer = { TitleText = NewFrame(world, nil, frame, nil, "FontString") }
	function frame:SetTitle(title) self.TitleContainer.TitleText:SetText(title) end
end

------------------------------------------------------------------------------------------
-- The world.

local World = {}
World.__index = World

-- options.toys: list of { id, name, icon, owned = true, usable = true, favorite, cooldown, loading,
--   expansion }
-- options.spells: list of { id, name, icon, known = true, usable = true, cooldown, loading, line = 1,
--   flyout, passive, offSpec, base }: line is its spellbook skill line; flyout (a flyout ID) puts it
--   in that flyout instead of on the line's own page; offSpec puts the line in a specialization the
--   player isn't in; base is the spell it overrides, which is then the spellbook item's actionID
--   (SpellBookItemInfo: spellID is the overriding spell). A spell that isn't known is a FutureSpell
--   on the line (SpellBookItemType). profession (1 to 5, its place in GetProfessions' returns: two
--   primary professions, archaeology, fishing, cooking) puts it in that profession's spells, after
--   every skill line's, instead of on a line.
-- options.items: list of { id, name, icon, count = 1, usable = true, cooldown, equippable, equipped,
--   loading, bag = 0, worn }: count in the bag bag (0 is the backpack), or worn in inventory slot worn
-- options.mounts: list of { id, name, spell = id * 100, icon, collected = true, usable = true,
--   favorite, hidden, shown = true, fanfare }: hidden is shouldHideOnChar (the game hides it on this
--   character); shown is whether the Mount Journal's filters list it; fanfare: it is still in its
--   gift wrap
-- options.pets: list of { guid, species, display = species * 10, name, icon, favorite,
--   summonable = true, fanfare }: one owned pet each; name and icon are its species'; fanfare: it is
--   still in its gift wrap
-- options.petSpecies: species ID -> { name, icon }, a species the game has that the player may own
--   none of (AddPet adds its pet's)
-- options.petLooks: species ID -> the display IDs the game lists for it (GetDisplayIDByIndex), owned
--   or not; a species with a pet and none given lists its pets' looks
-- options.macros: list of { name, icon, body }
-- options.account: another world's account, instead of toys and macros
-- options.toyList: entries, Clicky's toy list on this computer (see the top of this file)
-- options.toyHidden: item ID -> true, the toys its grid lists only when owned (ToyList.lua's TOY_HIDDEN)
-- options.toySource, options.petSource: item or species ID -> Enum.BattlePetSources, and
--   options.mountType: mountTypeID -> Enum.MountTypeFlag, ToyList.lua's TOY_SOURCE, PET_SOURCE and
--   MOUNT_TYPE
-- options.mountHidden, options.petHidden: mount ID or species ID -> true, ToyList.lua's MOUNT_HIDDEN
--   and PET_HIDDEN; options.petRandomLook: species ID -> true, its PET_RANDOM_LOOK
-- options.toysLoading: the player's toys haven't arrived yet (see World:LoadToys)
-- options.combat: logging in (or reloading) in combat
function wow.New(options)
	options = options or {}
	local world = setmetatable({
		combat = options.combat or false,
		toysLoaded = not options.toysLoading,
		macrosLoaded = false,
		-- Off would hide a missing useOnKeyDown attribute: on is the case that breaks.
		cvars = { ActionButtonUseKeyDown = true },
		time = 1000,
		eventFrames = {},
		errors = {},
		prints = {},
		used = {},
		equipped = {}, -- items the game wore because a click on them wasn't a use
		keys = {}, -- modifier keys held: alt, ctrl, shift
		mouse = {}, -- mouse buttons held
		-- The key that makes a click link instead of act: the CHATLINK modified click is the
		-- player's setting; the tests use shift.
		chatLinkKey = "shift",
		chat = {}, -- links put in the chat box (ChatFrameUtil.InsertLink)
		timers = {}, -- C_Timer.After callbacks waiting
		overrides = {}, -- frame -> key -> override binding, for this session only
	}, World)
	local account = options.account
	if not account then
		account = { toys = {}, toyOrder = {}, spells = {}, items = {}, mounts = {}, mountOrder = {}, pets = {},
			species = {}, macros = {}, characterMacros = {}, bars = {} }
		world.account = account
		for _, toy in ipairs(options.toys or {}) do
			world:AddToy(toy)
		end
		for _, spell in ipairs(options.spells or {}) do
			world:AddSpell(spell)
		end
		for _, item in ipairs(options.items or {}) do
			world:AddItem(item)
		end
		for _, mount in ipairs(options.mounts or {}) do
			world:AddMount(mount)
		end
		for _, pet in ipairs(options.pets or {}) do
			world:AddPet(pet)
		end
		account.petLooks = options.petLooks or {}
		for id, species in pairs(options.petSpecies or {}) do
			account.species[id] = species
		end
		for _, macro in ipairs(options.macros or {}) do
			table.insert(account.macros, { name = macro.name, icon = macro.icon, body = macro.body })
		end
	end
	world.account = account
	world.toys, world.toyOrder, world.macros, world.bars = account.toys, account.toyOrder, account.macros, account.bars
	world.spells, world.items = account.spells, account.items
	world.mounts, world.pets = account.mounts, account.pets
	world.characterMacros = account.characterMacros
	world.toyList = options.toyList or { unpack(account.toyOrder) }
	world.toyHidden = options.toyHidden or {}
	world.mountHidden = options.mountHidden or {}
	world.petHidden = options.petHidden or {}
	world.petRandomLook = options.petRandomLook or {}
	world.toySource, world.petSource = options.toySource or {}, options.petSource or {}
	world.mountType = options.mountType or {}
	-- The Toy Box's and the Pet Journal's filters as the player left them, and what they list (the
	-- Mount Journal's list is its mounts that are shown); set by a test. A window's sourcesOff and
	-- the like hold the filter indexes unticked.
	world.blizzard = {
		toys = { collected = true, uncollected = true, unusable = true, sourcesOff = {}, expansionsOff = {}, list = {},
			default = true },
		mounts = { collected = true, uncollected = true, unusable = true, typesOff = {}, sourcesOff = {}, default = true },
		pets = { collected = true, uncollected = true, battlePets = true, nonCombatPets = true, familiesOff = {},
			sourcesOff = {}, sortBy = 1, list = {}, default = true },
	}
	world:BuildEnv()
	world:LoadAddon()
	world:Fire("ADDON_LOADED", ADDON)
	-- Clicky can't count on macros being readable at ADDON_LOADED, so they arrive afterwards,
	-- announced by UPDATE_MACROS, before PLAYER_ENTERING_WORLD.
	world.macrosLoaded = true
	world:Fire("UPDATE_MACROS")
	world:Fire("PLAYER_ENTERING_WORLD", true, false)
	return world
end

-- The player's toys arriving after login, with a TOYS_UPDATED.
function World:LoadToys()
	self.toysLoaded = true
	self:Fire("TOYS_UPDATED")
end

-- Learning a toy: NEW_TOY_ADDED, then TOYS_UPDATED with itemID, isNew and hasFanfare
-- (ToyBoxInfoDocumentation.lua). toy.fanfare: it arrives gift-wrapped.
function World:LearnToy(toy)
	if not self.toys[toy.id] then
		self:AddToy(toy)
	end
	self.toys[toy.id].owned = true
	self.toys[toy.id].fanfare = toy.fanfare or false
	self:Fire("NEW_TOY_ADDED", toy.id)
	self:Fire("TOYS_UPDATED", toy.id, true, self.toys[toy.id].fanfare)
end

function World:AddToy(toy)
	local t = {
		id = toy.id,
		name = toy.name or ("Toy " .. toy.id),
		icon = toy.icon or (toy.id * 10),
		owned = toy.owned ~= false,
		usable = toy.usable ~= false,
		favorite = toy.favorite or false,
		cooldown = toy.cooldown or 0,
		loading = toy.loading or false,
		fanfare = toy.fanfare or false,
		expansion = toy.expansion,
	}
	self.account.toys[t.id] = t
	table.insert(self.account.toyOrder, t.id)
end

function World:AddSpell(spell)
	self.account.spells[spell.id] = {
		id = spell.id,
		name = spell.name or ("Spell " .. spell.id),
		icon = spell.icon or (spell.id * 10 + 1),
		known = spell.known ~= false,
		usable = spell.usable ~= false,
		cooldown = spell.cooldown or 0,
		loading = spell.loading or false,
		line = spell.line or 1,
		flyout = spell.flyout,
		passive = spell.passive or false,
		offSpec = spell.offSpec or false,
		base = spell.base,
		profession = spell.profession,
	}
end

function World:AddItem(item)
	self.account.items[item.id] = {
		id = item.id,
		name = item.name or ("Item " .. item.id),
		icon = item.icon or (item.id * 10 + 2),
		count = item.count or 1,
		usable = item.usable ~= false,
		cooldown = item.cooldown or 0,
		equippable = item.equippable or false,
		equipped = item.equipped or item.worn ~= nil,
		loading = item.loading or false,
		bag = item.bag or 0,
		worn = item.worn,
	}
end

function World:AddMount(mount)
	self.account.mounts[mount.id] = {
		id = mount.id,
		name = mount.name or ("Mount " .. mount.id),
		spell = mount.spell or mount.id * 100,
		icon = mount.icon or (mount.id * 10 + 3),
		collected = mount.collected ~= false,
		usable = mount.usable ~= false,
		favorite = mount.favorite or false,
		hidden = mount.hidden or false,
		shown = mount.shown ~= false,
		fanfare = mount.fanfare or false,
	}
	table.insert(self.account.mountOrder, mount.id)
end

-- A pet the player owns. Its species' name and icon are the species', kept once per species.
function World:AddPet(pet)
	self.account.species[pet.species] = self.account.species[pet.species]
		or { name = pet.name or ("Pet " .. pet.species), icon = pet.icon or (pet.species * 10 + 4) }
	table.insert(self.account.pets, {
		guid = pet.guid,
		species = pet.species,
		display = pet.display or pet.species * 10,
		favorite = pet.favorite or false,
		summonable = pet.summonable ~= false,
		fanfare = pet.fanfare or false,
	})
end

-- The looks the game lists for a species: options.petLooks', else its pets' looks.
function World:SpeciesLooks(id)
	if self.account.petLooks and self.account.petLooks[id] then return self.account.petLooks[id] end
	local looks, seen = {}, {}
	for _, pet in ipairs(self.pets) do
		if pet.species == id and not seen[pet.display] then
			seen[pet.display] = true
			looks[#looks + 1] = pet.display
		end
	end
	return looks
end

function World:Pet(guid)
	for _, pet in ipairs(self.pets) do
		if pet.guid == guid then return pet end
	end
end

-- Learning a pet, or caging one: the Pet Journal's list changes, PET_JOURNAL_LIST_UPDATE
-- (PetJournalInfoDocumentation.lua; Blizzard_PetCollection.lua redraws its list on it).
function World:LearnPet(pet)
	self:AddPet(pet)
	self:Fire("PET_JOURNAL_LIST_UPDATE")
end

function World:CagePet(guid)
	for i, pet in ipairs(self.pets) do
		if pet.guid == guid then table.remove(self.pets, i) break end
	end
	if self.summonedPet == guid then self.summonedPet = nil end
	self:Fire("PET_JOURNAL_LIST_UPDATE")
end

-- A spell's or item's data arriving after Clicky asked for it: SPELL_DATA_LOAD_RESULT
-- (SpellDocumentation.lua) and GET_ITEM_INFO_RECEIVED (ItemDocumentation.lua), each with the ID
-- and success.
function World:LoadSpell(id)
	self.spells[id].loading = false
	self:Fire("SPELL_DATA_LOAD_RESULT", id, true)
end

function World:LoadItem(id)
	self.items[id].loading = false
	self:Fire("GET_ITEM_INFO_RECEIVED", id, true)
end

-- A patch taking a toy out of the game's data.
function World:RemoveToyFromGame(id)
	self.account.toys[id] = nil
	for i, other in ipairs(self.account.toyOrder) do
		if other == id then
			table.remove(self.account.toyOrder, i)
			break
		end
	end
end

-- The Collections window loading (Blizzard_Collections is load-on-demand): its frames, hidden as
-- Blizzard_Collections.xml and Blizzard_ToyBox.xml make them, with the Toy Box's children that
-- Clicky hides and anchors to (parentKeys in Blizzard_ToyBox.xml), then ADDON_LOADED. `without`
-- names a parentKey a patch took away.
function World:LoadCollections(without)
	local env = self.env
	env.CollectionsJournal = env.CreateFrame("Frame", "CollectionsJournal", env.UIParent, "PortraitFrameTemplate")
	env.CollectionsJournal.shown = false
	env.CollectionsJournal.width, env.CollectionsJournal.height = 703, 606 -- Blizzard_Collections.xml:15
	env.ToyBox = env.CreateFrame("Frame", "ToyBox", env.CollectionsJournal)
	env.ToyBox.shown = false
	env.ToyBox:SetAllPoints()
	-- Its OnMouseWheel turns the pages of its PagingFrame (Blizzard_ToyBox.xml:154).
	env.ToyBox.mouseWheel = true
	for _, key in ipairs({ "progressBar", "searchBox", "FilterDropdown", "iconsFrame", "PagingFrame" }) do
		if key ~= without then
			env.ToyBox[key] = env.CreateFrame("Frame", nil, env.ToyBox)
		end
	end
	-- The icons frame holds 18 Toy Box buttons (Blizzard_ToyBox.xml:50-135), protected as
	-- CollectionsSpellButtonTemplate inherits SecureFrameTemplate (Blizzard_CollectionTemplates.xml:39).
	-- The game makes them whatever its combat state is, as it makes the Toy Box.
	local combat = self.combat
	self.combat = false
	for _ = 1, 18 do env.CreateFrame("CheckButton", nil, env.ToyBox.iconsFrame, "SecureFrameTemplate") end
	self.combat = combat
	self.collectionsLoaded = true
	self:Fire("ADDON_LOADED", "Blizzard_Collections")
end

-- The player opening the Toy Box tab, or closing the window. The game shows and hides these
-- windows itself, so the combat lock on protected frames doesn't stop it (the frames in them that
-- Clicky made still run their OnShow and OnHide in combat).
function World:OpenToyBox()
	SetShown(self.env.CollectionsJournal, true)
	SetShown(self.env.ToyBox, true)
end

function World:CloseToyBox()
	SetShown(self.env.CollectionsJournal, false)
end

-- The player choosing an entry of the menu that opened last (a button's callback, or a
-- checkbox's setter).
function World:ChooseMenuEntry(text)
	for _, entry in ipairs(self.menu.entries) do
		if entry.text == text then
			return (entry.kind == "CreateCheckbox" and entry.args[2] or entry.args[1])()
		end
	end
	error("no menu entry " .. text)
end

-- The player typing in the dialog's edit box (its whole text), pressing Enter in it, or clicking its
-- first button, which does nothing while it's disabled (see StaticPopup_Show above).
function World:TypeInDialog(text)
	assert(self.dialog and self.dialog:GetEditBox(), "no dialog with an edit box is shown")
	self.dialog:GetEditBox():SetText(text)
end

function World:PressEnterInDialog()
	local dialog = assert(self.dialog, "no dialog is shown")
	local info = self.env.StaticPopupDialogs[dialog.which]
	if info.EditBoxOnEnterPressed then info.EditBoxOnEnterPressed(dialog:GetEditBox(), dialog.data) end
end

function World:ClickDialogButton(index)
	assert(index == 1, "the stubs click only a dialog's first button")
	local dialog = assert(self.dialog, "no dialog is shown")
	if not dialog:GetButton1():IsEnabled() then return end
	local info = self.env.StaticPopupDialogs[dialog.which]
	if not (info.OnAccept and info.OnAccept(dialog, dialog.data, dialog.data2)) then dialog:Hide() end
end

-- The grid's filter menu as it opens: { text, isSelected(), toggle() } per checkbox.
-- A menu description as the generator builds it (Blizzard_Menu/MenuUtil.lua, MenuTemplates.lua):
-- checkboxes, radios, buttons (each one a submenu its entries are added to), titles, spacers and
-- dividers. Every entry goes in all, with its path ("Sources > Source 1"); a choice checks the
-- reset button again (WowDropdownFilterBehaviorMixin:OnMenuResponse, MenuTemplates.lua:906-909).
function MenuDescription(dropdown, all, path)
	local description = {}
	local function Add(entry)
		entry.path = path and (path .. " > " .. tostring(entry.text)) or tostring(entry.text)
		all[#all + 1] = entry
		return entry
	end
	function description.CreateCheckbox(_, text, isSelected, setSelected, data)
		Add({ kind = "checkbox", text = text, isSelected = function() return isSelected(data) end,
			toggle = function() setSelected(data) dropdown:ValidateResetState() end })
	end
	function description.CreateRadio(_, text, isSelected, setSelected, data)
		Add({ kind = "radio", text = text, isSelected = function() return isSelected(data) end,
			toggle = function() setSelected(data) dropdown:ValidateResetState() end })
	end
	function description.CreateButton(_, text, callback, data)
		local entry = Add({ kind = "button", text = text,
			toggle = function() if callback then callback(data) end dropdown:ValidateResetState() end })
		return MenuDescription(dropdown, all, entry.path)
	end
	function description.CreateTitle(_, text) Add({ kind = "title", text = text }) end
	function description.CreateSpacer() end
	function description.CreateDivider() end
	return description
end

-- The grid's filter menu as it opens: its top-level checkboxes in order, { text, isSelected(),
-- toggle() } each; all its entries in .all, and .find(path) for one by its path.
function World:GridFilterMenu()
	local dropdown = self.env.ClickyGridFilter
	local all = {}
	dropdown.menuGenerator(dropdown, MenuDescription(dropdown, all))
	local entries = { all = all }
	for _, entry in ipairs(all) do
		if entry.kind == "checkbox" and not entry.path:find(" > ", 1, true) then entries[#entries + 1] = entry end
	end
	function entries.find(path)
		for _, entry in ipairs(all) do
			if entry.path == path then return entry end
		end
		error("no filter menu entry " .. path, 2)
	end
	return entries
end

-- The player editing macros in /macro, which saves through EditMacro and CreateMacro; bodies are
-- cut to 255 characters, which can be more than 255 bytes (MacroFrameText letters="255").
function World:EditMacroInUI(index, name, body)
	assert(not self.combat, "/macro can't save in combat: EditMacro is nocombat (warcraft.wiki.gg API EditMacro)")
	local m = assert(self.macros[index], "no macro " .. tostring(index))
	m.name, m.body = name or m.name, FirstLetters(body or m.body, 255)
	SortMacros(self.macros, m)
	self:Fire("UPDATE_MACROS")
end

-- The player typing in the /macro window's text box, which marks the text changed
-- (Blizzard_MacroUI.xml, MacroFrameText OnTextChanged).
function World:TypeInMacroWindow(text)
	self.env.MacroFrameText:SetText(text)
end

function World:CreateMacroInUI(name, body, perCharacter)
	assert(not self.combat, "/macro can't save in combat: CreateMacro is nocombat (warcraft.wiki.gg API CreateMacro)")
	local macros = perCharacter and self.characterMacros or self.macros
	local m = { name = name, body = body }
	m.body = FirstLetters(body, 255) -- MacroFrameText letters="255" (Blizzard_MacroUI.xml)
	table.insert(macros, m)
	SortMacros(macros, m)
	self:Fire("UPDATE_MACROS")
	return m
end

function World:FindMacroByName(name)
	for _, macro in ipairs(self.macros) do
		if macro.name == name then
			return macro
		end
	end
end

function World:Fire(event, ...)
	for frame, events in pairs(self.eventFrames) do
		if events[event] and frame.scripts.OnEvent then
			frame.scripts.OnEvent(frame, event, ...)
		end
	end
	if self.luaErrors[1] then
		error(table.remove(self.luaErrors, 1), 0)
	end
end

-- PLAYER_REGEN_DISABLED is synchronous (UnitDocumentation.lua): its handlers run before the
-- lockdown starts, the last moment addon code can set secure attributes (SecureStateDriver.lua
-- refreshes its states on it).
function World:EnterCombat()
	self:Fire("PLAYER_REGEN_DISABLED")
	self.combat = true
end

function World:LeaveCombat()
	self.combat = false
	self:Fire("PLAYER_REGEN_ENABLED")
end

-- Time passing, running C_Timer callbacks as they fall due.
function World:Advance(seconds)
	local stop = self.time + seconds
	while true do
		table.sort(self.timers, function(a, b) return a.at < b.at end)
		local timer = self.timers[1]
		if not timer or timer.at > stop then break end
		table.remove(self.timers, 1)
		self.time = math.max(self.time, timer.at)
		timer.fn()
	end
	self.time = stop
end

-- The game using a toy: world.used lists what was used, a toy as its item ID, a spell as "s" and
-- its ID, an item as "i" and its ID, which are the entries' keys (Entries.lua).
function World:UseToy(itemID)
	table.insert(self.used, itemID)
end

-- A secure button's action (SECURE_ACTIONS in SecureTemplates.lua), as far as Clicky sets them:
-- toy uses the toy in its "toy" attribute (a number: UseToy); spell casts the spell ID in "spell"
-- (a number: CastSpellByID); item reads "item" and, for an item that can be worn and isn't,
-- wears it instead of using it (C_Item.IsEquippableItem, IsEquippedItem, EquipItemByName), else
-- uses it (UseItemByName). A bare number in "item" is a slot, not an item ID (SecureCmdItemParse,
-- ChatFrameUtil.lua), which Clicky must not pass.
function World:SecureAction(frame, button)
	local action = ModifiedAttribute(frame, "type", button)
	if action == "toy" then
		local toy = ModifiedAttribute(frame, "toy", button)
		if toy then self:UseToy(tonumber(toy) or toy) end
	elseif action == "spell" then
		local spell = ModifiedAttribute(frame, "spell", button)
		-- A mount's spell cast by its ID doesn't summon it (seen in play); by its name, as /cast
		-- does, CastSpellByName finds it.
		local id = tonumber(spell)
		if not id and spell then
			for _, t in pairs(self.spells) do
				if t.name == spell then id = t.id end
			end
			local mounted
			for _, m in pairs(self.mounts) do
				if m.name == spell then id, mounted = m.spell, m end
			end
			-- The player is on it: GetMountInfoByID's isActive (MountJournalDocumentation.lua). The
			-- Mount Journal redraws its list on COMPANION_UPDATE without reading its argument
			-- (Blizzard_MountCollection.lua:140, 414).
			if mounted then
				for _, m in pairs(self.mounts) do m.active = false end
				mounted.active = true
				self:Fire("COMPANION_UPDATE")
			end
		elseif id then
			for _, m in pairs(self.mounts) do
				if m.spell == id then id = nil break end
			end
		end
		if id then table.insert(self.used, "s" .. id) end
	elseif action == "macro" then
		-- Only /summonpet: it calls SummonPetByGUID with the GUID (SlashCommands.lua:1620-1634), which
		-- puts away the pet that's out when given it (/dismisspet, SlashCommands.lua:1659-1669). A pet
		-- that can't be summoned isn't (the Pet Journal's Summon button is off for it,
		-- Blizzard_PetCollection.lua:320). The pet that's out changing fires COMPANION_UPDATE with
		-- "CRITTER", on which the Pet Journal redraws its list and Summon button
		-- (Blizzard_PetCollection.lua:98, 271-275).
		local text = ModifiedAttribute(frame, "macrotext", button)
		if text then
			local guid = assert(text:match("^/summonpet (%S+)$"), "macro text the stubs don't run: " .. text)
			if self.summonedPet == guid then
				self.summonedPet = nil
				self:Fire("COMPANION_UPDATE", "CRITTER")
			elseif self:Pet(guid) and self:Pet(guid).summonable then
				self.summonedPet = guid
				table.insert(self.used, guid)
				self:Fire("COMPANION_UPDATE", "CRITTER")
			end
		end
	elseif action == "item" then
		local item = ModifiedAttribute(frame, "item", button)
		if item then
			assert(not tostring(item):match("^%d+$"), "a bare number in the item attribute is an inventory slot")
			local id = tonumber(tostring(item):match("^item:(%d+)$"))
			local t = id and self.items[id]
			if t and t.equippable and not t.equipped then
				t.equipped = true
				table.insert(self.equipped, id)
			elseif t then
				table.insert(self.used, "i" .. id)
			end
		end
	end
end

-- The player pressing a mouse button on a button, and releasing it: the mouse only reaches a
-- visible frame (a /click line or a key binding can click a hidden one), and sends each click the
-- button is registered for (RegisterForClicks). The button is held in between (IsMouseButtonDown).
function World:HoldMouse(frame, button)
	assert(Visible(frame), "the mouse can't click a frame that isn't visible")
	button = button or "LeftButton"
	self.mouse[button] = true
	if ReceivesClick(frame, button, true) then frame:Click(button, true) end
end

function World:ReleaseMouse(frame, button)
	button = button or "LeftButton"
	self.mouse[button] = nil
	if ReceivesClick(frame, button, false) then frame:Click(button, false) end
end

function World:MouseClick(frame, button)
	self:HoldMouse(frame, button)
	self:ReleaseMouse(frame, button)
end

-- The wheel turning over a frame; delta is -1 for a notch down (warcraft.wiki.gg UIHANDLER
-- OnMouseWheel).
function World:MouseWheel(frame, delta)
	assert(Visible(frame) and frame.mouseWheel, "the wheel only reaches a visible frame that enabled it")
	RunScripts(frame, "OnMouseWheel", delta)
end

-- The game updating the tooltip: GameTooltip_OnUpdate calls its owner's UpdateTooltip
-- (GameTooltip.lua:456-458).
function World:UpdateTooltip()
	local owner = self.tooltip and self.tooltip.owner
	if owner and owner.UpdateTooltip then owner:UpdateTooltip() end
end

-- The mouse dragging from a button.
function World:Drag(frame, button)
	assert(Visible(frame), "the mouse can't drag a frame that isn't visible")
	button = button or "LeftButton"
	for _, registered in ipairs(frame.drags or {}) do
		if registered == button then RunScripts(frame, "OnDragStart", button) return end
	end
	error("the frame isn't registered for drags with " .. button)
end

-- Pressing a key with an override binding clicks its target, down then up. Returns false if no
-- override binding has the key.
function World:PressKey(key)
	for _, keys in pairs(self.overrides) do
		local binding = keys[key]
		if binding then
			local frame = self.env[binding.name]
			frame:Click(binding.button or "LeftButton", true)
			frame:Click(binding.button or "LeftButton", false)
			return true
		end
	end
	return false
end

-- The keys with override bindings now.
function World:OverrideKeys()
	local keys = {}
	for _, bound in pairs(self.overrides) do
		for key in pairs(bound) do keys[#keys + 1] = key end
	end
	table.sort(keys)
	return keys
end

-- The mouse leaving every open frame long enough: frames registered for auto-hide close.
function World:MouseAway()
	for _, frame in pairs(self.frames) do
		if frame.autoHide and frame.shown then SetShown(frame, false) end
	end
end
function World:LastUsed() return self.used[#self.used] end

-- Errors shown since the last call, so a check never sees an earlier step's message.
function World:TakeErrors()
	local errors = self.errors
	self.errors = {}
	return errors
end

-- Slash commands, as typed in chat.
function World:Slash(text)
	local command, rest = text:match("^(/%S+)%s*(.-)$")
	for key, fn in pairs(self.env.SlashCmdList) do
		local i = 1
		while self.env["SLASH_" .. key .. i] do
			if self.env["SLASH_" .. key .. i] == command then
				return fn(rest)
			end
			i = i + 1
		end
	end
	error("unknown slash command " .. command)
end

-- Macro conditionals, as SecureCmdOptionParse reads them: "[conds][conds]value; ..." gives the
-- value of the first clause with a [conds] group whose comma-separated conditions all hold (or no
-- group at all), trimmed, or nil (warcraft.wiki.gg Macro conditionals). Only the conditions
-- Clicky uses: combat and btn:N (the mouse button the macro was clicked with, 1 = left,
-- 2 = right, 3 = middle; LeftButton for keys and /click).
local BUTTON_NUMBER = { LeftButton = "1", RightButton = "2", MiddleButton = "3" }

function World:OptionParse(msg)
	for clause in (msg .. ";"):gmatch("([^;]*);") do
		local groups, value = {}, clause
		while true do
			local group, rest = value:match("^%s*%[(.-)%](.*)$")
			if not group then break end
			groups[#groups + 1], value = group, rest
		end
		local matches = #groups == 0
		for _, group in ipairs(groups) do
			local all = true
			for cond in group:gmatch("[^,]+") do
				cond = strtrim(cond)
				local held
				if cond == "combat" then held = self.combat
				elseif cond:match("^btn:") then
					held = false
					for n in cond:sub(5):gmatch("[^/]+") do
						if n == BUTTON_NUMBER[self.clickedWith or "LeftButton"] then held = true end
					end
				else error("macro conditional the stubs don't know: " .. cond) end
				all = all and held
			end
			matches = matches or all
		end
		if matches then return strtrim(value) end
	end
	return nil
end

-- Presses an action bar slot holding a macro, with a mouse button (LeftButton if not given):
-- runs its /click lines as SLASH_COMMAND.CLICK does (SlashCommands.lua): the line goes through
-- SecureCmdOptionParse, then "name [mouseButton [down]]", with LeftButton and an up click if not
-- given. Returns false if the slot is empty.
function World:PressBar(slot, mouseButton)
	local macro = self.bars[slot]
	if not macro then
		return false
	end
	self.clickedWith = mouseButton or "LeftButton"
	for line in macro.body:gmatch("[^\n]+") do
		local msg = line:match("^/click%s+(.*)$")
		local action = msg and self:OptionParse(msg)
		if action and action ~= "" then
			local name, button, down = action:match("([^%s]+)%s+([^%s]+)%s*(.*)")
			name = name or action
			local frame = self.env[name]
			if frame and frame.Click then
				frame:Click(button or "LeftButton", down == "true" or down == "1")
			end
		end
	end
	self.clickedWith = nil
	return true
end

-- The spellbook the stubs show (SpellBookDocumentation.lua): skill lines in order, each with the
-- items on its pages (itemIndexOffset + 1 is its first slot) and a Flyout item per flyout; and the
-- flyouts' spells in order. Built from world.spells when asked.
function World:SpellBook()
	local ids = {}
	for id in pairs(self.spells) do ids[#ids + 1] = id end
	table.sort(ids)
	local book, flyouts, flyoutSeen = { lines = {}, slots = {}, professions = {} }, {}, {}
	book.flyouts = flyouts
	local lines, professions = {}, {}
	for _, id in ipairs(ids) do
		local t = self.spells[id]
		if t.profession then
			professions[t.profession] = professions[t.profession] or {}
			table.insert(professions[t.profession], { actionID = id, spellID = id, itemType = 1, name = t.name,
				subName = "", iconID = t.icon, isPassive = t.passive, isOffSpec = false })
		else
		lines[t.line] = lines[t.line] or { items = {}, offSpec = t.offSpec }
		local items = lines[t.line].items
		if t.flyout then
			flyouts[t.flyout] = flyouts[t.flyout] or {}
			table.insert(flyouts[t.flyout], id)
			if not flyoutSeen[t.flyout] then
				flyoutSeen[t.flyout] = true
				items[#items + 1] = { actionID = t.flyout, itemType = 4, name = "Flyout", subName = "", iconID = 1,
					isPassive = false, isOffSpec = t.offSpec }
			end
		else
			items[#items + 1] = { actionID = t.base or id, spellID = id, itemType = t.known and 1 or 2, name = t.name,
				subName = "", iconID = t.icon, isPassive = t.passive, isOffSpec = t.offSpec }
		end
		end
	end
	local numbers = {}
	for number in pairs(lines) do numbers[#numbers + 1] = number end
	table.sort(numbers)
	for _, number in ipairs(numbers) do
		local l = lines[number]
		l.offset = #book.slots
		for _, item in ipairs(l.items) do book.slots[#book.slots + 1] = item end
		book.lines[#book.lines + 1] = l
	end
	for i = 1, 5 do
		if professions[i] then
			book.professions[i] = { offset = #book.slots, count = #professions[i] }
			for _, item in ipairs(professions[i]) do book.slots[#book.slots + 1] = item end
		end
	end
	return book
end

-- The item IDs in a bag, by slot: the items counted in it, by ID.
function World:BagItems(bag)
	local ids = {}
	for id, t in pairs(self.items) do
		if t.bag == bag and t.count > 0 and not t.worn then ids[#ids + 1] = id end
	end
	table.sort(ids)
	return ids
end

function World:BuildEnv()
	local world = self
	local env = setmetatable({}, { __index = _G })
	self.env = env
	env._G = env
	env.strtrim = strtrim
	-- WoW's xpcall passes its arguments on (FunctionUtil.lua:4).
	env.xpcall = function(f, handler, ...)
		local n, args = select("#", ...), { ... }
		return xpcall(function() return f(unpack(args, 1, n)) end, handler)
	end
	env.tostringall = function(...) -- Blizzard_PrintHandler.lua:29
		local n, out = select("#", ...), {}
		for i = 1, n do out[i] = tostring((select(i, ...))) end
		return unpack(out, 1, n)
	end
	env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		table.insert(world.prints, table.concat(parts, " "))
	end
	env.InCombatLockdown = function() return world.combat end
	-- Milliseconds, for timing (warcraft.wiki.gg API debugprofilestop): the test's own clock.
	env.debugprofilestop = function() return os.clock() * 1000 end
	env.SlashCmdList = {}
	env.UIParent = NewFrame(world)
	env.UIErrorsFrame = { AddExternalErrorMessage = function(_, msg) table.insert(world.errors, msg) end }
	world.frames = {}
	env.CreateFrame = function(frameType, name, parent, template)
		local frame = NewFrame(world, name, parent, template, frameType)
		table.insert(world.frames, frame)
		return frame
	end
	-- C_Timer.After (UITimerDocumentation.lua).
	env.C_Timer = {
		After = function(delay, fn) table.insert(world.timers, { at = world.time + delay, fn = fn }) end,
	}
	env.SecureCmdOptionParse = function(msg) return world:OptionParse(msg) end
	-- SecureHandlers.lua: the header must be explicitly protected; frame refs are stored as the
	-- frame's "frameref-<label>" attribute, holding a handle. Neither can run in combat (they go
	-- through a protected frame's attributes).
	env.SecureHandlerWrapScript = function(frame, script, header, preBody)
		assert(not world.combat, "ADDON_ACTION_BLOCKED: SecureHandlerWrapScript in combat")
		assert(select(2, header:IsProtected()), "Header frame must be explicitly protected")
		assert(type(preBody) == "string", "Invalid pre-handler body")
		frame.wraps[script] = preBody
	end
	env.SecureHandlerSetFrameRef = function(frame, label, refFrame)
		assert(not world.combat, "ADDON_ACTION_BLOCKED: SecureHandlerSetFrameRef in combat")
		frame.attributes["frameref-" .. label] = HandleOf(refFrame)
	end
	-- The restricted environment's functions (RestrictedEnvironment.lua), those Clicky's snippets
	-- may use.
	world.restricted = {
		random = math.random, floor = math.floor, ceil = math.ceil, min = math.min, max = math.max,
		tostring = tostring, tonumber = tonumber, type = type,
		SecureCmdOptionParse = env.SecureCmdOptionParse,
	}
	-- GetAddOnMetadata reads the .toc's "## Field: value" lines (AddOnsDocumentation.lua).
	env.C_AddOns = {
		-- loadedOrLoading, loaded (AddOnsDocumentation.lua): the Collections window once
		-- World:LoadCollections has loaded it.
		IsAddOnLoaded = function(name)
			local loaded = name == "Blizzard_Collections" and world.collectionsLoaded == true
			return loaded, loaded
		end,
		GetAddOnMetadata = function(_, field) return world.toc[field] end,
	}
	-- Dialogs (Blizzard_StaticPopup/StaticPopup.lua, SharedTemplates.lua), as far as Clicky uses them:
	-- StaticPopup_Show errors on a dialog that isn't defined (:300-304), keeps the data on the dialog and
	-- runs its OnShow(dialog, data); the edit box's OnTextChanged runs EditBoxOnTextChanged(editBox,
	-- data), whoever set the text, and Enter runs EditBoxOnEnterPressed(editBox, data)
	-- (SharedTemplates.lua:37-66); button 1 runs OnAccept(dialog, data, data2), and the dialog stays
	-- open if it returns true (StaticPopup_OnClick, :709-713). world.dialog is the dialog shown; what
	-- Blizzard draws isn't here.
	env.StaticPopupDialogs = {}
	env.StaticPopup_Show = function(which, textArg1, textArg2, data)
		local info = env.StaticPopupDialogs[which]
		if not info then error("Dialog " .. which .. " does not exist.") end
		local dialog = { which = which, data = data, text = info.text:format(textArg1 or "", textArg2 or "") }
		local button1 = { enabled = true }
		function button1.SetEnabled(b, enabled) b.enabled = enabled and true or false end
		function button1.IsEnabled(b) return b.enabled end
		function button1.Click() world:ClickDialogButton(1) end
		local editBox = info.hasEditBox and { text = "" } or nil
		function dialog.GetButton1() return button1 end
		function dialog.GetEditBox() return editBox end
		function dialog.Hide(d) if world.dialog == d then world.dialog = nil end end
		if editBox then
			function editBox.GetParent() return dialog end
			function editBox.GetText(e) return e.text end
			function editBox.SetText(e, text)
				e.text = text
				if info.EditBoxOnTextChanged then info.EditBoxOnTextChanged(e, dialog.data) end
			end
			function editBox.HighlightText(e) e.selected = e.text end
		end
		world.dialog = dialog
		if info.OnShow then info.OnShow(dialog, data) end
		return dialog
	end
	-- StaticPopup.lua:138-146, with UserEditBoxNonEmpty (Blizzard_SharedXML/StringUtil.lua:9-15).
	env.StaticPopup_StandardNonEmptyTextHandler = function(editBox)
		editBox:GetParent():GetButton1():SetEnabled(strtrim(editBox:GetText()) ~= "")
	end
	env.StaticPopup_StandardEditBoxOnEscapePressed = function(editBox) editBox:GetParent():Hide() end
	-- EventUtil.ContinueOnAddOnLoaded (Blizzard_SharedXML/EventUtil.lua): the callback runs now if
	-- the add-on is loaded (IsAddOnLoaded's second result), else once on its ADDON_LOADED.
	env.EventUtil = {
		ContinueOnAddOnLoaded = function(addOnName, callback)
			local _, loaded = env.C_AddOns.IsAddOnLoaded(addOnName)
			if loaded then
				callback()
				return
			end
			local frame = env.CreateFrame("Frame")
			frame:RegisterEvent("ADDON_LOADED")
			frame:SetScript("OnEvent", function(waiting, _, name)
				if name == addOnName then
					waiting:UnregisterEvent("ADDON_LOADED")
					callback()
				end
			end)
		end,
	}
	-- The function that gets Lua errors (geterrorhandler, warcraft.wiki.gg API geterrorhandler):
	-- here it keeps them, and World:Fire raises the first so a test sees an error in a handler.
	-- A test that expects one sets world.errorHandler.
	world.luaErrors = {}
	world.errorHandler = function(err) table.insert(world.luaErrors, err) end
	env.geterrorhandler = function() return world.errorHandler end

	-- Toys. GetToyLink answers for any toy in the game, owned or not, and nil for an item that
	-- isn't one (warcraft.wiki.gg API_C_ToyBox.GetToyLink).
	-- A toy learned gift-wrapped needs its fanfare until it's cleared (ToyBoxInfoDocumentation.lua;
	-- Blizzard_ToyBox.lua clears it when the wrapped toy is clicked).
	env.C_ToyBoxInfo = {
		-- Both take a toy's item ID, a number (ToyBoxInfoDocumentation.lua: itemID, Type number).
		-- Which sources the Toy Box's menu offers: here, every one.
		IsToySourceValid = function() return true end,
		IsUsingDefaultFilters = function() return world.blizzard.toys.default end,
		NeedsFanfare = function(id)
			assert(type(id) == "number", "NeedsFanfare takes an item ID")
			return world.toys[id] and world.toys[id].fanfare or false
		end,
		ClearFanfare = function(id)
			assert(type(id) == "number", "ClearFanfare takes an item ID")
			if world.toys[id] then world.toys[id].fanfare = false end
		end,
	}
	env.C_ToyBox = {
		GetToyLink = function(id)
			return world.toys[id] and ("|cffffffff|Hitem:" .. id .. "::::::::::::|h[" .. world.toys[id].name .. "]|h|r") or nil
		end,
		-- A toy whose data hasn't loaded (toy.loading) has no name or icon yet (seen in play).
		GetToyInfo = function(id)
			local t = world.toys[id]
			if t and not t.loading then return id, t.name, t.icon end
			if t then return id end
		end,
		GetNumToys = function() return #world.toyOrder end,
		-- The Toy Box's list as its filters have it (world.blizzard.toys.list).
		GetNumFilteredToys = function() return #world.blizzard.toys.list end,
		GetToyFromIndex = function(i) return world.blizzard.toys.list[i] end,
		-- The Toy Box's filter settings, as Blizzard_ToyBox.lua:56-138 reads them.
		GetCollectedShown = function() return world.blizzard.toys.collected end,
		GetUncollectedShown = function() return world.blizzard.toys.uncollected end,
		GetUnusableShown = function() return world.blizzard.toys.unusable end,
		IsSourceTypeFilterChecked = function(i) return not world.blizzard.toys.sourcesOff[i] end,
		IsExpansionTypeFilterChecked = function(i) return not world.blizzard.toys.expansionsOff[i] end,
		-- The star calls take a toy's item ID (warcraft.wiki.gg API C_ToyBox.GetIsFavorite, SetIsFavorite).
		GetIsFavorite = function(id)
			assert(type(id) == "number", "GetIsFavorite takes an item ID")
			return world.toys[id] and world.toys[id].favorite or false
		end,
		SetIsFavorite = function(id, v)
			assert(type(id) == "number", "SetIsFavorite takes an item ID")
			world.toys[id].favorite = v
		end,
		IsToyUsable = function(id) return world.toys[id] and world.toys[id].usable or false end,
	}
	env.PlayerHasToy = function(id)
		return world.toysLoaded and world.toys[id] and world.toys[id].owned or false
	end
	-- Dragging a toy picks it up on the cursor (Blizzard_ToyBox.lua:298, ToySpellButton_OnDrag).
	env.C_ToyBox.PickupToyBoxItem = function(id) world.cursor = { toy = id } end
	-- startTime, duration, enable (ContainerDocumentation.lua).
	env.C_Container = {
		-- The bag's slots, with one empty slot after its items so a test sees an empty slot answered
		-- with nothing (GetContainerItemID MayReturnNothing, ContainerDocumentation.lua).
		GetContainerNumSlots = function(bag)
			local n = #world:BagItems(bag)
			return n > 0 and n + 1 or 0
		end,
		GetContainerItemID = function(bag, slot) return world:BagItems(bag)[slot] end,
		GetItemCooldown = function(id)
			local cd = world.toys[id] and world.toys[id].cooldown or world.items[id] and world.items[id].cooldown or 0
			if cd > 0 then return world.time - 1, cd + 1, 1 end
			return 0, 0, 1
		end,
	}
	-- GetItemInfoInstant never asks the server, so it answers for any item (warcraft.wiki.gg API
	-- C_Item.GetItemInfoInstant): itemID, itemType, itemSubType, itemEquipLoc, icon, ...
	env.C_Item = {
		RequestLoadItemDataByID = function() end,
		GetItemInfoInstant = function(id)
			local t = world.toys[id] or world.items[id]
			if t then return id, "Miscellaneous", "Junk", "", t.icon, 15, 0 end
		end,
		-- GetItemNameByID has no name for an item the game hasn't cached (itemName Nilable,
		-- ItemDocumentation.lua); RequestLoadItemDataByID and GET_ITEM_INFO_RECEIVED bring it.
		GetItemNameByID = function(id)
			local t = world.items[id]
			if t and not t.loading then return t.name end
		end,
		-- ItemDocumentation.lua: count, whether it's equippable, equipped, usable.
		GetItemCount = function(id) return world.items[id] and world.items[id].count or 0 end,
		IsEquippableItem = function(id) return world.items[id] and world.items[id].equippable or false end,
		IsEquippedItem = function(id) return world.items[id] and world.items[id].equipped or false end,
		-- ItemDocumentation.lua: PickupItem takes an item ID; GetItemInfo's second return is the
		-- link, nothing until the item's data has loaded.
		PickupItem = function(id) world.cursor = { item = id } end,
		-- Its 15th return is the expansion ID (ItemDocumentation.lua:604-630); toys are items too.
		GetItemInfo = function(id)
			local t = world.items[id] or world.toys[id]
			if t and not t.loading then
				return t.name, "|cffffffff|Hitem:" .. id .. "::::::::::::|h[" .. t.name .. "]|h|r", 1, 1, 1, "", "", 1, "",
					t.icon, 0, 0, 0, 0, t.expansion or 0
			end
		end,
		IsUsableItem = function(id)
			local t = world.items[id]
			return t and t.usable or false, false
		end,
	}
	-- Constants.lua:153-186: the inventory slots from the head to the tabard, and the bag slots the
	-- player equips (the four bags and the reagent bag).
	env.INVSLOT_FIRST_EQUIPPED, env.INVSLOT_LAST_EQUIPPED = 1, 19
	env.NUM_TOTAL_EQUIPPED_BAG_SLOTS = 5
	-- warcraft.wiki.gg API GetInventoryItemID (used so in Blizzard_UIPanels_Game/PaperDollFrame.lua):
	-- the ID of the item worn in a slot, nothing for an empty one.
	env.GetInventoryItemID = function(unit, slot)
		assert(unit == "player", "the stubs only have the player's inventory")
		for id, t in pairs(world.items) do
			if t.worn == slot then return id end
		end
	end
	-- Spells (SpellDocumentation.lua, SpellBookDocumentation.lua). GetSpellName and
	-- GetSpellTexture return nothing for a spell that isn't found; RequestLoadSpellData asks for a
	-- spell's data and SPELL_DATA_LOAD_RESULT says when it has arrived.
	-- GetSpellCooldown is SecretWhenCooldownsRestricted: with world.secretCooldowns its start and
	-- duration are secret values, here world.SECRET, a table, which errors if compared with a
	-- number; isActive and isEnabled are never secret (SpellSharedDocumentation.lua).
	world.SECRET = { secret = true }
	env.issecretvalue = function(value) return value == world.SECRET end
	env.C_SpellBook = {
		IsSpellKnown = function(id) return world.spells[id] and world.spells[id].known or false end,
		GetNumSpellBookSkillLines = function() return #world:SpellBook().lines end,
		GetSpellBookSkillLineInfo = function(line)
			local l = world:SpellBook().lines[line]
			if not l then return end
			return {
				name = "Line " .. line, iconID = 1, itemIndexOffset = l.offset, numSpellBookItems = #l.items,
				isGuild = false, shouldHide = false, offSpecID = l.offSpec and 1 or nil,
			}
		end,
		GetSpellBookItemInfo = function(slot, bank)
			assert(bank == env.Enum.SpellBookSpellBank.Player, "the stubs only have the player's spellbook")
			return world:SpellBook().slots[slot]
		end,
	}
	-- SpellBookConstantsDocumentation.lua.
	env.Enum = {
		SpellBookSpellBank = { Player = 0, Pet = 1 },
		SpellBookItemType = { None = 0, Spell = 1, FutureSpell = 2, PetAction = 3, Flyout = 4 },
		-- MountConstantsDocumentation.lua; MountTypeMeta.NumValues is the count of MountType's values.
		MountType = { Ground = 0, Flying = 1, Aquatic = 2, Dragonriding = 3, RideAlong = 4 },
		MountTypeFlag = { IsFlyingMount = 1, IsAquaticMount = 2, IsDragonRidingMount = 4, IsRideAlongMount = 8 },
		MountTypeMeta = { NumValues = 5 },
	}
	-- A flyout's number of slots and a slot's spell ID, name and whether it's known: the returns
	-- Blizzard_SpellSearchTextFilter.lua:230-237 reads (GetFlyoutInfo's third, GetFlyoutSlotInfo's
	-- first, third and fourth).
	env.GetFlyoutInfo = function(flyoutID)
		local flyout = world:SpellBook().flyouts[flyoutID]
		if flyout then return "Flyout " .. flyoutID, "", #flyout, true end
	end
	-- The player's professions as the Professions book reads them (Blizzard_ProfessionsBook.lua:58,
	-- 387): GetProfessions' five indexes, nil for one not learned, and GetProfessionInfo's fifth and
	-- sixth, its spells' count and the slot before its first. The stubs' index is the place.
	env.GetProfessions = function()
		local professions = world:SpellBook().professions
		local function At(i) return professions[i] and i or nil end
		return At(1), At(2), At(3), At(4), At(5)
	end
	env.GetProfessionInfo = function(index)
		local p = world:SpellBook().professions[index]
		return "Profession " .. index, 1, 1, 100, p.count, p.offset
	end
	env.GetFlyoutSlotInfo = function(flyoutID, slot)
		local id = world:SpellBook().flyouts[flyoutID][slot]
		local t = world.spells[id]
		return id, id, t.known, t.name
	end
	env.C_Spell = {
		GetSpellName = function(id)
			local t = world.spells[id]
			if t and not t.loading then return t.name end
			-- A mount's spell is called as the mount (its stub data has one name for both).
			for _, m in pairs(world.mounts) do
				if m.spell == id then return m.name end
			end
		end,
		GetSpellTexture = function(id)
			local t = world.spells[id]
			if t then return t.icon end
		end,
		RequestLoadSpellData = function() end,
		-- SpellDocumentation.lua: a link for a spell that exists, nothing for one that doesn't; the
		-- cursor holds the spell after PickupSpell.
		GetSpellLink = function(id)
			local t = world.spells[id]
			if t then return "|cff71d5ff|Hspell:" .. id .. ":0|h[" .. t.name .. "]|h|r" end
		end,
		PickupSpell = function(id) world.cursor = { spell = id } end,
		IsSpellUsable = function(id)
			local t = world.spells[id]
			return t and t.usable or false, false
		end,
		GetSpellCooldown = function(id)
			local t = world.spells[id]
			if not t then return end
			local active = t.cooldown > 0
			return {
				startTime = active and (world.secretCooldowns and world.SECRET or world.time - 1) or 0,
				duration = active and (world.secretCooldowns and world.SECRET or t.cooldown + 1) or 0,
				isEnabled = true, isActive = active, modRate = 1,
			}
		end,
	}

	-- Mounts (MountJournalDocumentation.lua): GetMountIDs lists every mount, GetMountInfoByID answers
	-- for any of them whatever the journal's filters; the "displayed" calls take a place in the Mount
	-- Journal's list as its filters have it (mount.shown), as do the star and pickup calls.
	local function Displayed()
		local ids = {}
		for _, id in ipairs(world.account.mountOrder) do
			if world.mounts[id].shown then ids[#ids + 1] = id end
		end
		return ids
	end
	env.C_MountJournal = {
		GetMountIDs = function() return { unpack(world.account.mountOrder) } end,
		-- name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction,
		-- shouldHideOnChar, isCollected, mountID. sourceType counts from 1, as the Sources checkboxes do
		-- (seen in play: Mounts.lua, ns.MountSource).
		GetMountInfoByID = function(id)
			local m = world.mounts[id]
			if m then
				return m.name, m.spell, m.icon, m.active == true, m.collected and m.usable, m.source or 0, m.favorite, false, nil,
					m.hidden, m.collected, id
			end
		end,
		-- The mount a spell summons, or nothing (MountJournalDocumentation.lua: mountID Nilable).
		GetMountFromSpell = function(spellID)
			for id, m in pairs(world.mounts) do
				if m.spell == spellID then return id end
			end
		end,
		-- creatureDisplayInfoID, description, source, isSelfMount, mountTypeID, ...
		GetMountInfoExtraByID = function(id)
			local m = world.mounts[id]
			if m then return nil, "", m.sourceText or "", false, m.mountTypeID or 230 end
		end,
		-- Which sources and types the Mount Journal's menu offers: here, every one.
		IsValidSourceFilter = function() return true end,
		IsValidTypeFilter = function() return true end,
		-- The Mount Journal's filter settings, as Blizzard_MountCollection.lua:221-258, 964-986 reads them.
		GetCollectedFilterSetting = function(setting)
			local f = world.blizzard.mounts
			return ({ f.collected, f.uncollected, f.unusable })[setting]
		end,
		IsTypeChecked = function(i) return not world.blizzard.mounts.typesOff[i] end,
		IsSourceChecked = function(i) return not world.blizzard.mounts.sourcesOff[i] end,
		IsUsingDefaultFilters = function() return world.blizzard.mounts.default end,
		GetNumDisplayedMounts = function() return #Displayed() end,
		GetDisplayedMountID = function(index) return Displayed()[index] end,
		-- isFavorite, canSetFavorite: the Mount Journal offers the star on collected mounts
		-- (Blizzard_MountCollection.lua:293-305, its menu is only for collected ones, 919-923).
		GetIsFavorite = function(index)
			local m = world.mounts[Displayed()[index]]
			return m.favorite, m.collected
		end,
		SetIsFavorite = function(index, favorite)
			assert(type(favorite) == "boolean", "SetIsFavorite takes a boolean")
			world.mounts[Displayed()[index]].favorite = favorite
		end,
		-- Both take a mount ID, a number (MountJournalDocumentation.lua: mountID, Type number,
		-- Nilable false); the journal clears a wrapped mount's fanfare when it's clicked
		-- (Blizzard_MountCollection.lua:868-881).
		NeedsFanfare = function(id)
			assert(type(id) == "number", "NeedsFanfare takes a mount ID")
			return world.mounts[id] ~= nil and world.mounts[id].fanfare
		end,
		ClearFanfare = function(id)
			assert(type(id) == "number", "ClearFanfare takes a mount ID")
			if world.mounts[id] then world.mounts[id].fanfare = false end
		end,
		Pickup = function(index) world.cursor = { mount = Displayed()[index] } end,
		GetMountLink = function(spellID)
			for id, m in pairs(world.mounts) do
				if m.spell == spellID then return "|cff71d5ff|Hmount:" .. id .. "|h[" .. m.name .. "]|h|r" end
			end
		end,
	}
	-- Pets (PetJournalInfoDocumentation.lua; the rest as Blizzard_PetCollection.lua calls them):
	-- GetOwnedPetIDs lists every pet owned, whatever the journal's filters; GetPetInfoByPetID returns
	-- speciesID, customName, level, xp, maxXp, displayID, isFavorite, name, icon (:409);
	-- GetPetInfoBySpeciesID its name and icon first; SetFavorite takes 1 or 0 (:930-934).
	env.C_PetJournal = {
		GetOwnedPetIDs = function()
			local ids = {}
			for i, pet in ipairs(world.pets) do ids[i] = pet.guid end
			return ids
		end,
		GetPetInfoByPetID = function(guid)
			local pet = world:Pet(guid)
			if pet then
				local species = world.account.species[pet.species]
				return pet.species, nil, pet.level or 1, 0, 100, pet.display, pet.favorite, species.name, species.icon
			end
		end,
		-- A species' looks, owned or not (PetJournalInfoDocumentation.lua: GetNumDisplays,
		-- GetDisplayIDByIndex, both Nilable).
		GetNumDisplays = function(id)
			local looks = world:SpeciesLooks(id)
			return #looks > 0 and #looks or nil
		end,
		GetDisplayIDByIndex = function(id, index) return world:SpeciesLooks(id)[index] end,
		-- speciesName, speciesIcon, petType (1 is Humanoid, PET_TYPE_SUFFIX, Constants.lua), companionID,
		-- tooltipSource, tooltipDescription, isWild, canBattle (warcraft.wiki.gg).
		GetPetInfoBySpeciesID = function(id)
			local species = world.account.species[id]
			if species then
				return species.name, species.icon, species.family or 1, 0, species.sourceText or "", "", false,
					species.canBattle ~= false
			end
		end,
		-- health, maxHealth, power, speed, rarity (warcraft.wiki.gg API C_PetJournal.GetPetStats).
		GetPetStats = function(guid) return 100, 100, 10, 10, world:Pet(guid).rarity or 1 end,
		-- Blizzard_PetCollection.lua:192-206 numbers the families and sources from 1.
		GetNumPetTypes = function() return 10 end,
		GetNumPetSources = function() return 12 end,
		PetIsFavorite = function(guid) return world:Pet(guid).favorite end,
		SetFavorite = function(guid, value)
			assert(value == 0 or value == 1, "SetFavorite takes 1 or 0")
			world:Pet(guid).favorite = value == 1
		end,
		-- Both take the pet's GUID (Blizzard_PetCollection.lua:770, 895-901, 1443-1455); Blizzard's
		-- generated documentation doesn't list them.
		PetNeedsFanfare = function(guid)
			assert(type(guid) == "string", "PetNeedsFanfare takes a pet GUID")
			return world:Pet(guid) ~= nil and world:Pet(guid).fanfare
		end,
		ClearFanfare = function(guid)
			assert(type(guid) == "string", "ClearFanfare takes a pet GUID")
			if world:Pet(guid) then world:Pet(guid).fanfare = false end
		end,
		PetIsSummonable = function(guid) return world:Pet(guid).summonable end,
		GetSummonedPetGUID = function() return world.summonedPet end,
		-- start, duration, isEnabled (warcraft.wiki.gg API C_PetJournal.GetPetCooldownByGUID), which the
		-- Pet Journal draws on a pet's button (Blizzard_PetCollection.lua:866-870). pet.cooldown is
		-- the seconds left, as a toy's.
		GetPetCooldownByGUID = function(guid)
			local cd = world:Pet(guid) and world:Pet(guid).cooldown or 0
			if cd > 0 then return world.time - 1, cd + 1, 1 end
			return 0, 0, 1
		end,
		GetBattlePetLink = function(guid) return "|cff0070dd|Hbattlepet:" .. guid .. "|h[Pet]|h|r" end,
		PickupPet = function(guid) world.cursor = { pet = guid } end,
		-- numPets, numOwned: the Pet Journal's list as its filters have it (world.blizzard.pets.list).
		GetNumPets = function() return #world.blizzard.pets.list, #world.pets end,
		-- petID, speciesID: the Pet Journal's list (Blizzard_PetCollection.lua:876-877).
		GetPetInfoByIndex = function(i) return nil, world.blizzard.pets.list[i] end,
		-- The Pet Journal's filter settings, as Blizzard_PetCollection.lua:172-212, 1481-1510 reads them.
		IsFilterChecked = function(setting)
			local f = world.blizzard.pets
			return ({ f.collected, f.uncollected, f.battlePets, f.nonCombatPets })[setting]
		end,
		IsPetTypeChecked = function(i) return not world.blizzard.pets.familiesOff[i] end,
		IsPetSourceChecked = function(i) return not world.blizzard.pets.sourcesOff[i] end,
		GetPetSortParameter = function() return world.blizzard.pets.sortBy end,
		IsUsingDefaultFilters = function() return world.blizzard.pets.default end,
	}

	-- Tooltips as data (TooltipInfoDocumentation.lua; a TooltipData's lines, each with leftText and
	-- rightText, Structure.lua in Ketho's annotations, as TooltipUtil.lua:55 reads them): the entry's
	-- name, then its own tooltip text (a toy's, spell's, item's, mount's or pet's species' tooltip
	-- field); nothing while its data is loading.
	local function Tooltip(t, name)
		if t and not t.loading then
			return { lines = { { leftText = name or t.name, rightText = "" }, { leftText = t.tooltip or "", rightText = "" } } }
		end
	end
	env.C_TooltipInfo = {
		GetToyByItemID = function(id) return Tooltip(world.toys[id]) end,
		GetSpellByID = function(id) return Tooltip(world.spells[id]) end,
		GetItemByID = function(id) return Tooltip(world.items[id]) end,
		GetMountBySpellID = function(spellID)
			for _, m in pairs(world.mounts) do
				if m.spell == spellID then return Tooltip(m) end
			end
		end,
		GetCompanionPet = function(guid)
			local pet = world:Pet(guid)
			return pet and Tooltip(world.account.species[pet.species])
		end,
	}

	-- Keys and clicks. The three keys SecureButton_GetModifierPrefix reads (SecureTemplates.lua:70-90).
	env.IsShiftKeyDown = function() return world.keys.shift or false end
	env.IsControlKeyDown = function() return world.keys.ctrl or false end
	env.IsAltKeyDown = function() return world.keys.alt or false end
	-- No argument: any mouse button (used so in ModelControlButtonMixin.lua:167); InputDocumentation.lua.
	env.IsMouseButtonDown = function(button)
		if button then return world.mouse[button] or false end
		return next(world.mouse) ~= nil
	end
	env.IsModifiedClick = function(action)
		assert(action == "CHATLINK", "a modified click the stubs don't know: " .. tostring(action))
		return world.keys[world.chatLinkKey] or false
	end
	-- Blizzard_ChatFrameBase/Mainline/ChatFrameUtilOverrides.lua:14: puts a link in the chat box.
	env.ChatFrameUtil = { InsertLink = function(link) table.insert(world.chat, link) return true end }

	-- The tooltip: its owner and the toy it shows, until GameTooltip_Hide (GameTooltip.lua:618).
	env.GameTooltip = {
		SetOwner = function(_, owner, anchor) world.tooltip = { owner = owner, anchor = anchor, lines = {} } end,
		-- warcraft.wiki.gg API GameTooltip:SetText and AddLine.
		SetText = function(_, text) world.tooltip.title = text end,
		AddLine = function(_, text) table.insert(world.tooltip.lines, text) end,
		-- Shows the toy, and answers whether it could (Blizzard_ToyBox.lua:215).
		SetToyByItemID = function(_, id)
			world.tooltip.toy = id
			return world.toys[id] ~= nil
		end,
		-- The tooltip data handler's SetSpellByID and SetItemByID (TooltipDataHandler.lua).
		SetSpellByID = function(_, id)
			world.tooltip.spell = id
			return world.spells[id] ~= nil
		end,
		SetItemByID = function(_, id)
			world.tooltip.item = id
			return world.items[id] ~= nil
		end,
		-- The Mount Journal's and Pet Journal's (Blizzard_MountCollection.lua:703,
		-- Blizzard_PetCollection.lua:1016).
		SetMountBySpellID = function(_, id) world.tooltip.mountSpell = id end,
		SetCompanionPet = function(_, guid) world.tooltip.pet = guid end,
		Show = function() end,
	}
	env.GameTooltip_Hide = function() world.tooltip = nil end
	-- Cooldown.lua:2-9: a cooldown swipe is set when it has started and lasts, and cleared otherwise.
	env.CooldownFrame_Set = function(cooldown, start, duration, enable)
		if enable and enable ~= 0 and start > 0 and duration > 0 then
			cooldown:SetCooldown(start, duration)
		else
			cooldown:Clear()
		end
	end
	-- Global strings and colors the toy grid and panel read (the files that define them aren't in
	-- wow-ui-source): the English texts of the filter names, which a test picks a filter by, and the
	-- gold of the Toy Box's toy names.
	env.COLLECTED, env.NOT_COLLECTED, env.PET_JOURNAL_FILTER_USABLE_ONLY = "Collected", "Not Collected", "Usable Only"
	-- The filter menus' other texts, which tests find entries by: any distinct texts do.
	env.SOURCES, env.CHECK_ALL, env.UNCHECK_ALL, env.EXPANSION_FILTER_TEXT = "Sources", "Check All", "Uncheck All", "Expansion"
	env.MOUNT_JOURNAL_FILTER_UNUSABLE, env.MOUNT_JOURNAL_FILTER_TYPE = "Unusable", "Type"
	env.MOUNT_JOURNAL_FILTER_GROUND, env.MOUNT_JOURNAL_FILTER_FLYING = "Ground", "Flying"
	env.MOUNT_JOURNAL_FILTER_AQUATIC, env.MOUNT_JOURNAL_FILTER_DRAGONRIDING = "Aquatic", "Skyriding"
	env.MOUNT_JOURNAL_FILTER_RIDEALONG = "Ride Along"
	env.PET_FILTER_TYPES, env.PET_FILTER_BATTLE_PETS, env.PET_FILTER_NON_COMBAT_PETS = "Pet Types", "Battle Pets", "Non-Combat Pets"
	env.PET_FAMILIES, env.RAID_FRAME_SORT_LABEL = "Pet Families", "Sort By"
	env.NAME, env.LEVEL, env.RARITY, env.TYPE = "Name", "Level", "Rarity", "Type"
	env.LE_SORT_BY_NAME, env.LE_SORT_BY_LEVEL, env.LE_SORT_BY_RARITY, env.LE_SORT_BY_PETTYPE = 1, 2, 3, 4
	-- The game's filter setting numbers: any distinct ones do (the stubs above index by them).
	env.LE_MOUNT_JOURNAL_FILTER_COLLECTED, env.LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED = 1, 2
	env.LE_MOUNT_JOURNAL_FILTER_UNUSABLE = 3
	env.LE_PET_JOURNAL_FILTER_COLLECTED, env.LE_PET_JOURNAL_FILTER_NOT_COLLECTED = 1, 2
	env.LE_PET_JOURNAL_FILTER_TYPE_BATTLE_PETS, env.LE_PET_JOURNAL_FILTER_TYPE_NON_COMBAT_PETS = 3, 4
	env.GetNumExpansions = function() return 12 end
	for i = 1, 12 do env["BATTLE_PET_SOURCE_" .. i] = "Source " .. i end
	for i = 1, 10 do env["BATTLE_PET_NAME_" .. i] = "Family " .. i end
	for i = 0, 11 do env["EXPANSION_NAME" .. i] = "Expansion " .. i end
	env.bit = bit
	env.NEW_CAPS = "NEW"
	-- Blizzard_Collections.lua:1
	env.COLLECTIONS_FANFARE_ICON = "Interface/Icons/Item_Shop_GiftBox01"
	env.DELETE = "Delete" -- the menu's entry is found by it
	-- The toy menu's star entries are found by these; any two different texts do.
	env.BATTLE_PET_FAVORITE, env.BATTLE_PET_UNFAVORITE = "Favorite", "Unfavorite"
	-- MenuUtil.CreateContextMenu calls the generator with the owner and a root description
	-- (MenuUtil.lua:151-161). Each entry the generator makes on it is kept in world.menu for
	-- World:ChooseMenuEntry; only the menu itself is stubbed, not what Blizzard draws.
	env.MenuUtil = {
		CreateContextMenu = function(owner, generator)
			local entries = {}
			local root = setmetatable({}, { __index = function(_, kind)
				return function(_, text, ...) table.insert(entries, { kind = kind, text = text, args = { ... } }) end
			end })
			generator(owner, root)
			world.menu = { owner = owner, entries = entries }
		end,
	}
	-- The panel's window functions do nothing here. Its list is ScrollList below; a data provider is
	-- the table of its elements.
	env.ButtonFrameTemplate_HidePortrait = function() end
	env.ButtonFrameTemplate_HideButtonBar = function() end
	env.ButtonFrameTemplate_HideAttic = function() end
	-- EventRegistry (Blizzard_SharedXMLBase/GlobalCallbackRegistry.lua): Clicky only registers
	-- callbacks; none is triggered here.
	env.EventRegistry = { RegisterCallback = function() end }
	-- PanelTemplates (Blizzard_SharedXML/Mainline/SharedUIPanelTemplates.lua:369-480): the selected
	-- tab and the count are kept on the frame; how the tabs look and their widths aren't here.
	env.PanelTemplates_SetNumTabs = function(frame, numTabs) frame.numTabs = numTabs end
	env.PanelTemplates_SetTab = function(frame, id) frame.selectedTab = id end
	env.PanelTemplates_GetSelectedTab = function(frame) return frame.selectedTab end
	-- A tab's width (SharedUIPanelTemplates.lua:403-437): its text's, plus 20, plus the padding, or
	-- absoluteSize, which cuts the text short if it's narrower. The font isn't here: a character is
	-- world.charWidth wide (6 by default), a stand-in for Friz Quadrata at 10.
	local TAB_SIDES_PADDING = 20
	world.charWidth = 6
	env.PanelTemplates_TabResize = function(tab, padding, absoluteSize)
		local natural = #(tab.text or "") * world.charWidth
		local width = absoluteSize or natural + TAB_SIDES_PADDING + (padding or 0)
		tab.truncated = width - TAB_SIDES_PADDING - (padding or 0) < natural
		tab:SetWidth(width)
	end
	-- SharedUIPanelTemplates.lua:439-468, as Blizzard writes it.
	env.PanelTemplates_ResizeTabsToFit = function(frame, maxWidthForAllTabs)
		local selectedIndex = frame.selectedTab
		if not selectedIndex then return end
		local currentWidth, truncatedText = 0, false
		for i = 1, frame.numTabs do
			currentWidth = currentWidth + frame.Tabs[i]:GetWidth()
			truncatedText = truncatedText or frame.Tabs[i].truncated
		end
		if not truncatedText and currentWidth <= maxWidthForAllTabs then return end
		local currentTab = frame.Tabs[selectedIndex]
		env.PanelTemplates_TabResize(currentTab, 0)
		local widthPerTab = (maxWidthForAllTabs - currentTab:GetWidth()) / (frame.numTabs - 1)
		for i = 1, frame.numTabs do
			if i ~= selectedIndex then env.PanelTemplates_TabResize(frame.Tabs[i], 0, widthPerTab) end
		end
	end
	-- The window manager doesn't take addon calls in combat (UIParentPanelManager.lua:840-864).
	local function PanelBlocked(what)
		if world.combat then error("ADDON_ACTION_BLOCKED: " .. what .. " by addon code in combat", 3) end
	end
	-- The value is kept as the frame's "UIPanelLayout-<name>" attribute (UIParentPanelManager.lua:111-122).
	env.SetUIPanelAttribute = function(frame, name, value)
		PanelBlocked("SetUIPanelAttribute")
		frame:SetAttribute("UIPanelLayout-" .. name, value)
	end
	env.UpdateUIPanelPositions = function() PanelBlocked("UpdateUIPanelPositions") end
	-- SetCollectionsJournalShown shows the window with ShowUIPanel, which refuses addon code in combat
	-- (Blizzard_Collections_Bootstrap.lua:22-28, UIParentPanelManager.lua:844-870); it then selects
	-- the tab. The toys tab follows the mounts' and pets' (Blizzard_Collections_Bootstrap.lua:7-9).
	env.COLLECTIONS_JOURNAL_TAB_INDEX_TOYS = 3
	env.SetCollectionsJournalShown = function(shown, tabIndex)
		PanelBlocked("ShowUIPanel")
		world.journal = { shown = shown, tab = tabIndex }
	end
	env.CreateDataProvider = function(elements) return elements end
	-- ScrollBoxListView.lua:487-: the view makes its rows from a frame type and an initializer.
	env.CreateScrollBoxListLinearView = function()
		return { SetElementExtentCalculator = function() end,
			SetElementInitializer = function(view, frameType, initializer) view.frameType, view.initializer = frameType, initializer end }
	end
	env.ScrollUtil = { InitScrollBoxListWithScrollBar = function(list, _, view) list.view = view end,
		-- Binds a scroll box to its bar (ScrollUtil.lua:149-151).
		RegisterScrollBoxWithScrollBar = function(scrollBox, scrollBar) scrollBox.scrollBar = scrollBar end }
	-- Windows Escape closes, by name (UIParentPanelManager.lua:21).
	env.UISpecialFrames = {}
	-- ScrollBox.lua:2-18.
	env.ScrollBoxConstants = { NoScrollInterpolation = true, RetainScrollPosition = true }
	env.BaseScrollBoxEvents = { OnScroll = "OnScroll", OnAllowScrollChanged = "OnAllowScrollChanged" }

	-- Macros: general (account) macros at 1..120, character macros from 121. Names are capped at
	-- 16 characters; bodies longer than 255 are cut (warcraft.wiki.gg API_EditMacro). Every
	-- change fires UPDATE_MACROS; none is allowed in combat.
	env.Constants = { MacroConsts = { MAX_ACCOUNT_MACROS = MAX_ACCOUNT, MAX_CHARACTER_MACROS = MAX_CHARACTER } }
	local function NoCombat(what)
		if world.combat then error("ADDON_ACTION_BLOCKED: " .. what .. " in combat", 3) end
	end
	local function MacroAt(i)
		if not world.macrosLoaded then return nil end
		if i > MAX_ACCOUNT then return world.characterMacros[i - MAX_ACCOUNT] end
		return world.macros[i]
	end
	env.GetNumMacros = function()
		if not world.macrosLoaded then return 0, 0 end
		return #world.macros, #world.characterMacros
	end
	env.GetMacroInfo = function(i)
		local m = MacroAt(i)
		if m then return m.name, m.icon, m.body end
	end
	env.CreateMacro = function(name, icon, body, perCharacter)
		NoCombat("CreateMacro")
		assert(Letters(name) <= 16, "macro name longer than 16 characters: " .. name)
		local list = perCharacter and world.characterMacros or world.macros
		assert(perCharacter or #list < MAX_ACCOUNT, "general macros are full")
		local m = { name = name, icon = icon, body = body:sub(1, 255) }
		table.insert(list, m)
		local index = SortMacros(list, m)
		world:Fire("UPDATE_MACROS")
		return perCharacter and MAX_ACCOUNT + index or index
	end
	env.EditMacro = function(i, name, icon, body)
		NoCombat("EditMacro")
		local m = assert(MacroAt(i), "no macro " .. tostring(i))
		name = name or m.name -- nil keeps the name (Blizzard_MacroUI.lua, MacroFrameMixin:SaveMacro)
		assert(Letters(name) <= 16, "macro name longer than 16 characters: " .. name)
		m.name, m.icon, m.body = name, icon or m.icon, body and body:sub(1, 255) or m.body
		local perCharacter = i > MAX_ACCOUNT
		local index = SortMacros(perCharacter and world.characterMacros or world.macros, m)
		world:Fire("UPDATE_MACROS")
		return perCharacter and MAX_ACCOUNT + index or index
	end
	env.DeleteMacro = function(i)
		NoCombat("DeleteMacro")
		assert(MacroAt(i), "no macro " .. tostring(i))
		table.remove(i > MAX_ACCOUNT and world.characterMacros or world.macros, i > MAX_ACCOUNT and i - MAX_ACCOUNT or i)
		world:Fire("UPDATE_MACROS")
	end
	env.PickupMacro = function(i)
		world.cursor = assert(MacroAt(i), "no macro " .. tostring(i))
	end

	-- The /macro window (Blizzard_MacroUI.lua, MacroFrameMixin), as far as Clicky drives it.
	-- Blizzard_MacroUI is load-on-demand: ShowMacroFrame loads it and shows MacroFrame
	-- (Blizzard_MacroUI_Bootstrap.lua), and showing it runs OnShow: ChangeTab(1).
	-- MacroFrameText's OnTextChanged sets MacroFrame.textChanged for any SetText, so SelectMacro
	-- marks the text changed too (Blizzard_MacroUI.xml).
	local function ChangeTab(frame, tabID)
		env.PanelTemplates_SetTab(frame, tabID)
		frame:SaveMacro()
		frame.macroBase = tabID == 1 and 0 or MAX_ACCOUNT
		frame:SelectMacro(1, true)
	end
	local function NewMacroFrame()
		local frame = { shown = false, macroBase = 0, selectedIndex = 1, ChangeTab = ChangeTab }
		frame.GetSelectedIndex = function(f) return f.selectedIndex end
		frame.SaveMacro = function(f)
			if f.textChanged and f.selectedIndex ~= nil then
				env.EditMacro(f.macroBase + f.selectedIndex, nil, nil, env.MacroFrameText:GetText())
				f:SelectMacro(f.selectedIndex)
				f.textChanged = nil
			end
		end
		frame.SelectMacro = function(f, index)
			if index then
				local general, character = env.GetNumMacros()
				if (f.macroBase == 0 and general or character) < index then
					index = nil
				end
			end
			f.selectedIndex = index or 1
			if index then
				local name, _, body = env.GetMacroInfo(f.macroBase + index)
				if name then
					env.MacroFrameText:SetText(body)
				end
			end
		end
		return frame
	end
	env.ShowMacroFrame = function()
		if not env.MacroFrame then
			env.MacroFrame = NewMacroFrame()
			env.MacroPopupFrame = { Hide = function() end }
			env.MacroFrameText = {
				text = "",
				GetText = function(t) return t.text end,
				SetText = function(t, text)
					t.text = text
					env.MacroFrame.textChanged = 1
				end,
				ClearFocus = function() end,
			}
		end
		if not env.MacroFrame.shown then
			env.MacroFrame.shown = true
			ChangeTab(env.MacroFrame, 1)
		end
	end
end

-- Loads the addon's files in .toc order into this world, as the game does.
function World:LoadAddon()
	local toc = assert(io.open(ROOT .. "/Clicky.toc"))
	local ns = {}
	self.ns = ns
	self.toc = {}
	for line in toc:lines() do
		line = strtrim(line)
		local field, value = line:match("^## ([^:]+): (.*)$")
		if field then
			self.toc[field] = value
		elseif line == "ToyList.lua" then
			ns.TOY_IDS, ns.TOY_LIST_BUILD, ns.TOY_HIDDEN = self.toyList, "test", self.toyHidden
			ns.MOUNT_HIDDEN, ns.PET_HIDDEN, ns.PET_RANDOM_LOOK = self.mountHidden, self.petHidden, self.petRandomLook
			ns.TOY_SOURCE, ns.PET_SOURCE, ns.MOUNT_TYPE = self.toySource, self.petSource, self.mountType
		elseif line ~= "" and not line:find("^#") then
			local chunk = assert(loadfile(ROOT .. "/" .. line))
			setfenv(chunk, self.env)
			chunk(ADDON, ns)
		end
	end
	toc:close()
end

return wow
