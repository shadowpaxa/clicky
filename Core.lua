-- Clicky: "Summon Random Favorite Mount", but for toys, and for any macro of toys, mounts, pets,
-- spells and items you make.
--
-- UseToy() is protected (warcraft.wiki.gg API UseToy), so each macro's entry (a toy, mount, pet,
-- spell or item, Entries.lua) is used by a hidden SecureActionButton with the entry's secure action.
-- The macro runs it with /click. The button gets a random entry from the macro before each click
-- (PreClick out of combat, a secure snippet in combat); a right-click opens the macro's drawer.
--
-- Favorites is a built-in macro backed by the Toy Box star. Every other Clicky macro is a general
-- macro that holds its own entries in a "#clicky" line (Macros.lua), so it follows the player to
-- any computer.
--
-- Files load in .toc order and share one namespace table, ns. Each file keeps its state local
-- and puts on ns only what other files call; the list is at the top of each file. This one has
-- the shared names, messages, tracing, change notification and event wiring:
--   ns.FAVORITES_ID, ns.FAVORITES_MACRO, ns.FAVORITES_ICON
--   ns.BUTTON_PREFIX, ns.DRAWER_BUTTON_PREFIX
--   ns.Print(msg), ns.ShowError(msg)
--   ns.Trace(format, ...), ns.IsTracing(), ns.SetTracing(on)
--   ns.RegisterView(name, isShown, refresh, delay), ns.Changed()   views (the panel, the grid)
--                                  and the one refresh path to them
--   ns.GetViews()                  { name, shown, pending } per view; for /clicky debug and tests
--   ns.RegisterEvent(event, fn)    fn(...) gets the payload; an error doesn't stop later handlers

local addonName, ns = ...

-- Players' macros /click these buttons by name, so the button names can't change.
-- A macro's id is four random consonants (its "code", Macros.lua); its buttons are
-- Clicky<id> (an entry) and ClickyP<id> (drawer). Favorites has the reserved id FVRT, which no new
-- macro is given.
ns.FAVORITES_ID = "FVRT"
ns.FAVORITES_MACRO = "Favorites" -- its macro's name when Clicky makes it
ns.FAVORITES_ICON = "Trade_Archaeology_ChestofTinyGlassAnimals" -- the Toy Box portrait
ns.BUTTON_PREFIX = "Clicky" -- followed by the macro's id: a click uses an entry
ns.DRAWER_BUTTON_PREFIX = "ClickyP" -- followed by the id: right-click opens the drawer

local tracing = false -- the debug window's Trace box: record every pick, click and change (Debug.lua)

function ns.Print(msg)
	print("|cff33ff99Clicky|r: " .. msg)
end

function ns.ShowError(msg)
	UIErrorsFrame:AddExternalErrorMessage(msg)
end

------------------------------------------------------------------------------------------
-- Tracing, while the debug window's Trace box is ticked (Debug.lua). tostringall makes nil safe
-- with %s. Callers with costly arguments check ns.IsTracing() first.

function ns.IsTracing()
	return tracing
end

function ns.SetTracing(on)
	tracing = on and true or false
end

function ns.Trace(format, ...)
	if not tracing then
		return
	end
	-- To the debug window only (Debug.lua): a trace has lines for every change, which would flood chat.
	ns.AddTraceLine(format:format(tostringall(...)))
end

------------------------------------------------------------------------------------------
-- Views. A burst of changes (toy names arrive one GET_ITEM_INFO_RECEIVED at a time) refreshes a
-- shown view once, after its delay; a hidden one draws itself when shown.

local views = {}

function ns.RegisterView(name, isShown, refresh, delay)
	views[#views + 1] = { name = name, isShown = isShown, refresh = refresh, delay = delay }
end

function ns.Changed()
	for _, view in ipairs(views) do
		if not view.pending and view.isShown() then
			view.pending = true
			C_Timer.After(view.delay, function()
				view.pending = false
				if view.isShown() then
					view.refresh()
				end
			end)
		end
	end
end

function ns.GetViews()
	local state = {}
	for i, view in ipairs(views) do
		state[i] = { name = view.name, shown = view.isShown(), pending = view.pending == true }
	end
	return state
end

------------------------------------------------------------------------------------------
-- Events. Files register handlers as they load; an event's handlers run in .toc order.
-- ADDON_LOADED handlers run only for Clicky itself.

local handlers = {}
local events = CreateFrame("Frame")

function ns.RegisterEvent(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		events:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

-- Each handler runs apart, errors to the player's error handler. WoW's xpcall passes arguments
-- (Blizzard_SharedXMLBase/FunctionUtil.lua:4).
events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" and ... ~= addonName then
		return
	end
	for _, fn in ipairs(handlers[event]) do
		xpcall(fn, geterrorhandler(), ...)
	end
end)
