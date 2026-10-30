-- The debug window, which /clicky debug opens (Commands.lua): Clicky's state as it was then, and
-- under it the trace, every pick and change (ns.Trace) while its Trace box is ticked. Chat's text
-- can't be copied; this can. It works as Blizzard's script errors window does
-- (Blizzard_ScriptErrorsFrame.xml:35-43, Blizzard_ScriptErrorsFrame.lua:58-60): opening it doesn't
-- give the text the keyboard, a click on the text selects all of it for Ctrl+C, and Escape lets the
-- keyboard go; then Escape closes the window, as for every window in UISpecialFrames
-- (UIParentPanelManager.lua:21). It isn't protected, so it opens in combat.
--   ns.ShowDebug(lines)     opens the window with these lines of state
--   ns.AddTraceLine(line)   keeps a trace line (the newest 1000), shown at once if the window's open
--   ns.GetTraceLines()      the trace lines kept, oldest first; for tests

local _, ns = ...

local TITLE = "Clicky debug"
local MAX_TRACE = 1000 -- the newest kept: a trace has lines for every change, all session
local WIDTH, HEIGHT = 640, 420
local TRACE_LABEL = "Trace: record each pick and change below"
local TRACE_OFF = "Tick Trace to record each pick and change here."

local state = {} -- the lines of state from the last /clicky debug
local traced = {}
local window -- made the first time it opens
local pending = false -- a redraw is queued for the next frame

local function Redraw()
	pending = false
	if not (window and window:IsShown()) then
		return
	end
	local trace = #traced > 0 and table.concat(traced, "\n") or TRACE_OFF
	window.text:SetText(table.concat(state, "\n") .. "\n\nTrace:\n" .. trace)
	window.trace:SetChecked(ns.IsTracing())
	-- New lines replace the text, and with it the selection: select it all again if it was.
	local editBox = window.text:GetEditBox()
	if editBox:HasFocus() then
		editBox:HighlightText(0)
	end
end

function ns.AddTraceLine(line)
	traced[#traced + 1] = line
	if #traced > MAX_TRACE then
		table.remove(traced, 1)
	end
	-- A change traces several lines: they're drawn together, once, on the next frame.
	if window and window:IsShown() and not pending then
		pending = true
		C_Timer.After(0, Redraw)
	end
end

function ns.GetTraceLines()
	return traced
end

-- A ButtonFrameTemplate, as the panel is made (Panel.lua), holding a ScrollingEditBoxTemplate with
-- a MinimalScrollBar, as the Calendar's event description does (Blizzard_Calendar.xml:855-875,
-- Blizzard_Calendar.lua:3646-3647), and a UICheckButtonTemplate (CheckButtonTemplates.xml:50-64)
-- under it.
local function CreateWindow()
	window = CreateFrame("Frame", "ClickyDebug", UIParent, "ButtonFrameTemplate")
	ButtonFrameTemplate_HidePortrait(window)
	ButtonFrameTemplate_HideButtonBar(window)
	window:SetTitle(TITLE)
	window:SetSize(WIDTH, HEIGHT)
	window:SetPoint("CENTER")
	window:SetFrameStrata("DIALOG")
	window:SetToplevel(true)
	-- Dragged by its top bar; where it's left isn't saved: Clicky saves nothing.
	window:SetMovable(true)
	window:SetDontSavePosition(true)
	window:EnableMouse(true)
	window:RegisterForDrag("LeftButton")
	window:SetScript("OnDragStart", window.StartMoving)
	window:SetScript("OnDragStop", window.StopMovingOrSizing)
	table.insert(UISpecialFrames, "ClickyDebug")

	window.trace = CreateFrame("CheckButton", nil, window.Inset, "UICheckButtonTemplate")
	window.trace:SetPoint("BOTTOMLEFT", 4, 4)
	window.trace.Text:SetText(TRACE_LABEL)
	window.trace:SetScript("OnClick", function(self)
		ns.SetTracing(self:GetChecked())
		ns.Trace("[debug] trace %s", ns.IsTracing() and "on" or "off")
		Redraw()
	end)

	window.text = CreateFrame("Frame", nil, window.Inset, "ScrollingEditBoxTemplate")
	window.text:SetPoint("TOPLEFT", 8, -8)
	window.text:SetPoint("BOTTOMRIGHT", -24, 40)
	window.text:GetEditBox():HookScript("OnEditFocusGained", function(self)
		self:HighlightText(0)
	end)
	window.scrollBar = CreateFrame("EventFrame", nil, window.Inset, "MinimalScrollBar")
	window.scrollBar:SetPoint("TOPLEFT", window.text, "TOPRIGHT", 8, 0)
	window.scrollBar:SetPoint("BOTTOMLEFT", window.text, "BOTTOMRIGHT", 8, 0)
	ScrollUtil.RegisterScrollBoxWithScrollBar(window.text:GetScrollBox(), window.scrollBar)
end

function ns.ShowDebug(lines)
	state = lines
	if not window then
		CreateWindow()
	end
	window:Show()
	Redraw()
	ns.Trace("[debug] shown, %d lines of state, %d of trace", #state, #traced)
end
