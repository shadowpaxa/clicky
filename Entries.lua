-- What a macro holds: entries. An entry is a toy, a spell or an item, named by its key, which is
-- its entry in ToyList.lua: a toy is its item ID (a number), a spell is "s" and its spell ID, an
-- item is "i" and its item ID. This file dispatches on the kind; each kind has one owner file
-- (Toys.lua, Spells.lua, Items.lua) that registers what the kind does, so a name, icon, tooltip,
-- cooldown, owned or usable test and secure action is the same in the panel, the drawers and the
-- macro buttons.
--   ns.RegisterEntryKind(kind, impl)    impl has name(id), icon(id), owned(id), usable(id),
--                                       onCooldown(id), updateCooldown(cooldown, id),
--                                       tooltip(owner, id, anchor), link(id), pickup(id),
--                                       action(id) -> type, attribute, value, and drawerOnly(id)
--   ns.EntryKind(key)                   "toy", "spell" or "item"; key's id is ns.EntryID(key)
--   ns.EntryID(key)
--   ns.EntryName(key)                   its name, or "" until the game has it (and asks for it)
--   ns.EntryIcon(key)
--   ns.IsEntryOwned(key)                the player has the toy, knows the spell, has the item
--   ns.IsEntryUsable(key)
--   ns.IsEntryOnCooldown(key)
--   ns.IsDrawerOnly(key)                an item that can be worn: its secure action wears it if it
--                                       isn't worn, so a click on the macro never picks it
--   ns.SetEntryTexture(texture, key, owned)   the icon, grey if not owned
--   ns.ShowEntryTooltip(owner, key, anchor)   anchor is "ANCHOR_RIGHT" if not given
--   ns.EntryLink(key)                   its chat link, or nil if the game has none yet
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
-- (SECURE_ACTIONS.toy, .spell and .item in Blizzard_FrameXML/SecureTemplates.lua).

local _, ns = ...

local kinds = {}
local KIND_RANK = { toy = 1, spell = 2, item = 3 }

ns.GCD_THRESHOLD = 1.5
ns.ACTION_ATTRIBUTES = { "toy", "spell", "item" }

function ns.RegisterEntryKind(kind, impl)
	kinds[kind] = impl
end

function ns.EntryKind(key)
	if type(key) == "number" then
		return "toy"
	end
	return key:sub(1, 1) == "s" and "spell" or "item"
end

function ns.EntryID(key)
	if type(key) == "number" then
		return key
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
