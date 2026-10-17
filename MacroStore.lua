-- Where Clicky's macros live: the player's macros, which WoW keeps on its servers per account and
-- syncs to every computer. This file reads them, builds their bodies, and creates, edits and
-- deletes them; Macros.lua decides what to write. Macros can't be created, edited or deleted in
-- combat; callers check first.
--   ns.ReadMacros()      records (see below)
--   ns.FindFavoritesMacro(), ns.PickupFavoritesMacro()
--   ns.CreateGeneralMacro(name, icon, body)   -> index | nil, reason
--   ns.EditMacroAt(index, name, icon, body)   -> index | nil, reason
--   ns.DeleteMacroAt(index)
--   ns.MACRO_BODY_LIMIT, ns.ClickLine(id), ns.NewBody(id, data), ns.SetDataLine(body, data),
--   ns.SetButtonID(body, oldID, newID), ns.ParseBody(body), ns.TruncateMacroName(name)
--                        game-independent; on ns so offline tests can reach them
--
-- A Clicky macro's body is
--   /click [nocombat] ClickySet<id>
--   #clicky <data>
-- plus any lines the player adds. Lines starting with "#" aren't run, so the data line is inert.
-- The /click line is what players' bars depend on and is never rewritten, except to give a
-- copied macro a button of its own.

local _, ns = ...

local MACRO_NAME_LIMIT = 16
-- MacroFrameText has letters="255" (Blizzard_MacroUI.xml), and EditMacro truncates longer bodies.
local MACRO_BODY_LIMIT = 255
local DATA_PREFIX = "#clicky "
local FULL_ERROR = "Your general macros are full. Delete one in /macro and try again."

-- Macro names are capped; cut on a character boundary rather than mid-way through one.
local function TruncateMacroName(name)
	if #name <= MACRO_NAME_LIMIT then
		return name
	end
	local cut = MACRO_NAME_LIMIT
	while cut > 0 do
		local nextByte = name:byte(cut + 1)
		if not nextByte or nextByte < 0x80 or nextByte >= 0xC0 then
			break
		end
		cut = cut - 1
	end
	return name:sub(1, cut)
end

local function ClickLine(id)
	return "/click [nocombat] " .. ns.SET_BUTTON_PREFIX .. id
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

-- The id of the first ClickySet button a /click line in body clicks, and the data line's data.
local function ParseBody(body)
	local id, data
	for _, line in ipairs(Lines(body or "")) do
		if not id and IsClickLine(line) then
			local n = line:match(ns.SET_BUTTON_PREFIX .. "(%d+)%f[%W]")
			id = tonumber(n)
		end
		if not data and line:sub(1, #DATA_PREFIX) == DATA_PREFIX then
			data = strtrim(line:sub(#DATA_PREFIX + 1))
		end
	end
	return id, data
end

-- Replaces the data line, or adds one after the first /click line.
local function SetDataLine(body, data)
	local lines, at = Lines(body), nil
	for i, line in ipairs(lines) do
		if line:sub(1, #DATA_PREFIX) == DATA_PREFIX then
			lines[i] = DATA_PREFIX .. data
			return table.concat(lines, "\n")
		end
		if not at and IsClickLine(line) then
			at = i
		end
	end
	table.insert(lines, (at or 0) + 1, DATA_PREFIX .. data)
	return table.concat(lines, "\n")
end

local function SetButtonID(body, oldID, newID)
	local lines = Lines(body)
	local pattern = ns.SET_BUTTON_PREFIX .. oldID .. "%f[%W]"
	for i, line in ipairs(lines) do
		if IsClickLine(line) then
			lines[i] = line:gsub(pattern, ns.SET_BUTTON_PREFIX .. newID)
		end
	end
	return table.concat(lines, "\n")
end

ns.MACRO_BODY_LIMIT = MACRO_BODY_LIMIT
ns.TruncateMacroName = TruncateMacroName
ns.ClickLine = ClickLine
ns.NewBody = NewBody
ns.ParseBody = ParseBody
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
-- Favorites' macro has no data: its toys are the Toy Box stars.

local FAVORITES_BODY = "/click [nocombat] " .. ns.FAVORITES_BUTTON

function ns.FindFavoritesMacro()
	for index = 1, GetNumMacros() do
		local _, _, body = GetMacroInfo(index)
		if body and strtrim(body) == FAVORITES_BODY then
			return index
		end
	end
	return nil
end

function ns.PickupFavoritesMacro()
	local index = ns.FindFavoritesMacro()
	if not index then
		local err
		index, err = ns.CreateGeneralMacro(ns.FAVORITES_MACRO, ns.FAVORITES_ICON, FAVORITES_BODY)
		if not index then
			ns.ShowError(err)
			return
		end
	end
	ns.Trace("[macro Favorites] picked up %d", index)
	PickupMacro(index)
end
