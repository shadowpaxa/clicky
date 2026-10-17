-- Slash command: /clicky opens the Toy Box; status, debug and trace are for checking on macros.
-- Nothing on ns.

local _, ns = ...

local Print = ns.Print

-- Blizzard_Collections_Bootstrap.lua (always loaded) loads the Collections window if needed.
local function OpenToyBox()
	SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_TOYS)
end

local function PrintStatus()
	Print(("%d toys owned."):format(ns.CountOwnedToys()))
	for _, m in ipairs(ns.GetMacros()) do
		local unreadable = ns.Unreadable(m)
		local line = unreadable and ("%s: %s"):format(m.name, unreadable)
		if not line then
			line = ("%s: %d toys, %d ready to use here."):format(
				m.name, #ns.GetMacroToys(m), #ns.GetCandidates(m, true))
			if m.linedUp then
				local _, name = C_ToyBox.GetToyInfo(m.linedUp)
				line = line .. " Next up: " .. (name or m.linedUp)
			end
		end
		Print(line)
	end
end

local function PrintDebug()
	Print(("toys in game: %d, listed by your Toy Box filters: %d, HasFavorites: %s, Collections loaded: %s"):format(
		C_ToyBox.GetNumToys(), C_ToyBox.GetNumFilteredToys(), tostring(C_ToyBox.HasFavorites()),
		tostring(C_AddOns.IsAddOnLoaded("Blizzard_Collections"))))
	Print(("saved data version: %s"):format(tostring(ClickyDB.version)))
	ns.Sync("debug")
	-- The probe should find as many toys as the game counts; fewer would mean some toys weren't
	-- recognised (C_ToyBox.GetToyLink returned nil for them).
	local list = ns.GetToyList()
	local probedUpTo, found, ms = ns.GetProbeInfo()
	Print(("toy list: %d toys (game counts %d), highest item %s, probed item IDs 1-%d in %d ms, owned: %d"):format(
		found, C_ToyBox.GetNumToys(), tostring(list.highest), probedUpTo, ms, ns.CountOwnedToys()))
	Print(("a macro holds up to %d toys and catches up on up to %d added (guaranteed while the game has up to %d toys)"):format(
		ns.MACRO_TOY_CAP, ns.CATCH_UP_LIMIT, ns.TOY_BOUND))
	local waits = {}
	for what, n in pairs(ns.GetWaiting()) do
		waits[#waits + 1] = ("%s: %d"):format(what, n)
	end
	table.sort(waits)
	Print("waiting: " .. (#waits > 0 and table.concat(waits, ", ") or "nothing"))
	for _, m in ipairs(ns.GetMacros()) do
		local members, unusable, cooldown, bad = 0, 0, 0, 0
		for itemID in pairs(ns.MemberPool(m)) do
			if ns.HasToy(m, itemID) then
				members = members + 1
				if not C_ToyBox.IsToyUsable(itemID) then unusable = unusable + 1 end
				if ns.IsToyOnCooldown(itemID) then cooldown = cooldown + 1 end
				if ns.FailedHere(itemID) then bad = bad + 1 end
			end
		end
		local macro
		if m.builtin then
			macro = tostring(ns.FindFavoritesMacro())
		else
			local written = m.data and ns.DecodeToys(m.data)
			macro = ("%s, state %s%s, data %d chars saved for %s toys up to item %s%s"):format(tostring(m.index),
				tostring(m.state), m.reason and (" (" .. m.reason .. ")") or "", m.data and #m.data or 0,
				written and tostring(written.count) or "?", written and tostring(written.highest) or "?",
				m.stale and " (needs re-saving)" or "")
		end
		Print(("%s (%s): %d toys (unusable: %d, on cooldown: %d, failed here: %d), lined up: %s, toy attr: %s, macro: %s"):format(
			m.name, m.buttonName, members, unusable, cooldown, bad, tostring(m.linedUp),
			tostring(m.button and m.button:GetAttribute("toy")), macro))
	end
end

SLASH_CLICKY1 = "/clicky"
SlashCmdList.CLICKY = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "status" then
		PrintStatus()
	elseif msg == "debug" then
		PrintDebug()
	elseif msg == "trace" then
		ns.SetTracing(not ns.IsTracing())
		Print("trace " .. (ns.IsTracing() and "on" or "off"))
	elseif msg == "" then
		OpenToyBox()
	else
		Print("/clicky - open the Toy Box to manage your macros")
		Print("/clicky status - show how many toys in each macro are ready")
	end
end
