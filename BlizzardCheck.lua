-- Checks Clicky's Toys, Mounts and Pets tabs against the Toy Box, the Mount Journal and the Pet
-- Journal in the game, with no setup: it reads each window's filters as the player left them
-- (read-only; they're the player's settings), lists what Clicky's tab lists with the same filters
-- (GridFilters.lua) and compares that with what the window lists, entry by entry. When the window
-- says it's on Blizzard's defaults, it also compares those with Clicky's (ns.DefaultGridFilters).
-- Blizzard filters inside the game client, so this is how Clicky's rules are seen to match.
--   ns.CheckAgainstBlizzard(tab)   for /clicky debug: "toys", "mounts" or "pets" -> a line
--   ns.CheckSources(tab)           for /clicky debug: "mounts" or "pets" -> a line: how many source
--                                  texts start with the label of the Sources box Clicky puts them
--                                  under, and how many would with the numbering one lower or higher
--
-- The windows read their settings so (Blizzard_ToyBox.lua:56-73, 109-138;
-- Blizzard_MountCollection.lua:221-258, 964-986; Blizzard_PetCollection.lua:172-212, 1481-1510) and
-- walk their lists so (Blizzard_ToyBox.lua:186; Blizzard_MountCollection.lua:667; Blizzard_PetCollection.lua:876).

local _, ns = ...

local SHOWN = 8 -- entries named per difference, at most

local function Unticked(count, IsChecked)
	local off = {}
	for filterIndex = 1, count do
		if not IsChecked(filterIndex) then
			off[filterIndex] = true
		end
	end
	return off
end

local WINDOWS = {
	toys = {
		title = "the Toy Box",
		read = function()
			return { collected = C_ToyBox.GetCollectedShown(), uncollected = C_ToyBox.GetUncollectedShown(),
				usableOnly = not C_ToyBox.GetUnusableShown(),
				sourcesOff = Unticked(C_PetJournal.GetNumPetSources(), C_ToyBox.IsSourceTypeFilterChecked),
				expansionsOff = Unticked(GetNumExpansions(), C_ToyBox.IsExpansionTypeFilterChecked) }
		end,
		isDefault = function() return C_ToyBoxInfo.IsUsingDefaultFilters() end,
		search = function() return ToyBox and ToyBox.searchBox:GetText() end,
		listed = function()
			local ids = {}
			for i = 1, C_ToyBox.GetNumFilteredToys() do
				local itemID = C_ToyBox.GetToyFromIndex(i)
				if itemID then ids[itemID] = true end
			end
			return ids
		end,
		id = function(key) return key end,
		key = function(id) return id end,
		name = function(id) return ns.EntryName(id) end,
	},
	mounts = {
		title = "the Mount Journal",
		read = function()
			local setting = C_MountJournal.GetCollectedFilterSetting
			return { collected = setting(LE_MOUNT_JOURNAL_FILTER_COLLECTED),
				uncollected = setting(LE_MOUNT_JOURNAL_FILTER_NOT_COLLECTED),
				unusable = setting(LE_MOUNT_JOURNAL_FILTER_UNUSABLE),
				typesOff = Unticked(Enum.MountTypeMeta.NumValues, C_MountJournal.IsTypeChecked),
				sourcesOff = Unticked(C_PetJournal.GetNumPetSources(), C_MountJournal.IsSourceChecked) }
		end,
		isDefault = function() return C_MountJournal.IsUsingDefaultFilters() end,
		search = function() return MountJournal and MountJournal.searchBox:GetText() end,
		listed = function()
			local ids = {}
			for i = 1, C_MountJournal.GetNumDisplayedMounts() do
				local mountID = C_MountJournal.GetDisplayedMountID(i)
				if mountID then ids[mountID] = true end
			end
			return ids
		end,
		id = function(key) return ns.EntryID(key) end,
		key = function(id) return "m" .. id end,
		name = function(id) return ns.EntryName("m" .. id) end,
	},
	-- The Pet Journal lists each pet owned and each species not owned, and Clicky each look, so they're
	-- compared by species.
	pets = {
		title = "the Pet Journal",
		read = function()
			local checked = C_PetJournal.IsFilterChecked
			return { collected = checked(LE_PET_JOURNAL_FILTER_COLLECTED), uncollected = checked(LE_PET_JOURNAL_FILTER_NOT_COLLECTED),
				battlePets = checked(LE_PET_JOURNAL_FILTER_TYPE_BATTLE_PETS),
				nonCombatPets = checked(LE_PET_JOURNAL_FILTER_TYPE_NON_COMBAT_PETS),
				familiesOff = Unticked(C_PetJournal.GetNumPetTypes(), C_PetJournal.IsPetTypeChecked),
				sourcesOff = Unticked(C_PetJournal.GetNumPetSources(), C_PetJournal.IsPetSourceChecked),
				sortBy = C_PetJournal.GetPetSortParameter() }
		end,
		isDefault = function() return C_PetJournal.IsUsingDefaultFilters() end,
		search = function() return PetJournal and PetJournal.searchBox:GetText() end,
		listed = function()
			local ids = {}
			for i = 1, C_PetJournal.GetNumPets() do
				local _, speciesID = C_PetJournal.GetPetInfoByIndex(i)
				if speciesID then ids[speciesID] = true end
			end
			return ids
		end,
		id = function(key) return tonumber(ns.EntryID(key):match("^(%d+):")) end,
		name = function(id) return (C_PetJournal.GetPetInfoBySpeciesID(id)) or tostring(id) end,
	},
}

-- "uncollected: Blizzard's true, Clicky's false", one per filter that differs.
local function DefaultsDiffer(tab, blizzard)
	local clicky, out = ns.DefaultGridFilters(tab), {}
	for name, value in pairs(blizzard) do
		if type(value) == "table" then
			for filterIndex in pairs(value) do
				if not clicky[name][filterIndex] then out[#out + 1] = ("%s %d unticked by Blizzard"):format(name, filterIndex) end
			end
			for filterIndex in pairs(clicky[name]) do
				if not value[filterIndex] then out[#out + 1] = ("%s %d unticked by Clicky"):format(name, filterIndex) end
			end
		elseif clicky[name] ~= value then
			out[#out + 1] = ("%s: Blizzard's %s, Clicky's %s"):format(name, tostring(value), tostring(clicky[name]))
		end
	end
	table.sort(out)
	return out
end

-- Why Clicky's tab leaves out an entry the window lists: the filter (GridFilters.lua), or that it
-- isn't one the tab lists at all (Toys.lua, Mounts.lua: not in Clicky's list, hidden on this
-- character, listed only when collected, or no data in the game). Pets are compared by species,
-- which has no one entry to ask about.
local function WhyLeftOut(tab, window, filters, id)
	local key = window.key and window.key(id)
	if not key then
		return nil
	elseif ns.GetToyList().index[key] == nil then
		return "not in Clicky's list"
	end
	local failure = ns.GridFilterFailure(tab, filters, key, ns.IsEntryOwned(key))
	if failure == "sources" and tab == "mounts" then
		-- Which checkbox a source is was inferred (GridFilters.lua, Off): name the one Clicky used.
		local source = ns.MountSource(id)
		return ("Clicky's sources filter, Sources %s"):format(source and tostring(source + 1) or "none")
	end
	return failure and ("Clicky's " .. failure .. " filter") or "not one the tab lists"
end

local function Named(window, ids, why)
	local names = {}
	for id in pairs(ids) do names[#names + 1] = id end
	table.sort(names)
	local out = {}
	for i = 1, math.min(#names, SHOWN) do
		local reason = why and why(names[i])
		out[i] = ("%s (%s%s)"):format(window.name(names[i]), tostring(names[i]), reason and (": " .. reason) or "")
	end
	return table.concat(out, ", ") .. (#names > SHOWN and ", ..." or "")
end

function ns.CheckAgainstBlizzard(tab)
	local window = WINDOWS[tab]
	local search = window.search()
	if search and search ~= "" then
		return ("not checked: %s has a search (%q)"):format(window.title, search)
	end
	local filters = window.read()
	local listed = window.listed()
	local section
	for _, s in ipairs(ns.GridSections({ [tab] = filters }, "")) do
		if s.name == tab then section = s end
	end
	local clicky = {}
	for _, key in ipairs(section.keys) do
		clicky[window.id(key)] = true
	end
	local onlyClicky, onlyBlizzard, n, m = {}, {}, 0, 0
	for id in pairs(clicky) do
		n = n + 1
		if not listed[id] then onlyClicky[id] = true end
	end
	for id in pairs(listed) do
		m = m + 1
		if not clicky[id] then onlyBlizzard[id] = true end
	end
	local line
	if next(onlyClicky) == nil and next(onlyBlizzard) == nil then
		line = ("matches %s with its filters (%d)"):format(window.title, n)
	else
		line = ("Clicky lists %d, %s %d with its filters (%s)"):format(n, window.title, m,
			ns.DescribeGridFilters(filters))
		if next(onlyClicky) then line = line .. "; only Clicky: " .. Named(window, onlyClicky) end
		if next(onlyBlizzard) then
			line = line .. "; only " .. window.title .. ": " .. Named(window, onlyBlizzard, function(id)
				return WhyLeftOut(tab, window, filters, id)
			end)
		end
	end
	if window.isDefault() then
		local differ = DefaultsDiffer(tab, filters)
		line = line .. (#differ == 0 and "; its defaults are Clicky's"
			or "; its defaults differ from Clicky's: " .. table.concat(differ, ", "))
	end
	return line
end

-- Which Sources box a source number is under isn't in Blizzard's source (GridFilters.lua, Off), so
-- it's checked against what the game says of each mount and species: the source text the Mount
-- Journal and the Pet Journal show for it (GetMountInfoExtraByID's third value,
-- Blizzard_MountCollection.lua:736, 759; GetPetInfoBySpeciesID's fifth, tooltipSource), which
-- often starts with its source's name, as "Drop: ...", and often doesn't ("Legacy", "Zone: ...":
-- seen in play). So the check is which numbering most texts agree with: Clicky's, or one off by
-- one; only entries that agree with a shifted one are named. Every source is checked at once,
-- whatever the windows' filters, so a patch that numbers them differently shows here.
local SOURCES = {
	mounts = function()
		local out = {}
		for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
			local name = C_MountJournal.GetMountInfoByID(mountID)
			if name then
				out[#out + 1] = { name = name, id = mountID, source = ns.MountSource(mountID),
					text = select(3, C_MountJournal.GetMountInfoExtraByID(mountID)) }
			end
		end
		return out
	end,
	pets = function()
		local out = {}
		for speciesID, source in pairs(ns.GetToyList().petSource) do
			local name, _, _, _, text = C_PetJournal.GetPetInfoBySpeciesID(speciesID)
			if name then
				out[#out + 1] = { name = name, id = speciesID, source = source, text = text }
			end
		end
		return out
	end,
}

-- Color codes, textures and line breaks taken out (warcraft.wiki.gg UI escape sequences).
local function Plain(text)
	return (text:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|r", ""):gsub("|T.-|t", ""):gsub("|n", " "))
end

-- Whether text starts with the label of the Sources box the source number plus shift is under.
local function Says(text, source, shift)
	local label = ns.SourceLabel(source + shift)
	return label ~= nil and text:lower():sub(1, #label) == label:lower()
end

function ns.CheckSources(tab)
	local agree, checked, lower, higher, shifted = 0, 0, 0, 0, {}
	for _, entry in ipairs(SOURCES[tab]()) do
		local text = type(entry.text) == "string" and not issecretvalue(entry.text) and strtrim(Plain(entry.text))
		-- A mount with no source number (sourceType 0, seen in play) is under no box: not checked.
		if entry.source and ns.SourceLabel(entry.source) and text and text ~= "" then
			checked = checked + 1
			local right, down, up = Says(text, entry.source, 0), Says(text, entry.source, -1), Says(text, entry.source, 1)
			agree, lower, higher = agree + (right and 1 or 0), lower + (down and 1 or 0), higher + (up and 1 or 0)
			if not right and (down or up) then
				shifted[#shifted + 1] = ("%s (%s: under %s, says %q)"):format(entry.name, tostring(entry.id),
					tostring(ns.SourceLabel(entry.source)), text:sub(1, 40))
			end
		end
	end
	table.sort(shifted)
	local shown = { unpack(shifted, 1, math.min(#shifted, SHOWN)) }
	return ("%d of %d agree%s (numbered one lower %d, one higher %d)%s"):format(agree, checked,
		(lower > agree or higher > agree) and ": ANOTHER NUMBERING AGREES MORE" or "", lower, higher,
		#shown > 0 and ("; agree only when shifted: " .. table.concat(shown, ", ") .. (#shifted > #shown and ", ..." or "")) or "")
end
