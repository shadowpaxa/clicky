-- The grid's search (Grid.lua): an entry matches when its name, the filter menus' labels that
-- describe it (its source, expansion, mount types or pet family, GridFilters.lua) or its tooltip's
-- text holds what was typed, ignoring case. Blizzard's Heirlooms search doesn't look at tooltips
-- ("rested" found none of the heirlooms whose set bonus mentions rested experience, seen in play);
-- Clicky searches more on purpose.
--   ns.EntryMatches(key, name, text)   text lowercased and trimmed, "" matching everything
--
-- A tooltip is read only when the name and labels don't match, and kept: reading every entry's on
-- every key typed would be thousands of reads. It's kept until the game says the entry's data has
-- arrived (GET_ITEM_INFO_RECEIVED, SPELL_DATA_LOAD_RESULT), which a tooltip read before may have
-- lacked; what else changes in it (a cooldown, whether it's collected) isn't what a search looks
-- for. One the game has no data for yet isn't kept, and is read again next time.
--   ns.GetSearchState()                for /clicky debug: how many tooltips are kept

local _, ns = ...

local tooltips = {} -- key -> its tooltip's text, lowercased
local kept = 0

local function Has(haystack, text)
	return haystack:lower():find(text, 1, true) ~= nil
end

function ns.EntryMatches(key, name, text)
	if text == "" or Has(name, text) then
		return true
	end
	for _, label in ipairs(ns.EntryFilterLabels(key)) do
		if Has(label, text) then
			return true
		end
	end
	local tooltip = tooltips[key]
	if not tooltip then
		tooltip = ns.EntryTooltipText(key)
		tooltip = tooltip and tooltip:lower()
		tooltips[key] = tooltip -- nil while the game has no data: read again next time
		kept = kept + (tooltip and 1 or 0)
	end
	return tooltip ~= nil and tooltip:find(text, 1, true) ~= nil
end

local function Forget(key)
	if key and tooltips[key] then
		tooltips[key], kept = nil, kept - 1
		ns.Trace("[search] %s's tooltip read again next time", tostring(key))
	end
end

function ns.GetSearchState()
	return ("%d tooltips kept"):format(kept)
end

-- A toy or an item, and a spell or the mount whose spell it is (C_MountJournal.GetMountFromSpell).
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(itemID)
	if itemID then
		Forget(itemID)
		Forget("i" .. itemID)
	end
end)
ns.RegisterEvent("SPELL_DATA_LOAD_RESULT", function(spellID)
	if spellID then
		Forget("s" .. spellID)
		local mountID = C_MountJournal.GetMountFromSpell(spellID)
		Forget(mountID and "m" .. mountID)
	end
end)
