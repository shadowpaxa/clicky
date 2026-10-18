-- Clicky's macros: Favorites, plus every macro with a "#clicky" line. WoW keeps macros on its
-- servers (warcraft.wiki.gg Macro), so a macro is the only copy of its toys that every computer
-- sees: they're read from it (ns.Sync) and written back to it on every change. Each macro has a hidden secure button its /click line clicks, and a
-- drawer its right-click opens (Drawer.lua). A click uses a random toy from the macro; the drawer
-- uses the toy clicked in it.
--   ns.expanded; ns.favorites (for tests)
--   ns.GetMacros(), ns.GetMacro(id), ns.HasOwnMacros()
--   ns.HasToy(m, itemID), ns.MemberPool(m), ns.GetMacroToys(m, all)
--   ns.NoToysMessage(m)                    why a click or right-click finds no toy to use
--   ns.GetCandidates(m, allowRepeat)
--   ns.SetToy(m, itemID, inMacro)          -> true | nil, reason
--   ns.MakeMacro(name, itemID)             -> macro | nil, reason
--   ns.RenameMacro(m, name), ns.DeleteMacro(m)   -> true | nil, reason
--   ns.PickupMacro(m)                      puts the macro on the cursor
--   ns.Unreadable(m)                       why m's toys can't be used or changed (for the player), or nil
--   ns.Sync(reason)                        re-reads every macro and does any waiting work
--   ns.GetWaiting()                        what -> count of work waiting (for /clicky debug)
--
-- A runtime macro m has: id, name, icon, index, buttonName, button, linedUp, lastUsed, data,
-- decodedFor (the toy list it was last read against), and state:
--   "ready"      toys (itemID -> true) read from data. stale is true when data was saved against
--                an earlier toy list (toys added to or taken out of the game since, worked out
--                from the check numbers in Codec.lua); a stale macro is re-saved against the
--                current list, without any toys that left the game
--   "lost"       missed (more than ns.CATCH_UP_LIMIT) toys were added inside its list since it
--                was saved, too many to work out
--   "newer"      saved by a newer Clicky
--   "unreadable" damaged, or changed in a way the check numbers can't work out
-- reason says why. Unreadable macros load nothing onto their buttons and can't have toys changed.
-- Favorites (id 0, builtin): its toys are the Toy Box stars, and its macro is found by its /click
-- line (ns.FindFavoritesMacro); it may not exist yet, and it holds no data.
--
-- Rules every write follows: nothing is written in combat (macros and secure attributes are
-- locked; the work waits for PLAYER_REGEN_ENABLED).

local _, ns = ...

local COMBAT_ERROR = "Can't change macros in combat."
local LOST_MESSAGE = "Clicky can't work out which toys this macro holds: %d toys were added to the game "
	.. "since it was saved, more than the %d it can catch up on. Delete it and make it again."
local NEWER_MESSAGE = "This macro was saved by a newer version of Clicky. Update Clicky to use it."
local UNREADABLE_MESSAGE = "Clicky can't read this macro's toys. Delete it and make it again."
local EMPTY_MESSAGE = "%s has no toys. Right-click toys in the Toy Box to add them."
local EMPTY_FAVORITES_MESSAGE = "%s has no toys. Star toys in the Toy Box to add them."

-- Runs inside the button's click, before the toy is used, in WoW's restricted environment. In
-- combat Clicky's own code can't set the button's toy, so this picks one with random from the
-- list handed over on PLAYER_REGEN_DISABLED (readycount, ready1..n), avoiding the last toy. Out of
-- combat it does nothing: PreClick has already lined up a toy, skipping cooldowns. (The list
-- isn't called toy1..n: a left click reads "toy1" before "toy".)
local COMBAT_PICK = [[
	local n = self:GetAttribute("readycount")
	if not n or SecureCmdOptionParse("[combat]1") ~= "1" then
		return
	end
	local last, skip = self:GetAttribute("lasttoy"), 0
	if n > 1 then
		for i = 1, n do
			if self:GetAttribute("ready" .. i) == last then
				skip = i
			end
		end
	end
	local toy
	if n > 0 then
		local i = random(skip > 0 and n - 1 or n)
		if skip > 0 and i >= skip then
			i = i + 1
		end
		toy = self:GetAttribute("ready" .. i)
	end
	self:SetAttribute("toy", toy)
	self:SetAttribute("lasttoy", toy)
]]

local favorites = {
	id = 0,
	icon = ns.FAVORITES_ICON,
	buttonName = ns.FAVORITES_BUTTON,
	builtin = true,
	state = "ready",
}
favorites.name = ns.FAVORITES_MACRO
local macros = { [0] = favorites }
-- id -> button. Buttons can't be destroyed, so an id's button outlives its macro and is reused.
local buttons = {}
local waiting = {}
local told = {} -- messages already printed this session
-- What changed since each saved toy list, worked out once per session: key (highest, count and
-- check numbers) -> { toys } or { err }. The game's list doesn't change during a session.
local recoveries = {}
ns.favorites = favorites
-- Macro id -> true for macros whose toys the panel shows. Everything starts collapsed each session.
ns.expanded = {}

local function HasToy(m, itemID)
	if m.builtin then
		return C_ToyBox.GetIsFavorite(itemID)
	end
	return m.toys ~= nil and m.toys[itemID] == true
end
ns.HasToy = HasToy

-- The toys a macro could ever contain: every toy in the game for Favorites (whether it's in is
-- read live from the star, so starring needs no event), the macro's own toys otherwise.
local function MemberPool(m)
	if m.builtin then
		return ns.GetToyList().set
	end
	return m.toys or {}
end
ns.MemberPool = MemberPool

local function CountToys(m)
	local n = 0
	for itemID in pairs(MemberPool(m)) do
		if HasToy(m, itemID) then
			n = n + 1
		end
	end
	return n
end

function ns.Unreadable(m)
	if m.state == "lost" then
		return LOST_MESSAGE:format(m.missed, ns.CATCH_UP_LIMIT)
	elseif m.state == "newer" then
		return NEWER_MESSAGE
	elseif m.state == "unreadable" then
		return UNREADABLE_MESSAGE
	end
end

-- Why a click, or a right-click for the drawer, finds no toy to use.
function ns.NoToysMessage(m)
	local empty = CountToys(m) == 0 and (m.builtin and EMPTY_FAVORITES_MESSAGE or EMPTY_MESSAGE)
	return ns.Unreadable(m) or (empty or "No usable toys in %s."):format(m.name)
end

-- toys (itemID -> true), only the ones the player owns unless all, sorted by name then item ID:
-- the panel's order and the drawer's.
local function InOrder(toys, all)
	local list, names = {}, {}
	for itemID in pairs(toys) do
		if all or PlayerHasToy(itemID) then
			local _, name = C_ToyBox.GetToyInfo(itemID)
			if not name then
				-- Not cached yet; GET_ITEM_INFO_RECEIVED refreshes the panel once it arrives.
				C_Item.RequestLoadItemDataByID(itemID)
			end
			names[itemID] = name or ""
			list[#list + 1] = itemID
		end
	end
	table.sort(list, function(a, b)
		if names[a] ~= names[b] then
			return names[a] < names[b]
		end
		return a < b
	end)
	return list
end

-- The macro's toys sorted by name: the ones the player owns (the drawer), or all of them (the
-- panel, where an unowned toy can still be taken out).
function ns.GetMacroToys(m, all)
	local toys = {}
	for itemID in pairs(MemberPool(m)) do
		if HasToy(m, itemID) then
			toys[itemID] = true
		end
	end
	return InOrder(toys, all)
end

-- Don't repeat the macro's last toy unless it's the only choice.
local function DropRepeat(candidates, lastUsed)
	if #candidates > 1 and lastUsed then
		for i, itemID in ipairs(candidates) do
			if itemID == lastUsed then
				table.remove(candidates, i)
				break
			end
		end
	end
	return candidates
end

local function GetCandidates(m, allowRepeat)
	local candidates = {}
	for itemID in pairs(MemberPool(m)) do
		if HasToy(m, itemID) and PlayerHasToy(itemID) and C_ToyBox.IsToyUsable(itemID)
			and not ns.IsToyOnCooldown(itemID) then
			candidates[#candidates + 1] = itemID
		end
	end
	if allowRepeat then
		return candidates
	end
	return DropRepeat(candidates, m.lastUsed)
end
ns.GetCandidates = GetCandidates

------------------------------------------------------------------------------------------
-- Buttons. Attributes on a secure button are locked in combat; every caller checks first.

local function LineUpToy(m, reason)
	reason = reason or "event"
	if not m.button then
		return
	end
	if InCombatLockdown() then
		ns.Trace("[%s %s] in combat, keeping %s", m.name, reason, m.linedUp)
		return
	end
	local candidates = GetCandidates(m)
	m.linedUp = #candidates > 0 and candidates[math.random(#candidates)] or nil
	m.button:SetAttribute("toy", m.linedUp)
	if ns.IsTracing() then
		ns.Trace("[%s %s] known %d, candidates %d, picked %s, attr %s", m.name, reason,
			#ns.GetToyList().ids, #candidates, m.linedUp, m.button:GetAttribute("toy"))
	end
end

-- PLAYER_REGEN_DISABLED, the last moment attributes can be set: the drawer gets the toys owned
-- now, and the button the toys ready now for COMBAT_PICK.
local function ReadyForCombat(m)
	if not m.button or not m.setUp then
		return
	end
	local button = m.button
	for i = 1, button:GetAttribute("readycount") or 0 do
		button:SetAttribute("ready" .. i, nil)
	end
	ns.FillDrawer(m)
	local ready = ns.Unreadable(m) and {} or GetCandidates(m, true)
	for i, itemID in ipairs(ready) do
		button:SetAttribute("ready" .. i, itemID)
	end
	button:SetAttribute("readycount", #ready)
	button:SetAttribute("lasttoy", m.lastUsed)
	ns.Trace("[%s] %d toys ready for combat", m.name, #ready)
end

local function SetUpButton(m)
	if InCombatLockdown() or not m.button then
		return
	end
	m.button:SetAttribute("type", "toy")
	-- /click sends an "up" click. Without this, players with the default "cast on key down"
	-- setting would get a button that silently does nothing.
	m.button:SetAttribute("useOnKeyDown", false)
	LineUpToy(m)
	ns.SetUpDrawer(m)
	ns.QueueDrawer(m)
	m.setUp = true
end

local function EmptyButton(button)
	button:SetAttribute("toy", nil)
	button:SetAttribute("type", nil)
	button:SetAttribute("readycount", nil)
end

-- The button looks its macro up by id on every click, since the runtime macro behind an id can
-- be replaced (a macro deleted, another made with the same id).
local function CreateButton(id, buttonName)
	local button = CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	button:SetScript("PreClick", function(_, mouseButton, down)
		local m = macros[id]
		if not m then
			return
		end
		ns.Trace("[%s] PreClick %s down=%s", m.name, mouseButton, down)
		LineUpToy(m, "PreClick")
	end)
	SecureHandlerWrapScript(button, "OnClick", button, COMBAT_PICK)
	-- The toy used is the button's toy after the click: in combat, COMBAT_PICK chose it.
	button:SetScript("PostClick", function(self)
		local m = macros[id]
		if not m then
			return
		end
		local used = self:GetAttribute("toy")
		ns.Trace("[%s] PostClick, used %s", m.name, used)
		if not used then
			ns.ShowError(ns.NoToysMessage(m))
			return
		end
		m.lastUsed = used
		LineUpToy(m, "PostClick")
	end)
	ns.Trace("[button] created %s", buttonName)
	return button
end

-- Protected frames can't be created in combat; the button is made when combat ends.
local function BindButton(m)
	if not m.button then
		local button = buttons[m.id]
		if not button and not InCombatLockdown() then
			button = CreateButton(m.id, m.buttonName)
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
-- Reading and writing toys against the game's toy list (Toys.lua) with the codec (Codec.lua).

local function Encode(toys, list)
	local positions = {}
	for itemID in pairs(toys) do
		local p = list.index[itemID]
		if not p then
			return nil, "That isn't in the game's toy list."
		end
		positions[#positions + 1] = p
	end
	table.sort(positions)
	return ns.EncodeToys(list.highest, #list.ids, list.checks, positions)
end

local function CantRead(m, state, reason)
	m.state, m.reason, m.toys, m.stale = state, reason, nil, nil
	ns.Trace("[%s] can't read its toys (%s): %s", m.name, state, reason)
end

-- The toys added to (or, with fewer now, taken out of) the toy list a macro was saved against.
local function Changed(ids, checks, d)
	local key = d.highest .. ":" .. d.count .. ":" .. table.concat(d.checks, ",")
	local found = recoveries[key]
	if not found then
		local toys, err, what
		if d.count > #ids then
			toys, err = ns.FindRemoved(ids, checks, d.count, d.checks, d.highest)
			what = "taken out"
		else
			toys, err = ns.FindLearned(ids, checks, d.count, d.checks)
			what = "added"
		end
		found = { toys = toys, err = err }
		recoveries[key] = found
		if toys and ns.IsTracing() then
			ns.Trace("[toys] %d toys %s since a list of %d: %s", #toys, what, d.count, table.concat(toys, ", "))
		end
	end
	return found.toys, found.err
end

local function Decode(m, data, list)
	m.data, m.decodedFor, m.setUp, m.missed = data, list, false, nil
	local d, err = ns.DecodeToys(data)
	if not d then
		return CantRead(m, err == "newer" and "newer" or "unreadable", err)
	end
	-- Toys added to the game later have higher item IDs, so the list up to the macro's highest
	-- is the list it was saved against, unless toys were added or taken out inside that range.
	local ids, checks = ns.ToysUpTo(d.highest)
	local missed = #ids - d.count
	if missed > ns.CATCH_UP_LIMIT then
		m.missed = missed
		return CantRead(m, "lost", ("%d toys added since it was saved"):format(missed))
	end
	local saved, gone = ids, {}
	if missed ~= 0 or not ns.SameChecks(checks, d.checks) then
		local changed, why = Changed(ids, checks, d)
		if not changed then
			return CantRead(m, "unreadable", why)
		end
		local isChanged = {}
		for _, itemID in ipairs(changed) do
			isChanged[itemID] = true
		end
		saved = {}
		for _, itemID in ipairs(ids) do
			if missed < 0 or not isChanged[itemID] then
				saved[#saved + 1] = itemID
			end
		end
		if missed < 0 then
			for _, itemID in ipairs(changed) do
				saved[#saved + 1] = itemID
			end
			table.sort(saved)
			gone = isChanged
		end
	end
	-- DecodeToys checked every position is below d.count, which is #saved. Toys taken out of the
	-- game leave the macro too; the re-save writes it without them.
	local toys = {}
	for _, p in ipairs(d.positions) do
		local itemID = saved[p + 1]
		if not gone[itemID] then
			toys[itemID] = true
		end
	end
	m.toys, m.state, m.reason = toys, "ready", nil
	m.stale = saved ~= ids or d.highest ~= list.highest
	if m.lastUsed and not toys[m.lastUsed] then
		m.lastUsed = nil
	end
	ns.Trace("[%s] read %d toys%s", m.name, #d.positions,
		missed ~= 0 and (", caught up on %d toys %s since"):format(math.abs(missed), missed > 0 and "added" or "taken out") or "")
end

local function TellOnce(key, msg)
	if not told[key] then
		told[key] = true
		ns.Print(msg)
	end
end

-- The smallest id no Clicky macro uses, bound or just read (records: ns.ReadMacros()).
local function FreeID(records)
	local taken = {}
	for _, rec in ipairs(records or ns.ReadMacros()) do
		taken[rec.id] = true
	end
	local id = 1
	while macros[id] or taken[id] do
		id = id + 1
	end
	return id
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

-- Writes m's macro (rec, as read) with toys: the one place a macro's data is written.
local function Save(m, rec, toys)
	local list = ns.GetToyList()
	local data, err = Encode(toys, list)
	if not data then
		return nil, err
	end
	local index
	index, err = ns.EditMacroAt(rec.index, rec.name, rec.icon, ns.SetDataLine(rec.body, data))
	if not index then
		return nil, err
	end
	m.toys, m.decodedFor, m.stale, m.data = toys, list, false, data
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
-- the button, each other one gets a free id written into its /click line.
local function SeparateCopies(records, canWrite)
	local live = {}
	for _, rec in ipairs(records) do
		live[rec.id] = live[rec.id] or Original(records, rec.id)
	end
	for _, rec in ipairs(records) do
		if live[rec.id] ~= rec then
			if canWrite then
				local newID = FreeID(records)
				local index, err = ns.EditMacroAt(rec.index, rec.name, rec.icon, ns.SetButtonID(rec.body, rec.id, newID))
				if index then
					ns.Trace("[%s] copy of %s%d, now %s%d", rec.name, ns.SET_BUTTON_PREFIX, rec.id, ns.SET_BUTTON_PREFIX, newID)
					return live, true
				end
				TellOnce("copy" .. rec.name, ("%s is a copy of another Clicky macro and couldn't be separated from it. %s"):format(rec.name, err))
			end
			Wait("copies to separate")
		end
	end
	return live, false
end

-- Runtime macros for what was read; ones whose macro is gone are dropped.
local function Bind(live, list)
	local seen = { [0] = true }
	for id, rec in pairs(live) do
		local m = macros[id]
		if not m then
			m = { id = id, buttonName = ns.SET_BUTTON_PREFIX .. id }
			macros[id] = m
		end
		m.name, m.icon, m.index = rec.name, rec.icon, rec.index
		if m.data ~= rec.data or m.decodedFor ~= list then
			Decode(m, rec.data, list)
		end
		seen[id] = true
	end
	-- Favorites is there with or without its macro.
	local fav = ns.FindFavoritesMacro()
	if fav then
		favorites.name, favorites.icon, favorites.index = fav.name, fav.icon, fav.index
	else
		favorites.icon, favorites.index = ns.FAVORITES_ICON, nil
	end
	for id, m in pairs(macros) do
		if not seen[id] then
			-- Macros can't be edited or deleted in combat, so neither can this happen then.
			ns.Trace("[%s] macro gone, emptying %s", m.name, m.buttonName)
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

-- A macro saved against an earlier toy list is re-saved against the current one, so the toys
-- added since don't count towards the next catch-up.
local function Resave(live, canWrite)
	for id, rec in pairs(live) do
		local m = macros[id]
		if m.state == "ready" and m.stale then
			if canWrite then
				local ok, err = Save(m, rec, m.toys)
				if ok then
					ns.Trace("[%s] re-saved for %d toys", m.name, #ns.GetToyList().ids)
					return true
				end
				TellOnce("save" .. id, ("Couldn't update %s for this patch's toy changes. %s"):format(m.name, err))
			end
			Wait("macros to re-save")
		end
	end
	return false
end

local function SyncPass()
	wipe(waiting)
	local list = ns.GetToyList()
	local records = ns.ReadMacros()
	local canWrite = not InCombatLockdown()
	local live, wrote = SeparateCopies(records, canWrite)
	if wrote then
		return true
	end
	Bind(live, list)
	return Resave(live, canWrite)
end

local syncing, again = false, false

function ns.Sync(reason)
	if syncing then
		again = true -- e.g. UPDATE_MACROS from our own write
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
		if id ~= 0 then
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

function ns.HasOwnMacros()
	for id in pairs(macros) do
		if id ~= 0 then
			return true
		end
	end
	return false
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

-- The checks every change to a macro's toys starts with.
local function Changeable(m)
	if InCombatLockdown() then
		return nil, COMBAT_ERROR
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

function ns.SetToy(m, itemID, inMacro)
	if m.builtin then
		return nil, "Favorites' toys are the toys you star in the Toy Box."
	end
	inMacro = inMacro and true or false
	local ok, err = Changeable(m)
	if not ok then
		return nil, err
	end
	if HasToy(m, itemID) == inMacro then
		return true
	end
	if inMacro and CountToys(m) >= ns.MACRO_TOY_CAP then
		ns.Trace("[%s] add %d refused: full", m.name, itemID)
		return nil, ("%s is full: a macro holds up to %d toys."):format(m.name, ns.MACRO_TOY_CAP)
	end
	local toys = {}
	for id in pairs(m.toys) do
		toys[id] = true
	end
	toys[itemID] = inMacro or nil
	local rec
	rec, err = FindRecord(m)
	if rec then
		ok, err = Save(m, rec, toys)
	end
	if not ok then
		ns.Trace("[%s] %s toy %d refused: %s", m.name, inMacro and "add" or "remove", itemID, err)
		return nil, err
	end
	ns.Trace("[%s] %s toy %d", m.name, inMacro and "add" or "remove", itemID)
	if not inMacro and m.lastUsed == itemID then
		m.lastUsed = nil
	end
	LineUpToy(m, "edit")
	ns.Sync("edit")
	return true
end

function ns.MakeMacro(name, itemID)
	if InCombatLockdown() then
		return nil, COMBAT_ERROR
	end
	local err
	name, err = CheckName(name, macros)
	if not name then
		ns.Trace("[macro] make refused: %s", err)
		return nil, err
	end
	local list = ns.GetToyList()
	local data
	data, err = Encode({ [itemID] = true }, list)
	if not data then
		return nil, err
	end
	local id = FreeID()
	local _, _, icon = C_ToyBox.GetToyInfo(itemID)
	local index
	index, err = ns.CreateGeneralMacro(name, icon or ns.FAVORITES_ICON, ns.NewBody(id, data))
	if not index then
		return nil, err
	end
	ns.Trace("[%s] made, id %d, button %s%d, first toy %d", name, id, ns.SET_BUTTON_PREFIX, id, itemID)
	ns.expanded[id] = true
	ns.Sync("make")
	return macros[id]
end

function ns.RenameMacro(m, name)
	if InCombatLockdown() then
		return nil, COMBAT_ERROR
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

-- The button can't be destroyed, so it's emptied instead (in Bind).
function ns.DeleteMacro(m)
	if InCombatLockdown() then
		return nil, COMBAT_ERROR
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
