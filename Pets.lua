-- The pet kind of entry (Entries.lua): a pet's name, icon, tooltip, owned and usable test, star,
-- gift wrap and secure action. A pet is the key "p", its species ID, ":" and the display ID of its
-- look: a species can come in several looks (colors), and each is an entry, which stands for every
-- pet the player owns of that species and look. A pet can have a look no table gives its species (seen in play),
-- so each species also has the look 0, which stands for its pets whose look Clicky's list doesn't
-- have, or, when there are none, all its pets. A later list can add such a look (it only grows), and
-- a macro holding the 0 then still has the species' pets rather than none.
--   ns.ListedPetEntries(uncollected)   the pets the grid can list: the looks the player owns that are
--                          in Clicky's list, and with uncollected one entry for each species the
--                          player owns none of, as the Pet Journal lists it, less those in PET_HIDDEN
--                          (ToyList.lua): its first look the game lists, or its 0; in no order
--   ns.PetFamily(id), ns.PetCanBattle(id)   the species' family (1 is Humanoid, as PET_TYPE_SUFFIX,
--                          Constants.lua) and whether it can battle (GetPetInfoBySpeciesID)
--   ns.PetSource(id)       Enum.BattlePetSources (ToyList.lua's PET_SOURCE), or nil
--   ns.PetLevel(id), ns.PetRarity(id)   of the pet the entry uses (GetPetInfoByPetID, GetPetStats), or
--                          0 for a look not owned
--   ns.GetPetState()       for /clicky debug: pets owned, their looks, how many pets have a look
--                          Clicky's list doesn't have, with those looks, and how many the Pet Journal
--                          lists with its own filters (to set to Not Collected and compare)
--   ns.GetPetLookAudit()   for /clicky debug: the looks the game lists for every species in Clicky's
--                          list (C_PetJournal.GetNumDisplays and GetDisplayIDByIndex answer for any
--                          species, owned or not) that the list doesn't have
--
-- GetOwnedPetIDs lists every pet the player owns, whatever the Pet Journal's filters (they're the
-- player's settings), and GetPetInfoByPetID gives a pet's species and look (its displayID). A pet is
-- summoned by the secure "macro" action running "/summonpet" with its GUID (SECURE_ACTIONS.macro,
-- SecureTemplates.lua), which calls C_PetJournal.SummonPetByGUID (SlashCommands.lua), on a drawer
-- button; a macro's button calls SummonPetByGUID itself (the kind's use). Summoning the pet that's
-- out puts it away, as /dismisspet does with the same call (SlashCommands.lua), so a click on a
-- macro doesn't pick it: of a look's pets, the one used is one that isn't out and can be
-- summoned (C_PetJournal.PetIsSummonable), a starred one first. The drawer uses the one that's out
-- when there's no other, which puts it away, as the Pet Journal's Summon button does
-- (Blizzard_PetCollection.lua).

local _, ns = ...

local looks -- "species:display" -> the GUIDs of the pets of that look, in GetOwnedPetIDs' order
local unlisted = {} -- "species:display" -> how many pets have that look, which Clicky's list doesn't
-- (they're under "species:0")
local bySpecies = {} -- species ID -> the GUIDs of its pets, every look

local function Read()
	if looks then
		return looks
	end
	looks, unlisted, bySpecies = {}, {}, {}
	local index = ns.GetToyList().index
	local owned = C_PetJournal.GetOwnedPetIDs()
	for _, guid in ipairs(owned) do
		local speciesID, _, _, _, _, displayID = C_PetJournal.GetPetInfoByPetID(guid)
		if speciesID and displayID then
			local id = speciesID .. ":" .. displayID
			if index["p" .. id] == nil then
				unlisted[id] = (unlisted[id] or 0) + 1
				id = speciesID .. ":0"
			end
			looks[id] = looks[id] or {}
			table.insert(looks[id], guid)
			bySpecies[speciesID] = bySpecies[speciesID] or {}
			table.insert(bySpecies[speciesID], guid)
		end
	end
	ns.Trace("[pets] read %d pets", #owned)
	return looks
end

local function PetsOf(id)
	local pets = Read()[id]
	if pets then
		return pets
	end
	local speciesID = tonumber(id:match("^(%d+):0$"))
	return speciesID and bySpecies[speciesID] or {}
end

-- The pet a click summons: not out, summonable, a starred one first; nil if none.
local function Summonable(id)
	local out, found = C_PetJournal.GetSummonedPetGUID(), nil
	for _, guid in ipairs(PetsOf(id)) do
		if guid ~= out and C_PetJournal.PetIsSummonable(guid) then
			if C_PetJournal.PetIsFavorite(guid) then
				return guid
			end
			found = found or guid
		end
	end
	return found
end

-- The annotations give these two no parameters; Blizzard passes the pet's GUID (see the pet kind).
local function NeedsFanfare(guid)
	---@diagnostic disable-next-line: redundant-parameter
	return C_PetJournal.PetNeedsFanfare(guid)
end

local function ClearFanfare(guid)
	---@diagnostic disable-next-line: redundant-parameter
	C_PetJournal.ClearFanfare(guid)
end

local function IsWrapped(id)
	for _, guid in ipairs(PetsOf(id)) do
		if NeedsFanfare(guid) then
			return true
		end
	end
	return false
end

-- The pet the entry shows and uses: the one a click summons, else the look's pet that's out (using
-- it puts it away), else the first.
local function Shown(id)
	local guid = Summonable(id)
	if guid then
		return guid
	end
	local out = C_PetJournal.GetSummonedPetGUID()
	for _, pet in ipairs(PetsOf(id)) do
		if pet == out then
			return pet
		end
	end
	return PetsOf(id)[1]
end

-- The Pet Journal draws each pet's cooldown on its button (GetPetCooldownByGUID,
-- Blizzard_PetCollection.lua:866-870, 1068-1074). A look shows the one of its pets that ends last.
-- After a summon the game gives its global cooldown to some pets and not others, the same ones each
-- time (984 of 1738), and the Pet Journal shows a swipe on those and not the rest, as Clicky does
-- (seen in play).
local function LastCooldown(id)
	local start, duration, enable, ends = 0, 0, 1, 0
	for _, guid in ipairs(PetsOf(id)) do
		local s, d, e = C_PetJournal.GetPetCooldownByGUID(guid)
		if s and s > 0 and d and d > 0 and s + d > ends then
			start, duration, enable, ends = s, d, e, s + d
		end
	end
	return start, duration, enable
end

-- As for toys: the pet a click would use, past the global cooldown.
local function IsOnCooldown(id)
	local guid = Summonable(id)
	if not guid then
		return false
	end
	local start, duration = C_PetJournal.GetPetCooldownByGUID(guid)
	return start ~= nil and start > 0 and duration ~= nil and duration > ns.GCD_THRESHOLD
end

local function Species(id)
	return tonumber(id:match("^(%d+):"))
end

local species -- the species in Clicky's list, made when first asked for: the list never changes

local function ListedSpecies()
	if not species then
		species = {}
		for _, entry in ipairs(ns.GetToyList().entries) do
			local id = type(entry) == "string" and tonumber(entry:match("^p(%d+):0$"))
			if id then
				species[#species + 1] = id
			end
		end
	end
	return species
end

function ns.ListedPetEntries(uncollected)
	local list = ns.GetToyList()
	local keys, owned = {}, {}
	for id in pairs(Read()) do
		owned[Species(id)] = true
		if list.index["p" .. id] ~= nil then
			keys[#keys + 1] = "p" .. id
		end
	end
	if uncollected then
		for _, speciesID in ipairs(ListedSpecies()) do
			-- A species the game has no data for on this computer would be a blank slot.
			if not owned[speciesID] and not list.petHidden[speciesID] and C_PetJournal.GetPetInfoBySpeciesID(speciesID) then
				local key = "p" .. speciesID .. ":" .. (C_PetJournal.GetDisplayIDByIndex(speciesID, 1) or 0)
				keys[#keys + 1] = list.index[key] ~= nil and key or "p" .. speciesID .. ":0"
			end
		end
	end
	return keys
end

function ns.PetFamily(id)
	return (select(3, C_PetJournal.GetPetInfoBySpeciesID(Species(id))))
end

function ns.PetCanBattle(id)
	return select(8, C_PetJournal.GetPetInfoBySpeciesID(Species(id))) == true
end

function ns.PetSource(id)
	return ns.GetToyList().petSource[Species(id)]
end

function ns.PetLevel(id)
	local guid = Shown(id)
	return guid and select(3, C_PetJournal.GetPetInfoByPetID(guid)) or 0
end

function ns.PetRarity(id)
	local guid = Shown(id)
	return guid and select(5, C_PetJournal.GetPetStats(guid)) or 0
end

function ns.GetPetState()
	local n, missing, missed = 0, 0, {}
	for _ in pairs(Read()) do
		n = n + 1
	end
	for id, count in pairs(unlisted) do
		missing = missing + count
		missed[#missed + 1] = "p" .. id
	end
	table.sort(missed)
	-- GetNumPets is the Pet Journal's list as its filters have it: the journal walks it so
	-- (Blizzard_PetCollection.lua:876).
	return ("%d pets owned in %d looks, %d of them with a look Clicky's list doesn't have, under their species' other looks%s; the Pet Journal lists %d with its own filters"):format(
		#C_PetJournal.GetOwnedPetIDs(), n, missing, #missed > 0 and (" (" .. table.concat(missed, ", ") .. ")") or "",
		(C_PetJournal.GetNumPets()))
end

local AUDIT_SHOWN = 20 -- looks named, at most

-- A species whose looks are random has none listed on purpose, so it isn't checked.
function ns.GetPetLookAudit()
	local list = ns.GetToyList()
	local checked, listed, missing = 0, 0, {}
	for _, speciesID in ipairs(ListedSpecies()) do
		checked = checked + 1
		for i = 1, not list.petRandomLook[speciesID] and C_PetJournal.GetNumDisplays(speciesID) or 0 do
			local displayID = C_PetJournal.GetDisplayIDByIndex(speciesID, i)
			if displayID then
				listed = listed + 1
				if list.index["p" .. speciesID .. ":" .. displayID] == nil then
					missing[#missing + 1] = "p" .. speciesID .. ":" .. displayID
				end
			end
		end
	end
	table.sort(missing)
	local shown = { unpack(missing, 1, math.min(#missing, AUDIT_SHOWN)) }
	return ("the game lists %d looks for the list's %d species, %d of them not in the list%s"):format(listed, checked,
		#missing, #shown > 0 and (" (" .. table.concat(shown, ", ") .. (#missing > #shown and ", ..." or "") .. ")") or "")
end

ns.RegisterEntryKind("pet", {
	-- The species' name and icon (GetPetInfoBySpeciesID's first two): a look has none of its own.
	name = function(id) return (C_PetJournal.GetPetInfoBySpeciesID(Species(id))) or "" end,
	icon = function(id) return (select(2, C_PetJournal.GetPetInfoBySpeciesID(Species(id)))) end,
	owned = function(id) return PetsOf(id)[1] ~= nil end,
	usable = function(id) return Summonable(id) ~= nil end,
	onCooldown = IsOnCooldown,
	updateCooldown = function(cooldown, id) CooldownFrame_Set(cooldown, LastCooldown(id)) end,
	-- The Pet Journal's tooltip, link and drag (Blizzard_PetCollection.lua: SetCompanionPet,
	-- GetBattlePetLink, PickupPet), with the pet the entry uses; a look not owned has only its name.
	tooltip = function(owner, id, anchor)
		GameTooltip:SetOwner(owner, anchor)
		local guid = Shown(id)
		if guid then
			-- The annotations give it no parameters; Blizzard passes the pet's GUID.
			---@diagnostic disable-next-line: redundant-parameter
			GameTooltip:SetCompanionPet(guid)
		else
			GameTooltip:SetText((C_PetJournal.GetPetInfoBySpeciesID(Species(id))) or "")
		end
		GameTooltip:Show()
	end,
	link = function(id)
		local guid = Shown(id)
		return guid and C_PetJournal.GetBattlePetLink(guid)
	end,
	pickup = function(id)
		local guid = Shown(id)
		if guid then
			C_PetJournal.PickupPet(guid)
		end
	end,
	action = function(id)
		local guid = Shown(id)
		return "macro", "macrotext", guid and ("/summonpet " .. guid)
	end,
	-- A macro's button summons from addon code, after the click (Entries.lua's use): /summonpet
	-- run by the secure "macro" action summoned nothing on a button the player's macro clicked, and
	-- did on a drawer button clicked with the mouse (seen in play). C_PetJournal.SummonPetByGUID
	-- puts away the pet that's out when given it, so with no pet of the look that isn't out nothing
	-- is summoned.
	use = function(id)
		local guid = Summonable(id)
		if guid then
			C_PetJournal.SummonPetByGUID(guid)
		end
	end,
	drawerOnly = function() return false end,
	-- The tooltip of the pet the entry uses; a look not owned has none.
	tooltipData = function(id)
		local guid = Shown(id)
		return guid and C_TooltipInfo.GetCompanionPet(guid)
	end,
	-- A look is starred if any of its pets is. Starring stars the pet the entry uses; unstarring
	-- clears every pet of the look, so the star goes (SetFavorite takes 1 or 0, as the Pet Journal
	-- calls it, Blizzard_PetCollection.lua).
	favorite = function(id)
		for _, guid in ipairs(PetsOf(id)) do
			if C_PetJournal.PetIsFavorite(guid) then
				return true
			end
		end
		return false
	end,
	-- A wrapped pet's menu offers only Unwrap (Blizzard_PetCollection.lua:895-901).
	canFavorite = function(id)
		if PetsOf(id)[1] == nil then
			return false, "You have no pet of that look."
		elseif IsWrapped(id) then
			return false, "Open that pet's gift wrap first: click it in the grid."
		end
		return true
	end,
	-- A look is wrapped while any of its pets is; unwrapping opens each of them. PetNeedsFanfare and
	-- ClearFanfare take the pet's GUID (Blizzard_PetCollection.lua:770-785, 895-901, 1443-1455); the
	-- Blizzard documentation doesn't list them.
	wrapped = IsWrapped,
	-- The Pet Journal shows a wrapped pet as the gift (Blizzard_PetCollection.lua:770-785).
	gift = true,
	unwrap = function(id)
		for _, guid in ipairs(PetsOf(id)) do
			if NeedsFanfare(guid) then
				ClearFanfare(guid)
			end
		end
	end,
	-- One of the look's pets is out, which the Pet Journal marks (PetJournal_InitPetButton,
	-- Blizzard_PetCollection.lua:845).
	active = function(id)
		local out = C_PetJournal.GetSummonedPetGUID()
		for _, guid in ipairs(PetsOf(id)) do
			if guid == out then
				return true
			end
		end
		return false
	end,
	setFavorite = function(id, favorite)
		if favorite then
			C_PetJournal.SetFavorite(Shown(id), 1)
			return
		end
		for _, guid in ipairs(PetsOf(id)) do
			if C_PetJournal.PetIsFavorite(guid) then
				C_PetJournal.SetFavorite(guid, 0)
			end
		end
	end,
})

-- The player's pets changed. The Pet Journal redraws its list on PET_JOURNAL_LIST_UPDATE
-- (Blizzard_PetCollection.lua:262) and on PET_JOURNAL_PET_DELETED, which carries the GUID of a pet
-- it caged (:246-252; the cage is requested at :54). NEW_PET_ADDED announces a pet just collected
-- (AlertFrames.lua:699). Clicky keeps GUIDs, so a caged pet's must go and a new pet's must come.
-- A star set in the Pet Journal: its menu calls SetFavorite and redraws nothing itself (:924-937).
-- No Blizzard source shows which event that fires; Clicky reads stars live, and refreshes on each
-- event the journal redraws its list on but COMPANION_UPDATE (as for mounts, Mounts.lua).
local function PetsChanged(event)
	ns.Trace("[pets] %s, forgetting the pets read", event)
	looks = nil
	ns.Changed()
end
ns.RegisterEvent("PET_JOURNAL_LIST_UPDATE", function() PetsChanged("PET_JOURNAL_LIST_UPDATE") end)
ns.RegisterEvent("PET_JOURNAL_PET_DELETED", function() PetsChanged("PET_JOURNAL_PET_DELETED") end)
ns.RegisterEvent("NEW_PET_ADDED", function() PetsChanged("NEW_PET_ADDED") end)
