-- The grid's search (Grid.lua): an entry matches when its name, the filter menus' labels that
-- describe it (its source, expansion, mount types or pet family, GridFilters.lua) or its tooltip's
-- text holds what was typed, ignoring case. Blizzard's Heirlooms search doesn't look at tooltips
-- ("rested" found none of the heirlooms whose set bonus mentions rested experience, seen in play);
-- Clicky searches more on purpose.
--   ns.EntryMatches(key, name, text)   text lowercased and trimmed, "" matching everything
--
-- A tooltip is read only when the name and labels don't match, and kept: reading every entry's on
-- every key typed would be thousands of reads. It's kept until the game says what it lacked has
-- arrived: the entry's data (GET_ITEM_INFO_RECEIVED or ITEM_DATA_LOAD_RESULT,
-- SPELL_DATA_LOAD_RESULT), or a lookup the tooltip itself waited on (TOOLTIP_DATA_UPDATE with its
-- dataInstanceID, "a sparse or cache lookup has resolved", TooltipInfoDocumentation.lua;
-- GameTooltip redraws on it, GameTooltip.lua). Forgetting one refreshes the views, so a search shown
-- finds what arrived (Items.lua refreshes only for the names it asked for). What else changes in a
-- tooltip (a cooldown, whether it's collected) isn't what a search looks for. One the game has no
-- data for yet isn't kept, and is read again next time.
--   ns.GetSearchState()                for /clicky debug: how many tooltips are kept

local _, ns = ...

local tooltips = {} -- key -> its tooltip's text, lowercased
local instances = {} -- a kept tooltip's dataInstanceID -> its key
local instanceOf = {} -- key -> its kept tooltip's dataInstanceID
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
		local instance
		tooltip, instance = ns.EntryTooltipText(key)
		if tooltip then -- nil while the game has no data: read again next time
			tooltip = tooltip:lower()
			tooltips[key], kept = tooltip, kept + 1
			if instance then
				instances[instance], instanceOf[key] = key, instance
			end
		end
	end
	return tooltip ~= nil and tooltip:find(text, 1, true) ~= nil
end

local function Forget(key)
	if key and tooltips[key] then
		tooltips[key], kept = nil, kept - 1
		if instanceOf[key] then
			instances[instanceOf[key]], instanceOf[key] = nil, nil
		end
		ns.Trace("[search] %s's tooltip read again next time", tostring(key))
		return true
	end
end

function ns.GetSearchState()
	return ("%d tooltips kept"):format(kept)
end

-- A toy or an item (an item's data arrives with either event, CLAUDE.md, WoW constraints), and a
-- spell or the mount whose spell it is (C_MountJournal.GetMountFromSpell).
local function ItemLoaded(itemID)
	if itemID then
		local toy, item = Forget(itemID), Forget("i" .. itemID)
		if toy or item then
			ns.Changed()
		end
	end
end
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", ItemLoaded)
ns.RegisterEvent("ITEM_DATA_LOAD_RESULT", ItemLoaded)
ns.RegisterEvent("SPELL_DATA_LOAD_RESULT", function(spellID)
	if spellID then
		local mountID = C_MountJournal.GetMountFromSpell(spellID)
		local spell, mount = Forget("s" .. spellID), Forget(mountID and "m" .. mountID)
		if spell or mount then
			ns.Changed()
		end
	end
end)
-- It fires for every tooltip the game resolves, so only one kept here counts. No dataInstanceID:
-- any tooltip may have changed (GameTooltip.lua refreshes on it then too).
ns.RegisterEvent("TOOLTIP_DATA_UPDATE", function(dataInstanceID)
	if dataInstanceID then
		if Forget(instances[dataInstanceID]) then
			ns.Changed()
		end
	elseif kept > 0 then
		ns.Trace("[search] every tooltip read again next time")
		tooltips, instances, instanceOf, kept = {}, {}, {}, 0
		ns.Changed()
	end
end)
