-- Clicky's list of entries, which macros are encoded against; and the toy kind of entry, which
-- Entries.lua dispatches to: a toy's name, icon, tooltip, cooldown, owned and usable test and
-- secure action.
--   ns.GetToyList()            { ids (the toys' item IDs, in ToyList.lua's order), index (entry
--                              key -> 0-based place in the whole list), entries (the whole list: a
--                              toy is its item ID, a spell "s" and an ID, an item "i" and an ID, a
--                              mount "m" and an ID, a pet "p", a species ID, ":" and a display ID,
--                              which are also entry keys, Entries.lua), hidden (item ID -> true:
--                              the toys listed only when owned, ToyList.lua), mountHidden (mount ID
--                              -> true) and petHidden (species ID -> true; the mounts and pet
--                              species listed only when the player has them), petRandomLook
--                              (species ID -> true: a look each summon, so its pets are its 0),
--                              toySource, petSource (ID -> Enum.BattlePetSources) and mountType
--                              (mountTypeID -> Enum.MountTypeFlag): the game has no API for these }
--   ns.ToySource(itemID)       Enum.BattlePetSources, or nil for a toy without a source
--   ns.ToyExpansion(itemID)    its expansion ID (C_Item.GetItemInfo), or nil until its data loads
--   ns.GetToyBoxState()        for /clicky debug: how many toys the Toy Box lists with its own
--                              filters, to set as Clicky's and compare
--   ns.ListedToyEntries(uncollected)   the toys the grid can list: the ones owned, and with
--                              uncollected the rest the Toy Box lists; in no order
--   ns.CountOwnedToys()
--   ns.ToyIcon(itemID)
--   ns.ToyName(itemID)         its name, or "" until the game has it (and asks the game for it)
--
-- As the toy kind of entry it also says whether a toy is still in its gift wrap
-- (C_ToyBoxInfo.NeedsFanfare) and opens it (C_ToyBoxInfo.ClearFanfare), without the animation.
--
-- The list is the one Clicky ships (ToyList.lua, written by tools/update_toys.py from the game's
-- tables): a toy's number is its place in it, and it only grows at the end, so patches can't
-- move a macro's entries. ids has only the toys; index has every entry. The list
-- doesn't depend on which toys the player owns, so learning a toy never changes it, and it never
-- reads or changes the Toy Box's filters: those are the player's own saved settings. A toy in the
-- game that the list doesn't have yet can't be put in a macro until Clicky is updated
-- (Macros.lua), and a toy taken out of the game keeps its place.

local _, ns = ...

-- Built once, as the file loads: ToyList.lua loads first (Clicky.toc) and never changes.
local list = { ids = {}, index = {}, entries = ns.TOY_IDS, hidden = ns.TOY_HIDDEN,
	mountHidden = ns.MOUNT_HIDDEN, petHidden = ns.PET_HIDDEN, petRandomLook = ns.PET_RANDOM_LOOK,
	toySource = ns.TOY_SOURCE, mountType = ns.MOUNT_TYPE, petSource = ns.PET_SOURCE }
for i, entry in ipairs(list.entries) do
	if type(entry) == "number" then
		list.ids[#list.ids + 1] = entry
	end
	list.index[entry] = i - 1
end

function ns.GetToyList()
	return list
end

-- A toy the game client has no data for would be a blank slot (GetItemInfoInstant answers from the
-- client's data, never the server: seen in play), so only an owned one is kept. One with the 2 bit in
-- the Toy table's Flags (ToyList.lua's TOY_HIDDEN) only when owned, which matches the Toy Box: with
-- Not Collected on, its list (C_ToyBox.GetNumFilteredToys) and the grid were seen in play to hold the
-- same 1076 toys.
function ns.ListedToyEntries(uncollected)
	local keys = {}
	for _, itemID in ipairs(list.ids) do
		if PlayerHasToy(itemID) or uncollected and not list.hidden[itemID] and ns.ToyIcon(itemID) ~= nil then
			keys[#keys + 1] = itemID
		end
	end
	return keys
end

function ns.ToySource(itemID)
	return list.toySource[itemID]
end

-- GetItemInfo's 15th value (ItemDocumentation.lua); it may return nothing until the item's data has
-- loaded (MayReturnNothing).
function ns.ToyExpansion(itemID)
	return (select(15, C_Item.GetItemInfo(itemID)))
end

-- GetNumFilteredToys is the Toy Box's list as its filters have it: the Toy Box walks and pages it
-- so (Blizzard_ToyBox.lua:186, 430).
function ns.GetToyBoxState()
	return ("the Toy Box lists %d with its own filters"):format(C_ToyBox.GetNumFilteredToys())
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

local function IsOnCooldown(itemID)
	local start, duration = C_Container.GetItemCooldown(itemID)
	return start and start > 0 and duration and duration > ns.GCD_THRESHOLD
end

-- C_ToyBox.GetToyInfo has no icon until the toy's data has loaded (seen in play: a drawer filled
-- after login had black buttons). GetItemInfoInstant never asks the server, so it has the icon
-- straight away (warcraft.wiki.gg API C_Item.GetItemInfoInstant).
function ns.ToyIcon(itemID)
	local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
	return icon
end

-- A name the game hasn't cached has to be loaded from the server; GET_ITEM_INFO_RECEIVED (below)
-- refreshes the views when it arrives.
function ns.ToyName(itemID)
	local _, name = C_ToyBox.GetToyInfo(itemID)
	if not name then
		C_Item.RequestLoadItemDataByID(itemID)
	end
	return name or ""
end

local function SetTooltip(owner, itemID, anchor)
	GameTooltip:SetOwner(owner, anchor)
	GameTooltip:SetToyByItemID(itemID)
	GameTooltip:Show()
end

local function UpdateCooldown(cooldown, itemID)
	CooldownFrame_Set(cooldown, C_Container.GetItemCooldown(itemID))
end

-- A toy is used by the secure "toy" action, which reads the "toy" attribute (SECURE_ACTIONS.toy,
-- SecureTemplates.lua): UseToy is protected (warcraft.wiki.gg API UseToy).
ns.RegisterEntryKind("toy", {
	name = ns.ToyName,
	icon = ns.ToyIcon,
	owned = function(itemID) return PlayerHasToy(itemID) end,
	usable = function(itemID) return C_ToyBox.IsToyUsable(itemID) end,
	onCooldown = IsOnCooldown,
	updateCooldown = UpdateCooldown,
	tooltip = SetTooltip,
	link = function(itemID) return C_ToyBox.GetToyLink(itemID) end,
	-- The Toy Box's drag (Blizzard_ToyBox.lua, ToySpellButton_OnDrag).
	pickup = function(itemID) C_ToyBox.PickupToyBoxItem(itemID) end,
	action = function(itemID) return "toy", "toy", itemID end,
	drawerOnly = function() return false end,
	tooltipData = function(itemID) return C_TooltipInfo.GetToyByItemID(itemID) end,
	-- The Toy Box's star calls take the item ID (warcraft.wiki.gg API C_ToyBox.GetIsFavorite).
	favorite = function(itemID) return C_ToyBox.GetIsFavorite(itemID) end,
	canFavorite = function() return true end,
	setFavorite = function(itemID, favorite) C_ToyBox.SetIsFavorite(itemID, favorite) end,
	wrapped = function(itemID) return C_ToyBoxInfo.NeedsFanfare(itemID) == true end,
	unwrap = function(itemID) C_ToyBoxInfo.ClearFanfare(itemID) end,
})

------------------------------------------------------------------------------------------
-- Events.

-- Learning a toy or starring one changes what the panel shows and what can be picked, never the
-- list.
ns.RegisterEvent("NEW_TOY_ADDED", ns.Changed)
ns.RegisterEvent("TOYS_UPDATED", ns.Changed)

ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(itemID, success)
	-- A toy's name may have just loaded. This fires for every item, so ignore the rest. A failed
	-- load (success false, ItemDocumentation.lua) brought no name, and refreshing would only ask
	-- for it again.
	if success and itemID and list.index[itemID] ~= nil then
		ns.Changed()
	end
end)
