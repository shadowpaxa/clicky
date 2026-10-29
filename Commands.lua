-- Slash command: /clicky opens the Toy Box; status, debug and trace are for checking on macros.
-- Nothing on ns.

local ADDON, ns = ...

local Print = ns.Print

-- Blizzard_Collections_Bootstrap.lua (always loaded) loads the Collections window if needed, and
-- shows it with ShowUIPanel, which refuses addon code in combat (UIParentPanelManager.lua:840-864).
local function OpenToyBox()
	if InCombatLockdown() then
		ns.ShowError("Can't open the Toy Box in combat.")
		return
	end
	SetCollectionsJournalShown(true, COLLECTIONS_JOURNAL_TAB_INDEX_TOYS)
end

local function PrintStatus()
	Print(("%d toys owned."):format(ns.CountOwnedToys()))
	for _, m in ipairs(ns.GetMacros()) do
		local unreadable = ns.Unreadable(m)
		Print(unreadable and ("%s: %s"):format(m.name, unreadable)
			or ("%s: %d %s owned, %d ready to use here."):format(m.name, #ns.GetMacroEntries(m), ns.MacroNoun(m),
				#ns.GetCandidates(m, true)))
	end
end

local function PrintDebug()
	Print(("Clicky %s"):format(tostring(C_AddOns.GetAddOnMetadata(ADDON, "Version"))))
	ns.Sync("debug")
	local list = ns.GetToyList()
	Print(("toy list: %d toys from build %s (game counts %d)"):format(
		#list.ids, tostring(ns.TOY_LIST_BUILD), C_ToyBox.GetNumToys()))
	Print(("a macro holds up to %d items"):format(ns.MACRO_ENTRY_CAP))
	Print(("grid: %s; new toys this session: %d"):format(ns.GetGridState(), ns.CountNewToys()))
	Print("panel: " .. ns.GetPanelState())
	local waits = {}
	for what, n in pairs(ns.GetWaiting()) do
		waits[#waits + 1] = ("%s: %d"):format(what, n)
	end
	table.sort(waits)
	Print("waiting: " .. (#waits > 0 and table.concat(waits, ", ") or "nothing"))
	local views = {}
	for _, view in ipairs(ns.GetViews()) do
		views[#views + 1] = ("%s %s%s"):format(view.name, view.shown and "shown" or "hidden",
			view.pending and ", refresh pending" or "")
	end
	Print("views: " .. table.concat(views, "; "))
	for _, m in ipairs(ns.GetMacros()) do
		local members, unusable, cooldown = 0, 0, 0
		for key in pairs(ns.MacroEntries(m)) do
			members = members + 1
			if not ns.IsEntryUsable(key) then unusable = unusable + 1 end
			if ns.IsEntryOnCooldown(key) then cooldown = cooldown + 1 end
		end
		local macro
		if m.builtin then
			local fav = ns.FindFavoritesMacro()
			macro = ("%s, state %s%s"):format(fav and tostring(fav.index) or "none", tostring(m.state),
				m.reason and (" (" .. m.reason .. ")") or "")
		else
			macro = ("%s, state %s%s, data %d chars, %s"):format(tostring(m.index),
				tostring(m.state), m.reason and (" (" .. m.reason .. ")") or "", m.data and #m.data or 0,
				m.state == "ready" and (members .. " items") or "no items")
		end
		local button = m.button
		local drawer = ns.GetDrawer(m.id)
		local count = drawer and drawer.frame:GetAttribute("count") or 0
		local mode = ("ready for combat %s, drawer %s"):format(tostring(button and button:GetAttribute("readycount")),
			drawer and (count .. " items" .. (drawer.frame:IsShown() and ", open" or "")) or "none")
		Print(("%s (%s): %d items (unusable: %d, on cooldown: %d), %s, macro: %s"):format(
			m.name, ns.ButtonName(m.id), members, unusable, cooldown, mode, macro))
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
		Print("/clicky status - show how many of each macro's items you own and can use here")
		Print("/clicky debug - print Clicky's full state")
		Print("/clicky trace - print each pick and change as it happens; type it again to stop")
	end
end
