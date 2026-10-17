-- Clicky: "Summon Random Favorite Mount", but for toys, and for any macro of toys you make.
--
-- UseToy() is protected, so each macro's toy is used by a hidden SecureActionButton (type "toy").
-- The macro runs it with /click. Out of combat, Clicky picks a fresh random toy from the macro
-- right before each click (PreClick) and lines up the next one afterwards (PostClick).
--
-- Favorites is a built-in macro backed by the Toy Box star. Every other Clicky macro is a general
-- macro that holds its own toys in a "#clicky" line (Macros.lua), so it follows the player to
-- any computer.
--
-- Files load in .toc order and share one namespace table, ns. Each file keeps its state local
-- and puts on ns only what other files call; the list is at the top of each file. This one has
-- the shared names, messages, tracing, change notification and event wiring:
--   ns.FAVORITES_BUTTON, ns.FAVORITES_MACRO, ns.FAVORITES_ICON, ns.SET_BUTTON_PREFIX
--   ns.Print(msg), ns.ShowError(msg)
--   ns.Trace(format, ...), ns.IsTracing(), ns.SetTracing(on)
--   ns.Changed()                   something the panel shows changed; calls ns.OnMacrosChanged
--   ns.OnMacrosChanged             set by Panel.lua
--   ns.RegisterEvent(event, fn)    fn(...) gets the event's payload

local addonName, ns = ...

-- Players' macros /click these buttons by name, and the macro names are what's on their bars,
-- so none of these can change.
ns.FAVORITES_BUTTON = "ClickyButton"
ns.FAVORITES_MACRO = "Clicky"
ns.FAVORITES_ICON = "Trade_Archaeology_ChestofTinyGlassAnimals" -- the Toy Box portrait
ns.SET_BUTTON_PREFIX = "ClickySet" -- followed by the macro's id (an older name; bars depend on it)

local tracing = false -- /clicky trace: print every pick, click and change

function ns.Print(msg)
	print("|cff33ff99Clicky|r: " .. msg)
end

function ns.ShowError(msg)
	UIErrorsFrame:AddExternalErrorMessage(msg)
end

------------------------------------------------------------------------------------------
-- Tracing. Every trace line goes through ns.Trace, which does nothing unless /clicky trace
-- is on. Arguments other than numbers are passed through tostring, so nil is safe with %s.
-- Callers whose arguments are costly to work out check ns.IsTracing() first.

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
	local n, args = select("#", ...), { ... }
	for i = 1, n do
		if type(args[i]) ~= "number" then
			args[i] = tostring(args[i])
		end
	end
	ns.Print(format:format(unpack(args, 1, n)))
end

-- Lets the panel know something it shows has changed.
function ns.Changed()
	if ns.OnMacrosChanged then
		ns.OnMacrosChanged()
	end
end

------------------------------------------------------------------------------------------
-- Events. Files register handlers as they load; an event's handlers run in .toc order, so
-- DB.lua's ADDON_LOADED (which readies ClickyDB) runs before anything that reads it, and
-- Toys.lua's before Macros.lua's.
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

events:SetScript("OnEvent", function(_, event, ...)
	if event == "ADDON_LOADED" and ... ~= addonName then
		return
	end
	for _, fn in ipairs(handlers[event]) do
		fn(...)
	end
end)
