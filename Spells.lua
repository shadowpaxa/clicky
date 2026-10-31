-- The spell kind of entry (Entries.lua): a spell's name, icon, tooltip, cooldown, owned and usable
-- test and secure action. A spell is the key "s" and its spell ID.
--   ns.KnownSpellEntries()   the keys of the spells the spellbook and the Professions book show that
--                            are in Clicky's list, in no order; the grid lists these (Grid.lua)
--
-- It's known when the spellbook says so (C_SpellBook.IsSpellKnown). The secure "spell" action
-- casts the spell ID in its "spell" attribute (SECURE_ACTIONS.spell, SecureTemplates.lua:
-- CastSpellByID for a number).
--
-- C_Spell.GetSpellCooldown is flagged SecretWhenCooldownsRestricted
-- (SpellDocumentation.lua): when combat, an encounter, a challenge mode or a PvP match restricts
-- addons, its start and duration are secret values (SecretPredicatesDocumentation.lua). Clicky
-- doesn't compare them (it asks issecretvalue first) and doesn't hand them to a cooldown frame
-- (Cooldown:SetCooldown is SecretArguments AllowedWhenUntainted, FrameAPICooldownDocumentation.lua).
-- Its isActive is never secret (SpellSharedDocumentation.lua). So a spell with an active cooldown
-- whose duration is secret counts as on cooldown, and shows no swipe.

local _, ns = ...

local function Name(spellID)
	local name = C_Spell.GetSpellName(spellID)
	if not name then
		C_Spell.RequestLoadSpellData(spellID)
	end
	return name or ""
end

local function IsOnCooldown(spellID)
	local info = C_Spell.GetSpellCooldown(spellID)
	if not info or not info.isActive then
		return false
	end
	return issecretvalue(info.duration) or info.duration > ns.GCD_THRESHOLD
end

local function UpdateCooldown(cooldown, spellID)
	local info = C_Spell.GetSpellCooldown(spellID)
	if info and not issecretvalue(info.startTime) and not issecretvalue(info.duration) then
		CooldownFrame_Set(cooldown, info.startTime, info.duration, info.isEnabled, false, info.modRate)
	else
		cooldown:Clear()
	end
end

-- The spells Clicky can hold that the spellbook shows: the active spells on its skill lines and the
-- known spells in its flyouts, and the professions' active spells. Blizzard's own spell search walks
-- flyouts with these two calls (Blizzard_SpellSearchTextFilter.lua, DerivedGetMatchTypeForFlyout).
-- The Professions book finds each profession's spells in the player's spellbook from GetProfessions
-- and GetProfessionInfo's numSpells and spellOffset (Blizzard_ProfessionsBook.lua:58, 387;
-- ProfessionSpellButtonMixin:UpdateButton). A spell the list lacks can't be put in a macro
-- (Macros.lua), so it isn't offered.
function ns.KnownSpellEntries()
	local index = ns.GetToyList().index
	local keys, seen = {}, {}
	local function Add(spellID)
		local key = spellID and "s" .. spellID
		if key and index[key] ~= nil and not seen[key] then
			seen[key] = true
			keys[#keys + 1] = key
			return true
		end
	end
	local bank = Enum.SpellBookSpellBank.Player
	local function AddSlot(slot)
		local info = C_SpellBook.GetSpellBookItemInfo(slot, bank)
		if not info or info.isPassive or info.isOffSpec then
			return
		end
		if info.itemType == Enum.SpellBookItemType.Spell then
			-- actionID is the spell's own ID, spellID the one overriding it, if any.
			if not Add(info.actionID) then
				Add(info.spellID)
			end
		elseif info.itemType == Enum.SpellBookItemType.Flyout then
			local numSlots = select(3, GetFlyoutInfo(info.actionID))
			for flyoutSlot = 1, numSlots or 0 do
				local spellID, _, isKnown = GetFlyoutSlotInfo(info.actionID, flyoutSlot)
				if isKnown then
					Add(spellID)
				end
			end
		end
	end
	for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
		local lineInfo = C_SpellBook.GetSpellBookSkillLineInfo(line)
		if lineInfo and not lineInfo.shouldHide and not lineInfo.offSpecID then
			for slot = lineInfo.itemIndexOffset + 1, lineInfo.itemIndexOffset + lineInfo.numSpellBookItems do
				AddSlot(slot)
			end
		end
	end
	-- Two primary professions, archaeology, fishing and cooking; nil for one the player hasn't learned.
	local professions = { GetProfessions() }
	for i = 1, 5 do
		if professions[i] then
			local numSpells, spellOffset = select(5, GetProfessionInfo(professions[i]))
			for slot = spellOffset + 1, spellOffset + numSpells do
				AddSlot(slot)
			end
		end
	end
	return keys
end

ns.RegisterEntryKind("spell", {
	name = Name,
	icon = function(spellID) return C_Spell.GetSpellTexture(spellID) end,
	owned = function(spellID) return C_SpellBook.IsSpellKnown(spellID) end,
	usable = function(spellID) return (C_Spell.IsSpellUsable(spellID)) end,
	onCooldown = IsOnCooldown,
	updateCooldown = UpdateCooldown,
	tooltip = function(owner, spellID, anchor)
		GameTooltip:SetOwner(owner, anchor)
		GameTooltip:SetSpellByID(spellID)
		GameTooltip:Show()
	end,
	link = function(spellID) return C_Spell.GetSpellLink(spellID) end,
	pickup = function(spellID) C_Spell.PickupSpell(spellID) end,
	action = function(spellID) return "spell", "spell", spellID end,
	drawerOnly = function() return false end,
	tooltipData = function(spellID) return C_TooltipInfo.GetSpellByID(spellID) end,
})

-- A name that was loading has arrived, and a spell learned or forgotten changes what is owned.
ns.RegisterEvent("SPELL_DATA_LOAD_RESULT", function(_, success)
	if success then
		ns.Changed()
	end
end)
ns.RegisterEvent("SPELLS_CHANGED", ns.Changed)
