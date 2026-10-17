-- Stubs of the WoW API Clicky calls, for running its real files under LuaJIT (Lua 5.1, like WoW).
--
-- wow.New(options) builds a fresh, isolated world: one login on one computer, with its own
-- globals, events and SavedVariables. What WoW keeps on its servers per account (toys, macros,
-- action bars) lives in world.account, which another world can share to play the same account on
-- a second computer: wow.New({ account = world.account }). It loads the files listed in
-- Clicky.toc as the game does (each file gets ("Clicky", ns)) and fires the login events.
--
-- Only game state is stubbed: toys, macros, action bars running /click lines, secure buttons,
-- combat lockdown and events, each following Blizzard's documentation or UI source (cited where
-- it matters). Blizzard's UI (the Toy Box, menus, dialogs, scroll lists, tooltips) isn't: tests
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

local function NewFrame(world, name, template)
	local frame = setmetatable({ world = world, name = name, scripts = {}, attributes = {} }, Frame)
	if template == "SecureActionButtonTemplate" then
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
function Frame:IsVisible() return false end

function Frame:RegisterEvent(event)
	self.world.eventFrames[self] = self.world.eventFrames[self] or {}
	self.world.eventFrames[self][event] = true
end

function Frame:UnregisterEvent(event)
	if self.world.eventFrames[self] then
		self.world.eventFrames[self][event] = nil
	end
end

-- Secure attributes are locked in combat for protected frames.
function Frame:SetAttribute(key, value)
	if self.protected and self.world.combat then
		error("ADDON_ACTION_BLOCKED: SetAttribute on " .. tostring(self.name) .. " in combat", 2)
	end
	self.attributes[key] = value
end

function Frame:GetAttribute(key) return self.attributes[key] end

-- A click: PreClick, the secure action, PostClick. SecureActionButton_OnClick acts on the down
-- click when useOnKeyDown is on and the up click otherwise; with the attribute unset it follows
-- the ActionButtonUseKeyDown setting (SecureTemplates.lua, SecureActionButton_ShouldUseOnKeyDown).
function Frame:Click(button, down)
	if self.scripts.PreClick then self.scripts.PreClick(self, button, down) end
	local a = self.attributes
	local useOnKeyDown = a.useOnKeyDown
	if useOnKeyDown == nil then
		useOnKeyDown = self.world.cvars.ActionButtonUseKeyDown
	end
	if (down and useOnKeyDown) or (not down and not useOnKeyDown) then
		if a.type == "toy" and a.toy then
			self.world:UseToy(a.toy)
		end
	end
	if self.scripts.PostClick then self.scripts.PostClick(self, button, down) end
end

------------------------------------------------------------------------------------------
-- The world.

local World = {}
World.__index = World

-- options.toys: list of { id, name, icon, owned = true, usable = true, favorite, cooldown }
-- options.saved: ClickyDB as it was saved; options.macros: list of { name, icon, body }
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
		failHere = {},
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
	world.env.ClickyDB = options.saved
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
	local m = assert(self.macros[index], "no macro " .. tostring(index))
	m.name, m.body = name or m.name, (body or m.body):sub(1, 255)
	self:Fire("UPDATE_MACROS")
end

function World:CreateMacroInUI(name, body, perCharacter)
	table.insert(perCharacter and self.characterMacros or self.macros, { name = name, body = body })
	self:Fire("UPDATE_MACROS")
	return perCharacter and self.characterMacros[#self.characterMacros] or self.macros[#self.macros]
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

function World:EnterCombat()
	self.combat = true
	self:Fire("PLAYER_REGEN_DISABLED")
end

function World:LeaveCombat()
	self.combat = false
	self:Fire("PLAYER_REGEN_ENABLED")
end

function World:ChangeZone() self:Fire("ZONE_CHANGED_NEW_AREA") end
function World:Advance(seconds) self.time = self.time + seconds end

-- The game using a toy. Toys marked with FailHere produce a UI error, as an unusable-here toy does.
function World:UseToy(itemID)
	table.insert(self.used, itemID)
	if self.failHere[itemID] then
		self:Fire("UI_ERROR_MESSAGE", 0, "secret")
	end
end

function World:FailHere(itemID) self.failHere[itemID] = true end
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

-- Presses an action bar slot holding a macro: runs its /click lines, honouring [nocombat], with
-- the up click /click sends. Returns false if the slot is empty.
function World:PressBar(slot)
	local macro = self.bars[slot]
	if not macro then
		return false
	end
	for line in macro.body:gmatch("[^\n]+") do
		local conditions, target = line:match("^/click%s*%[(.-)%]%s*(%S+)")
		if not target then
			target = line:match("^/click%s+(%S+)")
		end
		local blocked = conditions and conditions:find("nocombat") and self.combat
		if target and not blocked and self.env[target] then
			self.env[target]:Click("LeftButton", false)
		end
	end
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
	env.CreateFrame = function(_, name, _, template) return NewFrame(world, name, template) end
	env.C_AddOns = { IsAddOnLoaded = function() return false end }
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
		assert(#name <= 16, "macro name longer than 16 characters: " .. name)
		local list = perCharacter and world.characterMacros or world.macros
		assert(perCharacter or #list < MAX_ACCOUNT, "general macros are full")
		table.insert(list, { name = name, icon = icon, body = body:sub(1, 255) })
		world:Fire("UPDATE_MACROS")
		return perCharacter and MAX_ACCOUNT + #list or #list
	end
	env.EditMacro = function(i, name, icon, body)
		NoCombat("EditMacro")
		local m = assert(MacroAt(i), "no macro " .. tostring(i))
		assert(#name <= 16, "macro name longer than 16 characters: " .. name)
		m.name, m.icon, m.body = name, icon or m.icon, body and body:sub(1, 255) or m.body
		world:Fire("UPDATE_MACROS")
		return i
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
	for line in toc:lines() do
		line = strtrim(line)
		if line ~= "" and not line:find("^#") then
			local chunk = assert(loadfile(ROOT .. "/" .. line))
			setfenv(chunk, self.env)
			chunk(ADDON, ns)
		end
	end
	toc:close()
end

-- Saved variables, as written on logout.
function World:Saved()
	return self.env.ClickyDB
end

return wow
