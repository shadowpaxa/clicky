-- Where Clicky's macros live: the player's macros, which WoW keeps on its servers per account and
-- syncs to every computer. This file reads them, builds their bodies, and creates, edits and
-- deletes them; Macros.lua decides what to write. Macros can't be created, edited or deleted in
-- combat; callers check first.
--   ns.ReadMacros()      records (see below)
--   ns.FindFavoritesMacro()                   -> { index, name, icon, body, old } | nil
--   ns.MakeFavoritesMacro(name)               -> index | nil, reason
--   ns.CreateGeneralMacro(name, icon, body)   -> index | nil, reason
--   ns.EditMacroAt(index, name, icon, body)   -> index | nil, reason
--   ns.DeleteMacroAt(index)
--   ns.NewBody(id, data), ns.SetDataLine(body, data), ns.SetCode(body, oldID, newCode),
--   ns.ButtonName(id), ns.NewFavoritesBody(body), ns.TruncateMacroName(name)   game-independent
--   ns.CODE_LETTERS, ns.CODE_LENGTH           the letters and length of a macro's code
--   ns.IsFormat4ID(id)                        format 4: remove before the first full release
--   ns.MACRO_BODY_LIMIT, ns.ClickLine(id)     for tests
--
-- A Clicky macro's id is its code: four random capitals from CODE_LETTERS (Macros.lua draws it).
-- Its body is
--   /click [btn:2]ClickyP<code>;Clicky<code>
--   #clicky <data>
-- plus any lines the player adds; the /click line is a fixed 36 characters. The data line does
-- nothing when the macro runs (seen in play).
-- /click with no mouse button clicks with "LeftButton" (SlashCommands.lua, SLASH_COMMAND.CLICK),
-- so [btn:2] is the button the player clicked the macro with: a right-click goes to ClickyP<code>,
-- which opens the macro's drawer (Drawer.lua), anything else to Clicky<code>, which uses a toy.
-- Favorites' macro is the general macro whose line is /click [btn:2]ClickyPFVRT;ClickyFVRT, with
-- no data line (FVRT is its reserved code). The /click line is what players' bars depend on: it's
-- only rewritten to give a copied macro a code of its own, and once for each macro 0.4.0 wrote
-- (format 4), whose line was /click [btn:2]ClickyP<number>;ClickySet<number> (Favorites':
-- ClickyP0;ClickyButton); ParseBody and FindFavoritesMacro still read those, and the sync
-- (Macros.lua) rewrites them. Remove before the first full release.

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

local CODE_LETTERS = "BCDFGHJKLMNPQRSTVWXZ" -- consonants: a code can't spell a word
local CODE_LENGTH = 4
-- "Clicky" + a code + a non-word character. It can't match ClickyPanel, a drawer's name (five
-- capitals after "Clicky") or a format 4 name.
local CODE_PATTERN = "Clicky(" .. ("[" .. CODE_LETTERS .. "]"):rep(CODE_LENGTH) .. ")%f[%W]"
-- Format 4: remove before the first full release.
local FORMAT4_PATTERN = ns.SET_BUTTON_PREFIX .. "(%d+)%f[%W]"

-- A format 4 macro's id is its number as a string. Codes are letters, so they can't collide.
local function IsFormat4ID(id)
	return tostring(id):find("^%d+$") ~= nil
end

local function ButtonName(id)
	if IsFormat4ID(id) then
		return ns.SET_BUTTON_PREFIX .. id
	end
	return ns.BUTTON_PREFIX .. id
end

local function ClickLine(id)
	return ("/click [btn:2]%s%s;%s"):format(ns.DRAWER_BUTTON_PREFIX, id, ButtonName(id))
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

-- The id of the first Clicky button a /click line in body clicks (a code, or for format 4 the
-- number as a string), and the data line's data.
local function ParseBody(body)
	local id, data
	for _, line in ipairs(Lines(body or "")) do
		if not id and IsClickLine(line) then
			id = line:match(CODE_PATTERN) or line:match(FORMAT4_PATTERN)
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

-- Rewrites the toy and drawer button names in the /click lines from oldID's (whichever style) to
-- newCode's.
local function SetCode(body, oldID, newCode)
	local lines = Lines(body)
	for i, line in ipairs(lines) do
		if IsClickLine(line) then
			line = line:gsub(ButtonName(oldID) .. "%f[%W]", ButtonName(newCode))
			lines[i] = line:gsub(ns.DRAWER_BUTTON_PREFIX .. oldID .. "%f[%W]", ns.DRAWER_BUTTON_PREFIX .. newCode)
		end
	end
	return table.concat(lines, "\n")
end

ns.MACRO_BODY_LIMIT = MACRO_BODY_LIMIT
ns.TruncateMacroName = TruncateMacroName
ns.ClickLine = ClickLine
ns.NewBody = NewBody
ns.SetDataLine = SetDataLine
ns.SetCode = SetCode
ns.ButtonName = ButtonName
ns.IsFormat4ID = IsFormat4ID
ns.CODE_LETTERS = CODE_LETTERS
ns.CODE_LENGTH = CODE_LENGTH

------------------------------------------------------------------------------------------
-- Reading: every general macro (indexes 1..numAccount) with a #clicky line and a Clicky
-- /click line, in index order, as { index, name, icon, body, id, data }.

function ns.ReadMacros()
	local records = {}
	for index = 1, GetNumMacros() do
		local name, icon, body = GetMacroInfo(index)
		local id, data = ParseBody(body)
		-- A hand-typed Favorites line with a data line must not take Favorites' place.
		if id and data and id ~= ns.FAVORITES_ID then
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

local FAVORITES_LINE = ("/click [btn:2]%s%s;%s"):format(ns.DRAWER_BUTTON_PREFIX, ns.FAVORITES_ID, ns.FAVORITES_BUTTON)
-- Format 4's (remove before the first full release).
local OLD_FAVORITES_LINE = ("/click [btn:2]%s0;%s"):format(ns.DRAWER_BUTTON_PREFIX, ns.OLD_FAVORITES_BUTTON)

-- old is true if the macro still has format 4's line, which the sync rewrites.
function ns.FindFavoritesMacro()
	for index = 1, GetNumMacros() do
		local name, icon, body = GetMacroInfo(index)
		for _, line in ipairs(Lines(body or "")) do
			local trimmed = strtrim(line)
			if trimmed == FAVORITES_LINE or trimmed == OLD_FAVORITES_LINE then
				return { index = index, name = name, icon = icon, body = body, old = trimmed == OLD_FAVORITES_LINE }
			end
		end
	end
	return nil
end

-- body with format 4's Favorites line replaced by the current one.
function ns.NewFavoritesBody(body)
	local lines = Lines(body)
	for i, line in ipairs(lines) do
		if strtrim(line) == OLD_FAVORITES_LINE then
			lines[i] = FAVORITES_LINE
		end
	end
	return table.concat(lines, "\n")
end

function ns.MakeFavoritesMacro(name)
	return ns.CreateGeneralMacro(name, ns.FAVORITES_ICON, FAVORITES_LINE)
end
