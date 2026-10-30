-- The secure button that uses an entry (a toy, mount, pet, spell or item, Entries.lua), which the drawers
-- (Drawer.lua) and the grid (Grid.lua) are made of. Addon code can't use a toy (UseToy is
-- protected, warcraft.wiki.gg API UseToy), so the button's own secure action does, for the other
-- kinds too.
-- All three are out of combat only: the button is a protected frame.
--   ns.CreateEntryButton(parent, size, anchor, leftOnly)   icon, cooldown, highlight, the active
--                                           mark (button.active), tooltip (at anchor, default
--                                           "ANCHOR_RIGHT"); every click uses the entry, or only a
--                                           plain left click if leftOnly
--   ns.SetEntryButton(button, key, unusable)  shows the entry key (button.entry, and for a toy
--                                           button.itemID), marked if ns.IsEntryActive; a click
--                                           uses it unless nil or unusable
--   ns.EmptyEntryButton(button)               no entry, and hidden

local _, ns = ...

-- Also UpdateTooltip, which GameTooltip calls while shown (GameTooltip.lua:456-458): the tooltip
-- follows the button's entry, or goes when it holds none.
local function ShowTooltip(button)
	if button.entry then
		ns.ShowEntryTooltip(button, button.entry, button.tooltipAnchor)
	else
		GameTooltip_Hide()
	end
end

function ns.CreateEntryButton(parent, size, anchor, leftOnly)
	local button = CreateFrame("Button", nil, parent, "SecureActionButtonTemplate")
	button:SetSize(size, size)
	-- Secure buttons act on the up click (SecureActionButton_OnClick), and a wrapped snippet (the
	-- drawers' CLOSE) runs on every click the button is registered for.
	button:RegisterForClicks("AnyUp")
	button:SetAttribute("useOnKeyDown", false)
	button.icon = button:CreateTexture(nil, "ARTWORK")
	button.icon:SetAllPoints()
	button.cooldown = CreateFrame("Cooldown", nil, button, "CooldownFrameTemplate")
	button:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
	-- The journals' mark on the mount ridden and the pet that's out (ActiveTexture,
	-- Blizzard_MountCollection.xml:155, Blizzard_PetCollection.xml:86).
	button.active = button:CreateTexture(nil, "OVERLAY")
	button.active:SetTexture("Interface\\Buttons\\CheckButtonHilight")
	button.active:SetBlendMode("ADD")
	button.active:SetAllPoints()
	button.active:Hide()
	button.tooltipAnchor, button.leftOnly = anchor, leftOnly
	button:SetScript("OnEnter", ShowTooltip)
	button:SetScript("OnLeave", GameTooltip_Hide)
	button.UpdateTooltip = ShowTooltip
	return button
end

function ns.SetEntryButton(button, key, unusable)
	button.entry = key
	button.itemID = key and ns.EntryKind(key) == "toy" and key or nil
	-- The other of "type" and "type1" is cleared (SetButtonAction clears only the one it sets).
	local used = key and not unusable and key or nil
	button:SetAttribute(button.leftOnly and "type" or "type1", nil)
	ns.SetButtonAction(button, used, button.leftOnly and "type1" or "type")
	button.active:SetShown(key ~= nil and ns.IsEntryActive(key))
	if key then
		ns.SetEntryTexture(button.icon, key, ns.IsEntryOwned(key))
		ns.UpdateEntryCooldown(button.cooldown, key)
	end
end

function ns.EmptyEntryButton(button)
	ns.SetEntryButton(button, nil)
	button:Hide()
end
