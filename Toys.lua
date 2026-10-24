-- Clicky's toy list, which macros are encoded against; and toy cooldowns.
--   ns.GetToyList()            { ids (item IDs, in ToyList.lua's order), index (itemID -> 0-based
--                              place), set (itemID -> true) }
--   ns.CountOwnedToys()
--   ns.IsToyOnCooldown(itemID)
--   ns.ToyIcon(itemID)
--   ns.ToysUpTo(highest)       format 4: remove before the first full release
--                              ids, checks: the game's toys with item IDs up to highest
--   ns.GetProbeInfo()          format 4: probed up to, toys found, milliseconds the scan took;
--                              nil if it hasn't run
--
-- The list is the one Clicky ships (ToyList.lua, written by tools/update_toys.py from the game's
-- Toy table): a toy's number is its place in it, and it only grows at the end, so patches can't
-- move a macro's toys. It doesn't depend on which toys the player owns, so learning a toy never
-- changes it, and it never reads or changes the Toy Box's filters: those are the player's own
-- saved settings. A toy in the game that the list doesn't have yet can't be put in a macro until
-- Clicky is updated (Macros.lua), and a toy taken out of the game keeps its place.
--
-- Format 4 macros (0.4.0) were encoded against the toys the game reported when they were saved,
-- found by asking it, for every item ID in turn, whether it's a toy (C_ToyBox.GetToyLink returns
-- nil for an item that isn't one, warcraft.wiki.gg API C_ToyBox.GetToyLink). That scan runs only
-- when a format 4 macro needs reading, to convert it (Macros.lua).

local _, ns = ...

local GCD_THRESHOLD = 1.5 -- cooldowns at or below this are the global cooldown, not the toy's

local list -- ns.GetToyList()'s result, once built

function ns.GetToyList()
	if list then
		return list
	end
	local ids, index, set = ns.TOY_IDS, {}, {}
	for i, itemID in ipairs(ids) do
		index[itemID] = i - 1
		set[itemID] = true
	end
	list = { ids = ids, index = index, set = set }
	ns.Trace("[toys] list of %d toys, from build %s", #ids, tostring(ns.TOY_LIST_BUILD))
	return list
end

function ns.CountOwnedToys()
	local n = 0
	for _, itemID in ipairs(ns.GetToyList().ids) do
		if PlayerHasToy(itemID) then
			n = n + 1
		end
	end
	return n
end

function ns.IsToyOnCooldown(itemID)
	local start, duration = C_Container.GetItemCooldown(itemID)
	return start and start > 0 and duration and duration > GCD_THRESHOLD
end

-- C_ToyBox.GetToyInfo has no icon until the toy's data has loaded (seen in play: a drawer filled
-- after login had black buttons). GetItemInfoInstant never asks the server, so it has the icon
-- straight away (warcraft.wiki.gg API C_Item.GetItemInfoInstant).
function ns.ToyIcon(itemID)
	local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
	return icon
end

------------------------------------------------------------------------------------------
-- Format 4: remove before the first full release.

-- Toy item IDs are sparse. The scan stops this far past the last toy it found, so every computer
-- stops at the same place.
local PROBE_PAST_LAST_TOY = 50000

local scanned -- the game's toys in item ID order, once scanned
local upTo = {} -- highest -> { ids, checks }
local probedUpTo, probeMs = nil, 0 -- for /clicky debug

local function Scan()
	local started = debugprofilestop()
	local ids, lastToy, itemID = {}, 0, 0
	while itemID < lastToy + PROBE_PAST_LAST_TOY do
		itemID = itemID + 1
		if C_ToyBox.GetToyLink(itemID) then
			ids[#ids + 1] = itemID
			lastToy = itemID
		end
	end
	probedUpTo, probeMs = itemID, debugprofilestop() - started
	ns.Trace("[toys] format 4 scan of item IDs 1-%d in %d ms: %d toys", probedUpTo, probeMs, #ids)
	return ids
end

function ns.ToysUpTo(highest)
	local found = upTo[highest]
	if not found then
		scanned = scanned or Scan()
		local ids = {}
		for _, itemID in ipairs(scanned) do
			if itemID <= highest then
				ids[#ids + 1] = itemID
			end
		end
		found = { ids = ids, checks = ns.CheckNumbers(ids) }
		upTo[highest] = found
	end
	return found.ids, found.checks
end

function ns.GetProbeInfo()
	if probedUpTo then
		return probedUpTo, #scanned, probeMs
	end
end

------------------------------------------------------------------------------------------
-- Events.

-- Learning a toy or starring one changes what the panel shows and what can be picked, never the
-- list.
ns.RegisterEvent("NEW_TOY_ADDED", ns.Changed)
ns.RegisterEvent("TOYS_UPDATED", ns.Changed)

ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(itemID)
	-- A toy's name may have just loaded. This fires for every item, so ignore the rest.
	if itemID and list and list.set[itemID] then
		ns.Changed()
	end
end)
