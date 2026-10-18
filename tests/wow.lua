-- Stubs of the WoW API Clicky calls, for running its real files under LuaJIT (Lua 5.1, like WoW).
--
-- wow.New(options) builds a fresh, isolated world: one login on one computer, with its own
-- globals and events. What WoW keeps on its servers per account (toys, macros,
-- action bars) lives in world.account, which another world can share to play the same account on
-- a second computer: wow.New({ account = world.account }). It loads the files listed in
-- Clicky.toc as the game does (each file gets ("Clicky", ns)) and fires the login events.
--
-- Only game state is stubbed: toys, macros, action bars running /click lines (with macro
-- conditionals and the mouse button), secure buttons and their modified attributes, secure
-- snippets in a restricted-like environment, modifier keys, auto-hiding frames, timers, combat
-- lockdown and events, each following Blizzard's documentation or UI source (cited where it
-- matters). Blizzard's UI (the Toy Box, menus, dialogs, scroll lists, tooltips) isn't: tests
-- call the functions Clicky's UI is built on (the Macros API, ns.PanelRows, ns.ToyMenuEntries),
-- and the UI itself is checked by playing. tests/check_api.py checks every API Clicky calls
-- exists.

local wow = {}

local ADDON = "Clicky"
local ROOT = (debug.getinfo(1, "S").source:match("^@(.*)/tests/wow%.lua$") or ".")
local MAX_ACCOUNT = 120 -- MacroConstantsDocumentation.lua
local MAX_CHARACTER = 30

local function strtrim(s)
	return (s:gsub("^%s+", ""):gsub("%s+$", ""))
end

------------------------------------------------------------------------------------------
-- Frames. Methods Clicky calls only for layout and looks (SetPoint, CreateTexture...) are
-- accepted and do nothing.

local Frame = {}

Frame.__index = function(self, key)
	local method = rawget(Frame, key)
	if method then
		return method
	end
	if type(key) == "string" and key:find("^%u") then
		return function() return self end
	end
end

-- Templates that make a frame protected: each inherits SecureFrameTemplate (protected="true",
-- SecureTemplatesBase.xml).
local PROTECTED = {
	SecureFrameTemplate = true,
	SecureActionButtonTemplate = true, -- SecureTemplates.xml
	SecureHandlerBaseTemplate = true, -- SecureHandlerTemplates.xml
	SecureHandlerClickTemplate = true,
	SecureHandlerShowHideTemplate = true,
}

-- Characters in a UTF-8 string. Macro names hold 16 (the /macro name box has letters="16",
-- SharedUIPanelTemplates.xml), whatever their bytes.
local function Letters(s)
	return select(2, s:gsub("[^\128-\191]", ""))
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

local function NewFrame(world, name, parent, template)
	local frame = setmetatable({ world = world, name = name, parent = parent, template = template,
		scripts = {}, attributes = {}, wraps = {}, shown = true }, Frame)
	if PROTECTED[template] then
		if world.combat then
			error("ADDON_ACTION_BLOCKED: CreateFrame of a protected frame in combat", 3)
		end
		frame.protected = true
	end
	if name then
		world.env[name] = frame
	end
	return frame
end

function Frame:SetScript(script, fn) self.scripts[script] = fn end
function Frame:IsProtected() return self.protected or false, self.protected or false end

local RunSnippet

-- Showing or hiding: SecureHandlerShowHideTemplate's OnShow and OnHide run its _onshow and
-- _onhide snippets (SecureHandlerTemplates.xml, SecureHandler_OnSimpleEvent). A hidden frame
-- leaves auto-hide.
local function SetShown(frame, shown)
	if frame.shown == shown then return end
	frame.shown = shown
	if not shown then frame.autoHide = nil end
	local snippet = frame.template == "SecureHandlerShowHideTemplate"
		and frame.attributes[shown and "_onshow" or "_onhide"]
	if snippet then RunSnippet(frame.world, frame, snippet) end
end

-- Addon code can't show or hide a protected frame in combat; secure snippets can.
function Frame:Show()
	if self.protected and self.world.combat then
		error("ADDON_ACTION_BLOCKED: Show on a protected frame in combat", 2)
	end
	SetShown(self, true)
end

function Frame:Hide()
	if self.protected and self.world.combat then
		error("ADDON_ACTION_BLOCKED: Hide on a protected frame in combat", 2)
	end
	SetShown(self, false)
end

function Frame:IsShown() return self.shown end
function Frame:IsVisible() return false end -- nothing Clicky draws is on screen in the tests
function Frame:SetShown(shown) if shown then self:Show() else self:Hide() end end

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
-- SecureHandlers.lua; a snippet returning false stops the click), the template's OnClick,
-- PostClick. SecureActionButton_OnClick acts on the down click when useOnKeyDown is on and the up
-- click otherwise; with the attribute unset it follows the ActionButtonUseKeyDown setting
-- (SecureTemplates.lua, SecureActionButton_ShouldUseOnKeyDown), and SECURE_ACTIONS.toy uses the
-- modified "toy" attribute. SecureHandlerClickTemplate's OnClick runs its _onclick snippet
-- (SecureHandler_OnClick).
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
				if ModifiedAttribute(self, "type", button) == "toy" then
					local toy = ModifiedAttribute(self, "toy", button)
					if toy then world:UseToy(tonumber(toy) or toy) end
				end
			end
		elseif self.template == "SecureHandlerClickTemplate" and self.attributes._onclick then
			RunSnippet(world, self, self.attributes._onclick, button, down)
		end
	end
	if self.scripts.PostClick then self.scripts.PostClick(self, button, down) end
end

------------------------------------------------------------------------------------------
-- The world.

local World = {}
World.__index = World

-- options.toys: list of { id, name, icon, owned = true, usable = true, favorite, cooldown }
-- options.macros: list of { name, icon, body }
-- options.account: another world's account, instead of toys and macros
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
		keys = {}, -- modifier keys held: alt, ctrl, shift
		timers = {}, -- C_Timer.After callbacks waiting
		overrides = {}, -- frame -> key -> override binding, for this session only
	}, World)
	local account = options.account
	if not account then
		account = { toys = {}, toyOrder = {}, macros = {}, characterMacros = {}, bars = {} }
		world.account = account
		for _, toy in ipairs(options.toys or {}) do
			world:AddToy(toy)
		end
		for _, macro in ipairs(options.macros or {}) do
			table.insert(account.macros, { name = macro.name, icon = macro.icon, body = macro.body })
		end
	end
	world.account = account
	world.toys, world.toyOrder, world.macros, world.bars = account.toys, account.toyOrder, account.macros, account.bars
	world.characterMacros = account.characterMacros
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

-- Learning a toy: NEW_TOY_ADDED, then TOYS_UPDATED with itemID and isNew
-- (ToyBoxInfoDocumentation.lua).
function World:LearnToy(toy)
	if not self.toys[toy.id] then
		self:AddToy(toy)
	end
	self.toys[toy.id].owned = true
	self:Fire("NEW_TOY_ADDED", toy.id)
	self:Fire("TOYS_UPDATED", toy.id, true)
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
	}
	self.account.toys[t.id] = t
	table.insert(self.account.toyOrder, t.id)
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

-- The player editing macros in /macro, which saves through EditMacro and CreateMacro; bodies are
-- cut to 255 characters (MacroFrameText letters="255").
function World:EditMacroInUI(index, name, body)
	assert(not self.combat, "/macro can't save in combat: EditMacro is nocombat (warcraft.wiki.gg API EditMacro)")
	local m = assert(self.macros[index], "no macro " .. tostring(index))
	m.name, m.body = name or m.name, (body or m.body):sub(1, 255)
	SortMacros(self.macros, m)
	self:Fire("UPDATE_MACROS")
end

function World:CreateMacroInUI(name, body, perCharacter)
	assert(not self.combat, "/macro can't save in combat: CreateMacro is nocombat (warcraft.wiki.gg API CreateMacro)")
	local macros = perCharacter and self.characterMacros or self.macros
	local m = { name = name, body = body }
	m.body = body:sub(1, 255) -- MacroFrameText letters="255" (Blizzard_MacroUI.xml)
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

-- The game using a toy.
function World:UseToy(itemID)
	table.insert(self.used, itemID)
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

function World:LastError() return self.errors[#self.errors] end

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

function World:BuildEnv()
	local world = self
	local env = setmetatable({}, { __index = _G })
	self.env = env
	env._G = env
	env.strtrim = strtrim
	env.wipe = function(t) for k in pairs(t) do t[k] = nil end return t end
	env.print = function(...)
		local parts = {}
		for i = 1, select("#", ...) do parts[i] = tostring((select(i, ...))) end
		table.insert(world.prints, table.concat(parts, " "))
	end
	env.GetTime = function() return world.time end
	env.debugprofilestop = function() return world.time * 1000 end
	env.InCombatLockdown = function() return world.combat end
	env.SlashCmdList = {}
	env.UIParent = NewFrame(world)
	env.UIErrorsFrame = { AddExternalErrorMessage = function(_, msg) table.insert(world.errors, msg) end }
	world.frames = {}
	env.CreateFrame = function(_, name, parent, template)
		local frame = NewFrame(world, name, parent, template)
		table.insert(world.frames, frame)
		return frame
	end
	env.C_Timer = { After = function(delay, fn) table.insert(world.timers, { at = world.time + delay, fn = fn }) end }
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
		IsAddOnLoaded = function() return false end,
		GetAddOnMetadata = function(_, field) return world.toc[field] end,
	}
	env.Menu = { ModifyMenu = function() end }
	env.StaticPopupDialogs = {}

	-- Toys. GetToyLink answers for any toy in the game, owned or not, and nil for an item that
	-- isn't one (warcraft.wiki.gg API_C_ToyBox.GetToyLink).
	env.C_ToyBox = {
		GetToyLink = function(id)
			return world.toys[id] and ("|cffffffff|Hitem:" .. id .. "::::::::::::|h[" .. world.toys[id].name .. "]|h|r") or nil
		end,
		GetToyInfo = function(id)
			local t = world.toys[id]
			if t then return id, t.name, t.icon end
		end,
		GetNumToys = function() return #world.toyOrder end,
		GetNumFilteredToys = function() return #world.toyOrder end,
		HasFavorites = function()
			for _, t in pairs(world.toys) do if t.favorite then return true end end
			return false
		end,
		GetIsFavorite = function(id) return world.toys[id] and world.toys[id].favorite or false end,
		-- The Toy Box's own favorite menu (Blizzard_ToyBox.lua) calls this and doesn't refresh
		-- itself: the game fires TOYS_UPDATED.
		SetIsFavorite = function(id, v) world.toys[id].favorite = v; world:Fire("TOYS_UPDATED", id, false) end,
		IsToyUsable = function(id) return world.toys[id] and world.toys[id].usable or false end,
	}
	env.PlayerHasToy = function(id)
		return world.toysLoaded and world.toys[id] and world.toys[id].owned or false
	end
	-- startTime, duration, enable (ContainerDocumentation.lua).
	env.C_Container = {
		GetItemCooldown = function(id)
			local cd = world.toys[id] and world.toys[id].cooldown or 0
			if cd > 0 then return world.time - 1, cd + 1, 1 end
			return 0, 0, 1
		end,
	}
	env.C_Item = { RequestLoadItemDataByID = function() end }

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
		elseif line ~= "" and not line:find("^#") then
			local chunk = assert(loadfile(ROOT .. "/" .. line))
			setfenv(chunk, self.env)
			chunk(ADDON, ns)
		end
	end
	toc:close()
end

return wow
