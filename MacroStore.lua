-- Where Clicky's macros live: the player's macros, which WoW keeps on its servers per account and
-- syncs to every computer. This file reads them, builds their bodies, and creates, edits and
-- deletes them; Macros.lua decides what to write. Macros can't be created, edited or deleted in
-- combat; callers check first.
--   ns.ReadMacros()      records (see below)
--   ns.FindFavoritesMacro()                   -> { index, name, icon, body } | nil
--   ns.MakeFavoritesMacro(name)               -> index | nil, reason
--   ns.CreateGeneralMacro(name, icon, body)   -> index | nil, reason
--   ns.EditMacroAt(index, name, icon, body)   -> index | nil, reason
--   ns.DeleteMacroAt(index)
--   ns.NewBody(id, data), ns.SetDataLine(body, data), ns.SetButtonID(body, oldID, newID),
--   ns.TruncateMacroName(name)                game-independent
--   ns.MACRO_BODY_LIMIT, ns.ClickLine(id)   for tests
--
-- A Clicky macro's body is
--   /click [btn:2]ClickyP<id>;ClickySet<id>
--   #clicky <data>
-- plus any lines the player adds. The data line does nothing when the macro runs (seen in play).
-- /click with no mouse button clicks with "LeftButton" (SlashCommands.lua, SLASH_COMMAND.CLICK),
-- so [btn:2] is the button the player clicked the macro with: a right-click goes to ClickyP<id>,
-- which opens the macro's drawer (Drawer.lua), anything else to ClickySet<id>, which uses a toy.
-- Favorites' macro is the general macro whose line is /click [btn:2]ClickyP0;ClickyButton, with no
-- data line. The /click line is what players' bars depend on: it's only rewritten to give a copied
-- macro buttons of its own.

local _, ns = ...

local MACRO_NAME_LIMIT = 16
-- MacroFrameText has letters="255" (Blizzard_MacroUI.xml), and EditMacro saves only the first 255
-- characters (warcraft.wiki.gg API EditMacro).
local MACRO_BODY_LIMIT = 255
local DATA_PREFIX = "#clicky "
local FULL_ERROR = "Your general macros are full. Delete one in /macro and try again."

-- Macro names are capped at 16 characters: /macro's name box has letters="16"
-- (SharedUIPanelTemplates.xml) and passes what it holds to CreateMacro and EditMacro.
local function TruncateMacroName(name)
	local letters = 0
	for at = 1, #name do
		local byte = name:byte(at)
		-- A UTF-8 character starts with any byte but a continuation byte (0x80-0xBF).
		if byte < 0x80 or byte >= 0xC0 then
			letters = letters + 1
			if letters > MACRO_NAME_LIMIT then
				return name:sub(1, at - 1)
			end
		end
	end
	return name
end

local function ClickLine(id)
	return ("/click [btn:2]%s%d;%s%d"):format(ns.DRAWER_BUTTON_PREFIX, id, ns.SET_BUTTON_PREFIX, id)
end

local function NewBody(id, data)
	return ClickLine(id) .. "\n" .. DATA_PREFIX .. data
end

local function Lines(body)
	local lines = {}
	for line in (body .. "\n"):gmatch("([^\n]*)\n") do
		lines[#lines + 1] = line
	end
	return lines
end

local function IsClickLine(line)
	return line:find("^%s*/click") ~= nil
end

-- ParseBody reads ids with tonumber, so "ClickySet01" is id 1 and must match here too.
local function ButtonPattern(prefix, id)
	return prefix .. "0*" .. id .. "%f[%W]"
end

-- The id of the first ClickySet button a /click line in body clicks, and the data line's data.
local function ParseBody(body)
	local id, data
	for _, line in ipairs(Lines(body or "")) do
		if not id and IsClickLine(line) then
			id = tonumber(line:match(ns.SET_BUTTON_PREFIX .. "(%d+)%f[%W]"))
		end
		if not data and line:sub(1, #DATA_PREFIX) == DATA_PREFIX then
			data = strtrim(line:sub(#DATA_PREFIX + 1))
		end
	end
	return id, data
end

-- Replaces the data line, or adds one after the first /click line; data nil removes it.
local function SetDataLine(body, data)
	local lines, at = Lines(body), nil
	for i, line in ipairs(lines) do
		if line:sub(1, #DATA_PREFIX) == DATA_PREFIX then
			if data then
				lines[i] = DATA_PREFIX .. data
			else
				table.remove(lines, i)
			end
			return table.concat(lines, "\n")
		end
		if not at and IsClickLine(line) then
			at = i
		end
	end
	if data then
		table.insert(lines, (at or 0) + 1, DATA_PREFIX .. data)
	end
	return table.concat(lines, "\n")
end

local function SetButtonID(body, oldID, newID)
	local lines = Lines(body)
	for i, line in ipairs(lines) do
		if IsClickLine(line) then
			line = line:gsub(ButtonPattern(ns.SET_BUTTON_PREFIX, oldID), ns.SET_BUTTON_PREFIX .. newID)
			lines[i] = line:gsub(ButtonPattern(ns.DRAWER_BUTTON_PREFIX, oldID), ns.DRAWER_BUTTON_PREFIX .. newID)
		end
	end
	return table.concat(lines, "\n")
end

ns.MACRO_BODY_LIMIT = MACRO_BODY_LIMIT
ns.TruncateMacroName = TruncateMacroName
ns.ClickLine = ClickLine
ns.NewBody = NewBody
ns.SetDataLine = SetDataLine
ns.SetButtonID = SetButtonID

------------------------------------------------------------------------------------------
-- Reading: every general macro (indexes 1..numAccount) with a #clicky line and a ClickySet
-- /click line, in index order, as { index, name, icon, body, id, data }.

function ns.ReadMacros()
	local records = {}
	for index = 1, GetNumMacros() do
		local name, icon, body = GetMacroInfo(index)
		local id, data = ParseBody(body)
		if id and data then
			records[#records + 1] = { index = index, name = name, icon = icon, body = body, id = id, data = data }
		end
	end
	return records
end

------------------------------------------------------------------------------------------
-- Writing. Each returns the macro's index, or nil and the reason to show the player.

local function Fits(body)
	if #body > MACRO_BODY_LIMIT then
		return nil, "That macro is too long to update. Remove your own lines from it in /macro."
	end
	return true
end

function ns.CreateGeneralMacro(name, icon, body)
	local ok, err = Fits(body)
	if not ok then
		return nil, err
	end
	local numAccount = GetNumMacros()
	if numAccount >= Constants.MacroConsts.MAX_ACCOUNT_MACROS then
		ns.Trace("[macro %s] general macros full (%d)", name, numAccount)
		return nil, FULL_ERROR
	end
	local index = CreateMacro(TruncateMacroName(name), icon, body)
	ns.Trace("[macro %s] created %s", name, index)
	return index
end

function ns.EditMacroAt(index, name, icon, body)
	local ok, err = Fits(body)
	if not ok then
		ns.Trace("[macro %s] edit refused: body %d characters", name, #body)
		return nil, err
	end
	local newIndex = EditMacro(index, TruncateMacroName(name), icon, body)
	ns.Trace("[macro %s] edited %d, now %s, body %d characters", name, index, newIndex, #body)
	return newIndex
end

function ns.DeleteMacroAt(index)
	DeleteMacro(index)
	ns.Trace("[macro] deleted %d", index)
end

------------------------------------------------------------------------------------------
-- Favorites' macro: found by its /click line, whatever its name.

local FAVORITES_LINE = ("/click [btn:2]%s0;%s"):format(ns.DRAWER_BUTTON_PREFIX, ns.FAVORITES_BUTTON)

function ns.FindFavoritesMacro()
	for index = 1, GetNumMacros() do
		local name, icon, body = GetMacroInfo(index)
		for _, line in ipairs(Lines(body or "")) do
			if strtrim(line) == FAVORITES_LINE then
				return { index = index, name = name, icon = icon, body = body }
			end
		end
	end
	return nil
end

function ns.MakeFavoritesMacro(name)
	return ns.CreateGeneralMacro(name, ns.FAVORITES_ICON, FAVORITES_LINE)
end
