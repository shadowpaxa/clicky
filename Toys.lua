-- Clicky's list of entries, which macros are encoded against; and the toy kind of entry, which
-- Entries.lua dispatches to: a toy's name, icon, tooltip, cooldown, owned and usable test and
-- secure action.
--   ns.GetToyList()            { ids (the toys' item IDs, in ToyList.lua's order), index (entry
--                              key -> 0-based place in the whole list), entries (the whole list: a
--                              toy is its item ID, a spell "s" and an ID, an item "i" and an ID,
--                              which are also entry keys, Entries.lua), hidden (item ID -> true:
--                              the toys listed only when owned, ToyList.lua) }
--   ns.CountOwnedToys()
--   ns.ToyIcon(itemID)
--   ns.ToyName(itemID)         its name, or "" until the game has it (and asks the game for it)
--   ns.IsWrapped(itemID)       learned with a gift wrap not opened yet (C_ToyBoxInfo.NeedsFanfare)
--   ns.Unwrap(itemID)          opens it (C_ToyBoxInfo.ClearFanfare), without the animation
--   ns.IsNewToy(itemID)        learned this session and not hovered since, or still wrapped
--   ns.SeeToy(itemID)          hovered: no longer new unless still wrapped, as in the Toy Box
--                              (Blizzard_ToyBox.lua, ToySpellButton_OnEnter)
--   ns.CountNewToys()          for /clicky debug
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
local list = { ids = {}, index = {}, entries = ns.TOY_IDS, hidden = ns.TOY_HIDDEN }
for i, entry in ipairs(list.entries) do
	if type(entry) == "number" then
		list.ids[#list.ids + 1] = entry
	end
	list.index[entry] = i - 1
end
local newToys = {} -- itemID -> true: learned this session (TOYS_UPDATED's isNew), not hovered since

function ns.GetToyList()
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
})

function ns.IsWrapped(itemID)
	return C_ToyBoxInfo.NeedsFanfare(itemID) == true
end

function ns.Unwrap(itemID)
	C_ToyBoxInfo.ClearFanfare(itemID)
	newToys[itemID] = nil
	ns.Trace("[toys] unwrapped %d", itemID)
	ns.Changed()
end

function ns.IsNewToy(itemID)
	return newToys[itemID] == true or ns.IsWrapped(itemID)
end

function ns.SeeToy(itemID)
	if newToys[itemID] and not ns.IsWrapped(itemID) then
		newToys[itemID] = nil
		ns.Trace("[toys] %d seen, no longer new", itemID)
	end
end

function ns.CountNewToys()
	local n = 0
	for _ in pairs(newToys) do
		n = n + 1
	end
	return n
end

------------------------------------------------------------------------------------------
-- Events.

-- Learning a toy or starring one changes what the panel shows and what can be picked, never the
-- list.
ns.RegisterEvent("NEW_TOY_ADDED", ns.Changed)
ns.RegisterEvent("TOYS_UPDATED", function(itemID, isNew)
	if itemID and isNew then
		newToys[itemID] = true
		ns.Trace("[toys] %d is new", itemID)
	end
	ns.Changed()
end)

ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(itemID, success)
	-- A toy's name may have just loaded. This fires for every item, so ignore the rest. A failed
	-- load (success false, ItemDocumentation.lua) brought no name, and refreshing would only ask
	-- for it again.
	if success and itemID and list.index[itemID] ~= nil then
		ns.Changed()
	end
end)
