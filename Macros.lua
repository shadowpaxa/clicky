-- Clicky's macros: Favorites, plus every macro with a "#clicky" line. WoW keeps macros on its
-- servers and syncs them to every computer the player uses, while SavedVariables stay on one
-- computer, so a macro is the only copy of its toys: they're read from it (ns.Sync) and written
-- back to it on every change. Each macro has a hidden secure button its /click line clicks,
-- and a random pick loads a toy onto that button.
--   ns.favorites, ns.expanded
--   ns.GetMacros(), ns.GetMacro(id), ns.HasOwnMacros()
--   ns.HasToy(m, itemID), ns.MemberPool(m), ns.GetMacroToys(m), ns.CountToys(m)
--   ns.GetCandidates(m, allowRepeat), ns.FailedHere(itemID)
--   ns.SetToy(m, itemID, inMacro)          -> true | nil, reason
--   ns.MakeMacro(name, itemID)             -> macro | nil, reason
--   ns.RenameMacro(m, name), ns.DeleteMacro(m)   -> true | nil, reason
--   ns.PickupMacro(m)                      puts the macro on the cursor
--   ns.Unreadable(m)                       why m's toys can't be used or changed (for the player), or nil
--   ns.Sync(reason)                        re-reads every macro and does any waiting work
--   ns.GetWaiting()                        what -> count of work waiting (for /clicky debug)
--   ns.DropRepeat(candidates, lastUsed), ns.CheckName(name, existing, except)
--                                          game-independent; on ns so offline tests can reach them
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
-- Favorites (id 0, builtin) has no data: its toys are the Toy Box stars.
--
-- Rules every write follows: nothing is written in combat (macros and secure attributes are
-- locked; the work waits for PLAYER_REGEN_ENABLED).

local _, ns = ...

local FAILURE_WINDOW = 1 -- seconds after a click in which a UI error counts as "this toy failed"
local COMBAT_ERROR = "Can't change macros in combat."
local LOST_MESSAGE = "Clicky can't work out which toys this macro holds: %d toys were added to the game "
	.. "since it was saved, more than the %d it can catch up on. Delete it and make it again."
local NEWER_MESSAGE = "This macro was saved by a newer version of Clicky. Update Clicky to use it."
local UNREADABLE_MESSAGE = "Clicky can't read this macro's toys. Delete it and make it again."

local badHere = {} -- itemID -> true for toys that failed in the current zone
local lastClick = { time = 0 } -- the macro and toy of the most recent click, for failure tracking

local favorites = {
	id = 0,
	name = "Favorites",
	icon = ns.FAVORITES_ICON,
	buttonName = ns.FAVORITES_BUTTON,
	builtin = true,
	state = "ready",
}
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

-- The toys a macro could ever contain: everything known for Favorites (read live from the star,
-- so starring needs no event), the macro's own toys otherwise.
local function MemberPool(m)
	if m.builtin then
		return ns.GetToyList().set
	end
	return m.toys or {}
end
ns.MemberPool = MemberPool

function ns.CountToys(m)
	local n = 0
	for itemID in pairs(MemberPool(m)) do
		if HasToy(m, itemID) then
			n = n + 1
		end
	end
	return n
end

function ns.FailedHere(itemID)
	return badHere[itemID] == true
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

-- The macro's toys the player owns, sorted by name, for the panel.
function ns.GetMacroToys(m)
	local toys, names = {}, {}
	for itemID in pairs(MemberPool(m)) do
		if HasToy(m, itemID) and PlayerHasToy(itemID) then
			local _, name = C_ToyBox.GetToyInfo(itemID)
			if not name then
				-- Not cached yet; GET_ITEM_INFO_RECEIVED refreshes the panel once it arrives.
				C_Item.RequestLoadItemDataByID(itemID)
			end
			names[itemID] = name or ""
			toys[#toys + 1] = itemID
		end
	end
	table.sort(toys, function(a, b)
		if names[a] ~= names[b] then
			return names[a] < names[b]
		end
		return a < b
	end)
	return toys
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
ns.DropRepeat = DropRepeat

local function GetCandidates(m, allowRepeat)
	local candidates = {}
	for itemID in pairs(MemberPool(m)) do
		if HasToy(m, itemID) and PlayerHasToy(itemID) and C_ToyBox.IsToyUsable(itemID)
			and not badHere[itemID] and not ns.IsToyOnCooldown(itemID) then
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

local function SetUpButton(m)
	if InCombatLockdown() or not m.button then
		return
	end
	m.button:SetAttribute("type", "toy")
	-- /click sends an "up" click. Without this, players with the default "cast on key down"
	-- setting would get a button that silently does nothing.
	m.button:SetAttribute("useOnKeyDown", false)
	LineUpToy(m)
	m.setUp = true
end

local function EmptyButton(button)
	button:SetAttribute("toy", nil)
	button:SetAttribute("type", nil)
end

-- The button looks its macro up by id on every click, since the runtime macro behind an id can
-- be replaced (a macro deleted, another made with the same id).
local function CreateButton(id, buttonName)
	local button = CreateFrame("Button", buttonName, UIParent, "SecureActionButtonTemplate")
	button:RegisterForClicks("AnyUp", "AnyDown")
	-- Record the toy before the secure handler runs, so a failure reported mid-click
	-- is pinned on the right toy.
	button:SetScript("PreClick", function(_, mouseButton, down)
		local m = macros[id]
		if not m then
			return
		end
		ns.Trace("[%s] PreClick %s down=%s", m.name, mouseButton, down)
		LineUpToy(m, "PreClick")
		if m.linedUp then
			m.lastUsed = m.linedUp
			lastClick.macro, lastClick.itemID, lastClick.time = m, m.linedUp, GetTime()
		end
	end)
	button:SetScript("PostClick", function()
		local m = macros[id]
		if not m then
			return
		end
		ns.Trace("[%s] PostClick, used %s", m.name, m.lastUsed)
		if not m.linedUp then
			ns.ShowError(ns.Unreadable(m) or ("No usable toys in %s."):format(m.name))
			return
		end
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
	local key = (d.highest or ("owned " .. #ids .. " " .. checks[1])) .. ":" .. d.count .. ":" .. table.concat(d.checks, ",")
	local found = recoveries[key]
	if not found then
		local toys, err, what
		if d.count > #ids then
			toys, err = ns.FindRemoved(ids, checks, d.count, d.checks)
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
	m.data, m.decodedFor, m.setUp, m.missed, m.retry = data, list, false, nil, nil
	local d, err = ns.DecodeToys(data)
	if not d then
		return CantRead(m, err == "newer" and "newer" or "unreadable", err)
	end
	-- Toys added to the game later have higher item IDs, so the list up to the macro's highest
	-- is the list it was saved against, unless toys were added or taken out inside that range.
	-- Format 2 numbered the player's own toys instead: read it against them, then re-save it.
	local ids, checks
	if d.legacy then
		ids = {}
		for _, itemID in ipairs(list.ids) do
			if PlayerHasToy(itemID) then
				ids[#ids + 1] = itemID
			end
		end
		checks = ns.CheckNumbers(ids)
	else
		ids, checks = ns.ToysUpTo(d.highest)
	end
	local missed = #ids - d.count
	if missed > ns.CATCH_UP_LIMIT then
		m.missed = missed
		return CantRead(m, "lost", ("%d toys added since it was saved"):format(missed))
	end
	local saved, gone = ids, {}
	if missed ~= 0 or not ns.SameChecks(checks, d.checks) then
		local changed, why = Changed(ids, checks, d)
		if not changed then
			-- Format 2 depends on which toys are owned, which can still be arriving after login:
			-- read it again when they change (TOYS_UPDATED).
			m.retry = d.legacy
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
	-- Format 2 has no highest item ID, so it's always re-saved.
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

-- The smallest id no Clicky macro uses.
local function FreeID()
	local id = 1
	while macros[id] do
		id = id + 1
	end
	return id
end

------------------------------------------------------------------------------------------
-- Sync: read every macro, then do whatever is due. Returns true if it wrote a macro, after
-- which the caller reads again.

local function Wait(what)
	waiting[what] = (waiting[what] or 0) + 1
end

-- Two macros clicking the same button (a copy, or one pasted from elsewhere): the first keeps
-- the button, each other one gets a free id written into its /click line.
local function SeparateCopies(records, canWrite)
	local live = {}
	for _, rec in ipairs(records) do
		if not live[rec.id] then
			live[rec.id] = rec
		elseif canWrite then
			local newID = FreeID()
			local index, err = ns.EditMacroAt(rec.index, rec.name, rec.icon, ns.SetButtonID(rec.body, rec.id, newID))
			if index then
				ns.Trace("[%s] copy of %s%d, now %s%d", rec.name, ns.SET_BUTTON_PREFIX, rec.id, ns.SET_BUTTON_PREFIX, newID)
				return live, true
			end
			TellOnce("copy" .. rec.name, ("%s clicks the same button as another macro and couldn't get its own. %s"):format(rec.name, err))
			Wait("copies to separate")
		else
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
		if m.data ~= rec.data or m.decodedFor ~= list or m.retry then
			Decode(m, rec.data, list)
		end
		seen[id] = true
	end
	for id, m in pairs(macros) do
		if not seen[id] then
			ns.Trace("[%s] macro gone, emptying %s", m.name, m.buttonName)
			if m.button then
				EmptyButton(m.button)
			end
			macros[id] = nil
			ns.expanded[id] = nil
			if lastClick.macro == m then
				lastClick.macro = nil
			end
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
local function Resave(live, list, canWrite)
	for id, rec in pairs(live) do
		local m = macros[id]
		if m.state == "ready" and m.stale then
			if canWrite then
				local data, err = Encode(m.toys, list)
				local index
				if data then
					index, err = ns.EditMacroAt(rec.index, rec.name, rec.icon, ns.SetDataLine(rec.body, data))
				end
				if index then
					ns.Trace("[%s] re-saved for %d toys", m.name, #list.ids)
					m.data, m.decodedFor, m.stale = data, list, false
					return true
				end
				TellOnce("save" .. id, ("Couldn't update %s for your new toys. %s"):format(m.name, err))
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
	return Resave(live, list, canWrite)
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
ns.CheckName = CheckName

-- The macro behind m right now; indexes move when macros are added or removed.
local function FindRecord(m)
	for _, rec in ipairs((ns.ReadMacros())) do
		if rec.id == m.id then
			return rec
		end
	end
	return nil, "That macro is gone."
end

function ns.SetToy(m, itemID, inMacro)
	if m.builtin then
		return nil
	end
	inMacro = inMacro and true or false
	if InCombatLockdown() then
		return nil, COMBAT_ERROR
	end
	local unreadable = ns.Unreadable(m)
	if unreadable then
		return nil, unreadable
	end
	if HasToy(m, itemID) == inMacro then
		return true
	end
	if inMacro and ns.CountToys(m) >= ns.MACRO_TOY_CAP then
		ns.Trace("[%s] add %d refused: full", m.name, itemID)
		return nil, ("%s is full: a macro holds up to %d toys."):format(m.name, ns.MACRO_TOY_CAP)
	end
	local list = ns.GetToyList()
	local toys = {}
	for id in pairs(m.toys) do
		toys[id] = true
	end
	toys[itemID] = inMacro or nil
	local data, err = Encode(toys, list)
	local rec
	if data then
		rec, err = FindRecord(m)
	end
	local index
	if rec then
		index, err = ns.EditMacroAt(rec.index, rec.name, rec.icon, ns.SetDataLine(rec.body, data))
	end
	if not index then
		ns.Trace("[%s] %s toy %d refused: %s", m.name, inMacro and "add" or "remove", itemID, err)
		return nil, err
	end
	ns.Trace("[%s] %s toy %d", m.name, inMacro and "add" or "remove", itemID)
	m.toys, m.data, m.decodedFor, m.stale = toys, data, list, false
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
	rec, err = FindRecord(m)
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
	local rec, err = FindRecord(m)
	if not rec then
		return nil, err
	end
	ns.Trace("[%s] deleting macro %d", m.name, rec.index)
	ns.DeleteMacroAt(rec.index)
	ns.Sync("delete")
	return true
end

function ns.PickupMacro(m)
	if InCombatLockdown() then
		ns.ShowError(COMBAT_ERROR)
		return
	end
	if m.builtin then
		ns.PickupFavoritesMacro()
		return
	end
	local rec, err = FindRecord(m)
	if not rec then
		ns.ShowError(err)
		return
	end
	ns.Trace("[%s] picked up %d", m.name, rec.index)
	PickupMacro(rec.index)
end

------------------------------------------------------------------------------------------
-- Events. Macros may not be readable at ADDON_LOADED; until they are, ns.ReadMacros finds
-- none, so there's nothing to write, and UPDATE_MACROS syncs once they arrive.

local function SetUpAgain()
	for _, m in pairs(macros) do
		m.setUp = false
	end
end

ns.RegisterEvent("ADDON_LOADED", function()
	-- Buttons must exist before any macro /clicks them.
	ns.Sync("load")
end)

ns.RegisterEvent("TOYS_UPDATED", function()
	for _, m in pairs(macros) do
		if m.retry then
			ns.Sync("toys")
			return
		end
	end
end)

ns.RegisterEvent("UPDATE_MACROS", function()
	ns.Sync("macros changed")
end)

ns.RegisterEvent("PLAYER_ENTERING_WORLD", function()
	wipe(badHere)
	SetUpAgain()
	ns.Sync("entering world")
end)

ns.RegisterEvent("ZONE_CHANGED_NEW_AREA", function()
	wipe(badHere)
	for _, m in pairs(macros) do
		LineUpToy(m)
	end
end)

-- Covers everything that waited for combat to end.
ns.RegisterEvent("PLAYER_REGEN_ENABLED", function()
	SetUpAgain()
	ns.Sync("combat ended")
end)

ns.RegisterEvent("UI_ERROR_MESSAGE", function()
	-- The payload isn't read (it can be secret in Midnight instances); timing is enough.
	if lastClick.macro and GetTime() - lastClick.time < FAILURE_WINDOW then
		ns.Trace("[%s] error right after a click, %s failed here", lastClick.macro.name, lastClick.itemID)
		badHere[lastClick.itemID] = true
		lastClick.time = 0
		LineUpToy(lastClick.macro)
	end
end)
