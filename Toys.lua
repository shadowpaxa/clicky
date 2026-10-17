-- Every toy in the game, read from the game's own data, which macros are encoded against; and
-- per-toy checks.
--   ns.GetToyList()            { ids (sorted item IDs), index (itemID -> 0-based position), set
--                              (itemID -> true), highest (the last item ID), checks }
--   ns.ToysUpTo(highest)       ids, checks: the toys with item IDs up to highest (a macro's list)
--   ns.CountOwnedToys()
--   ns.GetProbeInfo()          probed up to, toys found, milliseconds the probe took
--   ns.IsToyOnCooldown(itemID)
--
-- The list comes from asking the game, for every item ID in turn, whether it's a toy
-- (C_ToyBox.GetToyLink returns nil for an item that isn't one). It doesn't depend on which toys the
-- player owns, so learning a toy never changes it, and it's the same on every character and
-- account on the same patch. It never reads or changes the Toy Box's filters: those are the
-- player's own saved settings.

local _, ns = ...

local GCD_THRESHOLD = 1.5 -- cooldowns at or below this are the global cooldown, not the toy's
-- Toy item IDs are sparse; the widest gap between two toys today is 11,406 (items 1973 to
-- 13379). The probe stops this far past the last toy it found, so every computer stops at the
-- same place.
local PROBE_PAST_LAST_TOY = 50000

local list -- ns.GetToyList()'s result, once probed
local upTo = {} -- highest -> { ids, checks }
local probedUpTo, probeMs = 0, 0 -- for /clicky debug

local function Probe()
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
	ns.Trace("[toys] probed item IDs 1-%d in %d ms: %d toys", probedUpTo, probeMs, #ids)
	return ids
end

function ns.GetToyList()
	if list then
		return list
	end
	local ids = Probe()
	local index, set = {}, {}
	for i, itemID in ipairs(ids) do
		index[itemID] = i - 1
		set[itemID] = true
	end
	list = { ids = ids, index = index, set = set, highest = ids[#ids] or 0, checks = ns.CheckNumbers(ids) }
	upTo[list.highest] = { ids = ids, checks = list.checks }
	return list
end

function ns.ToysUpTo(highest)
	local found = upTo[highest]
	if not found then
		local ids = {}
		for _, itemID in ipairs(ns.GetToyList().ids) do
			if itemID <= highest then
				ids[#ids + 1] = itemID
			end
		end
		found = { ids = ids, checks = ns.CheckNumbers(ids) }
		upTo[highest] = found
	end
	return found.ids, found.checks
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

function ns.GetProbeInfo()
	return probedUpTo, list and #list.ids or 0, probeMs
end

function ns.IsToyOnCooldown(itemID)
	local start, duration = C_Container.GetItemCooldown(itemID)
	return start and start > 0 and duration and duration > GCD_THRESHOLD
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
