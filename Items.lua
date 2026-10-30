-- The item kind of entry (Entries.lua): a bag or worn item's name, icon, tooltip, cooldown, owned
-- and usable test and secure action. An item is the key "i" and its item ID.
--   ns.CarriedItemEntries()   the keys of the items in the bags or worn that are in Clicky's list,
--                             in no order; the grid lists these (Grid.lua)
--
-- The player has it when it's in the bags or worn (C_Item.GetItemCount, C_Item.IsEquippedItem).
-- The secure "item" action reads the "item" attribute and, for an item that can be worn and isn't,
-- wears it instead of using it (SECURE_ACTIONS.item, SecureTemplates.lua), so an item that can be
-- worn is drawer-only: a click on the macro never picks it (Macros.lua). The attribute holds
-- "item:" and the ID, because a bare number is a worn slot there (SecureCmdItemParse,
-- ChatFrameUtil.lua).

local _, ns = ...

local requested = {} -- itemID -> true: its name was asked for and hasn't arrived

local function Name(itemID)
	local name = C_Item.GetItemNameByID(itemID)
	if not name then
		requested[itemID] = true
		C_Item.RequestLoadItemDataByID(itemID)
	end
	return name or ""
end

-- GetItemInfoInstant never asks the server, so it has the icon straight away (warcraft.wiki.gg
-- API C_Item.GetItemInfoInstant).
local function Icon(itemID)
	local _, _, _, _, icon = C_Item.GetItemInfoInstant(itemID)
	return icon
end

local function Owned(itemID)
	return C_Item.GetItemCount(itemID) > 0 or C_Item.IsEquippedItem(itemID)
end

local function IsOnCooldown(itemID)
	local start, duration = C_Container.GetItemCooldown(itemID)
	return start and start > 0 and duration and duration > ns.GCD_THRESHOLD
end

-- The items Clicky can hold that the player carries: in the bags (the backpack, the bag slots and
-- the reagent bag) or worn. An item the list lacks can't be put in a macro (Macros.lua), so it
-- isn't offered. The bank and the Warband bank aren't looked at.
function ns.CarriedItemEntries()
	local index = ns.GetToyList().index
	local keys, seen = {}, {}
	local function Add(itemID)
		local key = itemID and "i" .. itemID
		if key and index[key] ~= nil and not seen[key] then
			seen[key] = true
			keys[#keys + 1] = key
		end
	end
	for bag = 0, NUM_TOTAL_EQUIPPED_BAG_SLOTS do
		for slot = 1, C_Container.GetContainerNumSlots(bag) do
			Add(C_Container.GetContainerItemID(bag, slot))
		end
	end
	for slot = INVSLOT_FIRST_EQUIPPED, INVSLOT_LAST_EQUIPPED do
		Add(GetInventoryItemID("player", slot))
	end
	return keys
end

ns.RegisterEntryKind("item", {
	name = Name,
	icon = Icon,
	owned = Owned,
	usable = function(itemID) return (C_Item.IsUsableItem(itemID)) end,
	onCooldown = IsOnCooldown,
	updateCooldown = function(cooldown, itemID)
		CooldownFrame_Set(cooldown, C_Container.GetItemCooldown(itemID))
	end,
	tooltip = function(owner, itemID, anchor)
		GameTooltip:SetOwner(owner, anchor)
		GameTooltip:SetItemByID(itemID)
		GameTooltip:Show()
	end,
	-- GetItemInfo's second value is the link (ItemDocumentation.lua); it may return nothing (MayReturnNothing),
	-- so there may be no link.
	link = function(itemID) return (select(2, C_Item.GetItemInfo(itemID))) end,
	pickup = function(itemID) C_Item.PickupItem(itemID) end,
	action = function(itemID) return "item", "item", "item:" .. itemID end,
	drawerOnly = function(itemID) return C_Item.IsEquippableItem(itemID) end,
	tooltipData = function(itemID) return C_TooltipInfo.GetItemByID(itemID) end,
})

-- A name that was loading has arrived. This fires for every item, so only the ones asked for count.
ns.RegisterEvent("GET_ITEM_INFO_RECEIVED", function(itemID, success)
	if requested[itemID] then
		requested[itemID] = nil
		if success then
			ns.Changed()
		end
	end
end)
ns.RegisterEvent("BAG_UPDATE_DELAYED", ns.Changed)
ns.RegisterEvent("PLAYER_EQUIPMENT_CHANGED", ns.Changed)
