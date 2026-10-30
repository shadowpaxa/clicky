-- What a macro holds: entries. An entry is a toy, a mount, a pet, a spell or an item, named by its
-- key, which is its entry in ToyList.lua: a toy is its item ID (a number), a spell is "s" and its
-- spell ID, an item "i" and its item ID, a mount "m" and its mount ID, a pet "p", its species ID,
-- ":" and a look's display ID. This file dispatches on the kind; each kind has one owner file
-- (Toys.lua, Mounts.lua, Pets.lua, Spells.lua, Items.lua) that registers what the kind does, so a
-- name, icon, tooltip, cooldown, owned or usable test, star and secure action is the same in the
-- panel, the drawers, the macro buttons and the grid.
--   ns.RegisterEntryKind(kind, impl)    impl has name(id), icon(id), owned(id), usable(id),
--                                       onCooldown(id), updateCooldown(cooldown, id),
--                                       tooltip(owner, id, anchor), link(id), pickup(id),
--                                       action(id) -> type, attribute, value, and drawerOnly(id);
--                                       a kind with a star (the game's favorite) also favorite(id),
--                                       canFavorite(id) and setFavorite(id, favorite); a kind
--                                       the player can be on or have out also active(id); and
--                                       tooltipData(id): its tooltip as data (C_TooltipInfo), or nil
--   ns.EntryKind(key)                   "toy", "mount", "pet", "spell" or "item"; key's id is
--                                       ns.EntryID(key)
--   ns.EntryID(key)                     a number, or for a pet its "species:display" string
--   ns.EntryName(key)                   its name, or "" until the game has it (and asks for it)
--   ns.EntryIcon(key)
--   ns.IsEntryOwned(key)                the player has the toy, the mount or a pet of the look,
--                                       knows the spell, has the item
--   ns.IsEntryUsable(key)
--   ns.IsEntryOnCooldown(key)
--   ns.IsEntryFavorite(key)             it has the game's star (a toy's, mount's or pet's)
--   ns.CanFavoriteEntry(key)            the star can be set or cleared from Clicky's menu
--   ns.SetEntryFavorite(key, favorite)  sets or clears the star (the player picked it in the menu)
--   ns.IsEntryActive(key)               the mount the player is on, or a look whose pet is out
--   ns.IsDrawerOnly(key)                an item that can be worn: its secure action wears it if it
--                                       isn't worn, so a click on the macro never picks it
--   ns.SetEntryTexture(texture, key, owned)   the icon, grey if not owned
--   ns.ShowEntryTooltip(owner, key, anchor)   anchor is "ANCHOR_RIGHT" if not given
--   ns.EntryLink(key)                   its chat link, or nil if the game has none yet
--   ns.EntryTooltipText(key)            its tooltip's text, lines joined by newlines, or nil if the
--                                       game has no text for it yet
--   ns.PickupEntry(key)                 puts it on the cursor, to drop on an action bar
--   ns.UpdateEntryCooldown(cooldown, key)     the cooldown swipe, empty if not owned
--   ns.SortEntries(keys, names)         sorts keys by name, then kind, then ID, in place; names
--                                       (key -> name) is what the caller has looked up already
--   ns.EntryAction(key)                 -> type, attribute, value: what a secure button sets to use it
--   ns.SetButtonAction(button, key, typeAttribute)   sets the button's secure action to use key
--                                       (typeAttribute "type", or "type1" for a plain left click
--                                       only), or to nothing if key is nil; out of combat only
--   ns.ACTION_ATTRIBUTES                the attributes an action sets besides its type
--   ns.GCD_THRESHOLD                    cooldowns at or below this are the global cooldown
--
-- A secure button uses an entry the way Select's flyout buttons do (its secure/button.lua): set
-- the button's "type" to the action and the attribute that action reads to the entry's value
-- (SECURE_ACTIONS.toy, .spell, .item and .macro in Blizzard_FrameXML/SecureTemplates.lua).

local _, ns = ...

local kinds = {}
local KIND_RANK = { toy = 1, mount = 2, pet = 3, spell = 4, item = 5 }
local KIND_OF = { s = "spell", i = "item", m = "mount", p = "pet" }

ns.GCD_THRESHOLD = 1.5
ns.ACTION_ATTRIBUTES = { "toy", "spell", "item", "macrotext" }

function ns.RegisterEntryKind(kind, impl)
	kinds[kind] = impl
end

function ns.EntryKind(key)
	if type(key) == "number" then
		return "toy"
	end
	return KIND_OF[key:sub(1, 1)]
end

function ns.EntryID(key)
	if type(key) == "number" then
		return key
	elseif key:sub(1, 1) == "p" then
		return key:sub(2)
	end
	return tonumber(key:sub(2))
end

local function Of(key)
	return kinds[ns.EntryKind(key)], ns.EntryID(key)
end

function ns.EntryName(key)
	local kind, id = Of(key)
	return kind.name(id)
end

function ns.EntryIcon(key)
	local kind, id = Of(key)
	return kind.icon(id)
end

function ns.IsEntryOwned(key)
	local kind, id = Of(key)
	return kind.owned(id)
end

function ns.IsEntryUsable(key)
	local kind, id = Of(key)
	return kind.usable(id)
end

function ns.IsEntryOnCooldown(key)
	local kind, id = Of(key)
	return kind.onCooldown(id)
end

function ns.IsEntryFavorite(key)
	local kind, id = Of(key)
	return kind.favorite ~= nil and kind.favorite(id) == true
end

function ns.CanFavoriteEntry(key)
	local kind, id = Of(key)
	return kind.canFavorite ~= nil and kind.canFavorite(id) == true
end

function ns.IsEntryActive(key)
	local kind, id = Of(key)
	return kind.active ~= nil and kind.active(id) == true
end

function ns.SetEntryFavorite(key, favorite)
	local kind, id = Of(key)
	kind.setFavorite(id, favorite)
	ns.Trace("[entries] %s %s", tostring(key), favorite and "starred" or "unstarred")
	ns.Changed()
end

function ns.IsDrawerOnly(key)
	local kind, id = Of(key)
	return kind.drawerOnly(id)
end

function ns.SetEntryTexture(texture, key, owned)
	texture:SetTexture(ns.EntryIcon(key))
	texture:SetDesaturated(not owned)
end

function ns.ShowEntryTooltip(owner, key, anchor)
	local kind, id = Of(key)
	kind.tooltip(owner, id, anchor or "ANCHOR_RIGHT")
end

function ns.UpdateEntryCooldown(cooldown, key)
	local kind, id = Of(key)
	if kind.owned(id) then
		kind.updateCooldown(cooldown, id)
	else
		cooldown:Clear()
	end
end

function ns.EntryLink(key)
	local kind, id = Of(key)
	return kind.link(id)
end

-- A TooltipData's lines each have a leftText and rightText (as TooltipUtil.lua:55 reads them). Text
-- the game keeps secret (issecretvalue) is left out: it can't be read.
function ns.EntryTooltipText(key)
	local kind, id = Of(key)
	local data = kind.tooltipData and kind.tooltipData(id)
	if not data or not data.lines then
		return nil
	end
	local parts = {}
	for _, line in ipairs(data.lines) do
		for _, text in ipairs({ line.leftText, line.rightText }) do
			if type(text) == "string" and not issecretvalue(text) and text ~= "" then
				parts[#parts + 1] = text
			end
		end
	end
	return #parts > 0 and table.concat(parts, "\n") or nil
end

function ns.PickupEntry(key)
	local kind, id = Of(key)
	kind.pickup(id)
end

function ns.EntryAction(key)
	local kind, id = Of(key)
	return kind.action(id)
end

function ns.SortEntries(keys, names)
	names = names or {}
	for _, key in ipairs(keys) do
		names[key] = names[key] or ns.EntryName(key)
	end
	table.sort(keys, function(a, b)
		if names[a] ~= names[b] then
			return names[a] < names[b]
		end
		local rankA, rankB = KIND_RANK[ns.EntryKind(a)], KIND_RANK[ns.EntryKind(b)]
		if rankA ~= rankB then
			return rankA < rankB
		end
		return ns.EntryID(a) < ns.EntryID(b)
	end)
end

-- "type" answers every click, "type1" only a plain left click: modified and right clicks never
-- look up type1 (warcraft.wiki.gg SecureActionButtonTemplate, "Modified attributes"). The
-- attributes of the other actions are cleared, so a button that held a toy and now holds a spell
-- keeps nothing of the toy.
function ns.SetButtonAction(button, key, typeAttribute)
	local action, attribute, value
	if key then
		action, attribute, value = ns.EntryAction(key)
	end
	button:SetAttribute(typeAttribute, action)
	for _, name in ipairs(ns.ACTION_ATTRIBUTES) do
		button:SetAttribute(name, name == attribute and value or nil)
	end
end
