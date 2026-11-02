-- Clicky's macros: Favorites, plus every macro with a "#clicky" line. WoW keeps macros on its
-- servers (warcraft.wiki.gg Macro), so a macro is the only copy of its entries that every computer
-- sees: they're read from it (ns.Sync) and written back to it on every change. Each macro has a
-- hidden secure button its /click line clicks, and a drawer its right-click opens (Drawer.lua). A
-- click uses a random entry from the macro; the drawer uses the entry clicked in it. An entry is a
-- toy, a mount, a pet, a spell or an item, named by its key (Entries.lua), and what uses it is the
-- kind's secure action, except a pet, which PostClick summons from addon code (ns.UseEntry).
--   ns.expanded
--   ns.GetMacros(), ns.GetMacro(id)
--   ns.HasEntry(m, key), ns.MacroEntries(m)  the macro's entries (key -> true), not to be changed
--   ns.GetMacroEntries(m, all)             the keys the player has (all of them if all), by name
--   ns.NoEntriesMessage(m)                 why a click or right-click finds nothing to use
--   ns.MacroNoun(m)                        what the player's messages call m's entries: "toys" for
--                                          Favorites, which holds only toys, "items" for the rest
--   ns.GetCandidates(m, allowRepeat)       the keys a click can pick from now
--   ns.SetEntry(m, key, inMacro)           -> true | nil, reason   Favorites: a toy's star is set or
--                                          cleared (works in combat); anything else is refused
--   ns.MakeMacro(name, key)                -> macro | nil, reason
--   ns.RenameMacro(m, name), ns.DeleteMacro(m)   -> true | nil, reason
--   ns.SetMacroIcon(m, key)                -> true | nil, reason   m's icon in /macro becomes entry
--                                          key's; the macro's items and name stay as they are
--   ns.PickupMacro(m)                      puts the macro on the cursor
--   ns.OpenMacroInUI(m)                    opens /macro on General with the macro selected
--   ns.InMacroUI(m)                        whether the macro exists in /macro (Favorites' only
--                                          once made)
--   ns.COMBAT_ERROR                        why a change to a macro is refused in combat
--   ns.Unreadable(m)                       why m's entries can't be used or changed (for the
--                                          player), or nil
--   ns.Sync(reason)                        re-reads every macro and does any waiting work
--   ns.GetWaiting()                        what -> count of work waiting (for /clicky debug)
--
-- A runtime macro m has: id, name, icon, index, button, lastUsed (a key), data, and state:
--   "ready"      entries (key -> true) read from data
--   "newer"      saved by a newer Clicky, or holding an entry this Clicky's list doesn't have yet
--   "unreadable" damaged: anything but format 1
-- reason says why. Unreadable macros load nothing onto their buttons and can't have entries changed.
-- Favorites (id ns.FAVORITES_ID, builtin): its toys are the Toy Box stars, and its macro is found
-- by its /click line (ns.FindFavoritesMacro); it may not exist yet, and it holds no data.
-- A macro's id is its code (four random letters, NewCode).
--
-- Rules every write follows: nothing is written in combat (macros and secure attributes are
-- locked; the work waits for PLAYER_REGEN_ENABLED).

local _, ns = ...

ns.COMBAT_ERROR = "Can't change macros in combat."
local NEWER_MESSAGE = "This macro was saved by a newer version of Clicky. Update Clicky to use it."
local UNREADABLE_MESSAGE = "Clicky can't read this macro's items. Delete it and make it again."
local UNKNOWN_ENTRY_MESSAGE = "Clicky doesn't know this item yet. Update Clicky."
local EMPTY_MESSAGE = "%s has no items. Right-click a toy, mount, pet, spell or item in the Toy Box to add it."
local EMPTY_FAVORITES_MESSAGE = "%s has no toys. Star toys in the Toy Box to add them."

-- Runs inside the button's click, before the entry is used, in WoW's restricted environment. In
-- combat Clicky's own code can't set the button's action, so this picks an entry with random from
-- the list handed over on PLAYER_REGEN_DISABLED (readycount, and for each entry ready<i> its key
-- and readytype<i>, readyattr<i> and readyvalue<i> its secure action, none for an entry used from
-- code, ns.UsedFromCode), avoiding the last entry, and sets the button's type and the attribute
-- that type reads, as ns.SetButtonAction does (no type for an entry used from code: PostClick
-- uses it). Out of combat it does nothing: PreClick has already picked an entry, skipping
-- cooldowns. (The list isn't called toy1..n: a left click reads "toy1" before "toy".)
local COMBAT_PICK = [[
	local n = self:GetAttribute("readycount")
	if not n or SecureCmdOptionParse("[combat]1") ~= "1" then
		return
	end
	local last, skip = self:GetAttribute("lastentry"), 0
	if n > 1 then
		for i = 1, n do
			if self:GetAttribute("ready" .. i) == last then
				skip = i
			end
		end
	end
	local entry
	if n > 0 then
		local i = random(skip > 0 and n - 1 or n)
		if skip > 0 and i >= skip then
			i = i + 1
		end
		entry = self:GetAttribute("ready" .. i)
		local action = self:GetAttribute("readytype" .. i)
		self:SetAttribute("type", action)
		if action then
			self:SetAttribute(self:GetAttribute("readyattr" .. i), self:GetAttribute("readyvalue" .. i))
		end
	else
		self:SetAttribute("type", nil)
	end
	self:SetAttribute("entry", entry)
	self:SetAttribute("lastentry", entry)
]]

local favorites = {
	id = ns.FAVORITES_ID,
	icon = ns.FAVORITES_ICON,
	builtin = true,
	state = "ready",
}
favorites.name = ns.FAVORITES_MACRO
local macros = { [ns.FAVORITES_ID] = favorites }
-- id -> button. Buttons can't be destroyed, so an id's button outlives its macro (and is reused
-- if a macro is ever given that id again).
local buttons = {}
local waiting = {}
-- Macro id -> true for macros whose entries the panel shows. Everything starts collapsed each session.
ns.expanded = {}

local function HasEntry(m, key)
	return m.entries ~= nil and m.entries[key] == true
end
ns.HasEntry = HasEntry

-- The macro's entries (key -> true), for whoever needs to go through them: Favorites' are read
-- live from the stars, so starring needs no event; another macro's are the ones read from it. The
-- caller doesn't change it.
local function MacroEntries(m)
	if not m.builtin then
		return m.entries or {}
	end
	local entries = {}
	for _, itemID in ipairs(ns.GetToyList().ids) do
		if C_ToyBox.GetIsFavorite(itemID) then
			entries[itemID] = true
		end
	end
	return entries
end
ns.MacroEntries = MacroEntries

local function CountEntries(m)
	local n = 0
	for _ in pairs(MacroEntries(m)) do
		n = n + 1
	end
	return n
end

function ns.Unreadable(m)
	if m.state == "newer" then
		return NEWER_MESSAGE
	elseif m.state == "unreadable" then
		return UNREADABLE_MESSAGE
	end
end

-- Messages call what a macro holds "items": a toy, a mount, a pet, a spell or an item from the
-- bags. Favorites holds only toys (the Toy Box's stars), so its messages say "toys".
function ns.MacroNoun(m)
	return m.builtin and "toys" or "items"
end

-- Why a click, or a right-click for the drawer, finds nothing to use.
function ns.NoEntriesMessage(m)
	local empty = CountEntries(m) == 0 and (m.builtin and EMPTY_FAVORITES_MESSAGE or EMPTY_MESSAGE)
	return ns.Unreadable(m) or (empty or ("No usable " .. ns.MacroNoun(m) .. " in %s.")):format(m.name)
end

-- The macro's entries sorted by name: the ones the player has (the drawer), or all of them (the
-- panel, where an entry the player lacks can still be taken out).
function ns.GetMacroEntries(m, all)
	local keys = {}
	for key in pairs(MacroEntries(m)) do
		if all or ns.IsEntryOwned(key) then
			keys[#keys + 1] = key
		end
	end
	ns.SortEntries(keys)
	return keys
end

-- Don't repeat the macro's last entry unless it's the only choice.
local function DropRepeat(candidates, lastUsed)
	if #candidates > 1 and lastUsed then
		for i, key in ipairs(candidates) do
			if key == lastUsed then
				table.remove(candidates, i)
				break
			end
		end
	end
	return candidates
end

-- What a click can pick: entries the player has that can be used now, off cooldown, and not
-- drawer-only. In list order: pairs' order over string keys changes from run to run in LuaJIT,
-- which would make the same random numbers pick different entries (tests replay a seed).
local function GetCandidates(m, allowRepeat)
	local candidates = {}
	for key in pairs(MacroEntries(m)) do
		if ns.IsEntryOwned(key) and not ns.IsDrawerOnly(key) and ns.IsEntryUsable(key)
			and not ns.IsEntryOnCooldown(key) then
			candidates[#candidates + 1] = key
		end
	end
	local index = ns.GetToyList().index
	table.sort(candidates, function(a, b) return index[a] < index[b] end)
	if allowRepeat then
		return candidates
	end
	return DropRepeat(candidates, m.lastUsed)
end
ns.GetCandidates = GetCandidates

------------------------------------------------------------------------------------------
-- Buttons. Attributes on a secure button are locked in combat; every caller checks first.

-- PLAYER_REGEN_DISABLED, the last moment attributes can be set: the drawer gets the entries the
-- player has now, and the button the entries ready now, each with its secure action (none for an
-- entry used from code), for COMBAT_PICK.
local function ReadyForCombat(m)
	if not m.button or not m.setUp then
		return
	end
	local button = m.button
	for i = 1, button:GetAttribute("readycount") or 0 do
		for _, name in ipairs({ "ready", "readytype", "readyattr", "readyvalue" }) do
			button:SetAttribute(name .. i, nil)
		end
	end
	ns.FillDrawer(m)
	local ready = GetCandidates(m, true)
	for i, key in ipairs(ready) do
		local action, attribute, value
		if not ns.UsedFromCode(key) then
			action, attribute, value = ns.EntryAction(key)
		end
		button:SetAttribute("ready" .. i, key)
		button:SetAttribute("readytype" .. i, action)
		button:SetAttribute("readyattr" .. i, attribute)
		button:SetAttribute("readyvalue" .. i, value)
	end
	button:SetAttribute("readycount", #ready)
	button:SetAttribute("lastentry", m.lastUsed)
	ns.Trace("[%s] %d entries ready for combat", m.name, #ready)
end

local function SetUpButton(m)
	if InCombatLockdown() or not m.button then
		return
	end
	-- /click sends an "up" click. Without this, players with the default "cast on key down"
	-- setting would get a button that silently does nothing.
	m.button:SetAttribute("useOnKeyDown", false)
	ns.SetUpDrawer(m)
	ns.QueueDrawer(m)
	m.setUp = true
end

local function EmptyButton(button)
	ns.SetButtonAction(button, nil, "type")
	button:SetAttribute("entry", nil)
	button:SetAttribute("readycount", nil)
end

-- The button looks its macro up by id on every click, since the runtime macro behind an id can
-- be replaced (a macro deleted, another given the same code).
local function CreateButton(id)
	local button = CreateFrame("Button", ns.ButtonName(id), UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetScript("PreClick", function(_, mouseButton, down)
		local m = macros[id]
		if not m then
			return
		end
		ns.Trace("[%s] PreClick %s down=%s", m.name, mouseButton, down)
		-- In combat the button's attributes are locked: COMBAT_PICK picks.
		if not InCombatLockdown() then
			local candidates = GetCandidates(m)
			local key = #candidates > 0 and candidates[math.random(#candidates)] or nil
			-- An entry used from code has no secure action: PostClick uses it.
			ns.SetButtonAction(button, key and not ns.UsedFromCode(key) and key or nil, "type")
			button:SetAttribute("entry", key)
			ns.Trace("[%s] %d candidates, picked %s", m.name, #candidates, key)
		end
	end)
	SecureHandlerWrapScript(button, "OnClick", button, COMBAT_PICK)
	-- The entry used is the button's entry after the click: in combat, COMBAT_PICK chose it.
	button:SetScript("PostClick", function(self, _, down)
		local m = macros[id]
		if not m then
			return
		end
		local used = self:GetAttribute("entry")
		ns.Trace("[%s] PostClick, used %s", m.name, used)
		if not used then
			ns.ShowError(ns.NoEntriesMessage(m))
			return
		end
		m.lastUsed = used
		-- Only on the up click, the one a macro's /click sends (SlashCommands.lua): the button takes
		-- down clicks too (RegisterForClicks above), and a second summon would put the pet away.
		if not down and ns.UsedFromCode(used) then
			ns.Trace("[%s] using %s from code", m.name, used)
			ns.UseEntry(used)
		end
	end)
	ns.Trace("[button] created %s", ns.ButtonName(id))
	return button
end

-- Protected frames can't be created in combat; the button is made when combat ends.
local function BindButton(m)
	if not m.button then
		local button = buttons[m.id]
		if not button and not InCombatLockdown() then
			button = CreateButton(m.id)
			buttons[m.id] = button
		end
		m.button = button
		m.setUp = false
	end
	if m.button and not m.setUp then
		SetUpButton(m)
	end
	return m.button ~= nil
end

------------------------------------------------------------------------------------------
-- Reading and writing entries against Clicky's list (Toys.lua) with the codec (Codec.lua).

local function Encode(entries)
	local list = ns.GetToyList()
	local positions = {}
	for key in pairs(entries) do
		local p = list.index[key]
		if not p then
			return nil, UNKNOWN_ENTRY_MESSAGE
		end
		positions[#positions + 1] = p
	end
	table.sort(positions)
	return ns.EncodePlaces(positions)
end

local function CantRead(m, state, reason)
	m.state, m.reason, m.entries = state, reason, nil
	ns.Trace("[%s] can't read its entries (%s): %s", m.name, state, reason)
end

-- The entries at a format 1 macro's places in the list, or nil, why not, and the state it reads
-- as: a place past the list's end is an entry a newer list has.
local function ReadFormat1(d)
	local list = ns.GetToyList().entries
	local entries = {}
	for _, p in ipairs(d.positions) do
		local entry = list[p + 1]
		if not entry then
			return nil, ("place %d is past the end of this Clicky's list of %d entries"):format(p, #list), "newer"
		end
		entries[entry] = true
	end
	return entries
end

local function Decode(m, data)
	m.data, m.setUp = data, false
	local d, err = ns.DecodePlaces(data)
	if not d then
		return CantRead(m, err == "newer" and "newer" or "unreadable", err)
	end
	local entries, state
	entries, err, state = ReadFormat1(d)
	if not entries then
		return CantRead(m, state, err)
	end
	m.entries, m.state, m.reason = entries, "ready", nil
	if m.lastUsed and not entries[m.lastUsed] then
		m.lastUsed = nil
	end
	ns.Trace("[%s] read %d entries", m.name, #d.positions)
end

-- A new code: four random letters that aren't Favorites', and aren't the id of a macro bound or
-- just read (records: ns.ReadMacros()). Clicky keeps no saved data, so it can't know a deleted
-- macro's code: a new macro could draw it again (1 in 160,000 for a given one), which would
-- send a /click line the player copied from the deleted macro to the new one.
local function NewCode(records)
	local taken = {}
	for _, rec in ipairs(records or ns.ReadMacros()) do
		taken[rec.id] = true
	end
	while true do
		local code = ""
		for _ = 1, ns.CODE_LENGTH do
			local at = math.random(#ns.CODE_LETTERS)
			code = code .. ns.CODE_LETTERS:sub(at, at)
		end
		if code ~= ns.FAVORITES_ID and not taken[code] and not macros[code] then
			return code
		end
	end
end

-- Of the records clicking id's button, the one bound to it: same name, else same index, else
-- the first. General macros are sorted by name (warcraft.wiki.gg API_EditMacro), so a copy can be
-- listed before the macro it was copied from.
local function Original(records, id)
	local m, first, atIndex = macros[id], nil, nil
	for _, rec in ipairs(records) do
		if rec.id == id then
			if m and rec.name == m.name then
				return rec
			end
			first = first or rec
			if m and rec.index == m.index then
				atIndex = rec
			end
		end
	end
	return atIndex or first
end

-- The macro behind m right now; indexes move when macros are added or removed.
local function FindRecord(m)
	local rec = Original(ns.ReadMacros(), m.id)
	if rec then
		return rec
	end
	return nil, "That macro is gone."
end

-- Writes m's macro (rec, as read) with entries: the one place a macro's data is written.
local function Save(m, rec, entries)
	local data, err = Encode(entries)
	if not data then
		return nil, err
	end
	local index
	index, err = ns.EditMacroAt(rec.index, rec.name, rec.icon, ns.SetDataLine(rec.body, data))
	if not index then
		return nil, err
	end
	m.entries, m.data = entries, data
	return true
end

-- Favorites' macro, made if it doesn't exist yet (as dragging Favorites does).
local function FavoritesRecord()
	local rec = ns.FindFavoritesMacro()
	if rec then
		return rec
	end
	local _, err = ns.MakeFavoritesMacro(favorites.name)
	if err then
		return nil, err
	end
	return ns.FindFavoritesMacro()
end

------------------------------------------------------------------------------------------
-- Sync: read every macro, then do whatever is due. Returns true if it wrote a macro, after
-- which the caller reads again.

local function Wait(what)
	waiting[what] = (waiting[what] or 0) + 1
end

-- Two macros clicking the same button (a copy, or one pasted from elsewhere): the original keeps
-- the button, each other one gets a new code written into its /click line.
local function SeparateCopies(records, canWrite)
	local live = {}
	for _, rec in ipairs(records) do
		live[rec.id] = live[rec.id] or Original(records, rec.id)
	end
	for _, rec in ipairs(records) do
		if live[rec.id] ~= rec then
			if canWrite then
				local newCode = NewCode(records)
				-- A code replaces a code of the same length, so the body never grows. But /macro holds
				-- 255 characters (MacroFrameText letters="255"), which can be more bytes than Clicky
				-- writes (MacroStore.lua): such a copy is left as it is, or this would retry forever.
				if ns.EditMacroAt(rec.index, rec.name, rec.icon, ns.SetCode(rec.body, rec.id, newCode)) then
					ns.Trace("[%s] copy of %s, now %s", rec.name, ns.ButtonName(rec.id), ns.ButtonName(newCode))
					return live, true
				end
				Wait("copies too long to separate")
			else
				Wait("copies to separate")
			end
		end
	end
	return live, false
end

-- Runtime macros for what was read; ones whose macro is gone are dropped.
local function Bind(live)
	local seen = { [ns.FAVORITES_ID] = true }
	for id, rec in pairs(live) do
		local m = macros[id]
		if not m then
			m = { id = id }
			macros[id] = m
		end
		m.name, m.icon, m.index = rec.name, rec.icon, rec.index
		if m.data ~= rec.data then
			Decode(m, rec.data)
		end
		seen[id] = true
	end
	-- Favorites is there with or without its macro.
	local fav = ns.FindFavoritesMacro()
	if fav then
		favorites.name, favorites.icon, favorites.index = fav.name, fav.icon, fav.index
	else
		-- Its old name goes with its macro, as it would at the next login.
		favorites.name, favorites.icon, favorites.index = ns.FAVORITES_MACRO, ns.FAVORITES_ICON, nil
	end
	for id, m in pairs(macros) do
		if not seen[id] then
			-- Macros can't be edited or deleted in combat, so neither can this happen then.
			ns.Trace("[%s] macro gone, emptying %s", m.name, ns.ButtonName(id))
			if m.button then
				EmptyButton(m.button)
			end
			ns.EmptyDrawer(id)
			macros[id] = nil
			ns.expanded[id] = nil
		end
	end
	for _, m in pairs(macros) do
		if not BindButton(m) then
			Wait("buttons to make")
		end
	end
end

local function SyncPass()
	wipe(waiting)
	local records = ns.ReadMacros()
	local canWrite = not InCombatLockdown()
	local live, wrote = SeparateCopies(records, canWrite)
	if wrote then
		return true
	end
	Bind(live)
	return false
end

local syncing, again = false, false

function ns.Sync(reason)
	if syncing then
		again = true -- e.g. the macro hooks or UPDATE_MACROS after our own write
		return
	end
	syncing = true
	local passes = 0
	local ok, err = pcall(function()
		repeat
			again = false
			passes = passes + 1
			local wrote = SyncPass()
		until not (wrote or again)
	end)
	syncing = false
	if not ok then
		error(err, 0)
	end
	ns.Trace("[sync %s] %d pass(es)", reason, passes)
	ns.Changed()
end

function ns.GetWaiting()
	return waiting
end

------------------------------------------------------------------------------------------

-- Favorites first, then the player's macros by name.
function ns.GetMacros()
	local list = {}
	for id, m in pairs(macros) do
		if id ~= ns.FAVORITES_ID then
			list[#list + 1] = m
		end
	end
	table.sort(list, function(a, b)
		if a.name:lower() ~= b.name:lower() then
			return a.name:lower() < b.name:lower()
		end
		return a.id < b.id
	end)
	table.insert(list, 1, favorites)
	return list
end

function ns.GetMacro(id)
	return macros[id]
end

-- Returns the name as the macro will be called (cut to WoW's limit), or nil and the reason.
local function CheckName(name, existing, except)
	name = ns.TruncateMacroName(strtrim(name or ""))
	if name == "" then
		return nil, "Give the macro a name."
	end
	for _, m in pairs(existing) do
		if m ~= except and m.name:lower() == name:lower() then
			return nil, ("There's already a macro called %s."):format(m.name)
		end
	end
	return name
end

-- The checks every change to a macro's entries starts with.
local function Changeable(m)
	if InCombatLockdown() then
		return nil, ns.COMBAT_ERROR
	end
	local unreadable = ns.Unreadable(m)
	if unreadable then
		return nil, unreadable
	end
	return true
end

-- The record of m's macro, to write to: Favorites' is made if it doesn't exist yet.
local function Record(m)
	if m.builtin then
		return FavoritesRecord()
	end
	return FindRecord(m)
end

function ns.SetEntry(m, key, inMacro)
	inMacro = inMacro and true or false
	if m.builtin then
		if ns.EntryKind(key) ~= "toy" then
			return nil, "Favorites' toys are the toys you star in the Toy Box."
		end
		-- Favorites is the Toy Box's stars, so this is a star, not a macro write: it works in
		-- combat, as the grid's star does.
		if ns.IsEntryFavorite(key) ~= inMacro then
			ns.SetEntryFavorite(key, inMacro)
		end
		return true
	end
	local ok, err = Changeable(m)
	if not ok then
		return nil, err
	end
	if HasEntry(m, key) == inMacro then
		return true
	end
	if inMacro and CountEntries(m) >= ns.MACRO_ENTRY_CAP then
		ns.Trace("[%s] add %s refused: full", m.name, key)
		return nil, ("%s is full: a macro holds up to %d items."):format(m.name, ns.MACRO_ENTRY_CAP)
	end
	local entries = {}
	for id in pairs(m.entries) do
		entries[id] = true
	end
	entries[key] = inMacro or nil
	local rec
	rec, err = FindRecord(m)
	ok = false
	if rec then
		ok, err = Save(m, rec, entries)
	end
	if not ok then
		ns.Trace("[%s] %s entry %s refused: %s", m.name, inMacro and "add" or "remove", key, err)
		return nil, err
	end
	ns.Trace("[%s] %s entry %s", m.name, inMacro and "add" or "remove", key)
	ns.Sync("edit")
	return true
end

function ns.MakeMacro(name, key)
	if InCombatLockdown() then
		return nil, ns.COMBAT_ERROR
	end
	local err
	name, err = CheckName(name, macros)
	if not name then
		ns.Trace("[macro] make refused: %s", err)
		return nil, err
	end
	local data
	data, err = Encode({ [key] = true })
	if not data then
		ns.Trace("[macro] make refused: %s", err)
		return nil, err
	end
	local id = NewCode()
	local icon = ns.EntryIcon(key)
	local index
	index, err = ns.CreateGeneralMacro(name, icon or ns.FAVORITES_ICON, ns.NewBody(id, data))
	if not index then
		return nil, err
	end
	ns.Trace("[%s] made, id %s, button %s, first entry %s", name, id, ns.ButtonName(id), key)
	ns.expanded[id] = true
	ns.Sync("make")
	return macros[id]
end

function ns.RenameMacro(m, name)
	if InCombatLockdown() then
		return nil, ns.COMBAT_ERROR
	end
	local err
	name, err = CheckName(name, macros, m)
	if not name then
		ns.Trace("[%s] rename refused: %s", m.name, err)
		return nil, err
	end
	local rec, index
	rec, err = Record(m)
	if rec then
		index, err = ns.EditMacroAt(rec.index, name, rec.icon, rec.body)
	end
	if not index then
		return nil, err
	end
	ns.Trace("[%s] renamed to %s", m.name, name)
	m.name = name
	ns.Sync("rename")
	return true
end

-- The icon is the macro's own in /macro, which every later write keeps (rec.icon), so other
-- computers see it too. Favorites' macro is looked for, not made: its entry exists only once it does.
function ns.SetMacroIcon(m, key)
	if InCombatLockdown() then
		return nil, ns.COMBAT_ERROR
	end
	local icon = ns.EntryIcon(key)
	if not icon then
		ns.Trace("[%s] icon %s refused: not loaded", m.name, key)
		return nil, "That item's icon hasn't loaded yet."
	end
	local rec, err
	if m.builtin then
		rec, err = ns.FindFavoritesMacro(), "That macro is gone."
	else
		rec, err = FindRecord(m)
	end
	if not rec then
		return nil, err
	end
	if rec.icon == icon then
		return true
	end
	local index
	index, err = ns.EditMacroAt(rec.index, rec.name, icon, rec.body)
	if not index then
		return nil, err
	end
	ns.Trace("[%s] icon set to %s's, %s", m.name, key, icon)
	ns.Sync("icon")
	return true
end

-- The button can't be destroyed, so it's emptied instead (in Bind).
function ns.DeleteMacro(m)
	if InCombatLockdown() then
		return nil, ns.COMBAT_ERROR
	end
	local rec, err
	if m.builtin then
		rec = ns.FindFavoritesMacro()
		if not rec then
			return true -- nothing to delete; Favorites stays in the panel
		end
	else
		rec, err = FindRecord(m)
		if not rec then
			return nil, err
		end
	end
	ns.Trace("[%s] deleting macro %d", m.name, rec.index)
	ns.DeleteMacroAt(rec.index)
	ns.Sync("delete")
	return true
end

function ns.PickupMacro(m)
	if InCombatLockdown() then
		ns.ShowError("Can't drag macros in combat.")
		return
	end
	local rec, err = Record(m)
	if not rec then
		ns.ShowError(err)
		return
	end
	ns.Trace("[%s] picked up %d", m.name, rec.index)
	PickupMacro(rec.index)
end

function ns.InMacroUI(m)
	return m.index ~= nil
end

-- Opens /macro as Blizzard's /macro does, then selects the macro as clicking it there does
-- (Blizzard_MacroUI.lua, MacroFrameMacroButtonSelectedCallback), so edits to the macro that was
-- selected are saved first, as Blizzard saves them. That save is an EditMacro, refused in combat.
-- Favorites' macro isn't made for this.
function ns.OpenMacroInUI(m)
	if InCombatLockdown() then
		ns.ShowError(ns.COMBAT_ERROR)
		return
	end
	local rec, err
	if m.builtin then
		rec, err = ns.FindFavoritesMacro(), "That macro is gone."
	else
		rec, err = FindRecord(m)
	end
	if not rec then
		ns.ShowError(err)
		return
	end
	ns.Trace("[%s] opening in /macro at %d", m.name, rec.index)
	ShowMacroFrame()
	if PanelTemplates_GetSelectedTab(MacroFrame) ~= 1 then
		MacroFrame:ChangeTab(1)
	end
	MacroFrame:SaveMacro()
	MacroFrame:SelectMacro(rec.index, true)
	MacroPopupFrame:Hide()
	MacroFrameText:ClearFocus()
end

------------------------------------------------------------------------------------------
-- Events. If macros aren't readable yet at ADDON_LOADED, ns.ReadMacros finds none, so there's
-- nothing to write, and UPDATE_MACROS syncs once they arrive.

local function SetUpAgain()
	for _, m in pairs(macros) do
		m.setUp = false
	end
end

ns.RegisterEvent("ADDON_LOADED", function()
	-- Buttons must exist before any macro /clicks them.
	ns.Sync("load")
end)

ns.RegisterEvent("UPDATE_MACROS", function()
	ns.Sync("macros changed")
end)

-- No Blizzard source shows CreateMacro, EditMacro or DeleteMacro fire UPDATE_MACROS: the /macro
-- window redraws itself after its own calls (Blizzard_MacroUI.lua:294-303,
-- Blizzard_MacroIconSelector.lua:109-117). So a macro changed in /macro or by another addon is read
-- after the call itself: a post hook runs after the function with its arguments (warcraft.wiki.gg
-- API hooksecurefunc). Clicky's own writes run it too: inside ns.Sync it only asks for another pass,
-- and after a change the player asked for it reads the macros before that change's own ns.Sync.
for _, name in ipairs({ "CreateMacro", "EditMacro", "DeleteMacro" }) do
	hooksecurefunc(name, function()
		ns.Sync(name)
	end)
end

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
	SetUpAgain()
	ns.Sync("entering world")
end)

-- PLAYER_REGEN_DISABLED is synchronous (UnitDocumentation.lua), and Blizzard's own secure state
-- drivers still set attributes on it (SecureStateDriver.lua).
ns.RegisterEvent("PLAYER_REGEN_DISABLED", function()
	for _, m in pairs(macros) do
		ReadyForCombat(m)
	end
end)

-- Covers everything that waited for combat to end.
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	SetUpAgain()
	ns.Sync("combat ended")
end)
