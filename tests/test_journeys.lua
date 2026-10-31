-- The journeys in docs/macros-user-journeys.md, as far as Clicky's own logic goes: the real
-- addon files run against stubbed game state (tests/wow.lua), and each test drives the
-- functions Clicky's UI is built on (the Macros API, ns.PanelRows, ns.OpenEntryMenu) and the
-- frames it makes (the panel's rows, the drawers' and the grid's buttons). UI behavior is shown
-- here, or relies only on behavior Blizzard's source shows (tests/wow.lua cites it).

local wow = require("wow")

-- Assertions read actual-then-expected, like the journey steps they check.
local function eq(actual, expected, what) assert.are.equal(expected, actual, what) end
local function list(actual, expected, what) assert.are.same(expected, actual, what) end
local function ok(value, what) assert.is_truthy(value, what) end
local function has(items, value, what)
	for _, item in ipairs(items) do
		if item == value then return end
	end
	error(("%s: %s not in { %s }"):format(what or "list", tostring(value), table.concat(items, ", ")), 2)
end
local function hasNot(items, value, what)
	for _, item in ipairs(items) do
		if item == value then
			error(("%s: %s is in the list"):format(what or "list", tostring(value)), 2)
		end
	end
end

local PIRATE, ORB, GNOME, HAT, WINGS, CHEST = 101, 102, 103, 201, 202, 300
local NEW_TOY = 150 -- a toy in the game that the player doesn't own yet

local function Toys()
	return {
		{ id = PIRATE, name = "Pirate's Costume", icon = 1001 },
		{ id = ORB, name = "Orb of Deception", icon = 1002 },
		{ id = GNOME, name = "Gnomish Gravity Well", icon = 1003 },
		{ id = HAT, name = "Pirate Hat", icon = 2001 },
		{ id = WINGS, name = "Fairy Wings", icon = 2002, favorite = true },
		{ id = CHEST, name = "Treasure Chest", icon = 3001, favorite = true },
	}
end

local function World(options)
	options = options or {}
	if not options.account then
		options.toys = options.toys or Toys()
	end
	return wow.New(options)
end

-- The same account logging in again, on this computer or another: only the macros carry over.
local function NextLogin(world, options)
	options = options or {}
	options.account = world.account
	return wow.New(options)
end

local COMBAT = "Can't change macros in combat."
local FULL = "Your general macros are full. Delete one in /macro and try again."
local UNREADABLE = "Clicky can't read this macro's items. Delete it and make it again."
local NEWER = "This macro was saved by a newer version of Clicky. Update Clicky to use it."
local UNKNOWN_TOY = "Clicky doesn't know this item yet. Update Clicky."

-- A macro as Clicky 0.4.0 wrote it (its /click line names ClickySet<number>), made by the real
-- 0.4.0 code: a worktree of this repository at tag v0.4.0-alpha1, MakeMacro("Illusion", 101), then
-- SetEntry for 201. Its /click line isn't a Clicky macro's.
local V040_PIRATE_HAT = "/click [btn:2]ClickyP1;ClickySet1\n"
	.. "#clicky gAAlgAwAPxGLWZkHzieCBNLWI3kaW85vYmpr/ir2Xv55+LVKiUvhpguo/vw3XSjf0c"

-- The toys the grid lists.
-- filters: those to change from the Toys tab's defaults (GridFilters.lua).
local function GridToys(ns, filters, text)
	local toyFilters = ns.DefaultGridFilters("toys")
	for name, value in pairs(filters) do toyFilters[name] = value end
	return ns.GridSections({ toys = toyFilters }, text)[1].keys
end

local ALL_TOYS = { PIRATE, ORB, GNOME, HAT, WINGS, CHEST }
local function With(ids, extra)
	local out = { unpack(ids) }
	out[#out + 1] = extra
	return out
end

-- What /clicky debug shows: the debug window's text, as the player reads it (Debug.lua).
local function Debug(world)
	world:Slash("/clicky debug")
	return world.env.ClickyDebug.text:GetEditBox():GetText()
end

-- Clicky's macro called name.
local function Macro(world, name)
	for _, m in ipairs(world.ns.GetMacros()) do
		if m.name == name then return m end
	end
	error("no Clicky macro " .. name, 2)
end

local BODY_LIMIT = 255 -- WoW's (MacroFrameText letters="255")

local function Favorites(world)
	return world.ns.GetMacro(world.ns.FAVORITES_ID)
end

-- Journey 3's step (Add to new macro...), used by later journeys to get a macro.
local function MakeMacro(world, itemID, name)
	return assert(world.ns.MakeMacro(name, itemID))
end

-- Journey 4's step (ticking <macro> in a toy's menu).
local function AddTo(world, itemID, name)
	assert(world.ns.SetEntry(Macro(world, name), itemID, true))
end

-- Journey 7's step: pick up the macro, drop it on a bar slot.
local function PutOnBar(world, name, slot)
	world.ns.PickupMacro(Macro(world, name))
	world.bars[slot] = assert(world.cursor, "nothing picked up")
	world.cursor = nil
end

-- The toys a macro uses, by pressing its bar slot until every toy has come up.
local function UsedToys(world, slot, presses)
	local seen, ids = {}, {}
	for _ = 1, presses or 40 do
		world:PressBar(slot)
		local id = world:LastUsed()
		if id and not seen[id] then
			seen[id] = true
			ids[#ids + 1] = id
		end
	end
	table.sort(ids)
	return ids
end

-- What the panel lists: macro names, their toys' names indented, and notes.
local function PanelTexts(world)
	local texts = {}
	for _, row in ipairs(world.ns.PanelRows()) do
		if row.kind == "macro" then
			texts[#texts + 1] = row.macro.name
		elseif row.kind == "entry" then
			local name = type(row.key) == "number" and select(2, world.env.C_ToyBox.GetToyInfo(row.key))
				or world.ns.EntryName(row.key)
			texts[#texts + 1] = "  " .. name
		else
			texts[#texts + 1] = row.text
		end
	end
	return texts
end

local function PanelRow(world, name)
	for _, row in ipairs(world.ns.PanelRows()) do
		if row.kind == "macro" and row.macro.name == name then return row end
	end
	error("no panel row " .. name, 2)
end

-- What the panel lists under a macro, opened.
local function PanelToys(world, name)
	world.ns.expanded[Macro(world, name).id] = true
	local texts, inside = {}, false
	for _, text in ipairs(PanelTexts(world)) do
		if text:sub(1, 2) ~= "  " then
			inside = text == name
		elseif inside then
			texts[#texts + 1] = text:sub(3)
		end
	end
	return texts
end

-- The macro checkboxes in a toy's menu (in the grid and the panel): "[x] Illusion" if the toy is
-- in Illusion, "[ ] Illusion" if not.
local function MenuLabels(world, itemID)
	world.ns.OpenEntryMenu(world.env.UIParent, itemID)
	local labels = {}
	for _, entry in ipairs(world.menu.entries) do
		if entry.kind == "CreateCheckbox" then
			labels[#labels + 1] = (entry.args[1]() and "[x] " or "[ ] ") .. entry.text
		end
	end
	return labels
end

-- A patch adding toys to the game (not owned yet), as the account's game data sees them.
local function PatchAdds(world, ids)
	for _, id in ipairs(ids) do
		world:AddToy({ id = id, name = "New " .. id, owned = false })
	end
end

-- Journey 11: a macro that can't be read shows "?" and why, lists no toys, uses none, and its
-- toys can't be changed.
local function ExpectUnreadable(world, name, message, slot)
	local row = PanelRow(world, name)
	eq(row.count, "?", name .. "'s count")
	eq(row.unreadable, message, "the panel says why")
	list(PanelToys(world, name), {}, "no toys listed under it")
	hasNot(MenuLabels(world, PIRATE), "[ ] " .. name, "not in toy menus")
	hasNot(MenuLabels(world, PIRATE), "[x] " .. name, "not in toy menus")
	list({ world.ns.SetEntry(row.macro, ORB, true) }, { nil, message }, "its toys can't be changed")
	if slot then
		world:TakeErrors()
		world:PressBar(slot)
		eq(#world.used, 0, "never other toys")
		list(world:TakeErrors(), { message }, "clicking it says why")
	end
end

-- How many toys a drawer holds: the frame's "count" attribute, which the drawer's secure code reads.
local function DrawerCount(world, id)
	local drawer = world.ns.GetDrawer(id)
	return drawer and drawer.frame:GetAttribute("count") or 0
end

-- The toys in a macro's drawer, in order, as its buttons hold them.
local function DrawerToys(world, name)
	local drawer = assert(world.ns.GetDrawer(Macro(world, name).id), "no drawer")
	local toys = {}
	for i = 1, DrawerCount(world, Macro(world, name).id) do
		toys[i] = drawer.buttons[i].entry
	end
	return toys
end

local function DrawerOpen(world, name)
	return world.ns.GetDrawer(Macro(world, name).id).frame:IsShown()
end

-- Journey 14's step: click a toy in the open drawer.
local function ClickInDrawer(world, name, itemID)
	local drawer = world.ns.GetDrawer(Macro(world, name).id)
	for i = 1, DrawerCount(world, Macro(world, name).id) do
		local button = drawer.buttons[i]
		if button.entry == itemID then
			button:Click("LeftButton", false)
			return
		end
	end
	error("not in the drawer: " .. itemID, 2)
end

-- A macro's /click line, from its code (ns.FAVORITES_ID for Favorites).
local function Line(code)
	return ("/click [btn:2]ClickyP%s;Clicky%s"):format(code, code)
end
local FAVORITES_LINE = Line("FVRT")
local OLD_FAVORITES_LINE = "/click [btn:2]ClickyP0;ClickyButton" -- 0.4.0's; not a Clicky macro, not Favorites'
local CODE_PATTERN = "Clicky(" .. ("[BCDFGHJKLMNPQRSTVWXZ]"):rep(4) .. ")%f[%W]"

-- The code a body's /click line clicks, or nil.
local function CodeOf(body)
	return body:match(CODE_PATTERN)
end

-- The macro's code, as Clicky holds it.
local function Code(world, name)
	return Macro(world, name).id
end

-- An earlier Clicky's Codec.lua, from its release tag (CI fetches tags for tests/check_toylist.py).
local function OldCodec(tag)
	local pipe = assert(io.popen("git show " .. tag .. ":Codec.lua 2>/dev/null"))
	local source = pipe:read("*a")
	pipe:close()
	local old = {}
	assert(loadstring(source, tag .. ":Codec.lua"), "no Codec.lua at " .. tag)("Clicky", old)
	return old
end

describe("journeys", function()
	it("1. Discover macros: the panel lists Favorites, collapsed, and the hint", function()
		local world = World()
		list(PanelTexts(world), { "Favorites", "Right-click a toy, mount, pet, spell or item to make one." })
		eq(PanelRow(world, "Favorites").count, 2, "Favorites' count")
		world:LoadCollections()
		eq(world.env.ClickyPanel.TitleContainer.TitleText:GetText(), "Macros", "the panel's title, in its top bar")
	end)

	it("2. Dress up: each bar button uses a random toy from its own macro", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		AddTo(world, GNOME, "Illusion")
		MakeMacro(world, HAT, "Illusion mod")
		PutOnBar(world, "Illusion", 1)
		PutOnBar(world, "Illusion mod", 2)
		local costumes = { [PIRATE] = true, [ORB] = true, [GNOME] = true }
		for _ = 1, 20 do
			world:PressBar(1)
			ok(costumes[world:LastUsed()], "Illusion used a costume, got " .. tostring(world:LastUsed()))
			world:PressBar(2)
			eq(world:LastUsed(), HAT, "Illusion mod used its only toy")
		end
	end)

	it("2. Dress up: clicking again rerolls without repeating the last toy", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		local last
		for _ = 1, 10 do
			world:PressBar(1)
			ok(world:LastUsed() ~= last, "repeated " .. tostring(last))
			last = world:LastUsed()
			eq(world.env["Clicky" .. Code(world, "Illusion")]:GetAttribute("toy"), last, "the button holds the toy it used")
		end
	end)

	it("2. Dress up: toys that can't be used are skipped, then the error", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		AddTo(world, GNOME, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world.toys[ORB].usable = false
		world.toys[GNOME].cooldown = 300
		for _ = 1, 5 do
			world:PressBar(1)
			eq(world:LastUsed(), PIRATE, "only the usable, ready toy")
		end
		world.toys[PIRATE].cooldown = 300
		world:PressBar(1)
		list(world:TakeErrors(), { "No usable items in Illusion." })
	end)

	it("2. Dress up: a toy on the global cooldown is still picked", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world.toys[ORB].cooldown = 0.5 -- GetItemCooldown reports a 1.5-second duration: the GCD
		list(UsedToys(world, 1), { PIRATE, ORB })
	end)

	it("2. Dress up: in combat, random toys from those ready when the fight started", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		AddTo(world, GNOME, "Illusion")
		AddTo(world, HAT, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world.toys[HAT].cooldown = 300
		world:EnterCombat()
		world.toys[HAT].cooldown = 0 -- off cooldown mid-fight: waits for the fight to end
		world.toys[ORB].cooldown = 300 -- on cooldown mid-fight: can still come up
		list(UsedToys(world, 1, 60), { PIRATE, ORB, GNOME }, "the toys ready when the fight started")
		eq(#world.used, 60, "a toy every click")
		for i = 2, #world.used do
			ok(world.used[i] ~= world.used[i - 1], "repeated " .. world.used[i])
		end
		eq(world.env["Clicky" .. Code(world, "Illusion")]:GetAttribute("readycount"), 3, "the list it picks from")
		world:LeaveCombat()
		world.toys[ORB].cooldown = 0
		list(UsedToys(world, 1, 60), { PIRATE, ORB, GNOME, HAT }, "after the fight, the toys ready now")
	end)

	it("2. Dress up: the first click in combat doesn't repeat the last toy used before it", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		for _ = 1, 10 do
			world:PressBar(1)
			local before = world:LastUsed()
			world:EnterCombat()
			world:PressBar(1)
			ok(world:LastUsed() ~= before, "repeated " .. before)
			world:LeaveCombat()
		end
	end)

	it("2. Dress up: in combat with nothing ready, the error; out of combat, cooldowns still skipped", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world.toys[PIRATE].cooldown = 300
		world.toys[ORB].cooldown = 300
		world:EnterCombat()
		world.toys[PIRATE].cooldown = 0
		world:TakeErrors()
		world:PressBar(1)
		eq(#world.used, 0, "nothing was ready when the fight started")
		list(world:TakeErrors(), { "No usable items in Illusion." })
		world:LeaveCombat()
		list(UsedToys(world, 1), { PIRATE }, "out of combat, the toy on cooldown is skipped")
	end)

	it("3. Make a macro: a general macro with the toy and its icon, shown expanded", function()
		local world = World()
		list(MenuLabels(world, PIRATE), {}, "only Add to new macro... in the toy's menu")
		MakeMacro(world, PIRATE, "Illusion")
		list(PanelTexts(world), { "Favorites", "Illusion", "  Pirate's Costume" })
		eq(#world.macros, 1)
		local macro = world.macros[1]
		eq(macro.name, "Illusion")
		eq(macro.icon, 1001, "the toy's icon")
		eq(macro.body:match("^[^\n]*"), Line(Code(world, "Illusion")), "its /click line")
		ok(macro.body:find("^[^\n]*\n#clicky "), "then its toys: " .. macro.body)
	end)

	it("3. Make a macro: its buttons are named by a code of four consonants, 36 characters in all", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		local line = world.macros[1].body:match("^[^\n]*")
		local code = CodeOf(line)
		ok(code, "a code: " .. line)
		eq(line, "/click [btn:2]ClickyP" .. code .. ";Clicky" .. code)
		eq(#line, 36, "the line's length")
		ok(code ~= "FVRT", "not Favorites'")
		ok(world.env["Clicky" .. code] and world.env["ClickyP" .. code], "both buttons exist")
		eq(Code(world, "Illusion"), code, "the macro's id")
	end)

	it("3. Make a macro: a code already taken is drawn again", function()
		local world = World()
		math.randomseed(12345)
		MakeMacro(world, PIRATE, "Illusion")
		local first = Code(world, "Illusion")
		math.randomseed(12345) -- the same draws: the first is now taken
		world.ns.SetTracing(true)
		world.prints = {}
		MakeMacro(world, HAT, "Hats")
		local second = Code(world, "Hats")
		for _, line in ipairs(world.ns.GetTraceLines()) do
			-- A taken code written to the new macro would be found out and separated by the sync.
			ok(not line:find("copy of", 1, true), "the new macro was made a copy: " .. line)
		end
		world.ns.SetTracing(false)
		ok(second ~= first, "drew " .. first .. " again")
		ok(CodeOf(world:FindMacroByName("Hats").body) == second, "and wrote it")
		eq(CodeOf(world:FindMacroByName("Illusion").body), first, "the first keeps its own")
	end)

	it("3. Make a macro: Favorites' code is never drawn", function()
		local world = World()
		local real = math.random
		-- The first four draws spell FVRT (F, V, R, T are the 4th, 17th, 14th and 16th letters).
		local draws = { 4, 17, 14, 16 }
		rawset(math, "random", function(...)
			if #draws > 0 then return table.remove(draws, 1) end
			return real(...)
		end)
		local made, err = pcall(MakeMacro, world, PIRATE, "Illusion")
		rawset(math, "random", real)
		assert(made, err)
		eq(#draws, 0, "FVRT was drawn")
		ok(Code(world, "Illusion") ~= "FVRT", "and not used: " .. Code(world, "Illusion"))
	end)

	it("3. Make a macro: a line typed with Favorites' code and toys doesn't take Favorites' place", function()
		local world = World()
		local ns = world.ns
		world:CreateMacroInUI("Typed", "/click [btn:2]ClickyPFVRT;ClickyFVRT\n#clicky " .. ns.EncodePlaces({ 0 }))
		local macros = ns.GetMacros()
		eq(#macros, 1, "Favorites only")
		ok(macros[1].builtin, "Favorites is still Favorites")
		eq(macros[1].state, "ready")
		eq(macros[1].data, nil, "no toys read from the typed line")
		eq(PanelRow(world, macros[1].name).count, 2, "its toys are still the stars")
	end)

	it("3. Make a macro: a toy whose data hasn't loaded yet still gives it its icon", function()
		local world = World()
		world.toys[PIRATE].loading = true
		eq(world.ns.ToyName(PIRATE), "", "the game has no name for it yet")
		MakeMacro(world, PIRATE, "Illusion")
		eq(world.macros[1].icon, 1001, "the Pirate's Costume's icon, not Favorites'")
	end)

	it("3. Make a macro: names are cut to 16 characters, however many bytes they take", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion modification")
		eq(world.macros[1].name, "Illusion modific")
		has(PanelTexts(world), "Illusion modific")
		eq(world.ns.TruncateMacroName("Illusion modifiée"), "Illusion modifié", "\"é\" is bytes 16-17")
		MakeMacro(world, ORB, "Иллюзия и шляпы!") -- 16 letters, 29 bytes
		ok(world:FindMacroByName("Иллюзия и шляпы!"), "kept whole")
	end)

	it("3. Make a macro: an empty or taken name is refused with the reason", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		list({ world.ns.MakeMacro("illusion", ORB) }, { nil, "There's already a macro called Illusion." })
		list({ world.ns.MakeMacro("Favorites", ORB) }, { nil, "There's already a macro called Favorites." })
		list({ world.ns.MakeMacro("  ", ORB) }, { nil, "Give the macro a name." })
		eq(#world.macros, 1, "no macro made")
	end)

	it("3. Make a macro: full general macro slots are refused with the reason", function()
		local macros = {}
		for i = 1, 120 do macros[i] = { name = "m" .. i, body = "/say " .. i } end
		local world = World({ macros = macros })
		list({ world.ns.MakeMacro("Illusion", PIRATE) }, { nil, FULL })
		eq(#world.macros, 120)
	end)

	it("4. Add toys: the toy menu's checkbox ticks, and the macro itself holds the toys", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		MakeMacro(world, HAT, "Illusion mod")
		list(MenuLabels(world, ORB), { "[ ] Illusion", "[ ] Illusion mod" })
		AddTo(world, ORB, "Illusion")
		AddTo(world, ORB, "Illusion mod")
		list(MenuLabels(world, ORB), { "[x] Illusion", "[x] Illusion mod" })
		list(PanelTexts(world), { "Favorites", "Illusion", "  Orb of Deception", "  Pirate's Costume",
			"Illusion mod", "  Orb of Deception", "  Pirate Hat" })
		-- The macro itself holds the toys: a computer with no saved data reads them back.
		list(PanelToys(NextLogin(world), "Illusion"), { "Orb of Deception", "Pirate's Costume" })
	end)

	it("4. Add toys: a macro holds up to 100 toys; the 101st is refused with the reason", function()
		local toys = {}
		for i = 1, 101 do toys[i] = { id = 1000 + i * 7, name = ("Toy %03d"):format(i) } end
		local world = World({ toys = toys })
		MakeMacro(world, toys[1].id, "Big")
		for i = 2, 100 do AddTo(world, toys[i].id, "Big") end
		eq(PanelRow(world, "Big").count, 100)
		ok(#world:FindMacroByName("Big").body <= 255, "100 toys fit")
		list({ world.ns.SetEntry(Macro(world, "Big"), toys[101].id, true) }, { nil, "Big is full: a macro holds up to 100 items." })
		has(MenuLabels(world, toys[101].id), "[ ] Big", "the checkbox is unchanged")
		eq(PanelRow(world, "Big").count, 100, "still 100")
		assert(world.ns.SetEntry(Macro(world, "Big"), toys[100].id, false))
		AddTo(world, toys[101].id, "Big")
		has(PanelToys(world, "Big"), "Toy 101")
		list(PanelToys(NextLogin(world), "Big"), PanelToys(world, "Big"), "all 100 read back on another computer")
	end)

	it("4. Add toys: a macro the player filled with their own lines refuses with the reason", function()
		local toys = {}
		for i = 1, 300 do toys[i] = { id = 1000 + i, name = ("Toy %03d"):format(i) } end
		local world = World({ toys = toys })
		MakeMacro(world, toys[1].id, "Illusion")
		world:EditMacroInUI(1, nil, world.macros[1].body .. "\n/say " .. ("x"):rep(255))
		eq(#world.macros[1].body, 255, "as full as /macro lets it be")
		list({ world.ns.SetEntry(Macro(world, "Illusion"), toys[300].id, true) },
			{ nil, "That macro is too long to update. Remove your own lines from it in /macro." })
		has(MenuLabels(world, toys[300].id), "[ ] Illusion", "unchanged")
		ok(#world.macros[1].body <= 255)
	end)

	it("4. Add toys: a data line goes right after the /click line, keeping the player's lines in order", function()
		local ns = World().ns
		eq(ns.SetDataLine("#showtooltip\n/click ClickyBCDF\n/say hi", "abc"),
			"#showtooltip\n/click ClickyBCDF\n#clicky abc\n/say hi")
		eq(ns.SetDataLine("#showtooltip\n/click ClickyBCDF\n#clicky old\n/say hi", "abc"),
			"#showtooltip\n/click ClickyBCDF\n#clicky abc\n/say hi", "an existing one is replaced in place")
	end)

	it("4. Add toys: any 100 toys fit in a macro while Clicky's list has up to 140,387 places", function()
		local ns = World().ns
		eq(ns.MACRO_ENTRY_CAP, 100)
		local GUARANTEE = 140387
		local shipped = {}
		assert(loadfile("ToyList.lua"))("Clicky", shipped)
		-- Every entry holds a place, spells and items ("s", "i") too, and a later version puts
		-- them in macros, so the whole list counts.
		local places = #shipped.TOY_IDS
		ok(places > 1000, "ToyList.lua lists the game's toys")
		ok(places <= GUARANTEE, ("ToyList.lua has %d places, past the guarantee"):format(places))
		-- Codec.lua's arithmetic.
		eq(#ns.NewBody("BCDF", ""):match("^[^\n]*"), 36, "the /click line, a fixed length")
		local chars = BODY_LIMIT - 36 - 1 - #"#clicky "
		eq(chars, 210, "data characters")
		local bits = (chars - 2 - 2) * 6
		eq(bits, 1236, "bits for the positions, after the two header and two checksum characters")
		eq(100 * 11 + math.floor((GUARANTEE - 100) / 1024), 1236, "the worst case with Rice parameter 10")
		for r = 0, 15 do
			ok(100 * (r + 1) + math.floor((GUARANTEE + 1 - 100) / 2 ^ r) > 1236, "one more place is too many for r = " .. r)
		end
		local function Body(positions)
			return ns.NewBody("BCDF", assert(ns.EncodePlaces(positions)))
		end
		local function Longest(n, k)
			-- The longest encodings for k toys out of n places: one gap as big as it can be
			-- (Codec.lua's bound), and the same toys spread evenly.
			local tail, spread = {}, {}
			for i = 1, k do
				tail[i] = n - k + i - 1
				spread[i] = math.floor((i - 1) * n / k)
			end
			return math.max(#Body(tail), #Body(spread))
		end
		for k = 1, ns.MACRO_ENTRY_CAP do
			ok(Longest(places, k) <= BODY_LIMIT, k .. " toys of the shipped list")
			ok(Longest(GUARANTEE, k) <= BODY_LIMIT, k .. " toys of 140,387 places")
		end
		for n = 100, GUARANTEE, 997 do
			ok(Longest(n, 100) <= BODY_LIMIT, "100 toys of " .. n .. " places")
		end
		-- One place past the guarantee, the worst 100 toys no longer fit.
		ok(Longest(GUARANTEE + 1, 100) > BODY_LIMIT, "100 toys of 140,388 places")
	end)

	it("4. Add toys: the toys read back exactly, whatever the collection", function()
		local ns = World().ns
		math.randomseed(7)
		for _ = 1, 300 do
			local owned = math.random(1, math.random() < 0.5 and 4095 or 140387)
			local k = math.random(0, math.min(ns.MACRO_ENTRY_CAP, owned))
			local chosen, positions = {}, {}
			while #positions < k do
				local p = math.random(0, owned - 1)
				if not chosen[p] then
					chosen[p] = true
					positions[#positions + 1] = p
				end
			end
			table.sort(positions)
			local got = assert(ns.DecodePlaces(assert(ns.EncodePlaces(positions))))
			list(got.positions, positions)
		end
		eq(#ns.EncodePlaces({}), 4, "no toys: the two header characters and the checksum")
		list(assert(ns.DecodePlaces(ns.EncodePlaces({}))).positions, {}, "and it reads back as none")
		local good = ns.EncodePlaces({ 0, 1, 5, 40, 300, 301, 1100 })
		eq(#good, 15, "the two header characters, 11 characters of positions, then the checksum")
		list({ ns.DecodePlaces(good:sub(1, 2)) }, { nil, "damaged" }, "too short")
		list({ ns.DecodePlaces(good:sub(1, 3)) }, { nil, "damaged" }, "the header and one character")
		list({ ns.DecodePlaces(good:sub(1, -2)) }, { nil, "damaged" }, "cut off")
		for i = 1, #good do
			-- Any one character typed differently, as a hand edit in /macro might: never other toys.
			local c = good:sub(i, i) == "A" and "B" or "A"
			list({ ns.DecodePlaces(good:sub(1, i - 1) .. c .. good:sub(i + 1)) }, { nil, "damaged" }, "character " .. i .. " changed")
		end
		list({ ns.DecodePlaces(good:sub(1, 7) .. "|" .. good:sub(9)) }, { nil, "damaged" }, "not the alphabet")
		list({ ns.DecodePlaces("x" .. good:sub(2)) }, { nil, "newer" }, "format 7")
		list({ ns.DecodePlaces("/" .. good:sub(2)) }, { nil, "newer" }, "format 21 and later")
		list({ ns.DecodePlaces("rAvTtd") }, { nil, "damaged" }, "format 5, 0.5.0's: alpha releases may break macros")
		list({ ns.DecodePlaces("I" .. good:sub(2)) }, { nil, "damaged" }, "format 1, a development build's")
		list({ ns.DecodePlaces("Q" .. good:sub(2)) }, { nil, "damaged" }, "format 2, a development build's")
		list({ ns.DecodePlaces("g" .. good:sub(2)) }, { nil, "damaged" }, "format 4, 0.4.0's")
	end)

	it("5. See a macro: its toys listed alphabetically when open, with its toy count", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, GNOME, "Illusion")
		AddTo(world, ORB, "Illusion")
		world.ns.expanded[m.id] = nil
		list(PanelTexts(world), { "Favorites", "Illusion" }, "closed")
		eq(PanelRow(world, "Illusion").count, 3, "the toy count")
		world.ns.expanded[m.id] = true
		world.ns.expanded[world.ns.FAVORITES_ID] = true
		list(PanelTexts(world), { "Favorites", "  Fairy Wings", "  Treasure Chest", "Illusion",
			"  Gnomish Gravity Well", "  Orb of Deception", "  Pirate's Costume" })
	end)

	it("5. See a macro: macros start closed each session", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		list(PanelTexts(NextLogin(world)), { "Favorites", "Illusion" })
	end)

	it("5. See a macro: a copy of a macro starts closed", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion") -- open when made
		MakeMacro(world, HAT, "Hats")
		world.env.DeleteMacro(Macro(world, "Illusion").index)
		world:CreateMacroInUI("Hats 2", world:FindMacroByName("Hats").body)
		ok(Code(world, "Hats 2") ~= Code(world, "Hats"), "the copy has a code of its own")
		list(PanelTexts(world), { "Favorites", "Hats", "  Pirate Hat", "Hats 2" })
	end)

	it("5. See a macro: Favorites lists the starred toys, however they were starred", function()
		local world = World()
		world.ns.expanded[world.ns.FAVORITES_ID] = true
		world.env.C_ToyBox.SetIsFavorite(PIRATE, true)
		list(PanelTexts(world), { "Favorites", "  Fairy Wings", "  Pirate's Costume", "  Treasure Chest",
			"Right-click a toy, mount, pet, spell or item to make one." })
	end)

	it("5. See a macro: an open macro with no toys says how to add them", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		assert(world.ns.SetEntry(m, PIRATE, false))
		world.env.C_ToyBox.SetIsFavorite(WINGS, false)
		world.env.C_ToyBox.SetIsFavorite(CHEST, false)
		world.ns.expanded[world.ns.FAVORITES_ID] = true
		list(PanelTexts(world), { "Favorites", "Star toys to add them.", "Illusion",
			"Right-click a toy, mount, pet, spell or item to add it." })
	end)

	it("6. Remove a toy: other macros keep it", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		MakeMacro(world, ORB, "Tricks")
		assert(world.ns.SetEntry(Macro(world, "Illusion"), ORB, false))
		list(PanelTexts(world), { "Favorites", "Illusion", "  Pirate's Costume", "Tricks", "  Orb of Deception" })
		list(PanelToys(NextLogin(world), "Illusion"), { "Pirate's Costume" }, "the macro itself changed")
	end)

	it("7. Put a macro on a bar: picking it up gives its own macro, never a new one", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		world.ns.PickupMacro(m)
		eq(world.cursor, world.macros[1], "its own macro")
		PutOnBar(world, "Illusion", 1)
		eq(#world.macros, 1, "still one macro")
		world:PressBar(1)
		eq(world:LastUsed(), PIRATE)
	end)

	it("7. Put a macro on a bar: Favorites' macro is made once, and full slots get a message", function()
		local world = World()
		PutOnBar(world, "Favorites", 1)
		PutOnBar(world, "Favorites", 2)
		eq(#world.macros, 1, "made once")
		eq(world.macros[1].name, "Favorites")
		eq(world.macros[1].body, FAVORITES_LINE)
		world:PressBar(1)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "used a favorite")

		local macros = {}
		for i = 1, 120 do macros[i] = { name = "m" .. i, body = "/say " .. i } end
		local full = World({ macros = macros })
		full.ns.PickupMacro(Favorites(full))
		eq(full.cursor, nil, "nothing to drop")
		list(full:TakeErrors(), { FULL })
	end)

	it("7. Put a macro on a bar: clicking a macro with no toys says how to add some", function()
		local world = World()
		world.env.C_ToyBox.SetIsFavorite(WINGS, false)
		world.env.C_ToyBox.SetIsFavorite(CHEST, false)
		PutOnBar(world, "Favorites", 1)
		local m = MakeMacro(world, PIRATE, "Illusion")
		assert(world.ns.SetEntry(m, PIRATE, false))
		PutOnBar(world, "Illusion", 2)
		world:TakeErrors()
		world:PressBar(1)
		world:PressBar(2)
		list(world:TakeErrors(), { "Favorites has no toys. Star toys in the Toy Box to add them.",
			"Illusion has no items. Right-click a toy, mount, pet, spell or item in the Toy Box to add it." })
	end)

	it("7. Put a macro on a bar: Favorites uses its existing macro, whatever it's called", function()
		local world = World({ macros = { { name = "Stars", icon = "x", body = "#showtooltip\n" .. FAVORITES_LINE } } })
		eq(PanelRow(world, "Stars").macro, Favorites(world), "Favorites, by its macro's name")
		PutOnBar(world, "Stars", 1)
		eq(#world.macros, 1, "no second macro")
		world:PressBar(1)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "used a favorite")
	end)

	it("7. Put a macro on a bar: a player's macro named Favorites isn't Favorites'", function()
		local world = World({ macros = { { name = "Favorites", icon = "x", body = "/say hi" } } })
		MakeMacro(world, PIRATE, "Clicky")
		PutOnBar(world, "Clicky", 1)
		PutOnBar(world, "Favorites", 2)
		eq(#world.macros, 3, "Favorites gets its own macro")
		local bodies = {}
		for _, macro in ipairs(world.macros) do bodies[#bodies + 1] = macro.body end
		has(bodies, "/say hi", "the player's macro is untouched")
		world:PressBar(2)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "the Favorites button uses a favorite")
		world:PressBar(1)
		eq(world:LastUsed(), PIRATE)
	end)

	it("7. Put a macro on a bar: a player's macro clicking Favorites' button another way isn't Favorites'", function()
		local mine = "/click ClickyFVRT\n/say Party time!"
		local world = World({ macros = { { name = "Party", icon = "x", body = mine } } })
		world.ns.PickupMacro(Favorites(world))
		eq(#world.macros, 2, "Favorites gets its own macro")
		eq(world.cursor, world:FindMacroByName("Favorites"))
		eq(world.cursor.body, FAVORITES_LINE)
		eq(world:FindMacroByName("Party").body, mine, "the player's macro is untouched")
	end)

	it("8. Rename: the bar button keeps working; a taken name is refused", function()
		local world = World()
		MakeMacro(world, PIRATE, "Ilusion")
		MakeMacro(world, HAT, "Hats")
		PutOnBar(world, "Ilusion", 1)
		assert(world.ns.RenameMacro(Macro(world, "Ilusion"), "Illusion"))
		ok(world:FindMacroByName("Illusion"), "the macro is renamed")
		has(PanelTexts(world), "Illusion")
		world:PressBar(1)
		eq(world:LastUsed(), PIRATE)
		list({ world.ns.RenameMacro(Macro(world, "Hats"), "illusion") }, { nil, "There's already a macro called Illusion." })
	end)

	it("8. Delete: removes the macro and empties its button", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		world:Advance(1)
		local code = Code(world, "Illusion")
		eq(DrawerCount(world, code), 1)
		assert(world.ns.DeleteMacro(Macro(world, "Illusion")))
		list(PanelTexts(world), { "Favorites", "Right-click a toy, mount, pet, spell or item to make one." })
		eq(#world.macros, 0, "the macro is gone")
		eq(world.env["Clicky" .. code]:GetAttribute("type"), nil, "its button is emptied")
		world.env["ClickyP" .. code]:Click("LeftButton", false) -- a copy left in character macros
		ok(not world.ns.GetDrawer(code).frame:IsShown(), "and its drawer")
	end)

	it("8. Delete: never touches a macro the player wrote", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		world:CreateMacroInUI("Mine", "/say hi\n/click Clicky" .. Code(world, "Illusion"))
		assert(world.ns.DeleteMacro(Macro(world, "Illusion")))
		eq(#world.macros, 1, "the player's macro stays")
		eq(world.macros[1].name, "Mine")
	end)

	it("8. Rename or delete in /macro: the panel follows", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world:EditMacroInUI(1, "Costumes")
		list(PanelTexts(world), { "Favorites", "Costumes", "  Pirate's Costume" })
		world:PressBar(1)
		eq(world:LastUsed(), PIRATE)
		world:EditMacroInUI(1, nil, "#showtooltip\n" .. world.macros[1].body)
		AddTo(world, ORB, "Costumes")
		ok(world.macros[1].body:find("^#showtooltip\n/click"), "the player's own lines are kept")
		eq(#UsedToys(world, 1), 2, "and it still works")
		world.env.DeleteMacro(1)
		list(PanelTexts(world), { "Favorites", "Right-click a toy, mount, pet, spell or item to make one." })
	end)

	it("8. Upkeep: every macro change is refused in combat", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		local before = world.macros[1].body
		world:EnterCombat()
		list({ world.ns.MakeMacro("Other", ORB) }, { nil, COMBAT }, "make")
		list({ world.ns.SetEntry(m, ORB, true) }, { nil, COMBAT }, "add a toy")
		list({ world.ns.RenameMacro(m, "Other") }, { nil, COMBAT }, "rename")
		list({ world.ns.DeleteMacro(m) }, { nil, COMBAT }, "delete")
		world:TakeErrors()
		world.ns.PickupMacro(m)
		list(world:TakeErrors(), { "Can't drag macros in combat." }, "pick up")
		eq(world.cursor, nil)
		world:LeaveCombat()
		eq(#world.macros, 1)
		eq(world.macros[1].name, "Illusion")
		eq(world.macros[1].body, before, "nothing changed")
	end)

	it("9. Another computer: the macro, its toys and its bar button are there", function()
		local desktop = World()
		MakeMacro(desktop, PIRATE, "Illusion")
		AddTo(desktop, GNOME, "Illusion")
		PutOnBar(desktop, "Illusion", 1)
		local laptop = NextLogin(desktop) -- no saved data
		list(UsedToys(laptop, 1), { PIRATE, GNOME }, "the bar button uses its toys")
		list(PanelToys(laptop, "Illusion"), { "Gnomish Gravity Well", "Pirate's Costume" })
		AddTo(laptop, ORB, "Illusion")
		local back = NextLogin(laptop)
		list(UsedToys(back, 1), { PIRATE, ORB, GNOME }, "changes made on the laptop come back")
	end)

	it("9. Another computer: the macro is there before the toys have loaded, and works once they have", function()
		local desktop = World()
		MakeMacro(desktop, PIRATE, "Illusion")
		PutOnBar(desktop, "Illusion", 1)
		local before = desktop.macros[1].body
		local laptop = NextLogin(desktop, { toysLoading = true })
		eq(PanelRow(laptop, "Illusion").unreadable, nil, "readable: the list comes with Clicky")
		laptop:LoadToys()
		laptop:PressBar(1)
		eq(laptop:LastUsed(), PIRATE)
		eq(laptop.macros[1].body, before, "nothing to rewrite")
	end)

	it("10. Learn a toy: macros don't change, here and on other computers", function()
		local toys = Toys()
		toys[#toys + 1] = { id = NEW_TOY, name = "Wand", owned = false }
		local world = World({ toys = toys })
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, HAT, "Illusion")
		PutOnBar(world, "Illusion", 1)
		local before = world.macros[1].body
		world:LearnToy({ id = NEW_TOY, name = "Wand" })
		eq(world.macros[1].body, before, "learning a toy changes nothing")
		list(UsedToys(world, 1), { PIRATE, HAT })
		-- The collection changing while Clicky isn't running changes nothing either.
		world.toys[ORB].owned = false
		local laptop = NextLogin(world)
		list(UsedToys(laptop, 1), { PIRATE, HAT }, "another computer reads it")
		eq(laptop.macros[1].body, before)
		AddTo(laptop, NEW_TOY, "Illusion")
		list(UsedToys(laptop, 1, 60), { PIRATE, NEW_TOY, HAT })
	end)

	it("10. A patch adds toys: macros don't change, and the new toy is refused until Clicky is updated", function()
		local world = World({ toyList = ALL_TOYS })
		MakeMacro(world, PIRATE, "Illusion")
		PutOnBar(world, "Illusion", 1)
		local before = world.macros[1].body
		PatchAdds(world, { 400 })
		list(UsedToys(NextLogin(world, { toyList = ALL_TOYS }), 1), { PIRATE }, "the macro reads as before")
		eq(world.macros[1].body, before, "and isn't rewritten")
		list({ world.ns.MakeMacro("New", 400) }, { nil, UNKNOWN_TOY }, "a new macro can't start with it")
		list({ world.ns.SetEntry(Macro(world, "Illusion"), 400, true) }, { nil, UNKNOWN_TOY }, "nor can it be added")
		eq(#world.macros, 1, "no macro made")
		eq(world.macros[1].body, before, "nothing changed")
		-- Clicky updated for the patch: the same macro takes it.
		local updated = NextLogin(world, { toyList = With(ALL_TOYS, 400) })
		AddTo(updated, 400, "Illusion")
		list(updated.ns.GetMacroEntries(Macro(updated, "Illusion"), true), { 400, PIRATE })
		local laptop = NextLogin(updated, { toyList = With(ALL_TOYS, 400) })
		eq(PanelRow(laptop, "Illusion").count, 2, "and it's there on another computer")
	end)

	it("13. A toy leaves the collection: macros keep it, and just can't use it", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, HAT, "Illusion")
		PutOnBar(world, "Illusion", 1)
		local before = world.macros[1].body
		world.toys[HAT].owned = false
		local later = NextLogin(world)
		list(UsedToys(later, 1), { PIRATE })
		eq(later.macros[1].body, before, "nothing rewritten")
		world.toys[HAT].owned = true
		list(UsedToys(NextLogin(world), 1), { PIRATE, HAT }, "back when it's owned again")
	end)

	it("13. A patch takes a toy out of the game: it stays in its macros and can be removed", function()
		for _, gone in ipairs({ { HAT }, { HAT, GNOME }, { HAT, GNOME, ORB } }) do
			local world = World({ toyList = ALL_TOYS })
			MakeMacro(world, PIRATE, "Illusion")
			AddTo(world, HAT, "Illusion")
			AddTo(world, GNOME, "Illusion")
			MakeMacro(world, CHEST, "Loot")
			PutOnBar(world, "Illusion", 1)
			local before = world.macros[1].body
			for _, id in ipairs(gone) do
				world:RemoveToyFromGame(id)
			end
			local later = NextLogin(world, { toyList = ALL_TOYS })
			eq(later.macros[1].body, before, #gone .. " gone: nothing rewritten")
			eq(PanelRow(later, "Illusion").count, 3, "all three toys are still in it")
			has(later.ns.GetMacroEntries(Macro(later, "Illusion"), true), HAT, "the toy that left")
			list(PanelToys(later, "Loot"), { "Treasure Chest" }, "other macros work")
			assert(later.ns.SetEntry(Macro(later, "Illusion"), HAT, false))
			eq(PanelRow(later, "Illusion").count, 2, "removed from the panel")
			hasNot(later.ns.GetMacroEntries(Macro(later, "Illusion"), true), HAT)
		end
	end)

	it("13. A patch adds a toy and takes one out: macros keep their toys", function()
		local world = World({ toyList = ALL_TOYS })
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, HAT, "Illusion")
		PatchAdds(world, { 400 })
		world:RemoveToyFromGame(ORB)
		local later = NextLogin(world, { toyList = ALL_TOYS })
		eq(PanelRow(later, "Illusion").count, 2)
		list(later.ns.GetMacroEntries(Macro(later, "Illusion"), true), { HAT, PIRATE })
	end)

	it("11. Can't be read: a macro with a toy beyond this Clicky's list says it was saved by a newer Clicky", function()
		local toys = Toys()
		toys[#toys + 1] = { id = 400, name = "New 400" }
		local desktop = World({ toys = toys }) -- Clicky's list here has 400 at the end
		MakeMacro(desktop, PIRATE, "Illusion")
		AddTo(desktop, 400, "Illusion")
		PutOnBar(desktop, "Illusion", 1)
		MakeMacro(desktop, HAT, "Hats")
		PutOnBar(desktop, "Hats", 2)
		local before = desktop:FindMacroByName("Illusion").body
		local laptop = wow.New({ account = desktop.account, toyList = ALL_TOYS }) -- an older Clicky
		ExpectUnreadable(laptop, "Illusion", NEWER, 1)
		eq(laptop:FindMacroByName("Illusion").body, before, "left as it is")
		list(UsedToys(laptop, 2), { HAT }, "the other macro works")
		local back = wow.New({ account = desktop.account, toyList = With(ALL_TOYS, 400) })
		list(UsedToys(back, 1), { PIRATE, 400 }, "and it reads again with the newer list")
	end)

	it("10. Update Clicky: spells and items in Clicky's list change no toy's place, macro, Favorites or count", function()
		local ENTRIES = { PIRATE, ORB, GNOME, HAT, WINGS, CHEST, "s500", "i600" }
		local world = World({ toyList = ALL_TOYS })
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, HAT, "Illusion")
		PutOnBar(world, "Illusion", 1)
		local before = world.macros[1].body
		local filters = world.ns.DefaultGridFilters("toys")
		filters.uncollected = true
		local grid = { world.ns.GridSections({ toys = filters }, "") }
		local later = NextLogin(world, { toyList = ENTRIES })
		eq(later.macros[1].body, before, "the macro isn't rewritten")
		list(UsedToys(later, 1), { PIRATE, HAT }, "and reads the same toys")
		list(later.ns.GetMacroEntries(Favorites(later), true), world.ns.GetMacroEntries(Favorites(world), true), "Favorites' toys")
		list({ later.ns.GridSections({ toys = filters }, "") }, grid, "the grid's toys")
		list(later.ns.GetToyList().ids, ALL_TOYS, "the toys, without the spell and the item")
		eq(later.ns.CountOwnedToys(), 6)
		later.prints = {}
		later:Slash("/clicky status")
		eq(later.prints[1]:gsub("^|cff33ff99Clicky|r: ", ""), "6 toys owned.")
		local debug = Debug(later)
		ok(debug:find("toy list: 6 toys from build test", 1, true), debug)
		-- A toy listed after a spell is stored by its place in the whole list.
		local mixed = World({ toyList = { PIRATE, "s500", ORB, "i600", GNOME } })
		eq(mixed.ns.GetToyList().index[GNOME], 4)
		MakeMacro(mixed, PIRATE, "Mixed")
		AddTo(mixed, GNOME, "Mixed")
		list(assert(mixed.ns.DecodePlaces(mixed:FindMacroByName("Mixed").body:match("#clicky (%S+)"))).positions, { 0, 4 })
	end)

	it("11. Can't be read: a damaged macro never loads toys, says so, and can be renamed or deleted", function()
		local world = World()
		local ns = world.ns
		-- The right toys, but a character typed over.
		local data = ns.EncodePlaces({ 0, 1 })
		world.bars[1] = world:CreateMacroInUI("Broken", ns.NewBody("BRKN", data:sub(1, -2) .. (data:sub(-1) == "A" and "B" or "A")))
		ExpectUnreadable(world, "Broken", UNREADABLE, 1)
		world.bars[2] = world:CreateMacroInUI("Cut", ns.NewBody("CTXX", ns.EncodePlaces({ 0, 1, 5, 40, 300 }):sub(1, 6)))
		world:PressBar(2)
		eq(#world.used, 0, "a cut-off line loads nothing either")
		assert(ns.RenameMacro(Macro(world, "Broken"), "Fixed later"))
		ok(world:FindMacroByName("Fixed later"), "it can be renamed")
		assert(ns.DeleteMacro(Macro(world, "Fixed later")))
		eq(#world.macros, 1, "it can be deleted")
	end)

	it("10. Update Clicky: a macro saved by 0.5.0 can't be read and is left as it is", function()
		local world = World()
		local ns = world.ns
		-- 0.5.0's format 5 line for places 0, 3 and 40, as 0.5.0 wrote it.
		local body = ns.NewBody("BCDF", "rAvTtd")
		world.bars[1] = world:CreateMacroInUI("Old", body)
		ExpectUnreadable(world, "Old", UNREADABLE, 1)
		world:Fire("UPDATE_MACROS")
		world:Advance(1)
		eq(world.macros[1].body, body, "not rewritten")
		assert(ns.DeleteMacro(Macro(world, "Old")))
		MakeMacro(world, PIRATE, "Old")
		PutOnBar(world, "Old", 1)
		list(UsedToys(world, 1), { PIRATE }, "made again")
	end)

	it("10. Update Clicky: macros from 0.4.0 aren't Clicky macros: no row, left as they are", function()
		local world = World({ macros = { { name = "Illusion", icon = 1001, body = V040_PIRATE_HAT },
			{ name = "Illusion 2", icon = 1001, body = V040_PIRATE_HAT },
			{ name = "Stars", icon = "x", body = OLD_FAVORITES_LINE } } })
		world.bars[1] = world.macros[1]
		list(PanelTexts(world), { "Favorites", "Right-click a toy, mount, pet, spell or item to make one." })
		eq(world.macros[1].body, V040_PIRATE_HAT, "not rewritten")
		eq(world.macros[2].body, V040_PIRATE_HAT, "nor is its copy")
		eq(world.macros[3].body, OLD_FAVORITES_LINE, "nor is the old Favorites macro")
		eq(world.env.ClickySet1, nil, "no button for its line")
		eq(world.env.ClickyButton, nil)
		list(UsedToys(world, 1), {}, "it does nothing")
		world.ns.PickupMacro(Favorites(world))
		eq(#world.macros, 4, "Favorites gets a macro of its own")
		eq(world.cursor.body, FAVORITES_LINE)
		MakeMacro(world, PIRATE, "Illusion")
		eq(world:FindMacroByName("Illusion").body, V040_PIRATE_HAT, "a new macro of the same name leaves it alone")
		eq(#world:TakeErrors(), 0)
	end)

	it("11. Can't be read: a macro saved by a newer Clicky says to update", function()
		local world = World()
		local ns = world.ns
		local data = ns.EncodePlaces({ 0 })
		world:CreateMacroInUI("Future", ns.NewBody("FTRX", "x" .. data:sub(2)))
		ExpectUnreadable(world, "Future", NEWER)
	end)

	it("11. Can't be read: a macro the player breaks in /macro can't be changed", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		local broken = world.macros[1].body:gsub("\n#clicky .*", "\n#clicky broken")
		world:EditMacroInUI(1, nil, broken)
		list({ world.ns.SetEntry(Macro(world, "Illusion"), ORB, true) }, { nil, UNREADABLE })
		eq(world.macros[1].body, broken, "left as it is")
	end)

	it("12. Copy a macro: pasted on another account, it works there too", function()
		local desktop = World()
		MakeMacro(desktop, PIRATE, "Illusion")
		AddTo(desktop, ORB, "Illusion")
		local other = World() -- another account: its own macros and collection, the same game
		other.toys[ORB].owned = false
		other.bars[1] = other:CreateMacroInUI("Pasted", desktop.macros[1].body)
		list(UsedToys(other, 1), { PIRATE }, "the toys this account owns")
		list(PanelToys(other, "Pasted"), { "Orb of Deception", "Pirate's Costume" }, "every toy in it, owned or not")
		for _, row in ipairs(other.ns.PanelRows()) do
			if row.key then eq(row.owned, row.key == PIRATE, "only the owned toy looks owned") end
		end
		eq(PanelRow(other, "Pasted").count, 2)
		other:Advance(1) -- drawers are filled a few at a time
		list(DrawerToys(other, "Pasted"), { PIRATE }, "the drawer has only toys it can use")
		has(MenuLabels(other, ORB), "[x] Pasted", "an unowned toy can still be taken out")
		assert(other.ns.SetEntry(Macro(other, "Pasted"), ORB, false))
		list(PanelToys(other, "Pasted"), { "Pirate's Costume" })
	end)

	it("12. Copy a macro: the copy gets its own button and its own toys from then on", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		-- Named so it's listed before the original: general macros are sorted by name.
		world.bars[2] = world:CreateMacroInUI("Costumes", world.macros[1].body)
		local copy, original = world:FindMacroByName("Costumes"), world:FindMacroByName("Illusion")
		local copyCode, originalCode = CodeOf(copy.body), Code(world, "Illusion")
		ok(copyCode and copyCode ~= originalCode, "the copy clicks buttons of its own: " .. copy.body)
		eq(copyCode, Code(world, "Costumes"), "which are its id")
		eq(copy.body:match("^[^\n]*"), Line(copyCode))
		eq(original.body:match("^[^\n]*"), Line(originalCode), "the original keeps its /click line")
		list(UsedToys(world, 2), { PIRATE, ORB }, "the copy has the same toys")
		assert(world.ns.SetEntry(Macro(world, "Costumes"), ORB, false))
		list(UsedToys(world, 2), { PIRATE })
		list(UsedToys(world, 1), { PIRATE, ORB }, "the original is unchanged")
	end)

	it("12. Copy a macro: a copy too long to rewrite keeps the original's button, and nothing hangs", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		local body = world.macros[1].body
		-- A line of the player's own in accented letters: under /macro's 255 characters, over 255
		-- bytes, which Clicky can't write back.
		local long = body .. "\n/say " .. ("é"):rep(240 - #body)
		world.bars[1] = world:CreateMacroInUI("Mine", long)
		local copy = world:FindMacroByName("Mine")
		ok(#copy.body > 255, "more than 255 bytes: " .. #copy.body)
		eq(copy.body, long, "left as it is")
		eq(CodeOf(copy.body), Code(world, "Illusion"), "it still clicks the original's button")
		list(UsedToys(world, 1), { PIRATE }, "and uses the original's toys")
		ok(Debug(world):find("\nwaiting: copies too long to separate: 1\n", 1, true), Debug(world))
		-- The player shortens the line in /macro.
		world:EditMacroInUI(world.macros[2] == copy and 2 or 1, "Mine", body .. "\n/say hi")
		ok(CodeOf(copy.body) ~= Code(world, "Illusion"), "then it gets buttons of its own: " .. copy.body)
		ok(Debug(world):find("\nwaiting: nothing\n", 1, true), Debug(world))
		eq(#world:TakeErrors(), 0)
	end)

	it("7. Put a macro on a bar: the player's own macro can /click a Clicky macro's button", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		-- A macro of the player's own: a random Illusion toy, then a spell.
		world.bars[2] = world:CreateMacroInUI("Disguise", "/click Clicky" .. Code(world, "Illusion") .. "\n/cast Fireball")
		list(UsedToys(world, 2), { PIRATE, ORB }, "a random toy from Illusion")
		eq(#world.ns.GetMacros(), 2, "Favorites and Illusion: the player's macro isn't a Clicky macro")
	end)

	it("12. Copy a macro: a copy in character macros isn't read; it clicks the original's button", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		local body = world.macros[1].body
		local copy = world:CreateMacroInUI("Mine", body, true)
		world.bars[1] = copy
		list(PanelTexts(world), { "Favorites", "Illusion", "  Orb of Deception", "  Pirate's Costume" })
		list(UsedToys(world, 1), { PIRATE, ORB }, "Illusion's toys")
		eq(copy.body, body, "left as it is")
	end)

	it("12. Copy a macro: logging in during combat, a copy waits for combat to end", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		PutOnBar(world, "Illusion", 1)
		local before = world.macros[1].body
		-- Copied where Clicky wasn't running.
		table.insert(world.account.macros, { name = "Illusion 2", body = before })
		local later = NextLogin(world, { combat = true })
		later.bars[2] = later.macros[2]
		ok(Debug(later):find("\nwaiting: buttons to make: 2, copies to separate: 1\n", 1, true))
		eq(later.macros[1].body, before, "nothing written in combat")
		eq(later.macros[2].body, before)
		later:LeaveCombat()
		eq(later.macros[1].body, before, "nothing to re-save")
		local copyCode = CodeOf(later.macros[2].body)
		ok(copyCode and copyCode ~= CodeOf(before), "the copy has a code of its own: " .. later.macros[2].body)
		eq(later:PressBar(1) and later:LastUsed(), PIRATE)
		eq(later:PressBar(2) and later:LastUsed(), PIRATE)
		eq(#later.used, 2)
		ok(Debug(later):find("\nwaiting: nothing\n", 1, true))
	end)

	-- The format Clicky writes into players' macros, exactly as written. Macros live in players'
	-- games, so it keeps reading as it did; only an alpha release may drop a format (CLAUDE.md). A
	-- new format version needs a sample here before this test passes.
	local WRITTEN_FORMATS = {
		-- Format 6: places 0, 3 and 40.
		[6] = { data = "wDAvT1t", positions = { 0, 3, 40 } },
	}
	it("Saved macros: every format Clicky writes still reads exactly as it did", function()
		local ns = World().ns
		local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		-- Codec.lua: a first character of 48 + n is format 6 + n.
		local function Version(data) return alphabet:find(data:sub(1, 1), 1, true) - 1 - 42 end
		for version, sample in pairs(WRITTEN_FORMATS) do
			local d = assert(ns.DecodePlaces(sample.data), "format " .. version .. " no longer reads")
			list(d.positions, sample.positions, "format " .. version)
			eq(ns.EncodePlaces(sample.positions), sample.data, "format " .. version .. " is still written the same")
		end
		ok(WRITTEN_FORMATS[Version(ns.EncodePlaces({ 0 }))], "the format written has a sample here")
		-- Format 4 (written by 0.4.0) is no longer read.
		list({ ns.DecodePlaces("gAAlgAwAPxGLWZkHzieCBNLWI3kaW85vYmpr/ir2Xv55+LVKiUvhpguo/vw3XSjf0c") }, { nil, "damaged" },
			"format 4 reads as damaged")
		-- Format 3 (written by 0.3.0-alpha1) had no checksum, so it could be edited into other toys.
		list({ ns.DecodePlaces("YAAlgAwAPxGLWZkHzieCBNLWI3kaW85vYmpr/ir2Xv55+LVKiUvhpguo/vw3XSjf") }, { nil, "damaged" },
			"format 3 reads as damaged")
	end)

	it("Saved macros: Clicky 0.5.0 reads this version's macros, and every later format's, as saved by a newer Clicky", function()
		local ns = World().ns
		local old = OldCodec("v0.5.0-alpha1")
		eq(old.MACRO_TOY_CAP, 150, "0.5.0's Codec.lua")
		-- And the other way: every line 0.5.0 writes reads as damaged here, short or long.
		for k = 0, 150, 5 do
			local positions = {}
			for i = 1, k do positions[i] = (i - 1) * 80 end
			list({ ns.DecodePlaces(old.EncodeToys(positions)) }, { nil, "damaged" }, k .. " toys saved by 0.5.0")
		end
		local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local data = ns.EncodePlaces({ 0, 3, 40 })
		-- 0.5.0's Macros.lua shows "newer" as "saved by a newer version of Clicky" (CantRead there).
		list({ old.DecodeToys(data) }, { nil, "newer" }, "a macro this version writes")
		for v = 48, 63 do
			local later = alphabet:sub(v + 1, v + 1) .. data:sub(2)
			list({ old.DecodeToys(later) }, { nil, "newer" }, "format " .. v - 42 .. " in 0.5.0")
			if v > 48 then
				list({ ns.DecodePlaces(later) }, { nil, "newer" }, "format " .. v - 42 .. " in this version")
			end
		end
	end)

	it("14. Use the drawer: a toy whose data hasn't loaded yet still has its icon", function()
		local world = World()
		world.toys[HAT].loading = true
		local m = MakeMacro(world, HAT, "Hats")
		world.ns.FillDrawer(m)
		eq(world.ns.GetDrawer(m.id).buttons[1].icon.texture, 2001, "the icon the drawer shows")
	end)

	it("14. Use the drawer: right-click opens it; clicking a toy uses it, and saves nothing", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		AddTo(world, HAT, "Illusion")
		world.toys[HAT].owned = false
		PutOnBar(world, "Illusion", 1)
		local body = world.macros[1].body
		world:PressBar(1, "RightButton")
		ok(DrawerOpen(world, "Illusion"), "the drawer opened")
		list(DrawerToys(world, "Illusion"), { ORB, PIRATE }, "the owned toys, in the panel's order")
		local drawer = world.ns.GetDrawer(Macro(world, "Illusion").id)
		for i = 1, DrawerCount(world, Macro(world, "Illusion").id) do
			-- "item" is what WoW's item action uses (SecureTemplates.lua, SECURE_ACTIONS.item).
			eq(drawer.buttons[i]:GetAttribute("item"), nil, "a toy button holds its toy only as a toy")
		end
		ClickInDrawer(world, "Illusion", ORB)
		eq(world:LastUsed(), ORB, "used at once")
		ok(not DrawerOpen(world, "Illusion"), "and the drawer closed")
		eq(world.macros[1].body, body, "nothing saved")
		world:EnterCombat()
		world:PressBar(1, "RightButton")
		ClickInDrawer(world, "Illusion", ORB)
		eq(world:LastUsed(), ORB, "in combat too")
		world:LeaveCombat()
		eq(world.macros[1].body, body)
	end)

	it("14. Favorites' drawer: the starred toys; clicking one uses it", function()
		local world = World()
		PutOnBar(world, "Favorites", 1)
		eq(world.macros[1].body, FAVORITES_LINE)
		world:PressBar(1, "RightButton")
		list(DrawerToys(world, "Favorites"), { WINGS, CHEST }, "Fairy Wings, Treasure Chest")
		ClickInDrawer(world, "Favorites", CHEST)
		eq(world:LastUsed(), CHEST)
		eq(world.macros[1].body, FAVORITES_LINE, "nothing saved")
	end)

	it("14. Drawers: every button and opener exists after login; drawers fill a few at a time, or when combat starts", function()
		local desktop = World()
		MakeMacro(desktop, PIRATE, "Illusion")
		AddTo(desktop, ORB, "Illusion")
		PutOnBar(desktop, "Illusion", 1)
		PutOnBar(desktop, "Favorites", 2)
		local later = NextLogin(desktop)
		local code = Code(later, "Illusion")
		ok(later.env["ClickyP" .. code] and later.env.ClickyPFVRT, "the openers exist")
		eq(DrawerCount(later, code), 0, "not filled yet")
		later:Advance(1)
		eq(DrawerCount(later, code), 2, "filled soon after login")
		eq(DrawerCount(later, later.ns.FAVORITES_ID), 2)
		local fight = NextLogin(desktop)
		fight:EnterCombat()
		fight:PressBar(1, "RightButton")
		ok(DrawerOpen(fight, "Illusion"), "opens in combat straight after login")
		list(DrawerToys(fight, "Illusion"), { ORB, PIRATE }, "filled when combat started")
	end)

	it("14. Drawers: Escape closes an open drawer, in combat too, and leaves no key binding behind", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		list(world:OverrideKeys(), {}, "no binding while it's closed")
		world:PressBar(1, "RightButton")
		list(world:OverrideKeys(), { "ESCAPE" }, "Escape is bound while it's open")
		ok(world:PressKey("ESCAPE"), "Escape goes to the drawer")
		ok(not DrawerOpen(world, "Illusion"), "Escape closed it")
		list(world:OverrideKeys(), {}, "the binding is gone")
		world:EnterCombat()
		world:PressBar(1, "RightButton")
		ok(world:PressKey("ESCAPE"))
		ok(not DrawerOpen(world, "Illusion"), "in combat too")
		world:PressBar(1, "RightButton")
		ClickInDrawer(world, "Illusion", ORB)
		list(world:OverrideKeys(), {}, "closing it any other way clears it too")
		world:PressBar(1, "RightButton")
		world:MouseAway()
		list(world:OverrideKeys(), {}, "and when it hides by itself")
	end)

	it("8. Rename or delete: Favorites' macro like any other; it's found by its line", function()
		local world = World()
		PutOnBar(world, "Favorites", 1)
		assert(world.ns.RenameMacro(Favorites(world), "Stars"))
		eq(world.macros[1].name, "Stars", "renamed")
		eq(world.ns.PanelRows()[1].macro.name, "Stars", "still first in the panel")
		world:PressBar(1)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "still works on the bar")
		list({ world.ns.MakeMacro("stars", PIRATE) }, { nil, "There's already a macro called Stars." })
		assert(world.ns.DeleteMacro(Favorites(world)))
		eq(#world.macros, 0, "deleted")
		eq(world.ns.PanelRows()[1].macro, Favorites(world), "Favorites stays in the panel")
		eq(world.ns.PanelRows()[1].macro.name, "Favorites", "under its first name, as after a login")
		PutOnBar(world, "Favorites", 2)
		eq(#world.macros, 1, "made again when dragged")
		eq(world.macros[1].name, "Favorites")
		eq(world.macros[1].body, FAVORITES_LINE)
	end)

	-- Every line /clicky debug prints, as the player reads it.
	it("Debugging: /clicky debug prints the game's and Clicky's state, then each macro", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		AddTo(world, GNOME, "Illusion")
		world.toys[ORB].usable = false
		world.toys[GNOME].cooldown = 300
		world:CreateMacroInUI("Broken", "/click ClickyBCDF\n#clicky broken")
		world:Advance(1)
		local debug = Debug(world)
		local illusion = Macro(world, "Illusion")
		-- A line is checked for each of its facts, so one line wrong doesn't hide in another's text.
		local function Printed(start)
			for text in debug:gmatch("[^\n]+") do
				if text:sub(1, #start) == start then return text end
			end
			error("no line starts with " .. start, 2)
		end
		local function Says(line, facts)
			for _, fact in ipairs(facts) do
				ok(line:find(fact, 1, true), ("%q lacks %q"):format(line, fact))
			end
		end
		eq(Printed("Clicky @"), "Clicky @project-version@")
		Says(Printed("toy list"), { "6 toys from build test", "game counts 6" })
		Says(Printed("a macro holds"), { "up to 100 items" })
		Says(Printed("grid"), { "not made", "new toys this session: 0" })
		eq(Printed("waiting"), "waiting: nothing")
		eq(Printed("views"), "views: panel hidden; grid hidden")
		Says(Printed("Favorites ("), { "(ClickyFVRT): 2 items", "unusable: 0, on cooldown: 0", "drawer 2 items",
			"macro: none, state ready" })
		Says(Printed("Broken ("), { "(ClickyBCDF): 0 items", "drawer 0 items", "macro: 1",
			"state unreadable (damaged)", "data 6 chars", "no items" })
		Says(Printed("Illusion ("), { "(Clicky" .. illusion.id .. "): 3 items", "unusable: 1, on cooldown: 1",
			"ready for combat nil", "drawer 3 items", "macro: 2, state ready",
			("data %d chars"):format(#illusion.data), "3 items" })
		world.prints = {}
		world:Slash("/clicky status")
		local status = {}
		for i, line in ipairs(world.prints) do
			status[i] = line:gsub("^|cff33ff99Clicky|r: ", "")
		end
		list(status, {
			"6 toys owned.",
			"Favorites: 2 toys owned, 2 ready to use here.",
			"Broken: " .. UNREADABLE,
			"Illusion: 3 items owned, 1 ready to use here.",
		})
	end)

	it("Debugging: /clicky debug shows what the combat lists hold, an open drawer and a refresh waiting", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world:Advance(1)
		world:PressBar(1, "RightButton")
		local ns = world.ns
		local shown = true
		ns.RegisterView("test", function() return shown end, function() end, 5)
		ns.Changed()
		world:EnterCombat()
		local all = Debug(world)
		ok(all:find("views: panel hidden; grid hidden; test shown, refresh pending\n", 1, true), all)
		ok(all:find("Illusion %(Clicky%u+%): 2 items %(.-%), ready for combat 2, drawer 2 items, open, macro: "), all)
		ok(all:find("Favorites %(ClickyFVRT%): 2 items %(.-%), ready for combat 2, drawer 2 items, macro: "), all)
	end)

	-- Chat can't be copied from, so the state and the trace are in a window whose text can be, made
	-- as Blizzard's script errors window is.
	it("Debugging: /clicky debug opens a window of the state, in chat nothing; a click on its text selects it all", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		world.prints = {}
		world:Slash("/clicky debug")
		local window = world.env.ClickyDebug
		ok(window and window:IsShown(), "the window is open")
		eq(window.TitleContainer.TitleText:GetText(), "Clicky debug")
		local editBox = window.text:GetEditBox()
		local text = editBox:GetText()
		ok(text:find("^Clicky ") and text:find("\nIllusion %(Clicky%u+%): 1 items"), text)
		ok(text:find("\n\nTrace:\nTick Trace to record each pick and change here.$"), text)
		list(world.prints, {}, "nothing in chat")
		ok(not editBox:HasFocus(), "opening it leaves the keyboard alone: keys still reach the game")
		editBox:SetFocus() -- the player clicks the text
		eq(editBox.selected, text, "all of it selected, for Ctrl+C")
		editBox:ClearFocus() -- Escape
		has(world.env.UISpecialFrames, "ClickyDebug", "then Escape closes it")
	end)

	it("Debugging: the debug window's Trace box records each change under the state, in combat too, the newest 1000", function()
		local world = World()
		world:EnterCombat()
		Debug(world)
		local window = world.env.ClickyDebug
		local editBox = window.text:GetEditBox()
		eq(window.trace:GetChecked(), false, "off as each session starts")
		window.trace:Click()
		ok(world.ns.IsTracing(), "ticking it traces")
		world.ns.Trace("[test] one")
		world.ns.Trace("[test] two")
		ok(not editBox:GetText():find("[test] two", 1, true), "drawn on the next frame")
		world:Advance(0)
		local text = editBox:GetText()
		ok(text:find("\n\nTrace:\n[debug] trace on\n", 1, true), text)
		eq(text:sub(-#"[test] one\n[test] two"), "[test] one\n[test] two", text)
		editBox:SetFocus()
		world.ns.Trace("[test] three")
		world:Advance(0)
		eq(editBox.selected, editBox:GetText(), "a new line keeps it all selected while the text is clicked")
		window:Hide()
		Debug(world)
		eq(window.trace:GetChecked(), true, "still ticked when opened again")
		window.trace:Click()
		ok(not world.ns.IsTracing(), "unticking it stops")
		world.ns.SetTracing(true)
		for i = 1, 1005 do
			world.ns.Trace("line %d", i)
		end
		local lines = world.ns.GetTraceLines()
		eq(#lines, 1000)
		eq(lines[1], "line 6", "the oldest are dropped")
		eq(lines[1000], "line 1005")
	end)

	it("Debugging: a trace line, in the debug window only, shows nil, a number in a string and a boolean for any format", function()
		local world = World()
		world.ns.SetTracing(true)
		world.ns.Trace("[test] %s %d %s", nil, "5", true)
		local traced = world.ns.GetTraceLines()
		eq(traced[#traced], "[test] nil 5 true")
		eq(#world.prints, 0, "not in chat: a trace would flood it")
		world.ns.SetTracing(false)
		world.ns.Trace("[test] %s", nil)
		eq(#world.ns.GetTraceLines(), 1, "nothing is traced with tracing off")
	end)

	-- The Toy Box filters are the player's own saved settings: changing them outlives the addon.
	it("Never changes the player's settings: the code calls no setting-changing function", function()
		local forbidden = { "SetCollectedShown", "SetUncollectedShown", "SetUnusableShown",
			"SetSourceTypeFilter", "SetExpansionTypeFilter", "SetAllSourceTypeFilters",
			"SetAllExpansionTypeFilters", "SetFilterString", "ForceToyRefilter", "SetDefaultFilters",
			"SetCVar", "ConsoleExec", "SaveBindings", "SetBinding(",
			-- The Mount and Pet Journals' filters, search, sort, names and battle team
			-- (MountJournalDocumentation.lua, PetJournalInfoDocumentation.lua, Blizzard_PetCollection.lua and .xml).
			"SetCollectedFilterSetting", "SetTypeFilter", "SetSourceFilter", "SetAllSourceFilters",
			"SetAllTypeFilters", "SetSearch", "SetFilterChecked", "SetAllPetTypesChecked",
			"SetAllPetSourcesChecked", "SetPetSortParameter", "SetCustomName", "SetPetLoadOutInfo" }
		local toc = assert(io.open("Clicky.toc"))
		local files = {}
		for line in toc:lines() do
			if line:match("%.lua%s*$") then files[#files + 1] = line:match("^%s*(.-)%s*$") end
		end
		toc:close()
		ok(#files > 0, "files listed in Clicky.toc")
		for _, file in ipairs(files) do
			local f = assert(io.open(file))
			local source = f:read("*a")
			f:close()
			for _, name in ipairs(forbidden) do
				ok(not source:find(name, 1, true), file .. " calls " .. name)
			end
		end
	end)

	-- Runs fn, failing instead of hanging if it never returns (count hooks need the interpreter).
	local function Finishes(fn, what)
		require("jit").off()
		local steps = 0
		debug.sethook(function()
			steps = steps + 1
			if steps > 2000 then error("never finished: " .. what, 2) end
		end, "", 100000)
		local result = { pcall(fn) }
		debug.sethook()
		require("jit").on()
		assert(result[1], result[2])
		return unpack(result, 2)
	end

	-- The codes the account's general macros click, in order (false for one that clicks none).
	local function Codes(world)
		local codes = {}
		for _, macro in ipairs(world.macros) do
			codes[#codes + 1] = CodeOf(macro.body) or false
		end
		return codes
	end

	local function AllDifferent(codes)
		local seen = {}
		for _, code in ipairs(codes) do
			if not code or seen[code] then return false end
			seen[code] = true
		end
		return true
	end

	-- Copied in /macro on a computer without Clicky (or with it disabled): WoW saves the copy to the
	-- account as it is. makes: the toys of the macros made first (Illusion, Orb); copies: the number
	-- of the macro each copy is of.
	for _, case in ipairs({
		{ "a copy made where Clicky wasn't running gets its own button at the next login", { PIRATE }, { 1 } },
		{ "two copies arriving at login each get their own button", { PIRATE }, { 1, 1 } },
		{ "copies arriving at login don't take a code another macro clicks", { PIRATE, ORB }, { 2 } },
	}) do
		it("12. Copy a macro: " .. case[1], function()
			local world = World()
			local names = { "Illusion", "Orb" }
			local codes = {}
			for i, toy in ipairs(case[2]) do
				MakeMacro(world, toy, names[i])
				codes[names[i]] = CodeOf(world:FindMacroByName(names[i]).body)
			end
			for n, of in ipairs(case[3]) do
				table.insert(world.account.macros, { name = names[of] .. " " .. (n + 1), body = world.macros[of].body })
			end
			local later = Finishes(function() return NextLogin(world) end, "logging in")
			ok(#Codes(later) == #case[2] + #case[3] and AllDifferent(Codes(later)), "each macro clicks its own button")
			for name, code in pairs(codes) do
				eq(CodeOf(later:FindMacroByName(name).body), code, name .. " keeps its own")
			end
		end)
	end

	-- Hand edits the checksum is meant to catch (Codec.lua: "a hand-edited line then reads
	-- as damaged rather than as other toys"; journey 11: "It never uses toys that weren't put in it").
	local function RealisticData(ns)
		-- 40 toys in a row out of 1,000: runs of zero bits, so "A" (0) characters in the toys.
		local positions = {}
		for i = 1, 40 do positions[i] = 100 + i end
		return ns.EncodePlaces(positions), positions
	end

	it("11. Can't be read: either header character typed as any other never reads as other toys", function()
		local ns = World().ns
		local data = RealisticData(ns)
		local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local function Char(v) return alphabet:sub(v + 1, v + 1) end
		for v = 0, 63 do
			local first = Char(v) .. data:sub(2)
			if v ~= 48 then
				list({ ns.DecodePlaces(first) }, { nil, v > 48 and "newer" or "damaged" }, "first character " .. v)
			end
			local second = data:sub(1, 1) .. Char(v) .. data:sub(3)
			if second ~= data then
				list({ ns.DecodePlaces(second) }, { nil, "damaged" }, "second character " .. v)
			end
		end
		-- Codec.lua's checksum, so a line can pass it: what the header alone refuses.
		local function Sum(body)
			local a, b = 0, 0
			for i = 1, #body do
				a = (a + alphabet:find(body:sub(i, i), 1, true) - 1) % 64
				b = (b + a) % 64
			end
			return body .. Char(a) .. Char(b)
		end
		local body = data:sub(1, -3)
		eq(Sum(body), data, "the same checksum as Codec.lua's")
		list({ ns.DecodePlaces(Sum("w")) }, { nil, "damaged" }, "no Rice parameter, even with a good checksum")
		for v = 0, 63 do
			if v < 48 then
				list({ ns.DecodePlaces(Sum(Char(v) .. body:sub(2))) }, { nil, "damaged" },
					"first character " .. v .. ": formats 1 to 5, even with a good checksum")
			end
			if v >= 16 then
				list({ ns.DecodePlaces(Sum("w" .. Char(v) .. body:sub(3))) }, { nil, "damaged" },
					"Rice parameter " .. v .. ", even with a good checksum")
			end
		end
	end)

	it("11. Can't be read: one character deleted or added never reads as other toys", function()
		local ns = World().ns
		local data, positions = RealisticData(ns)
		local want = table.concat(positions, ",")
		for i = 2, #data - 1 do
			for _, edited in ipairs({ data:sub(1, i - 1) .. data:sub(i + 1), data:sub(1, i - 1) .. "A" .. data:sub(i) }) do
				local d = ns.DecodePlaces(edited)
				ok(d == nil or table.concat(d.positions, ",") == want,
					("character %d deleted or an A added there reads as %s"):format(i, d and table.concat(d.positions, ",") or ""))
			end
		end
	end)

	it("11. Can't be read: right-clicking it on a bar says why, as a click does", function()
		local world = World()
		local ns = world.ns
		local data = ns.EncodePlaces({ 0, 1 })
		world.bars[1] = world:CreateMacroInUI("Broken",
			ns.NewBody("BRKN", data:sub(1, -2) .. (data:sub(-1) == "A" and "B" or "A")))
		world:Advance(1)
		world:TakeErrors()
		world:PressBar(1, "RightButton")
		list(world:TakeErrors(), { UNREADABLE }, "right-click says why")
	end)

	it("12. Copy a macro: the copy's right-click opens its own drawer", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		world.bars[2] = world:CreateMacroInUI("Costumes", world.macros[1].body)
		assert(world.ns.SetEntry(Macro(world, "Costumes"), ORB, false))
		world:PressBar(2, "RightButton")
		ok(DrawerOpen(world, "Costumes"), "its own drawer opened")
		list(DrawerToys(world, "Costumes"), { PIRATE })
		ok(not DrawerOpen(world, "Illusion"), "not the original's")
	end)

	it("15. The toy grid: favorites first, then the toys owned, each by name; filters and search narrow it", function()
		local toys = Toys()
		toys[#toys + 1] = { id = NEW_TOY, name = "Wand", owned = false }
		local world = World({ toys = toys })
		local ns = world.ns
		local filters = { collected = true, uncollected = false, usableOnly = false }
		for name, value in pairs(filters) do
			eq(ns.DefaultGridFilters("toys")[name], value, "starts with " .. name .. " " .. tostring(value))
		end
		list(GridToys(ns, filters, ""), { WINGS, CHEST, GNOME, ORB, HAT, PIRATE }, "the stars, then the rest owned")
		filters.uncollected = true
		list(GridToys(ns, filters, ""), { WINGS, CHEST, GNOME, ORB, HAT, PIRATE, NEW_TOY }, "Not Collected: then the rest")
		filters.collected = false
		list(GridToys(ns, filters, ""), { NEW_TOY }, "only the toys not owned")
		filters.collected, filters.uncollected, filters.usableOnly = true, false, true
		world.toys[GNOME].usable = false
		world.toys[NEW_TOY].usable = false
		list(GridToys(ns, filters, ""), { WINGS, CHEST, ORB, HAT, PIRATE }, "Usable Only: not a collected unusable toy")
		filters.uncollected = true
		list(GridToys(ns, filters, ""), { WINGS, CHEST, ORB, HAT, PIRATE, NEW_TOY },
			"Usable Only leaves the toys not collected to Not Collected")
		filters.uncollected = false
		list(GridToys(ns, filters, "  PIRATE "), { HAT, PIRATE }, "search, by name")
	end)

	it("15. The toy grid: a toy this game client has no data for isn't listed, rather than a blank slot", function()
		local toys = Toys()
		toys[#toys + 1] = { id = NEW_TOY, name = "Wand", owned = false }
		local ids = {}
		for i, toy in ipairs(toys) do ids[i] = toy.id end
		local world = World({ toys = toys, toyList = ids })
		world:RemoveToyFromGame(NEW_TOY)
		local filters = { collected = false, uncollected = true, usableOnly = false }
		list(GridToys(world.ns, filters, ""), {}, "Clicky's list has it; the game doesn't")
	end)

	it("15. The toy grid: a toy never released or no longer obtainable is listed only once owned, as in the Toy Box", function()
		local toys = Toys()
		toys[#toys + 1] = { id = NEW_TOY, name = "Wand", owned = false }
		local ids = {}
		for i, toy in ipairs(toys) do ids[i] = toy.id end
		local world = World({ toys = toys, toyList = ids, toyHidden = { [NEW_TOY] = true, [PIRATE] = true } })
		local filters = { collected = true, uncollected = true, usableOnly = false }
		list(GridToys(world.ns, filters, ""), { WINGS, CHEST, GNOME, ORB, HAT, PIRATE },
			"the Pirate's Costume, owned, is listed; the Wand, not owned, isn't")
		world:LearnToy({ id = NEW_TOY })
		list(GridToys(world.ns, filters, ""), { WINGS, CHEST, GNOME, ORB, HAT, PIRATE, NEW_TOY }, "learned: listed")
	end)

	it("15. The toy grid: a toy learned this session says NEW until hovered; a gift-wrapped one until a click opens it", function()
		local GIFT, OLD_GIFT = 151, 152
		local toys = Toys()
		toys[#toys + 1] = { id = NEW_TOY, name = "Wand", owned = false }
		toys[#toys + 1] = { id = GIFT, name = "Gift", owned = false }
		toys[#toys + 1] = { id = OLD_GIFT, name = "Old gift", fanfare = true } -- still wrapped from an earlier session
		local world = World({ toys = toys })
		local ns = world.ns
		ok(not ns.IsNewToy(PIRATE), "a toy owned before isn't new")

		world:LearnToy({ id = NEW_TOY })
		ok(ns.IsNewToy(NEW_TOY), "new once learned")
		ns.SeeToy(NEW_TOY)
		ok(not ns.IsNewToy(NEW_TOY), "not new once hovered")

		world:LearnToy({ id = GIFT, fanfare = true })
		ns.SeeToy(GIFT)
		ok(ns.IsNewToy(GIFT), "hovering doesn't open the wrap")
		ns.Unwrap(GIFT)
		ok(not ns.IsNewToy(GIFT), "opened: no longer new")

		ok(ns.IsNewToy(OLD_GIFT), "new, though not learned this session")
		ns.SeeToy(OLD_GIFT)
		ok(ns.IsNewToy(OLD_GIFT), "hovering doesn't open the wrap")
		ns.Unwrap(OLD_GIFT)
		ok(not ns.IsNewToy(OLD_GIFT), "opened: no longer new")
		eq(#world:TakeErrors(), 0)
	end)

	it("15. The toy grid: a section's entries in rows, the favorites and the rest one after the other, as in the Toy Box", function()
		local ns = World().ns
		local function Shape(rows)
			local shape = {}
			for i, row in ipairs(rows) do shape[i] = table.concat(row.keys, " ") end
			return shape
		end
		list(Shape(ns.GridRows({ name = "toys", keys = { 1, 2, 3, 4, 5 } }, 2)), { "1 2", "3 4", "5" })
		list(Shape(ns.GridRows({ name = "spells", keys = { "s1", "s2" } }, 2)), { "s1 s2" })
		list(Shape(ns.GridRows({ name = "items", keys = {} }, 2)), {}, "nothing listed")
	end)

	-- A view that counts its refreshes, registered with Core as the panel and the grid are.
	local function CountingView(ns, name, delay, isShown)
		local view = { refreshes = 0 }
		ns.RegisterView(name, isShown or function() return true end,
			function() view.refreshes = view.refreshes + 1 end, delay)
		return view
	end

	it("15. The toy grid: a toy whose data fails to load doesn't refresh the grid and panel again", function()
		local world = World()
		local view = CountingView(world.ns, "test", 0)
		-- GET_ITEM_INFO_RECEIVED carries itemID and success (ItemDocumentation.lua).
		world:Fire("GET_ITEM_INFO_RECEIVED", HAT, false)
		world:Advance(1)
		eq(view.refreshes, 0, "a failed load brought no name")
		world:Fire("GET_ITEM_INFO_RECEIVED", HAT, true)
		world:Advance(1)
		eq(view.refreshes, 1, "a loaded name refreshes")
		world:Fire("GET_ITEM_INFO_RECEIVED", 999, true)
		world:Advance(1)
		eq(view.refreshes, 1, "an item that isn't a toy doesn't")
	end)

	it("Toy names: the panel, the drawer and the grid sort by name, then ID; a name not loaded yet is empty and asked for", function()
		local world = World()
		local ns = world.ns
		local requested = {}
		world.env.C_Item.RequestLoadItemDataByID = function(id) requested[id] = true end
		world.toys[GNOME].loading = true
		eq(ns.ToyName(PIRATE), "Pirate's Costume")
		eq(ns.ToyName(GNOME), "", "no name yet")
		list(requested, { [GNOME] = true }, "only the toy without a name is asked for")
		local ids = { HAT, GNOME, PIRATE, ORB, WINGS }
		ns.SortEntries(ids)
		list(ids, { GNOME, WINGS, ORB, HAT, PIRATE }, "the empty name first, then by name")
		world.toys[ORB].name = "Fairy Wings"
		ids = { WINGS, ORB }
		ns.SortEntries(ids)
		list(ids, { ORB, WINGS }, "the same name: by item ID")
		ids = { ORB, WINGS }
		ns.SortEntries(ids, { [WINGS] = "A", [ORB] = "Z" })
		list(ids, { WINGS, ORB }, "names the caller has looked up are used")
	end)

	-- Entries: what a macro holds is toys, spells and items, each named by its key in Clicky's
	-- list (a toy's item ID, "s" and a spell ID, "i" and an item ID). Nothing lets a player add
	-- spells or items yet, so these macros are written into the account as their bodies, as
	-- another computer or a later Clicky would have saved them.
	describe("Entries: toys, spells and items", function()
		local FIRE, HOME = "s500", "s501" -- Path of the Fire, Teleport: Home
		local RING, CLOAK = "i600", "i601" -- Hearth Ring, Cloak of Teleport (can be worn)
		local LIST = { PIRATE, ORB, FIRE, HOME, RING, CLOAK }
		local PLACE = { [PIRATE] = 0, [ORB] = 1, [FIRE] = 2, [HOME] = 3, [RING] = 4, [CLOAK] = 5 }

		local function MixedWorld(options)
			options = options or {}
			options.toyList = LIST
			options.spells = options.spells or {
				{ id = 500, name = "Path of the Fire", icon = 5000 },
				{ id = 501, name = "Teleport: Home", icon = 5010 },
			}
			options.items = options.items or {
				{ id = 600, name = "Hearth Ring", icon = 6000 },
				{ id = 601, name = "Cloak of Teleport", icon = 6010, equippable = true },
			}
			return World(options)
		end

		-- A macro as its body, holding these keys.
		local function Write(world, name, code, keys)
			local positions = {}
			for i, key in ipairs(keys) do positions[i] = PLACE[key] end
			table.sort(positions)
			return world:CreateMacroInUI(name, world.ns.NewBody(code, world.ns.EncodePlaces(positions)))
		end

		local function Set(keys)
			local set = {}
			for _, key in ipairs(keys) do set[key] = true end
			return set
		end

		-- LuaJIT walks string keys in an order that changes from run to run, so a click's choices are
		-- put in list order: a seed then replays the same picks (tests/test_random_play.lua).
		it("4. Use a macro: a click chooses among its entries in the list's order, every run", function()
			local spells, list_ = {}, {}
			for i = 1, 24 do
				spells[i] = { id = 700 + i, name = ("Spell %02d"):format(25 - i) }
				list_[i] = "s" .. (700 + i)
			end
			local world = World({ toyList = list_, spells = spells })
			local m = assert(world.ns.MakeMacro("Many", list_[1]))
			for i = 2, 24 do assert(world.ns.SetEntry(m, list_[i], true)) end
			list(world.ns.GetCandidates(m, true), list_)
		end)

		-- How a click on each entry is set on a button: its type, then the attribute that type reads.
		local ACTION = {
			[PIRATE] = { "toy", "toy", PIRATE },
			[FIRE] = { "spell", "spell", 500 },
			[HOME] = { "spell", "spell", 501 },
			[RING] = { "item", "item", "item:600" },
			[CLOAK] = { "item", "item", "item:601" },
		}

		-- Presses the slot until every key in expected has come up (or presses run out); the
		-- keys that did.
		local function Pressed(world, slot, presses)
			local seen = {}
			for _ = 1, presses or 60 do
				world:PressBar(slot)
				seen[world:LastUsed()] = true
			end
			return seen
		end

		it("11. Entries: a macro's spells and items read as entries; one past the end of the list reads as newer", function()
			local world = MixedWorld()
			local ns = world.ns
			Write(world, "Portal", "PRTL", { PIRATE, FIRE, RING, CLOAK })
			local m = Macro(world, "Portal")
			eq(m.state, "ready")
			list(ns.MacroEntries(m), Set({ PIRATE, FIRE, RING, CLOAK }))
			eq(PanelRow(world, "Portal").count, 4)
			list(PanelToys(world, "Portal"), { "Cloak of Teleport", "Hearth Ring", "Path of the Fire", "Pirate's Costume" },
				"listed by name, whatever the kind")
			world:CreateMacroInUI("Future", ns.NewBody("FTRX", ns.EncodePlaces({ 0, 6 })))
			ExpectUnreadable(world, "Future", NEWER)
			ok(Macro(world, "Future").reason:find("place 6 is past the end of this Clicky's list of 6 entries", 1, true),
				Macro(world, "Future").reason)
		end)

		it("4. Entries: a spell or an item goes into a macro and comes out of it by its key", function()
			local world = MixedWorld()
			local ns = world.ns
			local m = MakeMacro(world, PIRATE, "Portal")
			assert(ns.SetEntry(m, FIRE, true))
			assert(ns.SetEntry(m, CLOAK, true))
			list(ns.MacroEntries(m), Set({ PIRATE, FIRE, CLOAK }))
			local data = world:FindMacroByName("Portal").body:match("#clicky (%S+)")
			list(assert(ns.DecodePlaces(data)).positions, { 0, 2, 5 }, "stored by place in the list")
			local later = NextLogin(world, { toyList = LIST })
			eq(later.ns.MacroEntries(Macro(later, "Portal"))[FIRE], true, "and read back")
			assert(ns.SetEntry(m, FIRE, false))
			list(ns.MacroEntries(m), Set({ PIRATE, CLOAK }))
			list({ ns.SetEntry(m, "s999", true) }, { nil, UNKNOWN_TOY }, "an entry the list doesn't have")
			local made = assert(ns.MakeMacro("Spells", HOME))
			eq(world:FindMacroByName("Spells").icon, 5010, "a macro made from a spell has its icon")
			list(ns.MacroEntries(made), Set({ HOME }))
		end)

		it("Entries: each kind has one owner for its name, icon, owned and usable test, cooldown and tooltip", function()
			local world = MixedWorld({ spells = {
				{ id = 500, name = "Path of the Fire", icon = 5000, cooldown = 30 },
				{ id = 501, name = "Teleport: Home", icon = 5010, known = false, usable = false },
			}, items = {
				{ id = 600, name = "Hearth Ring", icon = 6000, count = 0 },
				{ id = 601, name = "Cloak of Teleport", icon = 6010, equippable = true, equipped = true, count = 0 },
			} })
			local ns = world.ns
			eq(ns.EntryName(PIRATE), "Pirate's Costume")
			eq(ns.EntryName(FIRE), "Path of the Fire")
			eq(ns.EntryName(RING), "Hearth Ring")
			eq(ns.EntryIcon(PIRATE), 1001)
			eq(ns.EntryIcon(FIRE), 5000)
			eq(ns.EntryIcon(RING), 6000)
			eq(ns.EntryKind(HOME), "spell")
			eq(ns.EntryID(CLOAK), 601)
			eq(ns.IsEntryOwned(PIRATE), true)
			eq(ns.IsEntryOwned(FIRE), true)
			eq(ns.IsEntryOwned(HOME), false, "a spell the player doesn't know")
			eq(ns.IsEntryOwned(RING), false, "an item that isn't in the bags")
			eq(ns.IsEntryOwned(CLOAK), true, "an item that is worn")
			eq(ns.IsEntryUsable(FIRE), true)
			eq(ns.IsEntryUsable(HOME), false)
			eq(ns.IsEntryOnCooldown(FIRE), true)
			eq(ns.IsEntryOnCooldown(PIRATE), false)
			world.spells[500].cooldown = 0.2
			eq(ns.IsEntryOnCooldown(FIRE), false, "the global cooldown isn't the spell's")
			world.items[601].cooldown = 60
			eq(ns.IsEntryOnCooldown(CLOAK), true, "an item's cooldown")
			eq(ns.IsDrawerOnly(CLOAK), true, "an item that can be worn")
			eq(ns.IsDrawerOnly(RING), false)
			eq(ns.IsDrawerOnly(FIRE), false)
			list({ ns.EntryAction(PIRATE) }, ACTION[PIRATE])
			list({ ns.EntryAction(FIRE) }, ACTION[FIRE])
			list({ ns.EntryAction(RING) }, ACTION[RING], "an item's value is item: and its ID, since a bare number is a slot")
			local owner = world.env.UIParent
			ns.ShowEntryTooltip(owner, FIRE)
			eq(world.tooltip.spell, 500)
			eq(world.tooltip.anchor, "ANCHOR_RIGHT")
			ns.ShowEntryTooltip(owner, RING, "ANCHOR_LEFT")
			eq(world.tooltip.item, 600)
			eq(world.tooltip.anchor, "ANCHOR_LEFT")
			ns.ShowEntryTooltip(owner, PIRATE)
			eq(world.tooltip.toy, PIRATE)
		end)

		it("Entries: names sort across kinds by name, then toy, spell, item, then ID", function()
			local world = MixedWorld({ spells = { { id = 500, name = "Same" }, { id = 501, name = "Same" } },
				items = { { id = 600, name = "Same" }, { id = 601, name = "Alpha" } } })
			world.toys[PIRATE].name = "Same"
			local keys = { RING, HOME, FIRE, PIRATE, CLOAK }
			world.ns.SortEntries(keys)
			list(keys, { CLOAK, PIRATE, FIRE, HOME, RING })
		end)

		it("Entries: a button holds any kind, sets its action and clears the last one's", function()
			local world = MixedWorld({ spells = { { id = 500, name = "Path of the Fire", icon = 5000, cooldown = 30 } } })
			local ns = world.ns
			local button = ns.CreateEntryButton(world.env.UIParent, 36, "ANCHOR_LEFT")
			ns.SetEntryButton(button, PIRATE)
			list({ button:GetAttribute("type"), button:GetAttribute("toy") }, { "toy", PIRATE })
			eq(button.itemID, PIRATE)
			ns.SetEntryButton(button, FIRE)
			list({ button:GetAttribute("type"), button:GetAttribute("spell"), button:GetAttribute("toy") }, { "spell", 500, nil },
				"the toy's attribute is gone")
			eq(button.entry, FIRE)
			eq(button.itemID, nil, "only a toy has an item ID")
			eq(button.icon.texture, 5000)
			ok(button.cooldown.start ~= nil, "a spell on cooldown shows it")
			button.scripts.OnEnter(button)
			eq(world.tooltip.spell, 500)
			ns.SetEntryButton(button, RING)
			list({ button:GetAttribute("type"), button:GetAttribute("item"), button:GetAttribute("spell") }, { "item", "item:600", nil })
			eq(button.cooldown.start, nil)
			ns.SetEntryButton(button, RING, true)
			list({ button:GetAttribute("type"), button:GetAttribute("item") }, { nil, nil }, "unusable: shown, uses nothing")
			eq(button.entry, RING)
			ns.EmptyEntryButton(button)
			eq(button.entry, nil)
			eq(button:GetAttribute("item"), nil)
			-- A plain left click only: the grid's buttons.
			local left = ns.CreateEntryButton(world.env.UIParent, 36, "ANCHOR_LEFT", true)
			ns.SetEntryButton(left, HOME)
			list({ left:GetAttribute("type"), left:GetAttribute("type1"), left:GetAttribute("spell") }, { nil, "spell", 501 })
			ns.SetEntryButton(left, PIRATE)
			list({ left:GetAttribute("type1"), left:GetAttribute("spell"), left:GetAttribute("toy") }, { "toy", nil, PIRATE })
		end)

		it("2. Entries: a click uses a random toy, spell or item, setting the button's action for it", function()
			local world = MixedWorld()
			Write(world, "Portal", "PRTL", { PIRATE, FIRE, RING })
			world.bars[1] = world:FindMacroByName("Portal")
			local button = world.env.ClickyPRTL
			local used = {}
			for _ = 1, 60 do
				world:PressBar(1)
				local key = world:LastUsed()
				used[key] = true
				list({ button:GetAttribute("type"), button:GetAttribute(ACTION[key][2]) }, { ACTION[key][1], ACTION[key][3] },
					"the button's action for " .. key)
				eq(button:GetAttribute("entry"), key, "the entry it holds is the one used")
			end
			list(used, Set({ PIRATE, FIRE, RING }), "all three kinds come up")
			eq(Macro(world, "Portal").lastUsed, world:LastUsed())
			-- A pick of another kind leaves nothing of the last in the button.
			eq((button:GetAttribute("toy") ~= nil and 1 or 0) + (button:GetAttribute("spell") ~= nil and 1 or 0)
				+ (button:GetAttribute("item") ~= nil and 1 or 0), 1, "only the attribute its type reads")
			-- Not the entry used last, unless it's the only one.
			local last = world:LastUsed()
			for _ = 1, 20 do
				world:PressBar(1)
				ok(world:LastUsed() ~= last, "not repeated")
				last = world:LastUsed()
			end
		end)

		it("2. Entries: a click skips spells not known, items not had, ones unusable and ones on cooldown", function()
			local world = MixedWorld()
			Write(world, "Portal", "PRTL", { PIRATE, FIRE, HOME, RING, CLOAK })
			world.bars[1] = world:FindMacroByName("Portal")
			world.spells[501].known = false
			world.items[600].count = 0
			world.items[601].equippable = false
			list(Pressed(world, 1), Set({ PIRATE, FIRE, CLOAK }), "a spell not known and an item not had are left out")
			world.spells[500].usable = false
			world.toys[PIRATE].cooldown = 30
			list(Pressed(world, 1), Set({ CLOAK }), "an unusable spell and a toy on cooldown too")
			world.items[601].cooldown = 30
			world:TakeErrors()
			world:PressBar(1)
			list(world:TakeErrors(), { "No usable items in Portal." }, "none left")
			eq(world.bars[1] and world.env.ClickyPRTL:GetAttribute("type"), nil, "and the button uses nothing")
			world.items[601].cooldown = 0
			world:PressBar(1)
			eq(world:LastUsed(), CLOAK, "usable again")
			-- The player has the worn item by wearing it, not carrying it.
			world.items[601].count, world.items[601].equipped = 0, true
			world:PressBar(1)
			eq(world:LastUsed(), CLOAK, "worn items count")
		end)

		it("2. Entries: a spell's cooldown the game hides counts as a cooldown, and no error", function()
			local world = MixedWorld({ spells = { { id = 500, name = "Path of the Fire", icon = 5000 },
				{ id = 501, name = "Teleport: Home", icon = 5010, cooldown = 30 } } })
			Write(world, "Portal", "PRTL", { FIRE, HOME })
			world.bars[1] = world:FindMacroByName("Portal")
			world.secretCooldowns = true
			eq(world.ns.IsEntryOnCooldown(HOME), true, "an active cooldown with a duration Clicky can't read")
			eq(world.ns.IsEntryOnCooldown(FIRE), false)
			list(Pressed(world, 1), Set({ FIRE }), "so only the spell with none comes up")
			local button = world.ns.CreateEntryButton(world.env.UIParent, 36)
			world.ns.SetEntryButton(button, HOME)
			eq(button.cooldown.start, nil, "and no swipe is drawn from values addon code can't pass on")
		end)

		it("2. Entries: a macro of only an item that can be worn is never clicked; it's in the drawer", function()
			local world = MixedWorld()
			Write(world, "Cloak", "CLKK", { CLOAK })
			world.bars[1] = world:FindMacroByName("Cloak")
			world:PressBar(1)
			list(world:TakeErrors(), { "No usable items in Cloak." })
			eq(#world.used + #world.equipped, 0, "a click doesn't wear it")
			world:PressBar(1, "RightButton")
			ok(DrawerOpen(world, "Cloak"), "the drawer opens")
			list(DrawerToys(world, "Cloak"), { CLOAK })
			ClickInDrawer(world, "Cloak", CLOAK)
			list(world.equipped, { 601 }, "its action wears it, as the game's item action does when it isn't worn")
			eq(#world.used, 0)
			world:PressBar(1, "RightButton")
			ClickInDrawer(world, "Cloak", CLOAK)
			list(world.used, { CLOAK }, "worn, the same click uses it")
		end)

		it("14. Entries: the drawer holds the entries the player has, each with its own action and cooldown", function()
			local world = MixedWorld({ spells = { { id = 500, name = "Path of the Fire", icon = 5000, cooldown = 30 },
				{ id = 501, name = "Teleport: Home", icon = 5010, known = false } } })
			Write(world, "Portal", "PRTL", { PIRATE, FIRE, HOME, RING })
			world.bars[1] = world:FindMacroByName("Portal")
			world:PressBar(1, "RightButton")
			list(DrawerToys(world, "Portal"), { RING, FIRE, PIRATE }, "by name, without the spell not known")
			local drawer = world.ns.GetDrawer(Macro(world, "Portal").id)
			for i, key in ipairs(DrawerToys(world, "Portal")) do
				local button = drawer.buttons[i]
				eq(button:GetAttribute("type"), ACTION[key][1], key)
				eq(button:GetAttribute(ACTION[key][2]), ACTION[key][3], key)
			end
			ok(drawer.buttons[2].cooldown.start ~= nil, "the spell shows its cooldown")
			ok(drawer.buttons[1].cooldown.start == nil)
			ClickInDrawer(world, "Portal", RING)
			list(world.used, { RING }, "a click uses it")
			world:PressBar(1, "RightButton")
			ClickInDrawer(world, "Portal", FIRE)
			eq(world:LastUsed(), FIRE)
		end)

		it("2. Entries: in combat a macro picks from the list handed over, with each entry's action", function()
			local world = MixedWorld()
			Write(world, "Portal", "PRTL", { PIRATE, FIRE, RING, CLOAK })
			world.bars[1] = world:FindMacroByName("Portal")
			world.spells[500].usable = false
			world:EnterCombat()
			local button = world.env.ClickyPRTL
			eq(button:GetAttribute("readycount"), 2, "the toy and the item: not the spell that can't be used, nor the item to wear")
			local ready = {}
			for i = 1, 2 do
				local key = button:GetAttribute("ready" .. i)
				ready[key] = true
				list({ button:GetAttribute("readytype" .. i), button:GetAttribute("readyattr" .. i), button:GetAttribute("readyvalue" .. i) },
					ACTION[key], "the action handed over for " .. key)
			end
			list(ready, Set({ PIRATE, RING }))
			local used, last = {}, nil
			for _ = 1, 30 do
				world:PressBar(1)
				local key = world:LastUsed()
				used[key] = true
				ok(key ~= last, "not repeated")
				last = key
				list({ button:GetAttribute("type"), button:GetAttribute(ACTION[key][2]) }, { ACTION[key][1], ACTION[key][3] })
				eq(Macro(world, "Portal").lastUsed, key)
			end
			list(used, Set({ PIRATE, RING }), "both come up")
			world:PressBar(1, "RightButton")
			list(DrawerToys(world, "Portal"), { CLOAK, RING, FIRE, PIRATE }, "the drawer holds all four")
			ClickInDrawer(world, "Portal", FIRE)
			eq(world:LastUsed(), FIRE, "a spell from the drawer in combat")
			world:LeaveCombat()
			world:PressBar(1)
			ok(world:LastUsed() == PIRATE or world:LastUsed() == RING, "out of combat again")
		end)

		it("2. Entries: in combat a macro with nothing ready uses nothing, and keeps no action from before", function()
			local world = MixedWorld()
			Write(world, "Portal", "PRTL", { PIRATE, FIRE })
			world.bars[1] = world:FindMacroByName("Portal")
			world:PressBar(1)
			local button = world.env.ClickyPRTL
			ok(button:GetAttribute("type") ~= nil, "it held an action")
			world.toys[PIRATE].usable = false
			world.spells[500].known = false
			world:EnterCombat()
			eq(button:GetAttribute("readycount"), 0)
			local before = #world.used
			world:PressBar(1)
			eq(#world.used, before, "nothing used")
			eq(button:GetAttribute("type"), nil)
			eq(button:GetAttribute("entry"), nil)
			list(world:TakeErrors(), { "No usable items in Portal." })
		end)

		it("Entries: a spell's or item's name arriving, and a spell learned or a bag changed, refresh the views", function()
			local world = MixedWorld({ spells = { { id = 500, name = "Path of the Fire", icon = 5000, loading = true } },
				items = { { id = 600, name = "Hearth Ring", icon = 6000, loading = true } } })
			local ns = world.ns
			local view = CountingView(ns, "test", 0)
			local asked = {}
			world.env.C_Spell.RequestLoadSpellData = function(id) asked["s" .. id] = true end
			world.env.C_Item.RequestLoadItemDataByID = function(id) asked["i" .. id] = true end
			eq(ns.EntryName(FIRE), "", "no name yet")
			eq(ns.EntryName(RING), "")
			list(asked, Set({ FIRE, RING }), "both are asked for")
			world:LoadSpell(500)
			world:Advance(1)
			eq(view.refreshes, 1, "a spell's name arriving")
			eq(ns.EntryName(FIRE), "Path of the Fire")
			world:LoadItem(600)
			world:Advance(1)
			eq(view.refreshes, 2, "an item's name arriving")
			world:Fire("GET_ITEM_INFO_RECEIVED", 601, true)
			world:Advance(1)
			eq(view.refreshes, 2, "an item nobody asked for doesn't")
			world:Fire("GET_ITEM_INFO_RECEIVED", 600, true)
			world:Advance(1)
			eq(view.refreshes, 2, "nor does the same one twice")
			for i, event in ipairs({ "SPELLS_CHANGED", "BAG_UPDATE_DELAYED", "PLAYER_EQUIPMENT_CHANGED" }) do
				world:Fire(event)
				world:Advance(1)
				eq(view.refreshes, 2 + i, event)
			end
		end)

		it("4. Entries: a spell's or item's menu has the macros' checkboxes and no star", function()
			local world = MixedWorld()
			local m = MakeMacro(world, PIRATE, "Portal")
			list(MenuLabels(world, FIRE), { "[ ] Portal" })
			for _, entry in ipairs(world.menu.entries) do
				ok(entry.kind ~= "CreateButton" or entry.text == "Add to new macro...", "no star: " .. tostring(entry.text))
			end
			world:ChooseMenuEntry("Portal")
			list(world.ns.MacroEntries(m), Set({ PIRATE, FIRE }), "ticking it adds the spell")
			list(MenuLabels(world, FIRE), { "[x] Portal" })
			list(MenuLabels(world, PIRATE), { "[x] Portal" })
			eq(world.menu.entries[1].text, world.env.BATTLE_PET_FAVORITE, "a toy's menu starts with the star")
			list(PanelToys(world, "Portal"), { "Path of the Fire", "Pirate's Costume" })
			world.ns.OpenEntryMenu(world.env.UIParent, FIRE)
			world:ChooseMenuEntry("Portal")
			list(world.ns.MacroEntries(m), Set({ PIRATE }), "and unticking it takes it out")
		end)

	end)

	it("8. Delete: a copy listed before its original leaves the original its buttons and code", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		local code = m.id
		local body = world:FindMacroByName("Illusion").body
		-- General macros are sorted by name (warcraft.wiki.gg API EditMacro), so this copy is listed first.
		world:CreateMacroInUI("Costumes", body)
		eq(world.macros[1].name, "Costumes", "the copy is listed first")
		eq(CodeOf(world:FindMacroByName("Illusion").body), code, "the original keeps its code")
		ok(CodeOf(world:FindMacroByName("Costumes").body) ~= code, "the copy gets its own")
		eq(Macro(world, "Illusion").id, code, "and the macro is still Illusion's")
		eq(world.env["Clicky" .. code]:GetAttribute("useOnKeyDown"), false, "with its button")
		world:Advance(1)
		eq(DrawerCount(world, code), 1, "and its drawer")
	end)

	it("8. Delete: a macro deleted while its drawer is open closes the drawer and empties its buttons", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		world:Advance(1)
		local drawer = world.ns.GetDrawer(m.id)
		drawer.opener:Click("RightButton", false)
		ok(drawer.frame:IsShown(), "open")
		assert(world.ns.DeleteMacro(m))
		ok(not drawer.frame:IsShown(), "closed with the macro")
		eq(drawer.buttons[1]:GetAttribute("toy"), nil, "its toy button uses nothing")
		eq(drawer.buttons[1].itemID, nil)
		ok(not drawer.buttons[1]:IsShown(), "and is hidden")
		eq(DrawerCount(world, m.id), 0)
	end)

	describe("14. The drawer is filled again", function()
		local function WorldWithWand()
			local toys = Toys()
			toys[#toys + 1] = { id = NEW_TOY, name = "Wand", owned = false }
			local world = World({ toys = toys })
			local m = MakeMacro(world, PIRATE, "Illusion")
			AddTo(world, NEW_TOY, "Illusion")
			world:Advance(1)
			eq(DrawerCount(world, m.id), 1, "the Wand isn't owned")
			return world, m
		end

		it("after combat ends, with a toy learned in combat", function()
			local world, m = WorldWithWand()
			world:EnterCombat()
			world:LearnToy({ id = NEW_TOY, name = "Wand" })
			world:Advance(1)
			eq(DrawerCount(world, m.id), 1, "nothing is refilled in combat")
			world:LeaveCombat()
			world:Advance(1)
			eq(DrawerCount(world, m.id), 2, "refilled once it ends")
		end)

		it("after a loading screen", function()
			local world, m = WorldWithWand()
			world:LearnToy({ id = NEW_TOY, name = "Wand" })
			world:Advance(1)
			eq(DrawerCount(world, m.id), 1, "a toy learned doesn't refill it")
			world:Fire("PLAYER_ENTERING_WORLD", false, false)
			world:Advance(1)
			eq(DrawerCount(world, m.id), 2, "the loading screen does")
		end)
	end)

	it("14. The drawer: its opener opens it on the up click only", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		world:Advance(1)
		local drawer = world.ns.GetDrawer(m.id)
		drawer.opener:Click("RightButton", true)
		ok(not drawer.frame:IsShown(), "the down click does nothing")
		drawer.opener:Click("RightButton", false)
		ok(drawer.frame:IsShown(), "the up click opens it")
		drawer.opener:Click("RightButton", true)
		ok(drawer.frame:IsShown(), "and a down click doesn't close it")
		drawer.opener:Click("RightButton", false)
		ok(not drawer.frame:IsShown(), "the next up click does")
	end)

	it("Sync: a macro that changes while a sync reads them is picked up by a second pass", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		local other = NextLogin(world)
		assert(other.ns.MakeMacro("Hats", HAT))
		local real, fired = world.env.GetMacroInfo, false
		world.env.GetMacroInfo = function(...)
			if not fired then
				fired = true
				world:Fire("UPDATE_MACROS") -- announced while the sync is reading
			end
			return real(...)
		end
		world.ns.SetTracing(true)
		world.prints = {}
		world.ns.Sync("test")
		ok(fired, "the event came during the sync")
		local passes = 0
		for _, line in ipairs(world.ns.GetTraceLines()) do
			passes = tonumber(line:match("%[sync test%] (%d+) pass")) or passes
		end
		ok(passes >= 2, "a second pass ran: " .. passes)
	end)

	it("5. Pick a toy: a toy taken out of a macro and put back can come up on the next click", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world:PressBar(1)
		local used = world:LastUsed()
		local button = world.env["Clicky" .. m.id]
		world:EnterCombat()
		eq(button:GetAttribute("lastentry"), used, "the toy used is the one not repeated")
		world:LeaveCombat()
		assert(world.ns.SetEntry(m, used, false))
		assert(world.ns.SetEntry(m, used, true))
		world:EnterCombat()
		eq(button:GetAttribute("lastentry"), nil, "taking it out and putting it back forgets it")
		world:LeaveCombat()
	end)

	it("5. Pick a toy: a toy another computer takes out of a macro is forgotten here", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world:PressBar(1)
		local used = world:LastUsed()
		local other = NextLogin(world)
		assert(other.ns.SetEntry(Macro(other, "Illusion"), used, false))
		world:Fire("UPDATE_MACROS")
		world:EnterCombat()
		eq(world.env["Clicky" .. m.id]:GetAttribute("lastentry"), nil, "no longer the last used")
		world:LeaveCombat()
	end)

	it("15. The toy grid: the filter reset arrow shows only when the filters differ from the defaults", function()
		local world = World()
		world:LoadCollections()
		world:OpenToyBox()
		local filter = world.env.ClickyGridFilter
		ok(filter.isDefaultCallback(), "the defaults at the start")
		world:GridFilterMenu()[2].toggle()
		ok(not filter.isDefaultCallback(), "Not Collected on")
		world:GridFilterMenu()[2].toggle()
		ok(filter.isDefaultCallback(), "and off again")
		world:GridFilterMenu()[3].toggle()
		ok(not filter.isDefaultCallback(), "Usable Only on")
		filter.defaultCallback()
		ok(filter.isDefaultCallback(), "reset")
	end)

	it("1. the arrow beside the Filter button hides the panel and brings it back, in combat too", function()
		local world = World()
		world:LoadCollections()
		world:OpenToyBox()
		local toggle, panel = world.env.ClickyPanelToggle, world.env.ClickyPanel
		ok(panel:IsVisible(), "shown as each session starts")
		ok(toggle.CloseButton:IsShown() and not toggle.OpenButton:IsShown(), "the arrow that hides it")
		world:EnterCombat()
		toggle.CloseButton:GetScript("OnClick")(toggle.CloseButton, "LeftButton")
		ok(not panel:IsShown(), "hidden")
		ok(toggle.OpenButton:IsShown() and not toggle.CloseButton:IsShown(), "the arrow that brings it back")
		ok(Debug(world):find("\npanel: made, hidden,", 1, true), "/clicky debug says so")
		local journal = world.env.CollectionsJournal
		ok(journal:GetAttribute("UIPanelLayout-extraWidth"), "the window keeps the panel's room in the fight")
		world:LeaveCombat()
		eq(journal:GetAttribute("UIPanelLayout-extraWidth"), nil, "and gives it up when the fight ends")
		list(world:TakeErrors(), {})
		toggle.OpenButton:GetScript("OnClick")(toggle.OpenButton, "LeftButton")
		ok(panel:IsVisible(), "back")
		ok(toggle.CloseButton:IsShown())
		eq(journal:GetAttribute("UIPanelLayout-extraWidth"), panel:GetWidth() + 2, "with its room")
	end)

	it("Debugging: the panel is in /clicky debug, and opening or closing a macro in the panel is traced", function()
		local world = World()
		eq(world.ns.GetPanelState(), "not made")
		MakeMacro(world, PIRATE, "Illusion")
		world:LoadCollections()
		world:OpenToyBox()
		world:Advance(1)
		world.ns.SetTracing(true)
		world.prints = {}
		local row = world.ns.PanelRows()[2]
		local rowFrame
		for _, shown in ipairs(world.scrollList.rows) do
			if shown:IsShown() and shown.name:GetText() == "Illusion" then rowFrame = shown end
		end
		local function Traced(text)
			for _, line in ipairs(world.ns.GetTraceLines()) do
				if line:find("[panel] " .. row.macro.id .. text, 1, true) then return true end
			end
		end
		rowFrame.scripts.OnClick(rowFrame, "LeftButton") -- it was open when made
		ok(Traced(" closed, scroll to it: false"), "closing is traced")
		world:Advance(1)
		rowFrame.scripts.OnClick(rowFrame, "LeftButton")
		ok(Traced(" opened, scroll to it: true"), "opening is traced")
		eq(world.ns.GetPanelState(), "made, shown, next refresh scrolls to " .. row.macro.id)
		world:Advance(1)
		eq(world.ns.GetPanelState(), "made, shown, next refresh scrolls to nothing")
		ok(Debug(world):find("panel: made, shown", 1, true), "in the debug output")
	end)

	describe("Views", function()
		it("ns.Changed refreshes every view that is shown, once per burst, after the view's own delay", function()
			local world = World()
			local ns = world.ns
			local shown = true
			local quick = CountingView(ns, "quick", 0)
			local slow = CountingView(ns, "slow", 0.2)
			local sometimes = CountingView(ns, "sometimes", 0, function() return shown end)
			ns.Changed()
			ns.Changed()
			ns.Changed()
			eq(quick.refreshes, 0, "not at once: a burst of changes is one refresh")
			shown = false
			world:Advance(0)
			eq(quick.refreshes, 1, "a view with no delay refreshes next frame")
			eq(slow.refreshes, 0, "a view with a delay waits for it")
			eq(sometimes.refreshes, 0, "a view hidden by then is not refreshed")
			world:Advance(0.2)
			eq(slow.refreshes, 1, "once, not once per change")
			eq(quick.refreshes, 1)
			ns.Changed()
			world:Advance(1)
			eq(quick.refreshes, 2, "the next change refreshes again")
			eq(slow.refreshes, 2)
			eq(sometimes.refreshes, 0, "still hidden")
			shown = true
			ns.Changed()
			world:Advance(1)
			eq(sometimes.refreshes, 1, "shown: refreshed")
		end)

		it("every change the player or the game makes reaches the views", function()
			local GIFT = 151
			local toys = Toys()
			toys[#toys + 1] = { id = GIFT, name = "Gift", owned = false }
			local world = World({ toys = toys })
			local ns = world.ns
			local view = CountingView(ns, "test", 0)
			-- Runs change, then lets time pass; true if the view refreshed.
			local function Refreshes(change)
				local before = view.refreshes
				change()
				world:Advance(1)
				return view.refreshes > before
			end
			local macro
			ok(Refreshes(function() macro = MakeMacro(world, PIRATE, "Illusion") end), "making a macro")
			ok(Refreshes(function() assert(ns.SetEntry(macro, ORB, true)) end), "adding a toy")
			ok(Refreshes(function() assert(ns.SetEntry(macro, ORB, false)) end), "taking one out")
			ok(Refreshes(function() assert(ns.RenameMacro(macro, "Dress up")) end), "renaming")
			ok(Refreshes(function() world:EditMacroInUI(1, "Dress up", world.macros[1].body) end), "editing in /macro")
			ok(Refreshes(function()
				ns.OpenEntryMenu(world.env.UIParent, HAT)
				world:ChooseMenuEntry(world.env.BATTLE_PET_FAVORITE)
			end), "starring a toy")
			ok(world.toys[HAT].favorite, "the star is set")
			ok(Refreshes(function()
				ns.OpenEntryMenu(world.env.UIParent, HAT)
				world:ChooseMenuEntry(world.env.BATTLE_PET_UNFAVORITE)
			end), "unstarring it")
			ok(Refreshes(function() world:Fire("NEW_TOY_ADDED", GIFT) end), "a toy added")
			ok(Refreshes(function() world:LearnToy({ id = GIFT, fanfare = true }) end), "learning a toy")
			ok(Refreshes(function() ns.Unwrap(GIFT) end), "opening a gift-wrapped toy")
			ok(Refreshes(function() world:Fire("GET_ITEM_INFO_RECEIVED", HAT, true) end), "a toy's name arriving")
			ok(Refreshes(function() world:LoadToys() end), "the player's toys arriving")
			ok(Refreshes(function() assert(ns.DeleteMacro(macro)) end), "deleting a macro")
		end)
	end)

	describe("Events", function()
		it("an error in one handler goes to the error handler and the handlers after it still run", function()
			local world = World()
			local ns = world.ns
			local seen, errors = {}, {}
			world.errorHandler = function(err) errors[#errors + 1] = err end
			ns.RegisterEvent("TEST_EVENT", function() seen[#seen + 1] = "first" end)
			ns.RegisterEvent("TEST_EVENT", function() error("second fails") end)
			ns.RegisterEvent("TEST_EVENT", function(...) seen[#seen + 1] = { n = select("#", ...), ... } end)
			world:Fire("TEST_EVENT", 1, nil, 3)
			eq(#errors, 1, "the error reached the error handler")
			ok(errors[1]:find("second fails", 1, true), errors[1])
			eq(seen[1], "first")
			list(seen[2], { n = 3, 1, nil, 3 }, "the next handler runs, with the whole payload")
		end)
	end)

	-- Every reader of Clicky's toy list, given the toys that list can't promise anything about.
	it("Edge-case toys: a toy the game no longer has, one only a patch added, one not owned and one still loading", function()
		local GONE, ADDED = 160, 170
		local toys = Toys()
		toys[#toys + 1] = { id = NEW_TOY, name = "Wand", owned = false }
		toys[#toys + 1] = { id = GONE, name = "Relic" } -- in Clicky's list; a patch takes it out of the game
		toys[#toys + 1] = { id = ADDED, name = "Novelty" } -- in the game; not in Clicky's list
		local ids = {}
		for _, toy in ipairs(toys) do
			if toy.id ~= ADDED then ids[#ids + 1] = toy.id end
		end
		local world = World({ toys = toys, toyList = ids })
		local ns = world.ns
		MakeMacro(world, PIRATE, "Edge")
		for _, id in ipairs({ NEW_TOY, GONE, HAT }) do
			AddTo(world, id, "Edge")
		end
		PutOnBar(world, "Edge", 1)
		world:RemoveToyFromGame(GONE)
		world.toys[HAT].loading = true
		ns.Sync("test")

		-- The grid, under every filter: whatever it lists can be drawn, and only from Clicky's list.
		for _, collected in ipairs({ true, false }) do
			for _, uncollected in ipairs({ true, false }) do
				for _, usableOnly in ipairs({ true, false }) do
					local filters = { collected = collected, uncollected = uncollected, usableOnly = usableOnly }
					for _, id in ipairs(GridToys(ns, filters, "")) do
						ok(ns.ToyIcon(id) ~= nil, ("the grid lists %d with nothing to draw"):format(id))
						ok(id ~= ADDED, "the grid lists a toy Clicky's list doesn't have")
					end
				end
			end
		end

		-- The panel, the toy menu, the drawer, a click and the slash commands don't fail.
		local edge = Macro(world, "Edge")
		ns.expanded[edge.id], ns.expanded[ns.FAVORITES_ID] = true, true
		ok(#ns.PanelRows() > 0, "the panel lists rows")
		eq(#MenuLabels(world, GONE), 1, "the toy menu, for a toy the game no longer has")
		eq(#MenuLabels(world, ADDED), 1, "the toy menu, for a toy Clicky doesn't know yet")
		ns.FillDrawer(edge)
		local drawer = ns.GetDrawer(edge.id)
		for i = 1, DrawerCount(world, edge.id) do
			local id = drawer.buttons[i]:GetAttribute("toy")
			ok(ns.ToyIcon(id) ~= nil, ("the drawer holds %d with nothing to draw"):format(id))
		end
		world:PressBar(1)
		world:Slash("/clicky status")
		world:Slash("/clicky debug")
		list(world:TakeErrors(), {}, "no errors shown")
	end)

	-- The panel and the drawer on screen: the rows and buttons Clicky makes, and what a click or
	-- hover on them does (the list is tests/wow.lua's ScrollList; menus are replaced by recording).
	describe("The panel and the drawer on screen", function()
		local function OpenPanel(world)
			world:LoadCollections()
			world:OpenToyBox()
			world:Advance(1)
		end

		-- The panel's rows that show: { row, name, count }.
		local function PanelShown(world)
			local shown = {}
			for _, row in ipairs(world.scrollList.rows) do
				if row:IsShown() then
					shown[#shown + 1] = { row = row, name = row.name:GetText(), count = row.count:GetText() }
				end
			end
			return shown
		end

		local function Names(shown)
			local names = {}
			for i, entry in ipairs(shown) do names[i] = entry.name end
			return names
		end

		it("14. The panel lists a row per macro, opens one to its toys on a click, and greys the toys not owned", function()
			local toys = Toys()
			toys[#toys + 1] = { id = NEW_TOY, name = "Wand", icon = 4001, owned = false }
			local world = World({ toys = toys })
			local ns = world.ns
			local menus = {}
			ns.OpenEntryMenu = function(owner, itemID) menus[#menus + 1] = { owner, itemID } end
			ns.OpenMacroMenu = function(owner, m) menus[#menus + 1] = { owner, m.name } end
			MakeMacro(world, PIRATE, "Illusion")
			AddTo(world, ORB, "Illusion")
			AddTo(world, NEW_TOY, "Illusion")
			OpenPanel(world)
			local shown = PanelShown(world)
			-- A macro the player just made is open.
			list(Names(shown), { "Favorites", "Illusion", "Orb of Deception", "Pirate's Costume", "Wand" })
			eq(shown[1].count, 2, "the two stars")
			eq(shown[2].count, 3)
			eq(shown[2].row.arrow.texture, "Interface\\Buttons\\UI-MinusButton-Up")
			ok(shown[2].row.macroIcon:IsShown() and not shown[2].row.toyIcon:IsShown())
			ok(not shown[2].row.macroIcon.warning:IsShown(), "no warning on a macro Clicky can read")
			shown[2].row.macroIcon.scripts.OnEnter(shown[2].row.macroIcon)
			list(world.tooltip.lines, { "Drag to an action bar.", "On the bar, right-click it to choose an item." },
				"the macro icon's tooltip")
			shown[1].row.macroIcon.scripts.OnEnter(shown[1].row.macroIcon)
			list(world.tooltip.lines, { "Drag to an action bar.", "On the bar, right-click it to choose a toy." },
				"Favorites holds only toys")
			local orb, wand = shown[3].row, shown[5].row
			eq(orb.toyIcon.texture, 1002)
			eq(orb.toyIcon.desaturated, false)
			eq(wand.toyIcon.texture, 4001)
			eq(wand.toyIcon.desaturated, true, "a toy not owned is grey")
			eq(wand.toyIcon.alpha, nil, "and not dimmed")
			ok(orb.toyIcon:IsShown() and not orb.macroIcon:IsShown() and not orb.arrow:IsShown())

			orb.scripts.OnEnter(orb)
			eq(world.tooltip.owner, orb)
			eq(world.tooltip.toy, ORB)
			eq(world.tooltip.anchor, "ANCHOR_RIGHT")
			orb.scripts.OnLeave(orb)
			eq(world.tooltip, nil)
			orb.scripts.OnClick(orb, "LeftButton")
			list(menus, {}, "a left click on a toy does nothing")
			orb.scripts.OnClick(orb, "RightButton")
			list(menus, { { orb, ORB } }, "a right click opens the toy's menu")
			shown[2].row.scripts.OnClick(shown[2].row, "RightButton")
			list(menus[2], { shown[2].row, "Illusion" }, "and on a macro, the macro's")

			shown[2].row.scripts.OnClick(shown[2].row, "LeftButton")
			world:Advance(1)
			list(Names(PanelShown(world)), { "Favorites", "Illusion" }, "a click closes it")
			eq(PanelShown(world)[2].row.arrow.texture, "Interface\\Buttons\\UI-PlusButton-Up")
			world.scrollList.scrolledTo = nil
			shown[2].row.scripts.OnClick(shown[2].row, "LeftButton")
			world:Advance(1)
			eq(#PanelShown(world), 5, "and opens it again")
			eq(world.scrollList.scrolledTo, 2, "scrolled to show the macro's row")
			assert(ns.RenameMacro(Macro(world, "Illusion"), "Dress up"))
			world:Advance(1)
			eq(Names(PanelShown(world))[2], "Dress up", "a rename shows")
			list(world:TakeErrors(), {})
		end)

		it("14. The panel: a macro Clicky can't read has a greyed icon, a warning and a ? and says why when hovered or clicked", function()
			local world = World()
			local ns = world.ns
			local data = ns.EncodePlaces({ 0, 1 })
			world:CreateMacroInUI("Broken", ns.NewBody("BRKN", data:sub(1, -2) .. (data:sub(-1) == "A" and "B" or "A")))
			OpenPanel(world)
			local shown = PanelShown(world)
			list(Names(shown), { "Favorites", "Broken" })
			local row = shown[2].row
			eq(shown[2].count, "?")
			ok(row.macroIcon.warning:IsShown(), "the warning mark")
			eq(row.macroIcon.texture.desaturated, true)
			row.scripts.OnEnter(row)
			eq(world.tooltip.owner, row)
			eq(world.tooltip.title, "Broken")
			eq(world.tooltip.lines[1], UNREADABLE)
			row.macroIcon.scripts.OnEnter(row.macroIcon)
			eq(world.tooltip.owner, row.macroIcon, "the icon says it too")
			row.scripts.OnClick(row, "LeftButton")
			list(world:TakeErrors(), { UNREADABLE }, "a click shows the reason")
			ok(not ns.expanded[ns.GetMacros()[1].id], "and doesn't open it")
			row.macroIcon.scripts.OnLeave(row.macroIcon)
			local favorites = shown[1].row
			favorites.scripts.OnEnter(favorites)
			eq(world.tooltip, nil, "a macro Clicky can read has no tooltip on its row")
		end)

		it("14. The drawer: each button shows its toy's icon and tooltip, the cooldown, and a click uses the toy and closes it", function()
			local world = World()
			MakeMacro(world, PIRATE, "Illusion")
			AddTo(world, ORB, "Illusion")
			PutOnBar(world, "Illusion", 1)
			world.toys[ORB].cooldown = 30
			world:PressBar(1, "RightButton")
			ok(DrawerOpen(world, "Illusion"))
			local drawer = world.ns.GetDrawer(Macro(world, "Illusion").id)
			local orb, pirate = drawer.buttons[1], drawer.buttons[2]
			eq(orb:GetAttribute("toy"), ORB)
			eq(orb.icon.texture, 1002)
			eq(pirate.icon.texture, 1001)
			ok(orb.cooldown.start ~= nil, "a toy on cooldown shows it when the drawer opens")
			ok(pirate.cooldown.start == nil)
			orb.scripts.OnEnter(orb)
			eq(world.tooltip.owner, orb)
			eq(world.tooltip.toy, ORB)
			eq(world.tooltip.anchor, "ANCHOR_LEFT")
			orb.scripts.OnLeave(orb)
			eq(world.tooltip, nil)
			world:MouseClick(pirate)
			list(world.used, { PIRATE }, "a click uses the toy")
			ok(not DrawerOpen(world, "Illusion"), "and closes the drawer")
			list(world:TakeErrors(), {})
		end)

		it("14. The drawer: when a macro loses toys, the buttons left over hold no toy", function()
			local world = World()
			MakeMacro(world, PIRATE, "Illusion")
			AddTo(world, ORB, "Illusion")
			AddTo(world, GNOME, "Illusion")
			local m = Macro(world, "Illusion")
			world.ns.FillDrawer(m)
			eq(DrawerCount(world, m.id), 3)
			assert(world.ns.SetEntry(m, ORB, false))
			assert(world.ns.SetEntry(m, GNOME, false))
			world:Advance(1)
			eq(DrawerCount(world, m.id), 1)
			list(DrawerToys(world, "Illusion"), { PIRATE })
			local drawer = world.ns.GetDrawer(m.id)
			for i = 2, 3 do
				local button = drawer.buttons[i]
				ok(not button:IsShown(), "button " .. i .. " is hidden")
				eq(button.itemID, nil)
				eq(button:GetAttribute("toy"), nil)
				eq(button:GetAttribute("type"), nil, "and a click uses nothing")
			end
		end)

		it("14. The panel: an error in the window manager's calls still leaves it filled", function()
			local world = World()
			MakeMacro(world, PIRATE, "Illusion")
			world:LoadCollections()
			world.env.SetUIPanelAttribute = function() error("no window manager") end
			ok(not pcall(world.OpenToyBox, world), "the error reaches the game")
			list(Names(PanelShown(world)), { "Favorites", "Illusion", "Pirate's Costume" })
		end)

		it("14. The panel: shown and hidden in combat, it leaves the window manager alone", function()
			local world = World()
			MakeMacro(world, PIRATE, "Illusion")
			world:LoadCollections()
			world:EnterCombat()
			world:OpenToyBox()
			world:Advance(1)
			list(Names(PanelShown(world)), { "Favorites", "Illusion", "Pirate's Costume" })
			world:CloseToyBox()
			list(world:TakeErrors(), {})
		end)

		it("14. The drawer: a cooldown that started while it was closed shows when it opens, in combat too", function()
			local world = World()
			MakeMacro(world, PIRATE, "Illusion")
			AddTo(world, ORB, "Illusion")
			PutOnBar(world, "Illusion", 1)
			world:Advance(1)
			world:EnterCombat() -- nothing refills the drawer when it opens in combat
			world.toys[ORB].cooldown = 30
			world:PressBar(1, "RightButton")
			ok(DrawerOpen(world, "Illusion"))
			ok(world.ns.GetDrawer(Macro(world, "Illusion").id).buttons[1].cooldown.start ~= nil, "the toy shows its cooldown")
		end)

		it("8. Delete: a macro that comes back with the same code starts closed", function()
			local world = World()
			local m = MakeMacro(world, PIRATE, "Illusion") -- open when made
			local body = world.macros[1].body
			assert(world.ns.DeleteMacro(m))
			world:CreateMacroInUI("Illusion", body)
			list(PanelTexts(world), { "Favorites", "Illusion" })
		end)

		it("4. The menus: renaming, deleting and making a macro from a toy are refused in combat, with the reason", function()
			local world = World()
			local m = MakeMacro(world, PIRATE, "Illusion")
			world:EnterCombat()
			world.ns.OpenMacroMenu(world.env.UIParent, m)
			world:ChooseMenuEntry("Rename")
			world:ChooseMenuEntry(world.env.DELETE)
			world.ns.OpenEntryMenu(world.env.UIParent, ORB)
			world:ChooseMenuEntry("Add to new macro...")
			list(world:TakeErrors(), { COMBAT, COMBAT, COMBAT })
		end)

		it("14. The panel: closing the Toy Box before it scrolls to a macro just opened doesn't scroll when it opens again", function()
			local world = World()
			MakeMacro(world, PIRATE, "Illusion")
			OpenPanel(world)
			local row = PanelShown(world)[2].row
			row.scripts.OnClick(row, "LeftButton")
			world:Advance(1)
			world.scrollList.scrolledTo = nil
			row.scripts.OnClick(row, "LeftButton") -- opens it: the next refresh scrolls
			world:CloseToyBox()
			world:Advance(1)
			world:OpenToyBox()
			world:Advance(1)
			eq(world.scrollList.scrolledTo, nil)
		end)
	end)

	-- Journey 15 on screen: the grid's buttons. The Collections window and the Toy Box are the
	-- minimal frames of World:LoadCollections; a click goes through the secure click path of
	-- tests/wow.lua, as the mouse does (World:MouseClick).
	describe("15. The toy grid's buttons", function()
		local STARS = { 1007, 1050, 1120 }
		local WAND = 2001 -- a toy in the game the player doesn't own yet

		-- Toys the player owns: "Toy 001", "Toy 002"... with item IDs 1001..., so by name is by ID;
		-- STARS are favorites.
		local function ManyToys(count)
			local toys = {}
			for i = 1, count do
				toys[i] = { id = 1000 + i, name = ("Toy %03d"):format(i), icon = 5000 + i }
			end
			for _, id in ipairs(STARS) do
				if toys[id - 1000] then toys[id - 1000].favorite = true end
			end
			toys[#toys + 1] = { id = WAND, name = "Wand", owned = false }
			return toys
		end

		-- The item IDs of toys 1001 to 1000 + count that aren't starred, in the order they're listed.
		local function Rest(count, starred)
			starred = starred or STARS
			local ids = {}
			for id = 1001, 1000 + count do
				local isStar = false
				for _, star in ipairs(starred) do isStar = isStar or id == star end
				if not isStar then ids[#ids + 1] = id end
			end
			return ids
		end

		local function Slice(ids, from, to)
			local out = {}
			for i = from, math.min(to, #ids) do out[#out + 1] = ids[i] end
			return out
		end

		-- The toys 1001 to 1000 + count as listed: the favorites, then the rest.
		local function Listed(count)
			local ids = {}
			for _, star in ipairs(STARS) do
				if star <= 1000 + count then ids[#ids + 1] = star end
			end
			for _, id in ipairs(Rest(count)) do ids[#ids + 1] = id end
			return ids
		end

		-- What the 8 rows of 12 from row top show.
		local function From(ids, top)
			return Slice(ids, (top - 1) * 12 + 1, (top - 1 + 8) * 12)
		end

		-- A world with the Collections window loaded and the Toy Box open: with count toys the
		-- player owns (ManyToys), or the toys given.
		local function GridWorld(toys)
			local world = World({ toys = type(toys) == "number" and ManyToys(toys) or toys })
			world:LoadCollections()
			world:OpenToyBox()
			return world
		end

		local function Shown(world)
			local shown = {}
			for _, button in ipairs(world.env.ClickyGrid.buttons) do
				if button:IsShown() then shown[#shown + 1] = button end
			end
			return shown
		end

		local function ButtonFor(world, id)
			for _, button in ipairs(Shown(world)) do
				if button.itemID == id then return button end
			end
		end

		local function ShownToys(world)
			local ids = {}
			for i, button in ipairs(Shown(world)) do ids[i] = button.itemID end
			return ids
		end

		local function TopRow(world)
			return tonumber(world.ns.GetGridState():match("top row (%d+) of"))
		end

		-- The mouse wheel over the grid: delta -1 is a notch down.
		local function Wheel(world, delta, times)
			for _ = 1, times or 1 do world:MouseWheel(world.env.ClickyGrid, delta) end
		end

		-- What the player sees on the buttons, to tell that nothing moved.
		local function Snapshot(world)
			local snapshot = {}
			for i, button in ipairs(world.env.ClickyGrid.buttons) do
				local point, _, _, x, y = button:GetPoint()
				snapshot[i] = { button.itemID, button:IsShown(), button:GetAttribute("type1"),
					button:GetAttribute("toy"), point, x, y, button.icon.texture, button.check:IsShown(),
					button.new:IsShown(), button.cooldown.start }
			end
			return snapshot
		end

		-- Clicks every button in view; each uses the toy it shows, and only that.
		local function ClickAll(world, what)
			for _, button in ipairs(Shown(world)) do
				world.used = {}
				world:MouseClick(button)
				list(world.used, { button.itemID }, ("%s: a click on %d"):format(what, button.itemID))
			end
		end

		-- How many times a view redrew, from the trace (with tracing on).
		local function Refreshes(world, view)
			local n = 0
			for _, line in ipairs(world.ns.GetTraceLines()) do
				if line:find("[" .. view .. "] refresh,", 1, true) then n = n + 1 end
			end
			return n
		end

		it("a button for each place in view, made when the Collections window loads, with the Toy Box's own grid hidden", function()
			local world = World({ toys = ManyToys(200) })
			local ns = world.ns
			eq(ns.GetGridState(), "not made")
			eq(world.env.ClickyGrid, nil)
			world:LoadCollections()
			local grid, bar = world.env.ClickyGrid, world.env.ClickyGridScrollBar
			-- The Collections window is 703 x 606 and the grid's room is what Blizzard's layout leaves.
			eq(#grid.buttons, 12 * 8)
			for _, button in ipairs(grid.buttons) do
				ok(button:IsProtected(), "a secure button")
			end
			ok(ns.GetGridState():find("made, showing toys, top row 1 of 17", 1, true), "drawn when made, shown or not: " .. ns.GetGridState())
			eq(#Shown(world), 96, "the first screen")
			ok(not grid:IsVisible(), "though the Toy Box isn't open")
			eq(world.env.ToyBox.mouseWheel, false, "the Toy Box's own wheel is off, so it can't turn its hidden pages")
			eq(world.env.ClickyGridFilter.resizeToText, false, "the filter button keeps its width")
			for _, key in ipairs({ "iconsFrame", "PagingFrame", "searchBox", "FilterDropdown", "progressBar" }) do
				ok(not world.env.ToyBox[key]:IsShown(), "the Toy Box's " .. key .. " is hidden")
			end
			ok(not grid.BGCornerTopLeft:IsShown() and not grid.BGCornerTopRight:IsShown(), "the top corners, under the tabs")
			world:OpenToyBox()
			eq(bar:GetVisibleExtentPercentage(), 1 / 10, "the thumb is the share of the 10 first rows it can scroll to")
			eq(bar:GetPanExtentPercentage(), 3 / 9, "a wheel step goes three rows")
			list(world:TakeErrors(), {})
		end)

		it("an error while the grid is built leaves no grid, and the Toy Box keeps its own", function()
			local world = World({ toys = ManyToys(20) })
			local ns = world.ns
			local CreateFrame = world.env.CreateFrame
			world.env.CreateFrame = function(frameType, name, parent, template)
				if name == "ClickyGridScrollBar" then error("no scroll bar") end
				return CreateFrame(frameType, name, parent, template)
			end
			local built, err = pcall(world.LoadCollections, world)
			ok(not built and tostring(err):find("no scroll bar", 1, true), err)
			eq(ns.GetGridState(), "not made")
			ok(not world.env.ClickyGrid:IsVisible(), "the half-built frame isn't on screen")
			ok(world.env.ToyBox.iconsFrame:IsShown(), "the Toy Box's own grid is still shown")
			-- Nothing else fails afterwards, or tries to build the grid again.
			world:OpenToyBox()
			world:Fire("TOYS_UPDATED")
			world:Advance(1)
			world:EnterCombat()
			world:LeaveCombat()
			world:Advance(1)
			ok(world.env.ToyBox.iconsFrame:IsShown())
			list(world:TakeErrors(), {})
		end)

		it("the rows in view: eight rows from the top row, clamped", function()
			local ns = World().ns
			local rows = {}
			for i = 1, 14 do rows[i] = { keys = { i } } end
			local function Offsets(from)
				local view, used, highest = ns.GridView(rows, from)
				local out = {}
				for i, entry in ipairs(view) do out[i] = entry.index .. "@" .. entry.offset end
				return out, used, highest
			end
			-- A toy row is 56 high (42 and a gap of 14, which a star's 13 above its icon clears); eight end at
			-- 434, the grid's height.
			list(Offsets(1), { "1@0", "2@56", "3@112", "4@168", "5@224", "6@280", "7@336", "8@392" })
			ok(392 + 42 <= 434, "the last row ends inside the grid")
			list(Offsets(4), { "4@0", "5@56", "6@112", "7@168", "8@224", "9@280", "10@336", "11@392" })
			local _, used, highest = Offsets(99)
			eq(used, 7, "past the end is the highest first row")
			eq(highest, 7, "the last row ends the view: rows 7 to 14")
			eq(select(2, Offsets(0)), 1, "before the start is the first")
			eq(select(2, Offsets(-3)), 1)
			rows = { rows[1], rows[2], rows[3] }
			list(Offsets(2), { "1@0", "2@56", "3@112" }, "few rows: nothing to scroll")
			eq(select(3, Offsets(2)), 1)
			rows = {}
			list(Offsets(1), {}, "no rows")
			eq(select(3, Offsets(1)), 1)
		end)

		it("a toy button's place, whether its plain left click is secure, and an emptied button", function()
			local toys = ManyToys(20)
			toys[3].fanfare = true -- 1003 is still in its gift wrap
			toys[4].owned = false
			local world = GridWorld(toys)
			world:GridFilterMenu()[2].toggle()
			local board = world.env.ClickyGridBoard
			list({ ButtonFor(world, 1007):GetPoint() }, { "TOPLEFT", board, "TOPLEFT", 0, 0 }, "the favorite first")
			list({ ButtonFor(world, 1001):GetPoint() }, { "TOPLEFT", board, "TOPLEFT", 48, 0 }, "the rest right after it, as in the Toy Box")
			list({ ButtonFor(world, 1002):GetPoint() }, { "TOPLEFT", board, "TOPLEFT", 2 * 48, 0 })
			ok(ButtonFor(world, 1007).star:IsShown(), "the favorite has the Toy Box's star")
			ok(not ButtonFor(world, 1001).star:IsShown(), "the others don't")
			eq(ButtonFor(world, 1001):GetAttribute("type1"), "toy")
			eq(ButtonFor(world, 1001):GetAttribute("type"), nil, "and no other click uses the toy")
			eq(ButtonFor(world, 1001):GetAttribute("toy"), 1001)
			eq(ButtonFor(world, 1003):GetAttribute("type1"), nil, "a wrapped toy: a click opens the wrap")
			eq(ButtonFor(world, 1004):GetAttribute("type1"), nil, "a toy not owned: a click does nothing")
			eq(ButtonFor(world, 1003):GetAttribute("toy"), nil, "nor does a wrapped toy hold one to use")
			eq(ButtonFor(world, 1004):GetAttribute("toy"), nil)
			world.env.ClickyGridSearch:SetText("Toy 002")
			list(ShownToys(world), { 1002 })
			local emptied = world.env.ClickyGrid.buttons[2]
			eq(emptied.itemID, nil, "a button with no toy to show holds none")
			eq(emptied:GetAttribute("toy"), nil)
			eq(emptied:GetAttribute("type1"), nil)
			ok(not emptied:IsShown())
			list(world:TakeErrors(), {})
		end)

		it("a button emptied while the mouse is over it hides its tooltip, one still holding a toy keeps it", function()
			local world = GridWorld(20)
			local buttons = Shown(world)
			buttons[1].scripts.OnEnter(buttons[1])
			world.env.ClickyGridSearch:SetText("Toy 007")
			list(ShownToys(world), { 1007 })
			world:UpdateTooltip()
			eq(world.tooltip.owner, buttons[1], "the button still holding its toy keeps the tooltip")
			world.env.ClickyGridSearch:SetText("")
			buttons[5].scripts.OnEnter(buttons[5])
			world.env.ClickyGridSearch:SetText("Toy 007")
			world:UpdateTooltip()
			eq(world.tooltip, nil, "the one that lost its toy hides it")
		end)

		it("a check mark on the toys in a Clicky macro, not Favorites, whose toys have their star, kept up to date", function()
			local world = GridWorld(20)
			local function Marked()
				world:Advance(1)
				local marked = {}
				for _, button in ipairs(Shown(world)) do
					if button.check:IsShown() then marked[#marked + 1] = button.itemID end
				end
				table.sort(marked)
				return marked
			end
			list(Marked(), {}, "the favorite, 1007, is in Favorites and has no mark")
			local macro = MakeMacro(world, 1002, "Illusion")
			list(Marked(), { 1002 }, "a toy in a new macro")
			AddTo(world, 1003, "Illusion")
			AddTo(world, 1007, "Illusion")
			list(Marked(), { 1002, 1003, 1007 }, "a favorite in a macro of the player's has one")
			assert(world.ns.SetEntry(macro, 1002, false))
			list(Marked(), { 1003, 1007 }, "taken out of the macro")
			assert(world.ns.DeleteMacro(macro))
			list(Marked(), {}, "its macro deleted")
			list(world:TakeErrors(), {})
		end)

		it("the scroll bar snaps to the row it is moved to, for every row", function()
			local world = GridWorld(200)
			local bar = world.env.ClickyGridScrollBar
			for row = 10, 1, -1 do
				bar:SetScrollPercentage((row - 1) / 9)
				eq(TopRow(world), row, "row " .. row)
				eq(bar:GetScrollPercentage(), (row - 1) / 9)
			end
			bar:SetScrollPercentage(0.05)
			eq(TopRow(world), 1, "a position between rows goes to the nearest")
			bar:SetScrollPercentage(0.3)
			eq(TopRow(world), 4)
			eq(bar:GetScrollPercentage(), 3 / 9, "and the bar is on it")
			bar:SetScrollPercentage(0.4)
			eq(TopRow(world), 5)
		end)

		it("a click on a button uses the toy it shows, wherever the grid is scrolled to", function()
			local world = GridWorld(200)
			local listed = Listed(200)
			-- The three favorites, then the rest: 8 rows of 12.
			list(ShownToys(world), From(listed, 1), "from the top")
			local buttons = Shown(world)
			eq(#buttons, 96)
			local board = world.env.ClickyGridBoard
			list({ buttons[3]:GetPoint() }, { "TOPLEFT", board, "TOPLEFT", 2 * 48, 0 }, "the third favorite")
			list({ buttons[4]:GetPoint() }, { "TOPLEFT", board, "TOPLEFT", 3 * 48, 0 }, "and the first of the rest after it")
			list({ buttons[13]:GetPoint() }, { "TOPLEFT", board, "TOPLEFT", 0, -56 }, "the second row")
			ClickAll(world, "top")

			-- The wheel scrolls three rows a notch, down to the last row and back.
			Wheel(world, -1)
			eq(TopRow(world), 4)
			list(ShownToys(world), From(listed, 4))
			ClickAll(world, "row 4")
			Wheel(world, -1)
			eq(TopRow(world), 7)
			list(ShownToys(world), From(listed, 7))
			ClickAll(world, "row 7")
			Wheel(world, -1)
			eq(TopRow(world), 10, "the last row ends the view")
			list(ShownToys(world), From(listed, 10), "the last toys, in the last 8 rows")
			ClickAll(world, "bottom")
			Wheel(world, -1, 5)
			eq(TopRow(world), 10, "no further")
			Wheel(world, 1)
			eq(TopRow(world), 7)
			list(ShownToys(world), From(listed, 7))
			ClickAll(world, "row 7, going up")
			Wheel(world, 1, 5)
			eq(TopRow(world), 1)
			list(ShownToys(world), From(listed, 1), "back at the top")

			world.env.ClickyGridScrollBar:SetScrollPercentage(1 / 9)
			eq(TopRow(world), 2)
			list(ShownToys(world), From(listed, 2))
			ClickAll(world, "row 2")
			list(world:TakeErrors(), {})
		end)

		it("a refresh keeps the place, and goes back to the top for a search or a filter", function()
			local world = GridWorld(200)
			Wheel(world, -1, 2)
			eq(TopRow(world), 7)
			world:Fire("GET_ITEM_INFO_RECEIVED", 1005, true)
			world:Advance(1)
			eq(TopRow(world), 7, "a toy's name arriving keeps the place")
			list(ShownToys(world), From(Listed(200), 7))

			Wheel(world, -1)
			eq(TopRow(world), 10)
			for id = 1176, 1200 do world.toys[id].owned = false end
			world:Fire("TOYS_UPDATED")
			world:Advance(1)
			eq(TopRow(world), 8, "fewer rows: the place is clamped to the last full view")
			list(ShownToys(world), From(Listed(175), 8), "ending with the last toy")

			world.env.ClickyGridSearch:SetText("Toy 12")
			world:Advance(1)
			eq(TopRow(world), 1, "a search goes to the top")
			list(ShownToys(world), { 1120, 1121, 1122, 1123, 1124, 1125, 1126, 1127, 1128, 1129 })
			ok(world.ns.GetGridState():find('search "Toy 12"', 1, true), world.ns.GetGridState())
			world.env.ClickyGridSearch:SetText("")
			world:Advance(1)
			eq(TopRow(world), 1)
			Wheel(world, -1, 2)
			eq(TopRow(world), 7)

			local filters = world:GridFilterMenu()
			list({ filters[1].text, filters[2].text, filters[3].text }, { "Collected", "Not Collected", "Usable Only" })
			list({ filters[1].isSelected(), filters[2].isSelected(), filters[3].isSelected() }, { true, false, false })
			filters[2].toggle()
			world:Advance(1)
			eq(TopRow(world), 1, "a filter goes to the top")
			ok(world.ns.GetGridState():find("not collected true", 1, true), "Not Collected is on")
			Wheel(world, -1, 2)
			eq(TopRow(world), 7, "Not Collected adds the toys not owned: more rows to scroll")
			world.env.ClickyGridFilter.defaultCallback()
			world:Advance(1)
			eq(TopRow(world), 1, "resetting the filters goes to the top")
			ok(world.ns.GetGridState():find("not collected false", 1, true))
			list(world:TakeErrors(), {})
		end)

		it("a search or a filter redraws the grid only; the other views are not refreshed", function()
			local world = GridWorld(20)
			local other = CountingView(world.ns, "other", 0)
			local before = Refreshes(world, "grid")
			world.ns.SetTracing(true)
			world.env.ClickyGridSearch:SetText("Toy 002")
			world:GridFilterMenu()[2].toggle()
			world.env.ClickyGridFilter.defaultCallback()
			world:Advance(1)
			eq(Refreshes(world, "grid") - before, 3, "the grid redrew for each")
			eq(other.refreshes, 0, "and no other view refreshed")
			world:Fire("TOYS_UPDATED")
			world:Advance(1)
			eq(other.refreshes, 1, "a change every view shows still refreshes them all")
			list(world:TakeErrors(), {})
		end)

		it("the grid waits its refresh delay for a burst of changes, and the panel only the next frame", function()
			local world = GridWorld(20)
			world.ns.SetTracing(true)
			world:Fire("TOYS_UPDATED")
			world:Advance(0)
			eq(Refreshes(world, "panel"), 1, "the panel next frame")
			eq(Refreshes(world, "grid"), 0, "the grid not yet")
			world:Advance(0.19)
			eq(Refreshes(world, "grid"), 0, "still waiting")
			world:Advance(0.02)
			eq(Refreshes(world, "grid"), 1, "and once the delay is over")
		end)

		it("a button isn't re-pointed while a mouse button is held: the toy used is the one pressed", function()
			local world = GridWorld(20)
			local other = CountingView(world.ns, "other", 0)
			local pressed = Shown(world)[2]
			eq(pressed.itemID, 1001)
			world:HoldMouse(pressed)
			world.toys[1001].name = "Zzz" -- its name arrives, and it goes to the end of the list
			world:Fire("GET_ITEM_INFO_RECEIVED", 1001, true)
			world:Advance(1)
			eq(pressed.itemID, 1001, "the button holds the toy that was pressed")
			eq(other.refreshes, 1, "waiting for the release doesn't refresh the other views again")
			ok(world.ns.GetGridState():find(", redrawing waits for the mouse button", 1, true), world.ns.GetGridState())
			world:ReleaseMouse(pressed)
			list(world.used, { 1001 }, "and the click uses it")
			world:Advance(1)
			eq(pressed.itemID, 1002, "the next refresh after the release redraws")
			list(world:TakeErrors(), {})
		end)

		it("a gift-wrapped toy unwraps on its first click, which doesn't use it, and the next click uses it", function()
			local toys = ManyToys(20)
			toys[3].fanfare = true
			local world = GridWorld(toys)
			local ns = world.ns
			local button = ButtonFor(world, 1003)
			eq(button:GetAttribute("type1"), nil, "a click doesn't use it")
			ok(button.new:IsShown(), "NEW until opened")
			world:MouseClick(button)
			list(world.used, {}, "the first click only opens it")
			ok(not ns.IsWrapped(1003), "opened")
			button = ButtonFor(world, 1003) -- redrawn at once, not after the refresh delay
			eq(button:GetAttribute("type1"), "toy")
			ok(not button.new:IsShown(), "no longer NEW")
			world:MouseClick(button)
			list(world.used, { 1003 }, "the next click uses it")
		end)

		it("a right click opens the toy's menu, a shift-click links it, and no other click uses the toy or does anything", function()
			local world = GridWorld(20)
			local menus = {}
			world.ns.OpenEntryMenu = function(owner, itemID) menus[#menus + 1] = { owner, itemID } end
			local button = Shown(world)[1]
			local id = button.itemID
			local link = world.env.C_ToyBox.GetToyLink(id)
			world:MouseClick(button, "RightButton")
			list(menus, { { button, id } }, "the menu opens on the button")
			list(world.used, {}, "and uses nothing")
			world.keys.shift = true
			world:MouseClick(button)
			list(world.chat, { link }, "linked in chat")
			list(world.used, {}, "and uses nothing")
			world:MouseClick(button, "RightButton")
			list(menus, { { button, id } }, "no menu for a shift-click")
			list(world.chat, { link, link }, "a shift-right-click links too, as in the Toy Box")
			world.chat = {}
			world.keys.shift, world.keys.ctrl = false, true
			world:MouseClick(button)
			world:MouseClick(button, "RightButton")
			world.keys.ctrl, world.keys.alt = false, true
			world:MouseClick(button)
			world.keys.alt = false
			world:MouseClick(button, "MiddleButton")
			list(world.chat, {}, "nothing else links")
			list(menus, { { button, id } }, "or opens a menu")
			list(world.used, {}, "or uses the toy")
			world:MouseClick(button)
			list(world.used, { id }, "a plain left click does")
			list(world:TakeErrors(), {})
		end)

		it("a toy not owned: greyed, no menu, no use, and a shift-click still links it", function()
			local world = GridWorld(20)
			local menus = 0
			world.ns.OpenEntryMenu = function() menus = menus + 1 end
			world:GridFilterMenu()[2].toggle()
			world:Advance(1)
			local button = Shown(world)[#Shown(world)]
			eq(button.itemID, WAND)
			eq(button:GetAttribute("type1"), nil)
			ok(button.icon.desaturated, "greyed")
			eq(button.icon.alpha, 0.5)
			world:MouseClick(button)
			world:MouseClick(button, "RightButton")
			eq(menus, 0)
			list(world.used, {})
			world.keys.shift = true
			world:MouseClick(button)
			list(world.chat, { world.env.C_ToyBox.GetToyLink(WAND) })
		end)

		it("each button shows its toy's icon, cooldown, check mark and NEW and tooltip, and drags the toy", function()
			local toys = ManyToys(200)
			toys[10].cooldown = 30
			local world = GridWorld(toys)
			local ns = world.ns
			MakeMacro(world, 1003, "Illusion")
			world:Advance(1)
			local byToy = {}
			for _, button in ipairs(Shown(world)) do byToy[button.itemID] = button end
			eq(byToy[1002].icon.texture, 5002, "the toy's icon")
			ok(not byToy[1002].icon.desaturated)
			eq(byToy[1002].icon.alpha, 1)
			ok(byToy[1003].check:IsShown(), "a toy in a macro")
			ok(not byToy[1002].check:IsShown())
			ok(byToy[1007].star:IsShown(), "a favorite has the Toy Box's star")
			ok(not byToy[1007].check:IsShown(), "and no check mark for Favorites")
			ok(not byToy[1002].star:IsShown())
			ok(byToy[1010].cooldown.start ~= nil, "a toy on cooldown")
			ok(byToy[1011].cooldown.start == nil)
			world.toys[1011].cooldown = 30
			world:Fire("SPELL_UPDATE_COOLDOWN")
			ok(byToy[1011].cooldown.start ~= nil, "a cooldown that starts")
			ok(byToy[1002].cooldown.start == nil)

			byToy[1002].scripts.OnEnter(byToy[1002])
			eq(world.tooltip.toy, 1002)
			eq(world.tooltip.owner, byToy[1002])
			eq(world.tooltip.anchor, "ANCHOR_RIGHT", "right of the button")
			byToy[1002].scripts.OnLeave(byToy[1002])
			eq(world.tooltip, nil)
			world:Drag(byToy[1002])
			list(world.cursor, { toy = 1002 }, "dragged")

			-- A toy learned this session says NEW until hovered over.
			world:LearnToy({ id = WAND })
			world.env.ClickyGridSearch:SetText("Wand")
			world:Advance(1)
			local wand = Shown(world)[1]
			eq(wand.itemID, WAND)
			ok(wand.new:IsShown(), "NEW")
			wand.scripts.OnEnter(wand)
			ok(not wand.new:IsShown(), "hovered")
			ok(not ns.IsNewToy(WAND))

			-- A tooltip follows the button when the grid scrolls under the mouse.
			world.env.ClickyGridSearch:SetText("")
			world:Advance(1)
			Wheel(world, -1)
			local button = Shown(world)[1]
			button.scripts.OnEnter(button)
			eq(world.tooltip.toy, button.itemID)
			local shown = button.itemID
			Wheel(world, -1)
			ok(button.itemID ~= shown, "the button holds another toy")
			eq(world.tooltip.toy, shown, "the tooltip hasn't noticed yet")
			button.UpdateTooltip(button)
			eq(world.tooltip.toy, button.itemID)
			list(world:TakeErrors(), {})
		end)

		it("a button moved from a toy on cooldown to a toy not owned has no cooldown swipe", function()
			local toys = ManyToys(20)
			toys[20].cooldown = 30
			local world = GridWorld(toys)
			world:GridFilterMenu()[2].toggle()
			local button = Shown(world)[20]
			eq(button.itemID, 1020, "the last toy owned")
			ok(button.cooldown.start ~= nil, "on cooldown")
			world.toys[1019].owned = false
			world:Fire("TOYS_UPDATED")
			world:Advance(1)
			eq(button.itemID, 1019, "the toy not owned is listed after the ones owned")
			eq(button.cooldown.start, nil, "no swipe")
		end)

		it("in combat every button still uses its toy, and the grid stays as it was until combat ends", function()
			local world = GridWorld(200)
			local ns = world.ns
			local bar = world.env.ClickyGridScrollBar
			world:LearnToy({ id = 1020 }) -- in view, says NEW
			world:Advance(1)
			ns.SetTracing(true)
			bar:SetScript("OnUpdate", function() end) -- a thumb being dragged
			local menus = {}
			ns.OpenEntryMenu = function(owner, itemID) menus[#menus + 1] = { owner, itemID } end
			local before = Snapshot(world)
			local toysBefore = ShownToys(world)
			world:EnterCombat()
			eq(bar:IsScrollAllowed(), false, "scrolling is off")
			eq(bar.scripts.OnUpdate, nil, "a drag is stopped")

			ClickAll(world, "in combat")
			local button = Shown(world)[2]
			world:MouseClick(button, "RightButton")
			list(menus, { { button, button.itemID } }, "the menu opens in combat")
			world.used = {}
			world.keys.shift = true
			world:MouseClick(button)
			world.keys.shift = false
			list(world.chat, { world.env.C_ToyBox.GetToyLink(button.itemID) }, "a chat link too")
			list(world.used, {})
			button.scripts.OnEnter(button)
			eq(world.tooltip.toy, button.itemID, "hover shows the tooltip")

			-- Scrolling does nothing.
			Wheel(world, -1, 3)
			Wheel(world, 1)
			bar:SetScrollPercentage(0.9)
			eq(TopRow(world), 1)
			-- Neither does anything that changes what's listed.
			world.env.ClickyGridSearch:SetText("Toy")
			world:GridFilterMenu()[2].toggle()
			world:LearnToy({ id = WAND })
			world.env.C_ToyBox.SetIsFavorite(1002, true)
			world:Fire("GET_ITEM_INFO_RECEIVED", 1005, true)
			world:Advance(5)
			list(Snapshot(world), before, "no button changed")
			list(ShownToys(world), toysBefore)
			list(world:TakeErrors(), {})
			ok(ns.GetGridState():find(", in combat: redrawing waits for it to end", 1, true), ns.GetGridState())
			eq(Refreshes(world, "grid"), 0, "no refresh yet")

			-- What is inside a button isn't locked: a toy used in combat shows its cooldown, and
			-- hovering over a NEW toy clears its label.
			local used = ButtonFor(world, 1021)
			world:MouseClick(used)
			eq(world:LastUsed(), 1021)
			world.toys[1021].cooldown = 30 -- the game starts it
			world:Fire("SPELL_UPDATE_COOLDOWN")
			ok(used.cooldown.start ~= nil, "the toy used in combat shows its cooldown")
			local new = ButtonFor(world, 1020)
			ok(new.new:IsShown(), "NEW")
			new.scripts.OnEnter(new)
			ok(not new.new:IsShown(), "hovering over it in combat clears the label")

			world:LeaveCombat()
			world:Advance(5)
			eq(bar:IsScrollAllowed(), true, "scrolling is on again")
			eq(Refreshes(world, "grid"), 1, "one refresh for everything asked for in combat")
			eq(ns.GetGridState():find("waits", 1, true), nil)
			ok(ns.GetGridState():find("not collected true", 1, true), "the filter changed in combat applies")
			ok(ns.GetGridState():find('search "Toy"', 1, true), "and the search")
			eq(TopRow(world), 1, "the search goes to the top")
			-- 1002 is a favorite now, and the toy learned in combat is in the list.
			list(ShownToys(world), { 1002, 1007, 1050, 1120, unpack(Slice(Rest(200, { 1002, 1007, 1050, 1120 }), 1, 92)) })
			ok(not ns.IsNewToy(1020), "and 1020 is no longer NEW")
			ClickAll(world, "after combat")
			Wheel(world, -1)
			eq(TopRow(world), 4, "the wheel works again")
			list(world:TakeErrors(), {})
			ns.SetTracing(false)
		end)

		it("when combat ends the grid asks for its own refresh, whatever else does", function()
			local world = GridWorld(200)
			local ns = world.ns
			world:EnterCombat()
			world.env.ClickyGridSearch:SetText("Toy 12")
			world:Advance(1)
			eq(#ShownToys(world), 96, "not yet")
			ns.Sync = function() end -- the macros' own call to ns.Changed, after combat
			world:LeaveCombat()
			world:Advance(1)
			list(ShownToys(world), { 1120, 1121, 1122, 1123, 1124, 1125, 1126, 1127, 1128, 1129 })
		end)

		it("a gift-wrapped toy clicked in combat opens, and a click after combat uses it", function()
			local toys = ManyToys(20)
			toys[3].fanfare = true
			local world = GridWorld(toys)
			local ns = world.ns
			local button = ButtonFor(world, 1003)
			world:EnterCombat()
			world:MouseClick(button)
			ok(not ns.IsWrapped(1003), "opened")
			world:Advance(1)
			world:MouseClick(button)
			list(world.used, {}, "not used in combat: its button can't be set then")
			world:LeaveCombat()
			world:Advance(1)
			world:MouseClick(button)
			list(world.used, { 1003 })
			list(world:TakeErrors(), {})
		end)

		it("the Collections window loading in combat: the grid is made when combat ends", function()
			local world = World({ toys = ManyToys(20), combat = true })
			local ns = world.ns
			world:LoadCollections()
			eq(ns.GetGridState(), "waiting for combat to end")
			eq(world.env.ClickyGrid, nil)
			ok(world.env.ToyBox.iconsFrame:IsShown(), "the Toy Box shows its own grid meanwhile")
			world:OpenToyBox()
			list(world:TakeErrors(), {})
			world:LeaveCombat()
			ok(ns.GetGridState():find("^made"), ns.GetGridState())
			ok(not world.env.ToyBox.iconsFrame:IsShown(), "its own grid is hidden once the grid is made")
			eq(#ShownToys(world), 20, "and the toys are listed, the Toy Box having been open")
			ClickAll(world, "made after combat")
			list(world:TakeErrors(), {})
		end)

		it("the Toy Box opened in combat shows the toys it had, and lists the rest when combat ends", function()
			local world = GridWorld(20)
			local ns = world.ns
			world:CloseToyBox()
			world:LearnToy({ id = WAND })
			world:EnterCombat()
			world:OpenToyBox()
			world:Advance(1)
			list(world:TakeErrors(), {})
			eq(#ShownToys(world), 20, "the toys it had")
			ok(ns.GetGridState():find(", in combat: redrawing waits for it to end", 1, true), ns.GetGridState())
			ClickAll(world, "in combat")
			world:LeaveCombat()
			world:Advance(1)
			eq(#ShownToys(world), 21, "and the toy learned meanwhile")
			ClickAll(world, "after combat")
		end)

		it("a patch that takes a part of the Toy Box away leaves the Toy Box with its own grid", function()
			local world = World({ toys = ManyToys(20) })
			world:LoadCollections("searchBox")
			eq(world.ns.GetGridState(), "not made")
			eq(world.env.ClickyGrid, nil)
			world:OpenToyBox()
			for _, key in ipairs({ "iconsFrame", "PagingFrame", "FilterDropdown" }) do
				ok(world.env.ToyBox[key]:IsShown(), "the Toy Box's " .. key .. " is still shown")
			end
			list(world:TakeErrors(), {})
		end)

		it("a wheel turn while a mouse button is held leaves the buttons alone: the toy used is the one pressed", function()
			local world = GridWorld(200)
			local pressed = Shown(world)[5]
			local id = pressed.itemID
			world:HoldMouse(pressed)
			Wheel(world, -1)
			eq(TopRow(world), 1, "not scrolled")
			world:ReleaseMouse(pressed)
			list(world.used, { id }, "the click uses the toy pressed")
			Wheel(world, -1)
			eq(TopRow(world), 4, "and the wheel works again")
		end)

		it("the Toy Box tab shown for the first time in combat, the Collections window having loaded before, lists the toys", function()
			local world = World({ toys = ManyToys(20) })
			world:LoadCollections()
			world:EnterCombat()
			world:OpenToyBox()
			eq(#ShownToys(world), 20)
			ClickAll(world, "in combat")
			list(world:TakeErrors(), {})
		end)

		it("the grid and the panel aren't refreshed while the Toy Box is closed, and draw when it opens", function()
			local world = GridWorld(20)
			world:Advance(1)
			world:CloseToyBox()
			world.ns.SetTracing(true)
			world:Fire("TOYS_UPDATED")
			world:Advance(1)
			eq(Refreshes(world, "grid"), 0, "the grid")
			eq(Refreshes(world, "panel"), 0, "the panel")
			world:OpenToyBox()
			eq(Refreshes(world, "grid"), 1, "the grid draws when shown")
			eq(Refreshes(world, "panel"), 1, "and so does the panel")
		end)
		it("a NEW toy that scrolls under the button the mouse is over stops saying NEW once its tooltip shows", function()
			local world = GridWorld(200)
			local button = Shown(world)[1]
			button.scripts.OnEnter(button)
			local target = From(Listed(200), 4)[1] -- the toy this button holds after one notch down
			world:LearnToy({ id = target })
			world:Advance(1)
			Wheel(world, -1)
			eq(button.itemID, target)
			ok(button.new:IsShown(), "NEW as it arrives under the button")
			world:UpdateTooltip()
			eq(world.tooltip.toy, target, "the tooltip follows")
			ok(not button.new:IsShown(), "and the toy is seen")
			ok(not world.ns.IsNewToy(target))
		end)

		it("the bar put on each row's position turns the grid to that row, for each of 27 first rows", function()
			-- 403 toys: 34 rows of 12, less 7 more in view, are 27 first rows. A row's position times 26 isn't
			-- always a whole number in floating point, so the bar's position has to be rounded to a row.
			local toys = ManyToys(403)
			local world = GridWorld(toys)
			local bar = world.env.ClickyGridScrollBar
			for row = 1, 27 do
				bar:SetScrollPercentage((row - 1) / 26)
				eq(TopRow(world), row, "row " .. row)
			end
		end)

		it("several changes while a mouse button is held make one retry, not one each", function()
			local world = GridWorld(20)
			local pending = #world.timers
			world:HoldMouse(Shown(world)[1])
			world.env.ClickyGridSearch:SetText("Toy 01")
			local after = #world.timers
			eq(after, pending + 1, "one retry waits")
			world.env.ClickyGridSearch:SetText("Toy 011")
			world.env.ClickyGridSearch:SetText("Toy 012")
			world.env.ClickyGridFilter.defaultCallback()
			eq(#world.timers, after, "and the others join it")
		end)

		it("a search typed while the grid is hidden re-points no button", function()
			local world = GridWorld(20)
			world:CloseToyBox()
			local before = Snapshot(world)
			world.env.ClickyGridSearch:SetText("Toy 012")
			world:Advance(1)
			list(Snapshot(world), before)
			world:OpenToyBox()
			list(ShownToys(world), { 1012 }, "and it applies when the grid shows")
		end)

		it("a right click with shift, ctrl or alt held opens no menu", function()
			local world = GridWorld(20)
			local menus = 0
			world.ns.OpenEntryMenu = function() menus = menus + 1 end
			local button = Shown(world)[4]
			for _, key in ipairs({ "shift", "ctrl", "alt" }) do
				world.keys[key] = true
				world:MouseClick(button, "RightButton")
				world.keys[key] = false
				eq(menus, 0, key)
			end
			world:MouseClick(button, "RightButton")
			eq(menus, 1, "a plain right click does")
		end)

	end)

	-- Journeys 4, 15 and the Portal journey with spells and items: the grid lists the spells the
	-- character knows and the items it carries after the toys, and they go into macros through the
	-- same menu.
	describe("15. The grid lists spells and items", function()
		local FIRE, STORM, HOME, OVER = "s500", "s506", "s501", "s508" -- Path of the Fire and Portal: Stormwind (in a flyout), Teleport: Home, a spell overriding another
		local RING, SPARE, CLOAK, SHADOWS = "i600", "i602", "i601", "i605"
		-- Hearth Ring and Spare Ring in bags, Cloak of Teleport worn, Cloak of Shadows in a bag and
		-- not worn (the item action wears it instead of using it).
		local LIST = { PIRATE, ORB, GNOME, HAT, WINGS, CHEST, FIRE, HOME, "s502", "s503", "s505", STORM, "s507", "s508",
			RING, CLOAK, SPARE, "i604", SHADOWS }

		local function GridWorld(options)
			options = options or {}
			options.toyList = options.toyList or LIST
			options.spells = options.spells or {
				{ id = 500, name = "Path of the Fire", icon = 5000, flyout = 1 },
				{ id = 506, name = "Portal: Stormwind", icon = 5060, flyout = 1 },
				{ id = 507, name = "Portal: Unlearned", icon = 5070, flyout = 1, known = false },
				{ id = 501, name = "Teleport: Home", icon = 5010 },
				{ id = 502, name = "Passive Gift", icon = 5020, passive = true },
				{ id = 503, name = "Future Spell", icon = 5030, known = false },
				{ id = 504, name = "Not In The List", icon = 5040 },
				{ id = 505, name = "Other Spec Spell", icon = 5050, line = 2, offSpec = true },
				{ id = 508, name = "Overriding Spell", icon = 5080, base = 509 }, -- the list has 508, the override
			}
			options.items = options.items or {
				{ id = 600, name = "Hearth Ring", icon = 6000 },
				{ id = 601, name = "Cloak of Teleport", icon = 6010, equippable = true, worn = 15 },
				{ id = 602, name = "Spare Ring", icon = 6020, bag = 5, count = 3 }, -- the reagent bag
				{ id = 603, name = "Not In The List", icon = 6030 },
				{ id = 604, name = "Gone Ring", icon = 6040, count = 0 },
				{ id = 605, name = "Cloak of Shadows", icon = 6050, equippable = true },
			}
			local world = World(options)
			world:LoadCollections()
			world:OpenToyBox()
			return world
		end

		local function Shown(world)
			local shown = {}
			for _, button in ipairs(world.env.ClickyGrid.buttons) do
				if button:IsShown() then shown[#shown + 1] = button end
			end
			return shown
		end

		local function ShownKeys(world)
			local keys = {}
			for i, button in ipairs(Shown(world)) do keys[i] = button.entry end
			return keys
		end

		local function ButtonFor(world, key)
			for _, button in ipairs(Shown(world)) do
				if button.entry == key then return button end
			end
			error("not in the grid: " .. tostring(key), 2)
		end

		-- The player clicking a tab: 1 Toys, 2 Mounts, 3 Pets, 4 Spells, 5 Items.
		local TOYS_TAB, SPELLS_TAB, ITEMS_TAB = 1, 4, 5
		local function ClickTab(world, index)
			local tab = world.env.ClickyGrid.Tabs[index]
			tab.scripts.OnClick(tab, "LeftButton", false)
		end

		local function TabTexts(world)
			local texts = {}
			for i, tab in ipairs(world.env.ClickyGrid.Tabs) do texts[i] = tab.text end
			return texts
		end

		it("the spells the character knows that Clicky has, flyouts included, then the items carried or worn, each by name", function()
			local world = GridWorld()
			local sections = world.ns.GridSections({}, "")
			list(sections[1].keys, { WINGS, CHEST, GNOME, ORB, HAT, PIRATE }, "the toys as before")
			list(sections[4].keys, { OVER, FIRE, STORM, HOME },
				"known spells in the list, and an overriding one by the ID the list has: not a passive, a spell not known yet, one off the spellbook's active page or one the list lacks")
			list(sections[5].keys, { SHADOWS, CLOAK, RING, SPARE },
				"items in a bag or worn and in the list: not one that is gone or the list lacks")
			list(ShownKeys(world), { WINGS, CHEST, GNOME, ORB, HAT, PIRATE }, "the Toys tab shows the toys")
			ClickTab(world, SPELLS_TAB)
			list(ShownKeys(world), { OVER, FIRE, STORM, HOME }, "the Spells tab, the spells")
			ClickTab(world, ITEMS_TAB)
			list(ShownKeys(world), { SHADOWS, CLOAK, RING, SPARE }, "the Items tab, the items")
			ok(world.ns.GetGridState():find("showing items, top row 1 of 1 (6 toys, 0 mounts, 0 pets, 4 spells, 4 items)", 1, true),
				"/clicky debug: " .. world.ns.GetGridState())
			eq(#world:TakeErrors(), 0)
		end)

		it("the professions' active spells are on the Spells tab, from the Professions book, and go in macros", function()
			local FIRE_COOK, FISH, SURVEY = "s520", "s521", "s522"
			local world = GridWorld({
				toyList = { PIRATE, HOME, FIRE_COOK, FISH, SURVEY, "s523" },
				spells = {
					{ id = 501, name = "Teleport: Home", icon = 5010 },
					{ id = 520, name = "Cooking Fire", icon = 5200, profession = 5 },
					{ id = 521, name = "Fishing", icon = 5210, profession = 4 },
					{ id = 522, name = "Survey", icon = 5220, profession = 3 },
					{ id = 523, name = "Herbalism Skills", icon = 5230, profession = 1, passive = true },
					{ id = 524, name = "Not In The List", icon = 5240, profession = 2 },
				},
			})
			list(world.ns.GridSections({}, "")[4].keys, { FIRE_COOK, FISH, SURVEY, HOME },
				"every learned profession's active spells the list has, with the spellbook's: not a passive one or one the list lacks")
			local m = assert(world.ns.MakeMacro("Camp", FIRE_COOK))
			world.ns.OpenEntryMenu(world.env.UIParent, FISH)
			world:ChooseMenuEntry("Camp")
			PutOnBar(world, "Camp", 1)
			local seen = {}
			for _ = 1, 40 do
				world:PressBar(1)
				seen[world:LastUsed()] = true
			end
			list(seen, { [FIRE_COOK] = true, [FISH] = true }, "a click casts one of them")
			ok(m.state == "ready")
			eq(#world:TakeErrors(), 0)
		end)

		it("a tab for the toys, the spells and the items, each with its count; a click shows its own from the top", function()
			local world = GridWorld()
			local grid = world.env.ClickyGrid
			list(TabTexts(world), { "Toys (6)", "Mounts (0)", "Pets (0)", "Spells (4)", "Items (4)" })
			eq(world.env.PanelTemplates_GetSelectedTab(grid), TOYS_TAB, "the toys first")
			ClickTab(world, SPELLS_TAB)
			eq(world.env.PanelTemplates_GetSelectedTab(grid), SPELLS_TAB)
			list(ShownKeys(world), { OVER, FIRE, STORM, HOME })
			world.env.ClickyGridSearch:SetText("portal")
			list(TabTexts(world), { "Toys (0)", "Mounts (0)", "Pets (0)", "Spells (1)", "Items (0)" }, "the counts follow the search, which looks at every tab")
			list(ShownKeys(world), { STORM }, "and the tab stays")
			world.env.ClickyGridSearch:SetText("ring")
			list(TabTexts(world), { "Toys (0)", "Mounts (0)", "Pets (0)", "Spells (0)", "Items (2)" })
			list(ShownKeys(world), {}, "nothing on this tab")
			ClickTab(world, ITEMS_TAB)
			list(ShownKeys(world), { RING, SPARE })
			world.env.ClickyGridSearch:SetText("")
			world:EnterCombat()
			ClickTab(world, TOYS_TAB)
			eq(world.env.PanelTemplates_GetSelectedTab(grid), ITEMS_TAB, "in combat a tab changes nothing")
			list(ShownKeys(world), { SHADOWS, CLOAK, RING, SPARE })
			world:LeaveCombat()
			world:Advance(1)
			ClickTab(world, TOYS_TAB)
			list(ShownKeys(world), { WINGS, CHEST, GNOME, ORB, HAT, PIRATE })
			list(world:TakeErrors(), {})
		end)

		it("a tab shows its own from the top", function()
			-- 200 toys and 200 spells: 17 rows of 12 each.
			local toys, spells, toyList = {}, {}, {}
			for i = 1, 200 do
				toys[i] = { id = 1000 + i, name = ("Toy %03d"):format(i) }
				spells[i] = { id = 5000 + i, name = ("Spell %03d"):format(i) }
				toyList[i], toyList[200 + i] = 1000 + i, "s" .. (5000 + i)
			end
			local world = GridWorld({ toys = toys, spells = spells, toyList = toyList })
			world:MouseWheel(world.env.ClickyGrid, -1)
			ok(world.ns.GetGridState():find("showing toys, top row 4 of 17", 1, true), world.ns.GetGridState())
			ClickTab(world, SPELLS_TAB)
			ok(world.ns.GetGridState():find("showing spells, top row 1 of 17", 1, true), world.ns.GetGridState())
			world:MouseWheel(world.env.ClickyGrid, -1)
			ClickTab(world, TOYS_TAB)
			ok(world.ns.GetGridState():find("showing toys, top row 1 of 17", 1, true), "and back: " .. world.ns.GetGridState())
		end)

		it("the filter button is on the Toys, Mounts and Pets tabs, not Spells or Items; the toys' filters change the toys only", function()
			local world = GridWorld()
			local filterButton = world.env.ClickyGridFilter
			ok(filterButton:IsShown(), "on the Toys tab")
			local menu = world:GridFilterMenu()
			world.spells[500].usable = false
			world.items[600].usable = false
			world.toys[GNOME].usable = false
			menu[3].toggle() -- Usable Only
			list(TabTexts(world), { "Toys (5)", "Mounts (0)", "Pets (0)", "Spells (4)", "Items (4)" }, "Usable Only leaves the spells and items")
			menu[1].toggle() -- Collected off
			list(TabTexts(world), { "Toys (0)", "Mounts (0)", "Pets (0)", "Spells (4)", "Items (4)" }, "and so does Collected off")
			ClickTab(world, SPELLS_TAB)
			ok(not filterButton:IsShown(), "not on the Spells tab")
			list(ShownKeys(world), { OVER, FIRE, STORM, HOME })
			ClickTab(world, ITEMS_TAB)
			ok(not filterButton:IsShown(), "nor the Items tab")
			ClickTab(world, 2)
			ok(filterButton:IsShown(), "on the Mounts tab")
			ClickTab(world, 3)
			ok(filterButton:IsShown(), "and the Pets tab")
			ClickTab(world, TOYS_TAB)
			ok(filterButton:IsShown())
			list(world:TakeErrors(), {})
		end)

		it("a spell learned or an item picked up shows in the grid; in combat the grid waits for the fight to end", function()
			local world = GridWorld()
			ClickTab(world, SPELLS_TAB)
			world.spells[503].known = true
			world:Fire("SPELLS_CHANGED")
			world:Advance(1)
			ok(ButtonFor(world, "s503"), "a spell learned (Future Spell is in the list)")
			ClickTab(world, ITEMS_TAB)
			world.items[604].count = 1
			world:Fire("BAG_UPDATE_DELAYED")
			world:Advance(1)
			ok(ButtonFor(world, "i604"), "an item picked up")
			world.items[601].worn = nil -- the cloak taken off and put away: gone from the grid
			world.items[601].equipped, world.items[601].count = false, 0
			world:Fire("PLAYER_EQUIPMENT_CHANGED")
			world:Advance(1)
			hasNot(ShownKeys(world), CLOAK, "gear taken off")
			world.items[601].worn, world.items[601].equipped = 15, true
			world:Fire("PLAYER_EQUIPMENT_CHANGED")
			world:Advance(1)
			ok(ButtonFor(world, CLOAK), "gear put on")
			local before = #Shown(world)
			world:EnterCombat()
			world.items[604].count = 0
			world.spells[503].known = false
			world:Fire("SPELLS_CHANGED")
			world:Fire("BAG_UPDATE_DELAYED")
			world:Advance(1)
			eq(#Shown(world), before, "the grid keeps what it had in combat")
			ok(ButtonFor(world, "i604"))
			list(TabTexts(world), { "Toys (6)", "Mounts (0)", "Pets (0)", "Spells (5)", "Items (5)" }, "and so do the counts")
			world:LeaveCombat()
			world:Advance(1)
			list(ShownKeys(world), { SHADOWS, CLOAK, RING, SPARE }, "and redraws when it ends")
			list(TabTexts(world), { "Toys (6)", "Mounts (0)", "Pets (0)", "Spells (4)", "Items (4)" })
			eq(#world:TakeErrors(), 0)
		end)

		it("a click uses a spell or an item, wears a cloak that isn't worn, and does so in combat", function()
			local world = GridWorld()
			ClickTab(world, SPELLS_TAB)
			world:MouseClick(ButtonFor(world, FIRE))
			eq(ButtonFor(world, FIRE):GetAttribute("type1"), "spell")
			eq(ButtonFor(world, FIRE):GetAttribute("spell"), 500)
			eq(ButtonFor(world, FIRE):GetAttribute("toy"), nil)
			ClickTab(world, ITEMS_TAB)
			world:MouseClick(ButtonFor(world, SPARE))
			world:MouseClick(ButtonFor(world, CLOAK))
			list(world.used, { FIRE, SPARE, CLOAK }, "a spell cast, an item used, a worn cloak used")
			list(world.equipped, {})
			world:MouseClick(ButtonFor(world, SHADOWS))
			list(world.equipped, { 605 }, "a cloak that isn't worn is worn instead")
			eq(ButtonFor(world, SPARE):GetAttribute("item"), "item:602", "not the bare ID, which names a slot")
			world:EnterCombat()
			world.used = {}
			world:MouseClick(ButtonFor(world, RING))
			list(world.used, { RING }, "in combat too")
			eq(#world:TakeErrors(), 0)
		end)

		it("a spell or item unknown or not carried any more has no action: it isn't listed to click", function()
			local world = GridWorld()
			ClickTab(world, SPELLS_TAB)
			world.spells[500].known = false
			world:Fire("SPELLS_CHANGED")
			world:Advance(1)
			hasNot(ShownKeys(world), FIRE, "a spell forgotten")
			ClickTab(world, ITEMS_TAB)
			world.items[600].count = 0
			world:Fire("BAG_UPDATE_DELAYED")
			world:Advance(1)
			hasNot(ShownKeys(world), RING, "an item gone from the bags")
		end)

		it("a right click opens the menu, shift-click links, a drag picks up: for spells and items as for toys", function()
			local world = GridWorld()
			local opened = {}
			world.ns.OpenEntryMenu = function(owner, key) opened[#opened + 1] = { owner, key } end
			world:Drag(ButtonFor(world, PIRATE))
			list(world.cursor, { toy = PIRATE }, "a toy as before")
			ClickTab(world, SPELLS_TAB)
			local fire = ButtonFor(world, FIRE)
			world:MouseClick(fire, "RightButton")
			world.keys.shift = true
			world:MouseClick(fire)
			world.keys.shift = false
			world:Drag(fire)
			list(world.cursor, { spell = 500 })
			ClickTab(world, ITEMS_TAB)
			local ring = ButtonFor(world, RING)
			world:MouseClick(ring, "RightButton")
			list(opened, { { fire, FIRE }, { ring, RING } })
			world.keys.shift = true
			world:MouseClick(ring)
			world.keys.shift = false
			list(world.chat, { world.env.C_Spell.GetSpellLink(500), (select(2, world.env.C_Item.GetItemInfo(600))) },
				"a spell's and an item's link")
			list(world.used, {}, "a shift-click uses nothing")
			world:Drag(ring)
			list(world.cursor, { item = 600 })
			world.items[600].loading = true
			world.chat = {}
			world.keys.shift = true
			world:MouseClick(ring)
			world.keys.shift = false
			list(world.chat, {}, "an item whose data hasn't loaded has no link yet")
		end)

		it("hovering shows the tooltip of a spell or an item; only a toy can say NEW", function()
			local world = GridWorld()
			ClickTab(world, SPELLS_TAB)
			local fire = ButtonFor(world, FIRE)
			fire:GetScript("OnEnter")(fire)
			eq(world.tooltip.spell, 500)
			ok(not fire.new:IsShown() and not fire.star:IsShown(), "no NEW, no star")
			ClickTab(world, ITEMS_TAB)
			local ring = ButtonFor(world, RING)
			ring:GetScript("OnEnter")(ring)
			eq(world.tooltip.item, 600)
			ok(not ring.new:IsShown() and not ring.star:IsShown())
			eq(#world:TakeErrors(), 0)
		end)

		it("a cooldown shows on a spell or an item and follows the cooldown events", function()
			local world = GridWorld()
			ClickTab(world, SPELLS_TAB)
			local fire = ButtonFor(world, FIRE)
			eq(fire.cooldown.start, nil)
			world.spells[500].cooldown = 30
			world.items[600].cooldown = 30
			eq(fire.cooldown.start, nil, "nothing changes until the game says so")
			world:Fire("SPELL_UPDATE_COOLDOWN")
			ok(fire.cooldown.start, "the spell's swipe")
			ClickTab(world, ITEMS_TAB)
			local ring = ButtonFor(world, RING)
			ring.cooldown:Clear()
			world:Fire("BAG_UPDATE_COOLDOWN")
			ok(ring.cooldown.start, "the item's swipe, on the bags' event")
		end)

		it("the check mark shows a spell or an item that is in a macro", function()
			local world = GridWorld()
			local m = MakeMacro(world, PIRATE, "Portal")
			assert(world.ns.SetEntry(m, FIRE, true))
			assert(world.ns.SetEntry(m, CLOAK, true))
			world:Advance(1)
			ClickTab(world, SPELLS_TAB)
			ok(ButtonFor(world, FIRE).check:IsShown() and not ButtonFor(world, HOME).check:IsShown())
			ClickTab(world, ITEMS_TAB)
			ok(ButtonFor(world, CLOAK).check:IsShown() and not ButtonFor(world, RING).check:IsShown())
			ClickTab(world, SPELLS_TAB)
			assert(world.ns.SetEntry(m, FIRE, false))
			world:Advance(1)
			ok(not ButtonFor(world, FIRE).check:IsShown(), "taken out")
		end)

		it("a spell's or an item's menu has the macros and no star; Favorites takes no spell or item", function()
			local world = GridWorld()
			MakeMacro(world, PIRATE, "Portal")
			for _, key in ipairs({ FIRE, RING }) do
				world.ns.OpenEntryMenu(world.env.UIParent, key)
				local texts = {}
				for _, entry in ipairs(world.menu.entries) do texts[#texts + 1] = entry.text or entry.kind end
				hasNot(texts, "Favorite", key .. " has no star")
				hasNot(texts, "Unfavorite", key .. " has no star")
				has(texts, "Portal", key .. " can go in a macro")
				has(texts, "Add to new macro...")
			end
			world.ns.OpenEntryMenu(world.env.UIParent, PIRATE)
			local texts = {}
			for _, entry in ipairs(world.menu.entries) do texts[#texts + 1] = entry.text or entry.kind end
			has(texts, "Favorite", "a toy still has its star")
			list({ world.ns.SetEntry(Favorites(world), FIRE, true) }, { nil, "Favorites' toys are the toys you star in the Toy Box." })
			eq(#world:TakeErrors(), 0)
		end)

		it("4. a macro holds up to 100 of any mix of toys, spells and items; one more is refused", function()
			local toys, spells, items, list_ = {}, {}, {}, {}
			for i = 1, 40 do
				toys[i] = { id = 3000 + i }
				list_[#list_ + 1] = 3000 + i
			end
			for i = 1, 35 do
				spells[i] = { id = 100 + i }
				list_[#list_ + 1] = "s" .. (100 + i)
			end
			for i = 1, 26 do
				items[i] = { id = 200 + i }
				list_[#list_ + 1] = "i" .. (200 + i)
			end
			local world = World({ toys = toys, spells = spells, items = items, toyList = list_ })
			local m = MakeMacro(world, list_[1], "Mix")
			for i = 2, 100 do
				assert(world.ns.SetEntry(m, list_[i], true))
			end
			ok(#world:FindMacroByName("Mix").body <= 255, "100 of any mix fit")
			list({ world.ns.SetEntry(m, list_[101], true) }, { nil, "Mix is full: a macro holds up to 100 items." })
			assert(world.ns.SetEntry(m, list_[1], false))
			assert(world.ns.SetEntry(m, list_[101], true), "room again once one is out")
		end)

		it("Portal: portal toys, a \"Path of the ...\" spell and a teleport cloak from the bags, in one macro", function()
			local world = GridWorld()
			-- Add to new macro... from a toy (the dialog calls MakeMacro), then tick Portal in a
			-- spell's and an item's menu.
			local m = assert(world.ns.MakeMacro("Portal", PIRATE))
			world.ns.OpenEntryMenu(world.env.UIParent, FIRE)
			world:ChooseMenuEntry("Portal")
			world.ns.OpenEntryMenu(world.env.UIParent, CLOAK)
			world:ChooseMenuEntry("Portal")
			world.ns.OpenEntryMenu(world.env.UIParent, RING)
			world:ChooseMenuEntry("Portal")
			list(MenuLabels(world, FIRE), { "[x] Portal" }, "ticked")
			list(PanelToys(world, "Portal"), { "Cloak of Teleport", "Hearth Ring", "Path of the Fire", "Pirate's Costume" },
				"the panel lists them by name")
			eq(PanelRow(world, "Portal").count, 4)
			PutOnBar(world, "Portal", 1)
			local seen = {}
			for _ = 1, 60 do
				world:PressBar(1)
				seen[world:LastUsed()] = true
			end
			list(seen, { [PIRATE] = true, [FIRE] = true, [RING] = true }, "a click picks the toy, the spell or the ring, never the cloak")
			list(world.equipped, {})
			world:PressBar(1, "RightButton")
			list(DrawerToys(world, "Portal"), { CLOAK, RING, FIRE, PIRATE }, "the drawer has all four, by name")
			world.used = {}
			ClickInDrawer(world, "Portal", CLOAK)
			list(world.used, { CLOAK }, "the cloak is worn already: the drawer uses it")
			eq(#world:TakeErrors(), 0)
			-- Other computer: the same macro, with the same entries.
			local later = NextLogin(world, { toyList = LIST })
			list(PanelToys(later, "Portal"), PanelToys(world, "Portal"), "on another computer")
			ok(m.state == "ready")
		end)
	end)

	-- Mounts and pets (journeys 15, 4, 2, 14, 13 and 17): the grid's Mounts and Pets tabs list what
	-- the player has collected, starred first; a mount is used by casting its spell, a pet by
	-- /summonpet with the GUID of one of the player's pets of that species and look.
	describe("Mounts and pets", function()
		local HORSE, RAM, RAPTOR, ELEKK, KODO = "m6", "m3", "m9", "m12", "m15"
		-- Cat in two looks (blue, white), and Dog.
		local BLUE_CAT, WHITE_CAT, DOG = "p40:300", "p40:301", "p7:200"
		local CAT1, CAT2, CAT3, DOG1 = "BattlePet-0-000000000A01", "BattlePet-0-000000000A02",
			"BattlePet-0-000000000A03", "BattlePet-0-000000000D01"
		local OTHER_CAT = "p40:0" -- the Cat's looks Clicky's list doesn't have
		local LIST = { PIRATE, ORB, HORSE, RAM, RAPTOR, ELEKK, KODO, BLUE_CAT, WHITE_CAT, DOG, OTHER_CAT }

		local function PetWorld(options)
			options = options or {}
			options.toyList = options.toyList or LIST
			options.mounts = options.mounts or {
				{ id = 6, name = "Brown Horse", spell = 458, icon = 7006 },
				{ id = 3, name = "Black Ram", spell = 6777, icon = 7003, favorite = true },
				{ id = 9, name = "Raptor", spell = 8395, icon = 7009, collected = false },
				{ id = 12, name = "Elekk", spell = 34406, icon = 7012, hidden = true }, -- the game hides it on this character
				{ id = 15, name = "Kodo", spell = 18990, icon = 7015, shown = false }, -- the journal's filters hide it
			}
			options.pets = options.pets or {
				{ guid = CAT1, species = 40, display = 300, name = "Cat", icon = 8040 },
				{ guid = CAT2, species = 40, display = 300, name = "Cat", icon = 8040 },
				{ guid = CAT3, species = 40, display = 301, name = "Cat", icon = 8040 },
				{ guid = DOG1, species = 7, display = 200, name = "Dog", icon = 8007 },
			}
			local world = World(options)
			world:LoadCollections()
			world:OpenToyBox()
			return world
		end

		local TOYS_TAB, MOUNTS_TAB, PETS_TAB = 1, 2, 3
		local function ClickTab(world, index)
			local tab = world.env.ClickyGrid.Tabs[index]
			tab.scripts.OnClick(tab, "LeftButton", false)
		end

		local function Shown(world)
			local keys = {}
			for _, button in ipairs(world.env.ClickyGrid.buttons) do
				if button:IsShown() then keys[#keys + 1] = button.entry end
			end
			return keys
		end

		local function ButtonFor(world, key)
			for _, button in ipairs(world.env.ClickyGrid.buttons) do
				if button:IsShown() and button.entry == key then return button end
			end
			error("not in the grid: " .. tostring(key), 2)
		end

		local function Starred(world)
			local keys = {}
			for _, button in ipairs(world.env.ClickyGrid.buttons) do
				if button:IsShown() and button.star:IsShown() then keys[#keys + 1] = button.entry end
			end
			return keys
		end

		local function MenuTexts(world, key)
			world.ns.OpenEntryMenu(world.env.UIParent, key)
			local texts = {}
			for _, entry in ipairs(world.menu.entries) do
				if entry.kind == "CreateButton" then texts[#texts + 1] = entry.text end
			end
			return texts
		end

		it("15. the Mounts tab lists the mounts collected, starred first, then by name; the Pets tab one entry per look", function()
			local world = PetWorld()
			local tabs = {}
			for i, tab in ipairs(world.env.ClickyGrid.Tabs) do tabs[i] = tab.text end
			list(tabs, { "Toys (2)", "Mounts (3)", "Pets (3)", "Spells (0)", "Items (0)" }, "no pet in a look the list lacks yet")
			ClickTab(world, MOUNTS_TAB)
			list(Shown(world), { RAM, HORSE, KODO },
				"the Ram starred first; not the Raptor (not collected) or the Elekk (hidden on this character); "
				.. "the Kodo though the Mount Journal's filters hide it")
			list(Starred(world), { RAM }, "with the Mount Journal's star")
			ClickTab(world, PETS_TAB)
			list(Shown(world), { BLUE_CAT, WHITE_CAT, DOG }, "two blue Cats are one entry; the white Cat another")
			world.env.ClickyGridSearch:SetText("dog")
			list(Shown(world), { DOG }, "the search looks at pets too")
			world.env.ClickyGridSearch:SetText("")
			world:LearnPet({ guid = "BattlePet-0-000000000A04", species = 40, display = 302, name = "Cat" })
			world:Advance(1)
			list(Shown(world), { OTHER_CAT, BLUE_CAT, WHITE_CAT, DOG },
				"a look Clicky's list doesn't have is listed as the species' other looks")
			world:MouseClick(ButtonFor(world, OTHER_CAT))
			eq(world.summonedPet, "BattlePet-0-000000000A04", "and summons that pet")
			world.summonedPet = nil
			local debug = Debug(world)
			ok(debug:find("pets: 5 pets owned in 4 looks, 1 of them with a look Clicky's list doesn't have, under their species' other looks (p40:302); the Pet Journal lists 0 with its own filters", 1, true),
				"/clicky debug says so: " .. debug)
			world.pets[3].favorite = true -- the white Cat starred in the Pet Journal
			world:Fire("PET_JOURNAL_LIST_UPDATE")
			world:Advance(1)
			list(Shown(world), { WHITE_CAT, OTHER_CAT, BLUE_CAT, DOG }, "a starred look first")
			list(Starred(world), { WHITE_CAT })
			eq(#world:TakeErrors(), 0)
		end)

		it("15. the tabs never reach the search box: past it, the selected tab keeps its label and the rest share what's left", function()
			local world = PetWorld()
			local grid = world.env.ClickyGrid
			local function Widths()
				local total, cut = 3 * (#grid.Tabs - 1), {}
				for i, tab in ipairs(grid.Tabs) do
					total = total + tab:GetWidth()
					cut[i] = tab.truncated
				end
				return total, cut
			end
			-- The room: from the first tab, 58 in, to the search box, 12 + 115 from the 703-wide window's right.
			local room = 703 - 12 - 115 - 58
			local total, cut = Widths()
			ok(total <= room, "the labels fit as they are: " .. total)
			list(cut, { false, false, false, false, false }, "none cut")
			eq(grid.Tabs[2]:GetWidth(), #"Mounts (3)" * world.charWidth + 20 + 16, "each with its own padding")
			world.charWidth = 14 -- a wider font, or longer counts
			world:Fire("PET_JOURNAL_LIST_UPDATE")
			world:Advance(1)
			total, cut = Widths()
			ok(total <= room + 0.001, "fitted to the room: " .. total)
			list(cut, { false, true, true, true, true }, "the selected Toys tab keeps its label")
			-- Reopened, each tab resizes itself to its full label as it shows: the fit follows.
			world:CloseToyBox()
			world:OpenToyBox()
			world:Advance(1)
			total, cut = Widths()
			ok(total <= room + 0.001, "still fitted after the window is reopened: " .. total)
			list(cut, { false, true, true, true, true })
		end)

		it("15. Not Collected on Mounts and Pets lists what the journals would, each tab keeping its own filters", function()
			local toyList = { unpack(LIST) }
			for _, key in ipairs({ "m18", "p55:0", "p55:900", "p66:0", "p77:0", "p88:0" }) do toyList[#toyList + 1] = key end
			local world = PetWorld({
				toyList = toyList,
				mountHidden = { [18] = true, [6] = true }, -- the Gray Wolf, not collected; the Horse, collected
				-- The Owl and the Frog aren't owned; species 66 is a tamer's pet, hidden from the journal;
				-- the game has no data for 77 on this computer.
				petSpecies = { [55] = { name = "Owl", icon = 8055 }, [66] = { name = "Tamer's Pet", icon = 8066 },
					[88] = { name = "Frog", icon = 8088 } },
				petLooks = { [55] = { 900, 901 }, [88] = { 950 } },
				petHidden = { [66] = true },
			})
			world:AddMount({ id = 18, name = "Gray Wolf", collected = false })
			local filterButton = world.env.ClickyGridFilter
			ClickTab(world, MOUNTS_TAB)
			world:GridFilterMenu()[2].toggle() -- Not Collected
			list(Shown(world), { RAM, HORSE, KODO, RAPTOR },
				"then the Raptor, not collected; not the Gray Wolf, which the journal shows only once collected, or the Elekk")
			eq(ButtonFor(world, RAPTOR).icon.alpha, 0.5, "greyed out")
			eq(filterButton.resetShown, true, "the reset button, for the Mounts tab's filters")
			ClickTab(world, TOYS_TAB)
			eq(filterButton.resetShown, false, "the Toys tab's are their own")
			eq(world:GridFilterMenu()[2].isSelected(), false, "and Not Collected is off there")
			ClickTab(world, PETS_TAB)
			world:GridFilterMenu()[2].toggle()
			list(Shown(world), { BLUE_CAT, WHITE_CAT, DOG, "p88:0", "p55:900" },
				"one entry per species not owned: its first look the game lists, or its 0 if the list lacks it")
			eq(ButtonFor(world, "p55:900").icon.alpha, 0.5)
			world:MouseClick(ButtonFor(world, "p55:900"))
			eq(world.summonedPet, nil, "a pet not owned summons nothing")
			world:GridFilterMenu()[2].toggle()
			-- The Pet Journal's other filters: families, and battle pets or not.
			world.account.species[7].family = 2
			world:GridFilterMenu().find("Pet Families > Family 2").toggle()
			list(Shown(world), { BLUE_CAT, WHITE_CAT }, "the Dog's family unticked")
			world:GridFilterMenu().find("Pet Families > Check All").toggle()
			list(Shown(world), { BLUE_CAT, WHITE_CAT, DOG }, "Check All ticks it again")
			world.account.species[40].canBattle = false
			world:GridFilterMenu().find("Non-Combat Pets").toggle()
			list(Shown(world), { DOG }, "Non-Combat Pets unticked: not the Cats, which can't battle")
			world:GridFilterMenu().find("Non-Combat Pets").toggle()
			local debug = Debug(world)
			ok(debug:find("mounts: the Mount Journal lists 5 with its own filters", 1, true), debug)
			ok(debug:find("the Pet Journal lists 0 with its own filters", 1, true), debug)
			list(world:TakeErrors(), {})
		end)

		-- The menu's entries as a player sees them, top level only: "title:" before a title.
		local function MenuTop(world)
			local out = {}
			for _, entry in ipairs(world:GridFilterMenu().all) do
				if not entry.path:find(" > ", 1, true) then
					out[#out + 1] = (entry.kind == "title" and "title:" or "") .. entry.text
				end
			end
			return out
		end

		it("15. each tab's Filter menu is its Blizzard window's: the same entries, in the same order", function()
			local world = PetWorld()
			list(MenuTop(world), { "Collected", "Not Collected", "Usable Only", "Sources", "Expansion" },
				"the Toy Box's (Blizzard_ToyBox.lua:109-138)")
			local menu = world:GridFilterMenu()
			eq(menu.find("Sources > Check All").kind, "button")
			eq(menu.find("Sources > Source 12").kind, "checkbox", "each source the game says the Toy Box offers")
			eq(menu.find("Expansion > Expansion 0").kind, "checkbox", "the expansions, named from 0")
			ClickTab(world, MOUNTS_TAB)
			list(MenuTop(world), { "Collected", "Not Collected", "Unusable", "title:Type", "Ground", "Flying", "Aquatic",
				"Skyriding", "Ride Along", "Sources" }, "the Mount Journal's (Blizzard_MountCollection.lua:221-258)")
			ClickTab(world, PETS_TAB)
			list(MenuTop(world), { "Collected", "Not Collected", "title:Pet Types", "Battle Pets", "Non-Combat Pets",
				"Pet Families", "Sources", "Sort By" }, "the Pet Journal's (Blizzard_PetCollection.lua:172-212)")
			menu = world:GridFilterMenu()
			eq(menu.find("Pet Families > Family 10").kind, "checkbox")
			eq(menu.find("Sort By > Level").kind, "radio")
		end)

		it("15. Toys: a source or an expansion unticked hides its toys; one without a source, or not loaded, stays", function()
			local toys = {
				{ id = 101, name = "Drop Toy", expansion = 2 },
				{ id = 102, name = "Vendor Toy", expansion = 5 },
				{ id = 103, name = "Plain Toy", expansion = 5 }, -- no source
				{ id = 104, name = "Slow Toy", expansion = 5 },
			}
			local world = World({ toys = toys, toyList = { 101, 102, 103, 104 }, toySource = { [101] = 0, [102] = 2 } })
			world:LoadCollections()
			world:OpenToyBox()
			world:GridFilterMenu().find("Sources > Source 1").toggle() -- Enum.BattlePetSources.Drop is 0
			list(Shown(world), { 103, 104, 102 }, "not the toy that drops; the one without a source stays")
			eq(world.env.ClickyGridFilter.resetShown, true)
			world:GridFilterMenu().find("Sources > Check All").toggle()
			world:GridFilterMenu().find("Expansion > Expansion 5").toggle()
			world.toys[104].loading = true -- its item data hasn't arrived: no expansion yet
			world:Fire("TOYS_UPDATED")
			world:Advance(1)
			list(Shown(world), { 104, 101 }, "not the toys of expansion 5, but the one not loaded yet (its name either: first)")
			world:GridFilterMenu().find("Expansion > Uncheck All").toggle()
			world.toys[104].loading = false
			world:Fire("TOYS_UPDATED")
			world:Advance(1)
			list(Shown(world), {}, "every expansion unticked")
			world.env.ClickyGridFilter.defaultCallback()
			world:Advance(1)
			eq(#Shown(world), 4, "the reset puts it all back")
		end)

		it("15. Mounts: Unusable, the types and the sources, as the Mount Journal's", function()
			local world = PetWorld({ mountType = { [424] = 5, [231] = 2 } })
			world.mounts[6].mountTypeID = 424 -- the Horse flies and skyrides
			world.mounts[3].mountTypeID = 231 -- the Ram swims
			world.mounts[15].source = 3 -- the Kodo: Vendor, the third of the Sources (sourceType counts from 1)
			ClickTab(world, MOUNTS_TAB)
			list(Shown(world), { RAM, HORSE, KODO })
			world:GridFilterMenu().find("Flying").toggle()
			list(Shown(world), { RAM, HORSE, KODO }, "the Horse also skyrides, which is still ticked")
			world:GridFilterMenu().find("Skyriding").toggle()
			list(Shown(world), { RAM, KODO }, "neither of its types ticked")
			world:GridFilterMenu().find("Ground").toggle()
			list(Shown(world), { RAM }, "the Kodo is a ground mount: no type flags")
			local state = world.ns.GetGridState()
			ok(state:find("collected true, not collected false, unusable true, types off 1 2 4, sources off none,", 1, true)
				and not state:find("usable only", 1, true), "/clicky debug shows the Mounts tab's own filters: " .. state)
			world.env.ClickyGridFilter.defaultCallback()
			world:GridFilterMenu().find("Sources > Source 3").toggle()
			list(Shown(world), { RAM, HORSE }, "the Kodo's source unticked")
			world.env.ClickyGridFilter.defaultCallback()
			world.mounts[6].usable = false
			world:GridFilterMenu().find("Unusable").toggle()
			list(Shown(world), { RAM, KODO }, "Unusable unticked: not a collected mount that can't be used here")
		end)

		it("15. Pets: sources, and Sort by level, rarity and family", function()
			local world = PetWorld({ petSource = { [40] = 4 } }) -- the Cat: Enum.BattlePetSources.WildPet
			world.account.species[7].family = 8
			world:Pet(CAT3).level, world:Pet(DOG1).level = 25, 10
			world:Pet(CAT1).rarity, world:Pet(DOG1).rarity = 4, 3
			ClickTab(world, PETS_TAB)
			world:GridFilterMenu().find("Sources > Source 5").toggle()
			list(Shown(world), { DOG }, "the Cat's source unticked")
			world.env.ClickyGridFilter.defaultCallback()
			world:GridFilterMenu().find("Sort By > Level").toggle()
			list(Shown(world), { WHITE_CAT, DOG, BLUE_CAT }, "highest level first")
			eq(world:GridFilterMenu().find("Sort By > Level").isSelected(), true)
			world:GridFilterMenu().find("Sort By > Rarity").toggle()
			list(Shown(world), { BLUE_CAT, DOG, WHITE_CAT }, "rarest first")
			world:GridFilterMenu().find("Sort By > Type").toggle()
			list(Shown(world), { BLUE_CAT, WHITE_CAT, DOG }, "by family: the Cats' 1, the Dog's 8")
			eq(world.env.ClickyGridFilter.resetShown, true, "a sort other than by name isn't the default")
			ok(Debug(world):find("toys: the Toy Box lists 0 with its own filters", 1, true))
		end)

		it("15. the search finds by name, by source, expansion, mount type or pet family, and by tooltip text", function()
			local world = PetWorld({ toySource = { [ORB] = 2 }, mountType = { [424] = 5 } })
			world.toys[PIRATE].tooltip = "Use: Rested experience is gained 10% faster."
			world.toys[ORB].tooltip, world.toys[ORB].loading = "Shows you the way home.", true -- its data hasn't arrived
			world.toys[PIRATE].expansion = 5
			world.mounts[6].mountTypeID = 424 -- the Horse flies and skyrides
			world.account.species[7].family = 8
			local search = world.env.ClickyGridSearch
			local function Tabs()
				local texts = {}
				for i, tab in ipairs(world.env.ClickyGrid.Tabs) do texts[i] = tab.text end
				return texts
			end
			search:SetText("RESTED")
			list(Shown(world), { PIRATE }, "the tooltip's text, ignoring case")
			search:SetText("source 3") -- BATTLE_PET_SOURCE_3: Enum.BattlePetSources.Vendor
			list(Shown(world), { ORB }, "a toy's source")
			search:SetText("expansion 5")
			list(Shown(world), { PIRATE }, "a toy's expansion")
			search:SetText("skyriding")
			list(Tabs(), { "Toys (0)", "Mounts (1)", "Pets (0)", "Spells (0)", "Items (0)" }, "a mount's type, on the Mounts tab")
			search:SetText("family 8")
			list(Tabs(), { "Toys (0)", "Mounts (0)", "Pets (1)", "Spells (0)", "Items (0)" }, "a pet's family")
			search:SetText("cat")
			list(Tabs(), { "Toys (0)", "Mounts (0)", "Pets (2)", "Spells (0)", "Items (0)" }, "and names, as before")
			-- A tooltip whose data hasn't arrived is read again once it has.
			search:SetText("way home")
			list(Shown(world), {}, "not loaded yet")
			world.toys[ORB].loading = false
			world:Fire("GET_ITEM_INFO_RECEIVED", ORB, true)
			world:Advance(1)
			list(Shown(world), { ORB }, "found once it has")
			-- A tooltip first read without its description (its data still arriving) is read again
			-- when the game says the data has arrived.
			search:SetText("feathered")
			list(Shown(world), {}, "the Pirate's tooltip, as first read, doesn't say it")
			world.toys[PIRATE].tooltip = world.toys[PIRATE].tooltip .. " Feathered hat included."
			world:Fire("GET_ITEM_INFO_RECEIVED", PIRATE, true)
			world:Advance(1)
			list(Shown(world), { PIRATE }, "read again once its data arrived")
			ok(Debug(world):find("search: %d+ tooltips kept"), "/clicky debug says how many")
		end)

		it("/clicky debug checks each tab against its Blizzard window, with the window's own filters, entry by entry", function()
			local world = PetWorld()
			local ns, blizzard = world.ns, world.blizzard
			-- The Mount Journal, collected and not, lists the mounts it shows here: not the Kodo, but the
			-- Elekk, which the game hides on this character for Clicky.
			blizzard.mounts.default = false
			eq(ns.CheckAgainstBlizzard("mounts"), "Clicky lists 4, the Mount Journal 4 with its filters (collected true, "
				.. "not collected true, unusable true, types off none, sources off none); "
				.. "only Clicky: Kodo (15); only the Mount Journal: Elekk (12: not one the tab lists)",
				"the window's filters, and the entries that differ, named, with why Clicky leaves one out")
			world.mounts[15].shown, world.mounts[12].hidden = true, false
			eq(ns.CheckAgainstBlizzard("mounts"), "matches the Mount Journal with its filters (5)")
			-- One the window lists that Clicky's filter, set as the window's, leaves out: the filter is named.
			world.mounts[6].usable, blizzard.mounts.unusable = false, false
			eq(ns.CheckAgainstBlizzard("mounts"), "Clicky lists 4, the Mount Journal 5 with its filters (collected true, "
				.. "not collected true, unusable false, types off none, sources off none); "
				.. "only the Mount Journal: Brown Horse (6: Clicky's unusable filter)")
			world.mounts[6].usable, blizzard.mounts.unusable = true, true
			-- A mount's sourceType is its Sources checkbox: with the fifth unticked, the Mount Journal kept
			-- the profession mounts, sourceType 4 (seen in play).
			world.mounts[6].source, blizzard.mounts.sourcesOff = 4, { [5] = true }
			eq(ns.CheckAgainstBlizzard("mounts"), "matches the Mount Journal with its filters (5)")
			-- Left out by a source: the checkbox Clicky put it under is named, as that was inferred.
			blizzard.mounts.sourcesOff = { [4] = true }
			eq(ns.CheckAgainstBlizzard("mounts"), "Clicky lists 4, the Mount Journal 5 with its filters (collected true, "
				.. "not collected true, unusable true, types off none, sources off 4); "
				.. "only the Mount Journal: Brown Horse (6: Clicky's sources filter, Sources 4)")
			world.mounts[6].source, blizzard.mounts.sourcesOff = nil, {}
			-- Its filters are read as the window has them: Not Collected off there is off for the check.
			blizzard.mounts.uncollected = false
			world.mounts[9].shown = false -- the Raptor, not collected
			eq(ns.CheckAgainstBlizzard("mounts"), "matches the Mount Journal with its filters (4)")
			-- On its defaults, they're compared with Clicky's.
			blizzard.mounts.default, blizzard.mounts.uncollected = true, true
			world.mounts[9].shown = true
			eq(ns.CheckAgainstBlizzard("mounts"), "matches the Mount Journal with its filters (5); its defaults differ "
				.. "from Clicky's: uncollected: Blizzard's true, Clicky's false")
			blizzard.mounts.uncollected, world.mounts[9].shown = false, false
			eq(ns.CheckAgainstBlizzard("mounts"), "matches the Mount Journal with its filters (4); its defaults are Clicky's")
			-- The Pet Journal lists species, and is compared by species.
			blizzard.pets.default, blizzard.pets.uncollected = false, false
			blizzard.pets.list = { 40, 40, 40, 7 }
			eq(ns.CheckAgainstBlizzard("pets"), "matches the Pet Journal with its filters (2)")
			-- A window with a search typed in lists only what matches it: not checked.
			world.env.PetJournal = { searchBox = { GetText = function() return "cat" end } }
			eq(ns.CheckAgainstBlizzard("pets"), 'not checked: the Pet Journal has a search ("cat")')
			blizzard.toys.default, blizzard.toys.uncollected = false, false
			-- The Toy Box lists toys this world's Clicky list doesn't have: they're named.
			blizzard.toys.list = { WINGS, CHEST, GNOME, ORB, HAT, PIRATE }
			eq(ns.CheckAgainstBlizzard("toys"), "Clicky lists 2, the Toy Box 6 with its filters (collected true, "
				.. "not collected false, usable only false, sources off none, expansions off none); only the Toy Box: "
				.. "Gnomish Gravity Well (103: not in Clicky's list), Pirate Hat (201: not in Clicky's list), "
				.. "Fairy Wings (202: not in Clicky's list), Treasure Chest (300: not in Clicky's list)")
			ok(Debug(world):find("check mounts: matches the Mount Journal", 1, true))
		end)

		-- Which Sources box a source number is under isn't in Blizzard's source: each mount's and species'
		-- source text, which starts with its source's name, shows whether Clicky has it right.
		it("/clicky debug checks every mount's and pet's source text against the Sources box Clicky puts it under", function()
			local world = PetWorld({ petSource = { [40] = 3 } }) -- the Cat: Enum.BattlePetSources.WildPet, the fourth box
			world.mounts[6].source, world.mounts[6].sourceText = 4, "|cFFFFD200Source 4: |rEngineering"
			world.mounts[3].source, world.mounts[3].sourceText = 3, "Source 2: Quartermaster"
			world.account.species[40].sourceText = "Source 4: Elwynn Forest"
			world.mounts[9].source, world.mounts[9].sourceText = 2, "Legacy" -- no source named: agrees with none
			world.mounts[15].source, world.mounts[15].sourceText = 0, "Drop: Coren Direbrew" -- no number: not checked
			local debug = Debug(world)
			ok(debug:find('\nmounts\' sources: 1 of 3 agree (numbered one lower 1, one higher 0); agree only when '
				.. 'shifted: Black Ram (3: under Source 3, says "Source 2: Quartermaster")\n', 1, true), debug)
			ok(debug:find("\npets' sources: 1 of 1 agree (numbered one lower 0, one higher 0)\n", 1, true), debug)
			-- Most agreeing one lower is a numbering off by one, said so.
			world.mounts[6].sourceText = "Source 3: Engineering"
			ok(Debug(world):find("\nmounts' sources: 0 of 3 agree: ANOTHER NUMBERING AGREES MORE (numbered one lower 2,",
				1, true))
		end)

		it("/clicky debug lists the looks the game gives a species that Clicky's list lacks, for pets not owned too", function()
			-- Species 55, the Owl, isn't owned: the game still lists its looks.
			-- Every species in the list has its 0 (tools/update_toys.py).
			local world = PetWorld({ toyList = { PIRATE, "p40:0", BLUE_CAT, WHITE_CAT, "p7:0", DOG, "p55:0", "p55:900" },
				petLooks = { [40] = { 300, 301, 302 }, [55] = { 900, 901 } } })
			local debug = Debug(world)
			ok(debug:find("pet looks: the game lists 6 looks for the list's 3 species, 2 of them not in the list (p40:302, p55:901)",
				1, true), debug)
			-- A species whose pets take a random look each summon has none of its looks listed, on purpose.
			world = PetWorld({ toyList = { PIRATE, "p40:0", BLUE_CAT, WHITE_CAT, "p7:0", DOG, "p55:0" },
				petLooks = { [40] = { 300, 301 }, [55] = { 900, 901 } }, petRandomLook = { [55] = true } })
			eq(world.ns.GetPetLookAudit(), "the game lists 3 looks for the list's 3 species, 0 of them not in the list",
				"the Owl's looks aren't checked")
		end)

		it("4. the menu stars a mount or a pet's look as the journals do; a mount the journal's filters hide has no star", function()
			local world = PetWorld()
			list(MenuTexts(world, HORSE), { "Favorite", "Add to new macro..." })
			world:ChooseMenuEntry("Favorite")
			ok(world.mounts[6].favorite, "the Horse is starred in the Mount Journal")
			list(MenuTexts(world, RAM), { "Unfavorite", "Add to new macro..." })
			world:ChooseMenuEntry("Unfavorite")
			ok(not world.mounts[3].favorite)
			list(MenuTexts(world, KODO), { "Add to new macro..." },
				"the game stars a mount by its place in the journal's list, which its filters leave it out of")
			list(MenuTexts(world, BLUE_CAT), { "Favorite", "Add to new macro..." })
			world:ChooseMenuEntry("Favorite")
			list({ world:Pet(CAT1).favorite, world:Pet(CAT2).favorite }, { true, false }, "one Cat of the look is starred")
			world:Pet(CAT2).favorite = true
			list(MenuTexts(world, BLUE_CAT), { "Unfavorite", "Add to new macro..." })
			world:ChooseMenuEntry("Unfavorite")
			list({ world:Pet(CAT1).favorite, world:Pet(CAT2).favorite }, { false, false }, "every Cat of the look loses its star")
		end)

		it("2. a click summons a mount that can be used here, by its spell; none usable says so", function()
			local world = PetWorld()
			MakeMacro(world, HORSE, "Ride")
			AddTo(world, RAM, "Ride")
			AddTo(world, RAPTOR, "Ride")
			PutOnBar(world, "Ride", 1)
			local cast = {}
			for _ = 1, 40 do
				world:PressBar(1)
				cast[world:LastUsed()] = true
			end
			list(cast, { s458 = true, s6777 = true }, "the Horse and the Ram by their spells; never the Raptor, not collected")
			world.mounts[6].usable, world.mounts[3].usable = false, false -- the game says neither can be used here
			world:Fire("MOUNT_JOURNAL_USABILITY_CHANGED")
			local before = #world.used
			world:PressBar(1)
			eq(#world.used, before, "nothing cast")
			list(world:TakeErrors(), { "No usable items in Ride." })
		end)

		it("2, 14. a click summons a pet of the look that isn't out, a starred one first; the drawer puts the only one away", function()
			local world = PetWorld()
			MakeMacro(world, BLUE_CAT, "Pets")
			AddTo(world, DOG, "Pets")
			PutOnBar(world, "Pets", 1)
			world.summonedPet = DOG1
			local summoned = {}
			for _ = 1, 20 do
				local before = #world.used
				world:PressBar(1)
				eq(#world.used, before + 1, "every click summons a pet; none puts the Dog away")
				summoned[world:LastUsed()] = true
				world.summonedPet = DOG1 -- put the Dog back out
			end
			list(summoned, { [CAT1] = true }, "the first blue Cat; never the Dog, which is out and would be put away")
			world:Pet(CAT2).favorite = true
			for _ = 1, 5 do
				world:PressBar(1)
				eq(world:LastUsed(), CAT2, "the starred blue Cat")
				world.summonedPet = DOG1
			end
			world.summonedPet = CAT2
			for _ = 1, 10 do
				world:PressBar(1)
				ok(world:LastUsed() ~= CAT2, "the starred Cat is out: the other one, or the Dog")
				world.summonedPet = CAT2
			end
			-- A look's pets all out or unsummonable: the drawer uses the one that's out, not the first.
			world:Pet(CAT1).summonable = false
			world.summonedPet = CAT2
			world:Pet(CAT2).favorite = false
			eq(select(3, world.ns.EntryAction(BLUE_CAT)), "/summonpet " .. CAT2, "the blue Cat that's out")
			world:Pet(CAT1).summonable = true
			-- The drawer: the Dog is the only one of its look; out, a click on it puts it away.
			world.summonedPet = DOG1
			world.bars[1].mouseButton = nil
			world:PressBar(1, "RightButton")
			ok(DrawerOpen(world, "Pets"))
			ClickInDrawer(world, "Pets", DOG)
			eq(world.summonedPet, nil, "the Dog is put away, as the Pet Journal's Summon button does")
			list(world:TakeErrors(), {})
		end)

		it("13. a look whose last pet is caged stays in its macros, greyed out, and isn't picked", function()
			local world = PetWorld()
			MakeMacro(world, DOG, "Pets")
			AddTo(world, BLUE_CAT, "Pets")
			PutOnBar(world, "Pets", 1)
			world:CagePet(CAT1)
			local summoned = {}
			for _ = 1, 20 do
				world:PressBar(1)
				summoned[world:LastUsed()] = true
				world.summonedPet = nil
			end
			list(summoned, { [CAT2] = true, [DOG1] = true }, "the other blue Cat still stands for the look")
			world:CagePet(CAT2)
			list(PanelToys(world, "Pets"), { "Cat", "Dog" }, "the Cat stays in the macro")
			local greyed = {}
			for _, row in ipairs(world.ns.PanelRows()) do
				if row.kind == "entry" then greyed[row.key] = not row.owned end
			end
			list(greyed, { [BLUE_CAT] = true, [DOG] = false }, "greyed out")
			for _ = 1, 5 do
				world:PressBar(1)
				eq(world:LastUsed(), DOG1, "only the Dog is picked")
				world.summonedPet = nil
			end
		end)

		it("15. in the grid a click casts the mount's spell or summons the pet; shift-click links; a drag picks it up", function()
			local world = PetWorld()
			ClickTab(world, MOUNTS_TAB)
			world:MouseClick(ButtonFor(world, HORSE))
			eq(world:LastUsed(), "s458")
			world:Drag(ButtonFor(world, HORSE))
			list(world.cursor, { mount = 6 }, "by its place in the Mount Journal's list")
			world.cursor = nil
			world:Drag(ButtonFor(world, KODO))
			eq(world.cursor, nil, "a mount the journal's filters hide can't be picked up")
			world.keys.shift = true
			world:MouseClick(ButtonFor(world, RAM))
			world.keys.shift = false
			list(world.chat, { world.env.C_MountJournal.GetMountLink(6777) })
			ButtonFor(world, HORSE):GetScript("OnEnter")(ButtonFor(world, HORSE))
			eq(world.tooltip.mountSpell, 458, "the Mount Journal's tooltip")
			ClickTab(world, PETS_TAB)
			world:MouseClick(ButtonFor(world, WHITE_CAT))
			eq(world.summonedPet, CAT3)
			world:Drag(ButtonFor(world, WHITE_CAT))
			list(world.cursor, { pet = CAT3 })
			ButtonFor(world, DOG):GetScript("OnEnter")(ButtonFor(world, DOG))
			eq(world.tooltip.pet, DOG1, "the Pet Journal's tooltip of the pet the entry uses")
			eq(#world:TakeErrors(), 0)
		end)

		it("15. in the grid a second click on a look summons its other pet, not the one it put out", function()
			local world = PetWorld()
			ClickTab(world, PETS_TAB)
			world:MouseClick(ButtonFor(world, BLUE_CAT))
			eq(world.summonedPet, CAT1)
			world:MouseClick(ButtonFor(world, BLUE_CAT))
			eq(world.summonedPet, CAT2, "at once, no wait: the other blue Cat; the first isn't put away")
			eq(#world:TakeErrors(), 0)
		end)

		it("15. a pet with a cooldown shows its swipe in the grid, as in the Pet Journal", function()
			local world = PetWorld()
			ClickTab(world, PETS_TAB)
			world:MouseClick(ButtonFor(world, BLUE_CAT))
			eq(world.summonedPet, CAT1)
			world:Pet(CAT1).cooldown = 30
			world:Fire("SPELL_UPDATE_COOLDOWN")
			ok(ButtonFor(world, BLUE_CAT).cooldown.start, "the swipe")
			world:Advance(1) -- the look moves on to its other pet, which isn't out
			ok(ButtonFor(world, BLUE_CAT).cooldown.start, "still the swipe of the pet just summoned")
			eq(ButtonFor(world, DOG).cooldown.start, nil, "no swipe on a pet without a cooldown")
		end)

		it("2, 17. a click skips a pet look on cooldown, as a toy; the global cooldown doesn't count", function()
			local world = PetWorld()
			MakeMacro(world, BLUE_CAT, "Pets")
			AddTo(world, DOG, "Pets")
			PutOnBar(world, "Pets", 1)
			world:Pet(CAT1).cooldown, world:Pet(CAT2).cooldown = 30, 30
			local summoned = {}
			for _ = 1, 10 do
				world:PressBar(1)
				summoned[world:LastUsed()] = true
				world.summonedPet = nil
			end
			list(summoned, { [DOG1] = true }, "only the Dog")
			world:Pet(CAT1).cooldown, world:Pet(CAT2).cooldown = 0.5, 0.5
			summoned = {}
			for _ = 1, 20 do
				world:PressBar(1)
				summoned[world:LastUsed()] = true
				world.summonedPet = nil
			end
			list(summoned, { [CAT1] = true, [DOG1] = true }, "the global cooldown isn't a cooldown")
		end)

		it("15, 17. the pet that's out and the mount ridden are marked at once, in the grid and the drawer, as in the journals", function()
			local world = PetWorld()
			ClickTab(world, PETS_TAB)
			world:MouseClick(ButtonFor(world, BLUE_CAT))
			ok(ButtonFor(world, BLUE_CAT).active:IsShown(), "a blue Cat is out, marked at once: no wait")
			ok(not ButtonFor(world, DOG).active:IsShown(), "the Dog isn't")
			MakeMacro(world, DOG, "Pets")
			AddTo(world, BLUE_CAT, "Pets")
			PutOnBar(world, "Pets", 1)
			world:PressBar(1, "RightButton")
			ok(DrawerOpen(world, "Pets"))
			local marked = {}
			local drawer = world.ns.GetDrawer(Macro(world, "Pets").id)
			for _, button in ipairs(drawer.buttons) do
				if button.entry then marked[button.entry] = button.active:IsShown() end
			end
			list(marked, { [BLUE_CAT] = true, [DOG] = false }, "in the drawer too")
			ClickTab(world, MOUNTS_TAB)
			world:MouseClick(ButtonFor(world, HORSE))
			ok(ButtonFor(world, HORSE).active:IsShown(), "riding the Horse, marked at once")
			ok(not ButtonFor(world, RAM).active:IsShown())
		end)

		it("2. in combat a macro picks from the mounts and pets ready when the fight started", function()
			local world = PetWorld()
			MakeMacro(world, HORSE, "Mix")
			AddTo(world, BLUE_CAT, "Mix")
			PutOnBar(world, "Mix", 1)
			world:EnterCombat()
			local button = world.env["Clicky" .. Code(world, "Mix")]
			local ready = {}
			for i = 1, button:GetAttribute("readycount") do
				ready[button:GetAttribute("ready" .. i)] = { button:GetAttribute("readytype" .. i),
					button:GetAttribute("readyattr" .. i), button:GetAttribute("readyvalue" .. i) }
			end
			list(ready, { [HORSE] = { "spell", "spell", "Brown Horse" }, [BLUE_CAT] = { "macro", "macrotext", "/summonpet " .. CAT1 } })
			local used = {}
			for _ = 1, 30 do
				world:PressBar(1)
				used[world:LastUsed()] = true
				world.summonedPet = nil
			end
			list(used, { s458 = true, [CAT1] = true })
			world:LeaveCombat()
		end)

		it("11. a macro with mounts and pets reads on a Clicky whose list has them, and as newer on one whose list doesn't", function()
			local world = PetWorld()
			MakeMacro(world, HORSE, "Mix")
			AddTo(world, DOG, "Mix")
			local m = Macro(world, "Mix")
			list(world.ns.MacroEntries(m), { [HORSE] = true, [DOG] = true })
			local older = NextLogin(world, { toyList = { PIRATE, ORB } })
			eq(Macro(older, "Mix").state, "newer", "an older Clicky's list stops before them")
			local later = NextLogin(world, { toyList = LIST })
			list(later.ns.MacroEntries(Macro(later, "Mix")), { [HORSE] = true, [DOG] = true }, "another computer reads them")
		end)

		it("11. a pet under its species' other looks stays usable in its macro once a later list has its look", function()
			local CAT4 = "BattlePet-0-000000000A04"
			local function Pets()
				return {
					{ guid = CAT1, species = 40, display = 300, name = "Cat", icon = 8040 },
					{ guid = CAT4, species = 40, display = 302, name = "Cat", icon = 8040 },
				}
			end
			local world = PetWorld({ pets = Pets() })
			MakeMacro(world, OTHER_CAT, "Odd")
			eq(select(3, world.ns.EntryAction(OTHER_CAT)), "/summonpet " .. CAT4, "the Cat whose look the list lacks")
			local newerList = { unpack(LIST) }
			newerList[#newerList + 1] = "p40:302"
			local later = PetWorld({ account = world.account, pets = Pets(), toyList = newerList })
			list(later.ns.MacroEntries(Macro(later, "Odd")), { [OTHER_CAT] = true })
			ok(later.ns.IsEntryOwned(OTHER_CAT), "not greyed out")
			eq(select(3, later.ns.EntryAction(OTHER_CAT)), "/summonpet " .. CAT1, "any of the species' pets")
			ClickTab(later, PETS_TAB)
			list(Shown(later), { BLUE_CAT, "p40:302" }, "the grid lists the look; the 0 only while a pet's look is unlisted")
			eq(#later:TakeErrors(), 0)
		end)
	end)

end)
