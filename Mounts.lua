-- The mount kind of entry (Entries.lua): a mount's name, icon, tooltip, owned and usable test, star
-- and secure action. A mount is the key "m" and its mount ID.
--   ns.ListedMountEntries(uncollected)   the mounts in Clicky's list the grid can list: the ones
--                                collected, and with uncollected the rest, less those in
--                                MOUNT_HIDDEN (ToyList.lua); none the game hides on this character
--                                (shouldHideOnChar) or has no data for; in no order
--   ns.MountSource(mountID)      Enum.BattlePetSources: GetMountInfoByID's sourceType less one
--   ns.MountTypeFlags(mountID)   its mountTypeID's (GetMountInfoExtraByID) Type in the MountType table
--                                (ToyList.lua's MOUNT_TYPE), read as Enum.MountTypeFlag: its values
--                                fit (0 for the ground mounts, 2 for the turtles, 5 for most flyers:
--                                flying and dragonriding), though nothing documents it
--   ns.GetMountState()           for /clicky debug: how many mounts the Mount Journal lists with its
--                                own filters, to set to Not Collected and compare with the grid's
--
-- GetMountInfoByID answers for any mount, whatever the Mount Journal's filters (they're the
-- player's settings), and GetMountIDs lists every mount. The Mount Journal summons with
-- C_MountJournal.SummonByID (Blizzard_MountCollection.lua), which no secure action calls. Casting the
-- mount's spell by ID didn't summon it (seen in play), so the secure "spell" action is given the
-- spell's name, which it casts with CastSpellByName as /cast does (SECURE_ACTIONS.spell,
-- SecureTemplates.lua).
-- The game stars and picks up a mount only by its place in the Mount Journal's list
-- (C_MountJournal.SetIsFavorite and Pickup take a displayIndex, MountJournalDocumentation.lua),
-- which the journal's filters decide, so a mount they hide can't be starred or dragged from here.

local _, ns = ...

-- name, spellID, icon, isActive, isUsable, sourceType, isFavorite, isFactionSpecific, faction,
-- shouldHideOnChar, isCollected (MountJournalDocumentation.lua); nothing for a mount the game
-- doesn't have (MayReturnNothing).
local function Info(mountID)
	return C_MountJournal.GetMountInfoByID(mountID)
end

local function Spell(mountID)
	return (select(2, Info(mountID)))
end

-- The mount's place in the Mount Journal's list as its filters have it, or nil.
local function DisplayIndex(mountID)
	for index = 1, C_MountJournal.GetNumDisplayedMounts() do
		if C_MountJournal.GetDisplayedMountID(index) == mountID then
			return index
		end
	end
end

function ns.ListedMountEntries(uncollected)
	local list = ns.GetToyList()
	local keys = {}
	for _, mountID in ipairs(C_MountJournal.GetMountIDs()) do
		local key = "m" .. mountID
		local name, _, _, _, _, _, _, _, _, hidden, collected = Info(mountID)
		if name and not hidden and list.index[key] ~= nil
			and (collected or uncollected and not list.mountHidden[mountID]) then
			keys[#keys + 1] = key
		end
	end
	return keys
end

-- A mount's sourceType counts from 1, as the Sources menu's checkboxes do, where Enum.BattlePetSources
-- counts from 0: the Mount Journal with its Sources 5 unticked kept the 57 mounts of sourceType 4,
-- the profession mounts (Profession is 3), seen in play.
function ns.MountSource(mountID)
	local sourceType = select(6, Info(mountID))
	return sourceType and sourceType - 1
end

function ns.MountTypeFlags(mountID)
	local mountTypeID = select(5, C_MountJournal.GetMountInfoExtraByID(mountID))
	return mountTypeID and ns.GetToyList().mountType[mountTypeID] or 0
end

-- GetNumDisplayedMounts is the Mount Journal's list as its filters have it (MountJournalDocumentation.lua).
function ns.GetMountState()
	return ("the Mount Journal lists %d with its own filters"):format(C_MountJournal.GetNumDisplayedMounts())
end

ns.RegisterEntryKind("mount", {
	name = function(mountID) return (Info(mountID)) or "" end,
	icon = function(mountID) return (select(3, Info(mountID))) end,
	owned = function(mountID) return select(11, Info(mountID)) == true end,
	usable = function(mountID) return select(5, Info(mountID)) == true end,
	onCooldown = function() return false end,
	updateCooldown = function(cooldown) cooldown:Clear() end,
	-- The Mount Journal's tooltip and link (Blizzard_MountCollection.lua: SetMountBySpellID,
	-- GetMountLink with the spell ID).
	tooltip = function(owner, mountID, anchor)
		GameTooltip:SetOwner(owner, anchor)
		local spellID = Spell(mountID)
		if spellID then
			-- The annotations give it no parameters; Blizzard passes the spell ID.
			---@diagnostic disable-next-line: redundant-parameter
			GameTooltip:SetMountBySpellID(spellID)
		end
		GameTooltip:Show()
	end,
	link = function(mountID)
		local spellID = Spell(mountID)
		return spellID and C_MountJournal.GetMountLink(spellID)
	end,
	pickup = function(mountID)
		local at = DisplayIndex(mountID)
		if at then
			C_MountJournal.Pickup(at)
		end
	end,
	action = function(mountID)
		local spellID = Spell(mountID)
		return "spell", "spell", spellID and C_Spell.GetSpellName(spellID)
	end,
	drawerOnly = function() return false end,
	tooltipData = function(mountID)
		local spellID = Spell(mountID)
		return spellID and C_TooltipInfo.GetMountBySpellID(spellID)
	end,
	active = function(mountID) return select(4, Info(mountID)) == true end,
	favorite = function(mountID) return select(7, Info(mountID)) == true end,
	-- As the Mount Journal's menu: GetIsFavorite's second value says whether it can be starred.
	canFavorite = function(mountID)
		local at = DisplayIndex(mountID)
		return at ~= nil and select(2, C_MountJournal.GetIsFavorite(at)) == true
	end,
	setFavorite = function(mountID, favorite)
		local at = DisplayIndex(mountID)
		if at then
			C_MountJournal.SetIsFavorite(at, favorite)
		end
	end,
})

-- A mount learned, and where the player is changing which mounts can be used.
ns.RegisterEvent("NEW_MOUNT_ADDED", ns.Changed)
ns.RegisterEvent("MOUNT_JOURNAL_USABILITY_CHANGED", ns.Changed)
