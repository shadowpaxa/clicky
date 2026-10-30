-- The grid's Filter menus (Grid.lua): Toys', Mounts' and Pets' each as the Toy Box's, the Mount
-- Journal's and the Pet Journal's own (ToyBox_InitFilterDropdown, Blizzard_ToyBox.lua:90-140;
-- MountJournal_InitFilterButton, Blizzard_MountCollection.lua:184-260;
-- PetJournal_InitFilterDropdown, Blizzard_PetCollection.lua:118-214), with the same labels, order
-- and checks of which sources and types to offer. The journals' own filters are the player's
-- settings, so Clicky keeps its own, which start as each session starts (no saved settings).
--   ns.DefaultGridFilters(tab)         a tab's filters as they start ("toys", "mounts", "pets")
--   ns.GridFiltersAreDefault(tab, f)
--   ns.PassesGridFilters(tab, f, key, owned)   whether an entry the player has (owned) or not passes
--   ns.GridFilterFailure(tab, f, key, owned)   the filter that leaves it out ("unusable", "sources"...),
--                                      or nil if it passes; for /clicky debug
--   ns.SortGridGroup(tab, f, keys, names)      sorts keys in place: by name, or as Pets' Sort by says
--   ns.AddGridFilterMenu(tab, f, rootDescription, changed)   the tab's menu; changed() after a choice
--   ns.SourceLabel(source)             the label of the Sources box an Enum.BattlePetSources value
--                                      is under, or nil
--   ns.EntryFilterLabels(key)          the menus' labels that describe the entry (its source,
--                                      expansion, mount types, pet family), for the search
--   ns.DescribeGridFilters(f)          for /clicky debug: every filter of a tab, the unticked ones
--                                      by filter index
--
-- Sources and the mount types are kept as the ones unticked, so a new source or type in a patch
-- starts ticked. An entry without a source, or whose expansion hasn't loaded, passes those filters.

local _, ns = ...

-- Blizzard_MountCollection.lua:11-17.
local MOUNT_TYPE_STRINGS = {
	[Enum.MountType.Ground] = MOUNT_JOURNAL_FILTER_GROUND,
	[Enum.MountType.Flying] = MOUNT_JOURNAL_FILTER_FLYING,
	[Enum.MountType.Aquatic] = MOUNT_JOURNAL_FILTER_AQUATIC,
	[Enum.MountType.Dragonriding] = MOUNT_JOURNAL_FILTER_DRAGONRIDING,
	[Enum.MountType.RideAlong] = MOUNT_JOURNAL_FILTER_RIDEALONG,
}
-- A mount type's flag for each Enum.MountType but Ground, which is a mount with none
-- (MountConstantsDocumentation.lua).
local MOUNT_TYPE_FLAGS = {
	[Enum.MountType.Flying] = Enum.MountTypeFlag.IsFlyingMount,
	[Enum.MountType.Aquatic] = Enum.MountTypeFlag.IsAquaticMount,
	[Enum.MountType.Dragonriding] = Enum.MountTypeFlag.IsDragonRidingMount,
	[Enum.MountType.RideAlong] = Enum.MountTypeFlag.IsRideAlongMount,
}

function ns.DefaultGridFilters(tab)
	local f = { collected = true, uncollected = false, sourcesOff = {} }
	if tab == "toys" then
		f.usableOnly, f.expansionsOff = false, {}
	elseif tab == "mounts" then
		f.unusable, f.typesOff = true, {}
	else
		f.battlePets, f.nonCombatPets, f.familiesOff, f.sortBy = true, true, {}, LE_SORT_BY_NAME
	end
	return f
end

local function Same(a, b)
	for k, v in pairs(a) do
		if type(v) == "table" then
			if not Same(v, b[k]) or not Same(b[k], v) then
				return false
			end
		elseif b[k] ~= v then
			return false
		end
	end
	return true
end

function ns.GridFiltersAreDefault(tab, f)
	local default = ns.DefaultGridFilters(tab)
	return Same(f, default) and Same(default, f)
end

-- Every tab's filters, in this order, each a tab has.
local DESCRIBED = {
	{ "collected", "collected" }, { "uncollected", "not collected" }, { "usableOnly", "usable only" },
	{ "unusable", "unusable" }, { "battlePets", "battle pets" }, { "nonCombatPets", "non-combat pets" },
	{ "typesOff", "types off" }, { "familiesOff", "families off" }, { "sourcesOff", "sources off" },
	{ "expansionsOff", "expansions off" }, { "sortBy", "sort by" },
}

function ns.DescribeGridFilters(f)
	local parts = {}
	for _, field in ipairs(DESCRIBED) do
		local value = f[field[1]]
		if type(value) == "table" then
			local off = {}
			for filterIndex in pairs(value) do off[#off + 1] = filterIndex end
			table.sort(off)
			parts[#parts + 1] = ("%s %s"):format(field[2], #off > 0 and table.concat(off, " ") or "none")
		elseif value ~= nil then
			parts[#parts + 1] = ("%s %s"):format(field[2], tostring(value))
		end
	end
	return table.concat(parts, ", ")
end

-- A filter index is the value plus one: the menus number their checkboxes from 1, and
-- EXPANSION_NAME0 is filter index 1 (Blizzard_ToyBox.lua:136-137). For sources this is inferred
-- (BATTLE_PET_SOURCE_1 for Enum.BattlePetSources.Drop, 0): Blizzard's source doesn't tie the two, so
-- it's checked in play, with the Blizzard windows' counts in /clicky debug. For mounts it was seen
-- with a source unticked (Mounts.lua, ns.MountSource); for toys and pets only with none unticked.
local function Off(set, value)
	return value ~= nil and set[value + 1] == true
end

local function MountTypeOff(f, mountID)
	local flags = ns.MountTypeFlags(mountID)
	if flags == 0 then
		return f.typesOff[Enum.MountType.Ground + 1] == true
	end
	for mountType, flag in pairs(MOUNT_TYPE_FLAGS) do
		if bit.band(flags, flag) ~= 0 and not f.typesOff[mountType + 1] then
			return false
		end
	end
	return true
end

function ns.GridFilterFailure(tab, f, key, owned)
	if owned and not f.collected then
		return "collected"
	elseif not owned and not f.uncollected then
		return "not collected"
	end
	local id = ns.EntryID(key)
	if tab == "toys" then
		if f.usableOnly and owned and not ns.IsEntryUsable(key) then
			return "usable only"
		elseif Off(f.sourcesOff, ns.ToySource(id)) then
			return "sources"
		elseif Off(f.expansionsOff, ns.ToyExpansion(id)) then
			return "expansions"
		end
	elseif tab == "mounts" then
		if not f.unusable and owned and not ns.IsEntryUsable(key) then
			return "unusable"
		elseif Off(f.sourcesOff, ns.MountSource(id)) then
			return "sources"
		elseif MountTypeOff(f, id) then
			return "types"
		end
	else
		local battle = ns.PetCanBattle(id)
		if battle and not f.battlePets then
			return "battle pets"
		elseif not battle and not f.nonCombatPets then
			return "non-combat pets"
		elseif f.familiesOff[ns.PetFamily(id) or 0] then
			return "pet families"
		elseif Off(f.sourcesOff, ns.PetSource(id)) then
			return "sources"
		end
	end
end

function ns.PassesGridFilters(tab, f, key, owned)
	return ns.GridFilterFailure(tab, f, key, owned) == nil
end

-- The Pet Journal's Sort by sets the player's own sort setting (Blizzard_PetCollection.lua:150-153),
-- which Clicky never changes, so Clicky sorts itself: by name, by level or rarity highest first, by family in its order;
-- then by name.
local PET_SORT = {
	[LE_SORT_BY_LEVEL] = function(id) return -ns.PetLevel(id) end,
	[LE_SORT_BY_RARITY] = function(id) return -ns.PetRarity(id) end,
	[LE_SORT_BY_PETTYPE] = function(id) return ns.PetFamily(id) or 0 end,
}

function ns.SortGridGroup(tab, f, keys, names)
	ns.SortEntries(keys, names)
	local By = tab == "pets" and PET_SORT[f.sortBy]
	if By then
		local order, rank = {}, {}
		for i, key in ipairs(keys) do
			order[key], rank[key] = i, By(ns.EntryID(key))
		end
		table.sort(keys, function(a, b)
			if rank[a] ~= rank[b] then
				return rank[a] < rank[b]
			end
			return order[a] < order[b]
		end)
	end
end

------------------------------------------------------------------------------------------
-- The menus.

-- A submenu of checkboxes with Check All and Uncheck All, for a set of unticked filter indexes.
local function Submenu(rootDescription, text, off, count, valid, label, changed)
	local submenu = rootDescription:CreateButton(text)
	submenu:CreateButton(CHECK_ALL, function()
		wipe(off)
		changed()
	end)
	submenu:CreateButton(UNCHECK_ALL, function()
		for filterIndex = 1, count do
			off[filterIndex] = true
		end
		changed()
	end)
	for filterIndex = 1, count do
		if not valid or valid(filterIndex) then
			submenu:CreateCheckbox(label(filterIndex), function()
				return not off[filterIndex]
			end, function()
				off[filterIndex] = not off[filterIndex] or nil
				changed()
			end)
		end
	end
end

local function Checkbox(rootDescription, text, f, name, changed)
	rootDescription:CreateCheckbox(text, function()
		return f[name]
	end, function()
		f[name] = not f[name]
		ns.Trace("[grid] filter %s %s", name, tostring(f[name]))
		changed()
	end)
end

local function SourceLabel(filterIndex)
	return _G["BATTLE_PET_SOURCE_" .. filterIndex]
end

function ns.SourceLabel(source)
	return source and SourceLabel(source + 1)
end

function ns.EntryFilterLabels(key)
	local kind, id, labels = ns.EntryKind(key), ns.EntryID(key), {}
	local function Add(text)
		if text then
			labels[#labels + 1] = text
		end
	end
	local function Source(source)
		Add(ns.SourceLabel(source))
	end
	if kind == "toy" then
		Source(ns.ToySource(id))
		local expansion = ns.ToyExpansion(id)
		Add(expansion and _G["EXPANSION_NAME" .. expansion])
	elseif kind == "mount" then
		Source(ns.MountSource(id))
		local flags = ns.MountTypeFlags(id)
		if flags == 0 then
			Add(MOUNT_TYPE_STRINGS[Enum.MountType.Ground])
		end
		for mountType, flag in pairs(MOUNT_TYPE_FLAGS) do
			if bit.band(flags, flag) ~= 0 then
				Add(MOUNT_TYPE_STRINGS[mountType])
			end
		end
	elseif kind == "pet" then
		Source(ns.PetSource(id))
		local family = ns.PetFamily(id)
		Add(family and _G["BATTLE_PET_NAME_" .. family])
	end
	return labels
end

function ns.AddGridFilterMenu(tab, f, rootDescription, changed)
	Checkbox(rootDescription, COLLECTED, f, "collected", changed)
	Checkbox(rootDescription, NOT_COLLECTED, f, "uncollected", changed)
	local numSources = C_PetJournal.GetNumPetSources()
	if tab == "toys" then
		Checkbox(rootDescription, PET_JOURNAL_FILTER_USABLE_ONLY, f, "usableOnly", changed)
		Submenu(rootDescription, SOURCES, f.sourcesOff, numSources, C_ToyBoxInfo.IsToySourceValid, SourceLabel, changed)
		-- EXPANSION_NAME is numbered from 0 (Blizzard_ToyBox.lua:136-137).
		Submenu(rootDescription, EXPANSION_FILTER_TEXT, f.expansionsOff, GetNumExpansions(), nil, function(filterIndex)
			return _G["EXPANSION_NAME" .. (filterIndex - 1)]
		end, changed)
	elseif tab == "mounts" then
		Checkbox(rootDescription, MOUNT_JOURNAL_FILTER_UNUSABLE, f, "unusable", changed)
		rootDescription:CreateSpacer()
		rootDescription:CreateTitle(MOUNT_JOURNAL_FILTER_TYPE)
		for filterIndex = 1, Enum.MountTypeMeta.NumValues do
			if C_MountJournal.IsValidTypeFilter(filterIndex) then
				rootDescription:CreateCheckbox(MOUNT_TYPE_STRINGS[filterIndex - 1], function()
					return not f.typesOff[filterIndex]
				end, function()
					f.typesOff[filterIndex] = not f.typesOff[filterIndex] or nil
					changed()
				end)
			end
		end
		Submenu(rootDescription, SOURCES, f.sourcesOff, numSources, C_MountJournal.IsValidSourceFilter, SourceLabel, changed)
	else
		rootDescription:CreateDivider()
		rootDescription:CreateTitle(PET_FILTER_TYPES)
		Checkbox(rootDescription, PET_FILTER_BATTLE_PETS, f, "battlePets", changed)
		Checkbox(rootDescription, PET_FILTER_NON_COMBAT_PETS, f, "nonCombatPets", changed)
		Submenu(rootDescription, PET_FAMILIES, f.familiesOff, C_PetJournal.GetNumPetTypes(), nil, function(filterIndex)
			return _G["BATTLE_PET_NAME_" .. filterIndex]
		end, changed)
		Submenu(rootDescription, SOURCES, f.sourcesOff, numSources, nil, SourceLabel, changed)
		local sortBy = rootDescription:CreateButton(RAID_FRAME_SORT_LABEL)
		for _, choice in ipairs({ { NAME, LE_SORT_BY_NAME }, { LEVEL, LE_SORT_BY_LEVEL },
			{ RARITY, LE_SORT_BY_RARITY }, { TYPE, LE_SORT_BY_PETTYPE } }) do
			sortBy:CreateRadio(choice[1], function()
				return f.sortBy == choice[2]
			end, function()
				f.sortBy = choice[2]
				changed()
			end)
		end
	end
end
