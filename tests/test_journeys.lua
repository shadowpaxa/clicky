-- The journeys in docs/macros-user-journeys.md, as far as Clicky's own logic goes: the real
-- addon files run against stubbed game state (tests/wow.lua), and each test drives the
-- functions Clicky's UI is built on (the Macros API, ns.PanelRows, ns.ToyMenuEntries). How the
-- Toy Box menus, dialogs, panel and tooltips look and respond is checked by playing.

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
local UNREADABLE = "Clicky can't read this macro's toys. Delete it and make it again."
local NEWER = "This macro was saved by a newer version of Clicky. Update Clicky to use it."
local UNKNOWN_TOY = "Clicky doesn't know this toy yet. Update Clicky."

-- Macros as Clicky 0.4.0 wrote them (format 4), made by the real 0.4.0 code: a worktree of this
-- repository at tag v0.4.0-alpha1, its tests/wow.lua with the toys below, MakeMacro("Illusion",
-- 101), then SetToy(..., true) for each further toy. The bodies are pasted as they came out.
-- Toys: 101 Pirate's Costume, 102 Orb of Deception, 103 Gnomish Gravity Well, 201 Pirate Hat,
-- 202 Fairy Wings, 300 Treasure Chest (the six toys of Toys() above).
-- Illusion holds 101 and 201. Their /click lines are 0.4.0's: ClickySet<number>.
local V040_PIRATE_HAT = "/click [btn:2]ClickyP1;ClickySet1\n"
	.. "#clicky gAAlgAwAPxGLWZkHzieCBNLWI3kaW85vYmpr/ir2Xv55+LVKiUvhpguo/vw3XSjf0c"
-- The same, made while the game had five toys, without 103.
local V040_FIVE_TOYS = "/click [btn:2]ClickyP1;ClickySet1\n"
	.. "#clicky gAAlgAoAOKF2oVZVz3rJKOD3MPb9yQK25bCajjDWP2cLcUlvZiMZesUds7QdEbKHQ"
-- Illusion holds no toys (101 added, then removed).
local V040_EMPTY = "/click [btn:2]ClickyP1;ClickySet1\n"
	.. "#clicky gAAlgAwAPxGLWZkHzieCBNLWI3kaW85vYmpr/ir2Xv55+LVKiUvhpguo/vw3XSnZs"

local ALL_TOYS = { PIRATE, ORB, GNOME, HAT, WINGS, CHEST }
local function With(ids, extra)
	local out = { unpack(ids) }
	out[#out + 1] = extra
	return out
end

-- Clicky's macro called name.
local function Macro(world, name)
	for _, m in ipairs(world.ns.GetMacros()) do
		if m.name == name then return m end
	end
	error("no Clicky macro " .. name, 2)
end

-- Journey 3's step (Add to new macro...), used by later journeys to get a macro.
local function MakeMacro(world, itemID, name)
	return assert(world.ns.MakeMacro(name, itemID))
end

-- Journey 4's step (Add to <macro> in a toy's menu).
local function AddTo(world, itemID, name)
	assert(world.ns.SetToy(Macro(world, name), itemID, true))
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
		elseif row.kind == "toy" then
			local _, name = world.env.C_ToyBox.GetToyInfo(row.itemID)
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

-- The macro entries in a toy's menu (the Toy Box's and the panel's).
local function MenuLabels(world, itemID)
	local labels = {}
	for _, entry in ipairs(world.ns.ToyMenuEntries(itemID)) do
		labels[#labels + 1] = entry.label
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
	hasNot(MenuLabels(world, PIRATE), "Add to " .. name, "not in toy menus")
	list({ world.ns.SetToy(row.macro, ORB, true) }, { nil, message }, "its toys can't be changed")
	if slot then
		world:TakeErrors()
		world:PressBar(slot)
		eq(#world.used, 0, "never other toys")
		list(world:TakeErrors(), { message }, "clicking it says why")
	end
end

-- The toys in a macro's drawer, in order, as its buttons hold them.
local function DrawerToys(world, name)
	local drawer = assert(world.ns.GetDrawer(Macro(world, name).id), "no drawer")
	local toys = {}
	for i = 1, drawer.count do
		toys[i] = drawer.buttons[i]:GetAttribute("item")
	end
	return toys
end

local function DrawerOpen(world, name)
	return world.ns.GetDrawer(Macro(world, name).id).frame:IsShown()
end

-- Journey 14's step: click a toy in the open drawer.
local function ClickInDrawer(world, name, itemID)
	local drawer = world.ns.GetDrawer(Macro(world, name).id)
	for i = 1, drawer.count do
		local button = drawer.buttons[i]
		if button:GetAttribute("item") == itemID then
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
local OLD_FAVORITES_LINE = "/click [btn:2]ClickyP0;ClickyButton" -- 0.4.0's
local CODE_PATTERN = "Clicky(" .. ("[BCDFGHJKLMNPQRSTVWXZ]"):rep(4) .. ")%f[%W]"

-- The code a body's /click line clicks, or nil.
local function CodeOf(body)
	return body:match(CODE_PATTERN)
end

-- The macro's code, as Clicky holds it.
local function Code(world, name)
	return Macro(world, name).id
end

-- The macros in a 0.4.0 world after Clicky converted them: each body is the current format.
local function ExpectConverted(world, index, positions, what)
	local ns = world.ns
	local body = world.macros[index].body
	local code = CodeOf(body)
	ok(code, (what or "converted") .. ": the /click line has a code: " .. body)
	eq(body, ns.NewBody(code, ns.EncodeToys(positions)), what or "converted")
	return code
end

describe("journeys", function()
	it("1. Discover macros: the panel lists Favorites, collapsed, and the hint", function()
		local world = World()
		list(PanelTexts(world), { "Favorites", "Right-click a toy to make one." })
		eq(PanelRow(world, "Favorites").count, 2, "Favorites' count")
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
		eq(world:LastError(), "No usable toys in Illusion.")
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
		list(world:TakeErrors(), { "No usable toys in Illusion." })
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
		for _, line in ipairs(world.prints) do
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
		world:CreateMacroInUI("Typed", "/click [btn:2]ClickyPFVRT;ClickyFVRT\n#clicky " .. ns.EncodeToys({ 0 }))
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
		eq(select(2, world.env.C_ToyBox.GetToyInfo(PIRATE)), nil, "the game has no name for it yet")
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

	it("4. Add toys: the toy menu's entry flips, and the macro itself holds the toys", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		MakeMacro(world, HAT, "Illusion mod")
		list(MenuLabels(world, ORB), { "Add to Illusion", "Add to Illusion mod" })
		AddTo(world, ORB, "Illusion")
		AddTo(world, ORB, "Illusion mod")
		list(MenuLabels(world, ORB), { "Remove from Illusion", "Remove from Illusion mod" })
		list(PanelTexts(world), { "Favorites", "Illusion", "  Orb of Deception", "  Pirate's Costume",
			"Illusion mod", "  Orb of Deception", "  Pirate Hat" })
		-- The macro itself holds the toys: a computer with no saved data reads them back.
		list(PanelToys(NextLogin(world), "Illusion"), { "Orb of Deception", "Pirate's Costume" })
	end)

	it("4. Add toys: a macro holds up to 150 toys; the 151st is refused with the reason", function()
		local toys = {}
		for i = 1, 151 do toys[i] = { id = 1000 + i * 7, name = ("Toy %03d"):format(i) } end
		local world = World({ toys = toys })
		MakeMacro(world, toys[1].id, "Big")
		for i = 2, 150 do AddTo(world, toys[i].id, "Big") end
		eq(PanelRow(world, "Big").count, 150)
		ok(#world:FindMacroByName("Big").body <= 255, "150 toys fit")
		list({ world.ns.SetToy(Macro(world, "Big"), toys[151].id, true) }, { nil, "Big is full: a macro holds up to 150 toys." })
		has(MenuLabels(world, toys[151].id), "Add to Big", "the entry is unchanged")
		eq(PanelRow(world, "Big").count, 150, "still 150")
		assert(world.ns.SetToy(Macro(world, "Big"), toys[150].id, false))
		AddTo(world, toys[151].id, "Big")
		has(PanelToys(world, "Big"), "Toy 151")
		list(PanelToys(NextLogin(world), "Big"), PanelToys(world, "Big"), "all 150 read back on another computer")
	end)

	it("4. Add toys: a macro the player filled with their own lines refuses with the reason", function()
		local toys = {}
		for i = 1, 300 do toys[i] = { id = 1000 + i, name = ("Toy %03d"):format(i) } end
		local world = World({ toys = toys })
		MakeMacro(world, toys[1].id, "Illusion")
		world:EditMacroInUI(1, nil, world.macros[1].body .. "\n/say " .. ("x"):rep(255))
		eq(#world.macros[1].body, 255, "as full as /macro lets it be")
		list({ world.ns.SetToy(Macro(world, "Illusion"), toys[300].id, true) },
			{ nil, "That macro is too long to update. Remove your own lines from it in /macro." })
		has(MenuLabels(world, toys[300].id), "Add to Illusion", "unchanged")
		ok(#world.macros[1].body <= 255)
	end)

	it("4. Add toys: a data line goes right after the /click line, keeping the player's lines in order", function()
		local ns = World().ns
		eq(ns.SetDataLine("#showtooltip\n/click ClickyBCDF\n/say hi", "abc"),
			"#showtooltip\n/click ClickyBCDF\n#clicky abc\n/say hi")
		eq(ns.SetDataLine("#showtooltip\n/click ClickyBCDF\n#clicky old\n/say hi", "abc"),
			"#showtooltip\n/click ClickyBCDF\n#clicky abc\n/say hi", "an existing one is replaced in place")
	end)

	it("4. Add toys: 150 toys fit in a macro while Clicky's toy list has up to 12,501 toys", function()
		local ns = World().ns
		eq(ns.MACRO_TOY_CAP, 150)
		local shipped = {}
		assert(loadfile("ToyList.lua"))("Clicky", shipped)
		local listed = #shipped.TOY_IDS
		ok(listed > 1000, "ToyList.lua lists the game's toys")
		-- Codec.lua's arithmetic.
		eq(#ns.ClickLine("BCDF"), 36, "the /click line, a fixed length")
		local chars = ns.MACRO_BODY_LIMIT - 36 - 1 - #"#clicky "
		eq(chars, 210, "data characters")
		local bits = (chars - 1 - 2) * 6
		eq(bits, 1242, "bits for the positions, after the header and the checksum")
		eq(150 * 7 + math.floor((12501 - 150) / 64), 1242, "the worst case with Rice parameter 6, over 12,501 toys")
		ok(150 * 7 + math.floor((12502 - 150) / 64) > 1242, "and 12,502 toys is one too many")
		local function Longest(toys, k)
			-- The longest encoding for k toys out of the list's toys: one gap as big as it can be
			-- (Codec.lua's bound), and the same toys spread evenly for good measure.
			local tail, spread = {}, {}
			for i = 1, k do
				tail[i] = toys - k + i - 1
				spread[i] = math.floor((i - 1) * toys / k)
			end
			local a = ns.NewBody("BCDF", assert(ns.EncodeToys(tail)))
			local b = ns.NewBody("BCDF", assert(ns.EncodeToys(spread)))
			return math.max(#a, #b)
		end
		for toys = 1, listed do
			local k = math.min(ns.MACRO_TOY_CAP, toys)
			local length = Longest(toys, k)
			if length > ns.MACRO_BODY_LIMIT then
				error(("%d toys out of %d take %d characters"):format(k, toys, length))
			end
		end
		for k = 1, ns.MACRO_TOY_CAP do
			ok(Longest(listed, k) <= ns.MACRO_BODY_LIMIT, k .. " of the shipped list's toys")
			ok(Longest(12501, k) <= ns.MACRO_BODY_LIMIT, k .. " of 12,501 toys")
		end
	end)

	it("4. Add toys: the toys read back exactly, whatever the collection", function()
		local ns = World().ns
		math.randomseed(7)
		for _ = 1, 300 do
			local owned = math.random(1, 4095)
			local k = math.random(0, math.min(ns.MACRO_TOY_CAP, owned))
			local chosen, positions = {}, {}
			while #positions < k do
				local p = math.random(0, owned - 1)
				if not chosen[p] then
					chosen[p] = true
					positions[#positions + 1] = p
				end
			end
			table.sort(positions)
			local got = assert(ns.DecodeToys(assert(ns.EncodeToys(positions))))
			eq(got.format, 5)
			list(got.positions, positions)
		end
		eq(#ns.EncodeToys({}), 3, "no toys: the header and the checksum")
		list(assert(ns.DecodeToys(ns.EncodeToys({}))).positions, {}, "and it reads back as none")
		local good = ns.EncodeToys({ 0, 1, 5, 40, 300, 301, 1100 })
		eq(#good, 14, "the header character, 11 characters of positions, then the checksum")
		list({ ns.DecodeToys(good:sub(1, 2)) }, { nil, "damaged" }, "too short")
		list({ ns.DecodeToys(good:sub(1, -2)) }, { nil, "damaged" }, "cut off")
		for i = 2, #good do
			-- Any one character typed differently, as a hand edit in /macro might: never other toys.
			local c = good:sub(i, i) == "A" and "B" or "A"
			list({ ns.DecodeToys(good:sub(1, i - 1) .. c .. good:sub(i + 1)) }, { nil, "damaged" }, "character " .. i .. " changed")
		end
		list({ ns.DecodeToys(good:sub(1, 7) .. "|" .. good:sub(9)) }, { nil, "damaged" }, "not the alphabet")
		list({ ns.DecodeToys("w" .. good:sub(2)) }, { nil, "newer" }, "a newer format")
		list({ ns.DecodeToys("I" .. good:sub(2)) }, { nil, "damaged" }, "format 1, a development build's")
		list({ ns.DecodeToys("Q" .. good:sub(2)) }, { nil, "damaged" }, "format 2, a development build's")
		list({ ns.DecodeToys("g" .. good:sub(2)) }, { nil, "damaged" }, "format 4 without its numbers")
		list(ns.CheckNumbers({ 1, 2, 3 }), ns.CheckNumbers({ 3, 1, 2 }), "check numbers don't depend on order")
		ok(not ns.SameChecks(ns.CheckNumbers({ 1, 2, 3 }), ns.CheckNumbers({ 1, 2, 4 })), "they depend on the toys")
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
			"Right-click a toy to make one." })
	end)

	it("5. See a macro: an open macro with no toys says how to add them", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		assert(world.ns.SetToy(m, PIRATE, false))
		world.env.C_ToyBox.SetIsFavorite(WINGS, false)
		world.env.C_ToyBox.SetIsFavorite(CHEST, false)
		world.ns.expanded[world.ns.FAVORITES_ID] = true
		list(PanelTexts(world), { "Favorites", "Star toys to add them.", "Illusion",
			"Right-click toys to add them." })
	end)

	it("6. Remove a toy: other macros keep it", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		MakeMacro(world, ORB, "Tricks")
		assert(world.ns.SetToy(Macro(world, "Illusion"), ORB, false))
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
		full.ns.PickupMacro(full.ns.favorites)
		eq(full.cursor, nil, "nothing to drop")
		list(full:TakeErrors(), { FULL })
	end)

	it("7. Put a macro on a bar: clicking a macro with no toys says how to add some", function()
		local world = World()
		world.env.C_ToyBox.SetIsFavorite(WINGS, false)
		world.env.C_ToyBox.SetIsFavorite(CHEST, false)
		PutOnBar(world, "Favorites", 1)
		local m = MakeMacro(world, PIRATE, "Illusion")
		assert(world.ns.SetToy(m, PIRATE, false))
		PutOnBar(world, "Illusion", 2)
		world:TakeErrors()
		world:PressBar(1)
		world:PressBar(2)
		list(world:TakeErrors(), { "Favorites has no toys. Star toys in the Toy Box to add them.",
			"Illusion has no toys. Right-click toys in the Toy Box to add them." })
	end)

	it("7. Put a macro on a bar: Favorites uses its existing macro, whatever it's called", function()
		local world = World({ macros = { { name = "Stars", icon = "x", body = "#showtooltip\n" .. FAVORITES_LINE } } })
		eq(PanelRow(world, "Stars").macro, world.ns.favorites, "Favorites, by its macro's name")
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

	it("7. Put a macro on a bar: a player's macro clicking ClickyButton another way isn't Favorites'", function()
		local mine = "/click ClickyButton\n/say Party time!"
		local world = World({ macros = { { name = "Party", icon = "x", body = mine } } })
		world.ns.PickupMacro(world.ns.favorites)
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
		eq(world.ns.GetDrawer(code).count, 1)
		assert(world.ns.DeleteMacro(Macro(world, "Illusion")))
		list(PanelTexts(world), { "Favorites", "Right-click a toy to make one." })
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
		list(PanelTexts(world), { "Favorites", "Right-click a toy to make one." })
	end)

	it("8. Upkeep: every macro change is refused in combat", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		local before = world.macros[1].body
		world:EnterCombat()
		list({ world.ns.MakeMacro("Other", ORB) }, { nil, COMBAT }, "make")
		list({ world.ns.SetToy(m, ORB, true) }, { nil, COMBAT }, "add a toy")
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
		list({ world.ns.SetToy(Macro(world, "Illusion"), 400, true) }, { nil, UNKNOWN_TOY }, "nor can it be added")
		eq(#world.macros, 1, "no macro made")
		eq(world.macros[1].body, before, "nothing changed")
		-- Clicky updated for the patch: the same macro takes it.
		local updated = NextLogin(world, { toyList = With(ALL_TOYS, 400) })
		AddTo(updated, 400, "Illusion")
		list(updated.ns.GetMacroToys(Macro(updated, "Illusion"), true), { 400, PIRATE })
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
			has(later.ns.GetMacroToys(Macro(later, "Illusion"), true), HAT, "the toy that left")
			list(PanelToys(later, "Loot"), { "Treasure Chest" }, "other macros work")
			assert(later.ns.SetToy(Macro(later, "Illusion"), HAT, false))
			eq(PanelRow(later, "Illusion").count, 2, "removed from the panel")
			hasNot(later.ns.GetMacroToys(Macro(later, "Illusion"), true), HAT)
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
		list(later.ns.GetMacroToys(Macro(later, "Illusion"), true), { HAT, PIRATE })
	end)

	it("10. Update Clicky: a macro saved by 0.4.0 keeps its toys and is saved in the new format", function()
		local world = World({ macros = { { name = "Illusion", icon = 1001, body = V040_PIRATE_HAT } } })
		world.bars[1] = world.macros[1]
		local code = ExpectConverted(world, 1, { 0, 3 }, "saved again in format 5, the Pirate's Costume and the Pirate Hat")
		local converted = world.macros[1].body
		eq(converted:match("^[^\n]*"), Line(code), "with a code in place of 0.4.0's number")
		eq(Code(world, "Illusion"), code, "which is the macro's id")
		eq(world.env.ClickySet1:GetAttribute("type"), nil, "the old button is emptied")
		list(PanelToys(world, "Illusion"), { "Pirate Hat", "Pirate's Costume" })
		list(UsedToys(world, 1), { PIRATE, HAT }, "the bar button uses both")
		world:Slash("/clicky debug")
		local all = table.concat(world.prints, "\n")
		ok(all:find("format 4 scan: item IDs 1%-50300 in"), "the scan ran, to read it: " .. all)
		ok(all:find("state ready, data %d+ chars, format 5, 2 toys"), all)
		ok(not all:find("needs re%-saving"), all)
		eq(NextLogin(world).macros[1].body, converted, "and a later login leaves it as it is")
		-- A macro with no toys converts too.
		local empty = World({ macros = { { name = "Illusion", icon = 1001, body = V040_EMPTY } } })
		ExpectConverted(empty, 1, {})
		eq(PanelRow(empty, "Illusion").count, 0)
	end)

	it("10. Update Clicky: a macro saved by 0.4.0 still converts after a patch adds toys above its highest item ID", function()
		local toys = Toys()
		toys[#toys + 1] = { id = 400, name = "New 400", owned = false }
		local world = World({ toys = toys, macros = { { name = "Illusion", icon = 1001, body = V040_PIRATE_HAT } } })
		ExpectConverted(world, 1, { 0, 3 }, "the same toys, in format 5")
		AddTo(world, 400, "Illusion")
		list(PanelToys(world, "Illusion"), { "New 400", "Pirate Hat", "Pirate's Costume" })
	end)

	it("10. Update Clicky: Favorites' macro from 0.4.0 gets the new /click line, once, and keeps working", function()
		local old = "#showtooltip\n" .. OLD_FAVORITES_LINE .. "\n/say hi"
		local world = World({ macros = { { name = "Stars", icon = "x", body = old } } })
		world.bars[1] = world.macros[1]
		local new = "#showtooltip\n" .. FAVORITES_LINE .. "\n/say hi"
		eq(world.macros[1].body, new, "the line is replaced, the player's own lines kept")
		eq(PanelRow(world, "Stars").macro, world.ns.favorites, "still Favorites")
		world:PressBar(1)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "its toy button works")
		world:Advance(1)
		world:PressBar(1, "RightButton")
		list(DrawerToys(world, "Stars"), { WINGS, CHEST }, "and its drawer")
		ok(world.ns.GetDrawer(world.ns.FAVORITES_ID).frame:IsShown(), "which opens")
		eq(NextLogin(world).macros[1].body, new, "and a later login leaves it as it is")
	end)

	it("10. Update Clicky: logging in during combat, Favorites' macro from 0.4.0 is rewritten when combat ends", function()
		local world = World({ combat = true, macros = { { name = "Favorites", icon = "x", body = OLD_FAVORITES_LINE } } })
		world.bars[1] = world.macros[1]
		eq(world.macros[1].body, OLD_FAVORITES_LINE, "nothing written in combat")
		world:Slash("/clicky debug")
		has(world.prints, "|cff33ff99Clicky|r: waiting: Favorites' macro to update: 1, buttons to make: 1")
		world:LeaveCombat()
		eq(world.macros[1].body, FAVORITES_LINE, "rewritten")
		world:PressBar(1)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "and it works")
		world.prints = {}
		world:Slash("/clicky debug")
		has(world.prints, "|cff33ff99Clicky|r: waiting: nothing")
	end)

	it("11. Can't be read: a macro from 0.4.0 saved against different game toys isn't converted", function()
		-- Made while the game had no Gnomish Gravity Well (103): now it does.
		local world = World({ macros = { { name = "Illusion", icon = 1001, body = V040_FIVE_TOYS } } })
		world.bars[1] = world.macros[1]
		ExpectUnreadable(world, "Illusion", UNREADABLE, 1)
		eq(world.macros[1].body, V040_FIVE_TOYS, "left as it is, with its old /click line")
		-- An old item turned into a toy inside its list, since it was saved.
		local toys = Toys()
		toys[#toys + 1] = { id = 110, name = "Old item", owned = false }
		local patched = World({ toys = toys, macros = { { name = "Illusion", icon = 1001, body = V040_PIRATE_HAT } } })
		patched.bars[1] = patched.macros[1]
		ExpectUnreadable(patched, "Illusion", UNREADABLE, 1)
		eq(patched.macros[1].body, V040_PIRATE_HAT, "left as it is")
		assert(patched.ns.DeleteMacro(Macro(patched, "Illusion")))
		MakeMacro(patched, PIRATE, "Illusion")
		PutOnBar(patched, "Illusion", 1)
		list(UsedToys(patched, 1), { PIRATE }, "made again, it works")
	end)

	it("11. Can't be read: a macro from 0.4.0 holding a toy missing from Clicky's list isn't converted", function()
		-- The game has the Pirate Hat (201), so the macro's list matches; Clicky's list doesn't.
		local world = World({ toyList = { PIRATE, ORB, GNOME, WINGS, CHEST },
			macros = { { name = "Illusion", icon = 1001, body = V040_PIRATE_HAT } } })
		world.bars[1] = world.macros[1]
		ExpectUnreadable(world, "Illusion", UNREADABLE, 1)
		eq(world.macros[1].body, V040_PIRATE_HAT, "left as it is")
	end)

	it("10. Update Clicky: logging in during combat, a macro from 0.4.0 works, and is converted when combat ends", function()
		local world = World({ combat = true, macros = {
			{ name = "Illusion", icon = 1001, body = V040_PIRATE_HAT },
			{ name = "Illusion 2", icon = 1001, body = V040_PIRATE_HAT } } })
		local ns = world.ns
		world.bars[1], world.bars[2] = world.macros[1], world.macros[2]
		local m = Macro(world, "Illusion")
		eq(PanelRow(world, "Illusion").unreadable, nil, "readable")
		local ready = ns.GetCandidates(m, true)
		table.sort(ready)
		list(ready, { PIRATE, HAT }, "its toys are usable")
		eq(world.macros[1].body, V040_PIRATE_HAT, "nothing written in combat")
		eq(world.macros[2].body, V040_PIRATE_HAT)
		world:Slash("/clicky debug")
		has(world.prints, "|cff33ff99Clicky|r: waiting: buttons to make: 2, copies to separate: 1, macros to re-save: 1")
		ns.SetTracing(true)
		world.prints = {}
		world:LeaveCombat()
		local first = ExpectConverted(world, 1, { 0, 3 }, "converted")
		local second = ExpectConverted(world, 2, { 0, 3 }, "and its copy")
		ok(first ~= second, "with a button of its own")
		-- The copy got its code when it was separated; converting it keeps that code.
		local recoded = 0
		for _, line in ipairs(world.prints) do
			if line:find("converted from format 4", 1, true) and line:find(", button ", 1, true) then
				recoded = recoded + 1
			end
		end
		eq(recoded, 1, "only the macro that still had 0.4.0's number was given a code in converting")
		list(UsedToys(world, 1), { PIRATE, HAT })
		list(UsedToys(world, 2), { PIRATE, HAT })
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

	it("11. Can't be read: a damaged macro never loads toys, says so, and can be renamed or deleted", function()
		local world = World()
		local ns = world.ns
		-- The right toys, but a character typed over.
		local data = ns.EncodeToys({ 0, 1 })
		world.bars[1] = world:CreateMacroInUI("Broken", ns.NewBody("BRKN", data:sub(1, -2) .. (data:sub(-1) == "A" and "B" or "A")))
		ExpectUnreadable(world, "Broken", UNREADABLE, 1)
		world.bars[2] = world:CreateMacroInUI("Cut", ns.NewBody("CTXX", ns.EncodeToys({ 0, 1, 5, 40, 300 }):sub(1, 6)))
		world:PressBar(2)
		eq(#world.used, 0, "a cut-off line loads nothing either")
		assert(ns.RenameMacro(Macro(world, "Broken"), "Fixed later"))
		ok(world:FindMacroByName("Fixed later"), "it can be renamed")
		assert(ns.DeleteMacro(Macro(world, "Fixed later")))
		eq(#world.macros, 1, "it can be deleted")
	end)

	it("11. Can't be read: a macro saved by a newer Clicky says to update", function()
		local world = World()
		local ns = world.ns
		local data = ns.EncodeToys({ 0 })
		world:CreateMacroInUI("Future", ns.NewBody("FTRX", "w" .. data:sub(2)))
		ExpectUnreadable(world, "Future", NEWER)
	end)

	it("11. Can't be read: a macro the player breaks in /macro can't be changed", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		local broken = world.macros[1].body:gsub("\n#clicky .*", "\n#clicky broken")
		world:EditMacroInUI(1, nil, broken)
		list({ world.ns.SetToy(Macro(world, "Illusion"), ORB, true) }, { nil, UNREADABLE })
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
			if row.itemID then eq(row.owned, row.itemID == PIRATE, "only the owned toy looks owned") end
		end
		eq(PanelRow(other, "Pasted").count, 2)
		other:Advance(1) -- drawers are filled a few at a time
		list(DrawerToys(other, "Pasted"), { PIRATE }, "the drawer has only toys it can use")
		has(MenuLabels(other, ORB), "Remove from Pasted", "an unowned toy can still be taken out")
		assert(other.ns.SetToy(Macro(other, "Pasted"), ORB, false))
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
		assert(world.ns.SetToy(Macro(world, "Costumes"), ORB, false))
		list(UsedToys(world, 2), { PIRATE })
		list(UsedToys(world, 1), { PIRATE, ORB }, "the original is unchanged")
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

	it("12. Copy a macro: a copy that can't get its own button says why, once, and waits", function()
		-- 0.4.0 macros that can't be converted (see journey 11) and whose /click line is shorter
		-- than a code's, padded with the player's own lines to the 255 characters /macro allows:
		-- the copy has no room for a code.
		local body = V040_FIVE_TOYS .. "\n/say " .. ("x"):rep(255)
		body = body:sub(1, 255)
		local world = World({ macros = { { name = "M1", icon = 1001, body = body },
			{ name = "M1 copy", icon = 1001, body = body } } })
		world:Slash("/clicky debug")
		local message = "|cff33ff99Clicky|r: M1 copy is a copy of another Clicky macro and couldn't be separated from it. "
			.. "That macro is too long to update. Remove your own lines from it in /macro."
		local times = 0
		for _, line in ipairs(world.prints) do
			if line == message then times = times + 1 end
		end
		eq(times, 1, "printed once, though every sync tries again")
		has(world.prints, "|cff33ff99Clicky|r: waiting: copies to separate: 1")
		eq(world:FindMacroByName("M1 copy").body, body, "left as it is")
		eq(world:FindMacroByName("M1").body, body, "and so is the original")
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
		later:Slash("/clicky debug")
		has(later.prints, "|cff33ff99Clicky|r: waiting: buttons to make: 2, copies to separate: 1")
		eq(later.macros[1].body, before, "nothing written in combat")
		eq(later.macros[2].body, before)
		later:LeaveCombat()
		eq(later.macros[1].body, before, "nothing to re-save")
		local copyCode = CodeOf(later.macros[2].body)
		ok(copyCode and copyCode ~= CodeOf(before), "the copy has a code of its own: " .. later.macros[2].body)
		eq(later:PressBar(1) and later:LastUsed(), PIRATE)
		eq(later:PressBar(2) and later:LastUsed(), PIRATE)
		eq(#later.used, 2)
		later.prints = {}
		later:Slash("/clicky debug")
		has(later.prints, "|cff33ff99Clicky|r: waiting: nothing")
	end)

	-- The format Clicky writes into players' macros, exactly as written. Macros live in players'
	-- games, so it must keep reading as it did; a new format version needs a sample here before
	-- this test passes.
	local WRITTEN_FORMATS = {
		-- Format 5: places 0, 3 and 40.
		[5] = { data = "rAvTtd", positions = { 0, 3, 40 } },
	}
	-- Format 4 (0.4.0) is only read, to convert it.
	local FORMAT_4 = { data = "gAAlgAwAPxGLWZkHzieCBNLWI3kaW85vYmpr/ir2Xv55+LVKiUvhpguo/vw3XSjf0c",
		highest = 300, count = 6, positions = { 0, 3 } }

	it("Saved macros: every format Clicky writes still reads exactly as it did, and 0.4.0's still reads", function()
		local ns = World().ns
		local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local function Version(data) return math.floor((alphabet:find(data:sub(1, 1), 1, true) - 1) / 8) end
		for version, sample in pairs(WRITTEN_FORMATS) do
			local d = assert(ns.DecodeToys(sample.data), "format " .. version .. " no longer reads")
			eq(d.format, version)
			list(d.positions, sample.positions, "format " .. version)
			eq(ns.EncodeToys(sample.positions), sample.data, "format " .. version .. " is still written the same")
		end
		ok(WRITTEN_FORMATS[Version(ns.EncodeToys({ 0 }))], "the format written has a sample here")
		list({ ns.DecodeToys("w" .. WRITTEN_FORMATS[5].data:sub(2)) }, { nil, "newer" }, "a newer format")
		local d = assert(ns.DecodeToys(FORMAT_4.data), "format 4 no longer reads")
		eq(d.format, 4)
		eq(d.count, FORMAT_4.count)
		eq(d.highest, FORMAT_4.highest)
		list(d.positions, FORMAT_4.positions)
		-- Format 3 (written by 0.3.0-alpha1) had no checksum, so it could be edited into other toys.
		list({ ns.DecodeToys("YAAlgAwAPxGLWZkHzieCBNLWI3kaW85vYmpr/ir2Xv55+LVKiUvhpguo/vw3XSjf") }, { nil, "damaged" },
			"format 3 reads as damaged")
	end)

	it("14. Use the drawer: a toy whose data hasn't loaded yet still has its icon", function()
		local world = World()
		world.toys[HAT].loading = true
		eq(select(3, world.env.C_ToyBox.GetToyInfo(HAT)), nil, "the game has no icon for it yet")
		eq(world.ns.ToyIcon(HAT), 2001, "the icon the drawer and the panel show")
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
		eq(later.ns.GetDrawer(code).count, 0, "not filled yet")
		later:Advance(1)
		eq(later.ns.GetDrawer(code).count, 2, "filled soon after login")
		eq(later.ns.GetDrawer(later.ns.FAVORITES_ID).count, 2)
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
		assert(world.ns.RenameMacro(world.ns.favorites, "Stars"))
		eq(world.macros[1].name, "Stars", "renamed")
		eq(world.ns.PanelRows()[1].macro.name, "Stars", "still first in the panel")
		world:PressBar(1)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "still works on the bar")
		list({ world.ns.MakeMacro("stars", PIRATE) }, { nil, "There's already a macro called Stars." })
		assert(world.ns.DeleteMacro(world.ns.favorites))
		eq(#world.macros, 0, "deleted")
		eq(world.ns.PanelRows()[1].macro, world.ns.favorites, "Favorites stays in the panel")
		PutOnBar(world, "Stars", 2)
		eq(#world.macros, 1, "made again when dragged")
		eq(world.macros[1].body, FAVORITES_LINE)
	end)

	it("Debugging: /clicky status and debug report on macros", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		world:CreateMacroInUI("Broken", "/click ClickySet4\n#clicky broken")
		world:Advance(1) -- drawers are filled a few at a time after login
		world:Slash("/clicky status")
		has(world.prints, "|cff33ff99Clicky|r: 6 toys owned.")
		has(world.prints, "|cff33ff99Clicky|r: Broken: " .. UNREADABLE)
		world:Slash("/clicky debug")
		local all = table.concat(world.prints, "\n")
		ok(all:find("toy list: 6 toys from build test %(game counts 6%), owned: 6"), all)
		ok(not all:find("format 4 scan"), "no scan without a format 4 macro: " .. all)
		ok(all:find("a macro holds up to 150 toys\n"), all)
		local button = "Clicky" .. Code(world, "Illusion")
		ok(all:find("Illusion %(" .. button .. "%).-state ready, data %d+ chars, format 5, 1 toys"), all)
		ok(all:find("state unreadable %(damaged%)"), all)
		ok(all:find("Illusion %(" .. button .. "%).-ready for combat nil, drawer 1 toys"), all)
		ok(all:find("Favorites %(ClickyFVRT%).-ready for combat nil, drawer 2 toys, .-macro: none, state ready"), all)
	end)

	-- The Toy Box filters are the player's own saved settings: changing them outlives the addon.
	it("Never changes the player's settings: the code calls no setting-changing function", function()
		local forbidden = { "SetCollectedShown", "SetUncollectedShown", "SetUnusableShown",
			"SetSourceTypeFilter", "SetExpansionTypeFilter", "SetAllSourceTypeFilters",
			"SetAllExpansionTypeFilters", "SetFilterString", "ForceToyRefilter", "SetDefaultFilters",
			"SetCVar", "ConsoleExec", "SaveBindings", "SetBinding(" }
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

	it("12. Copy a macro: a copy made where Clicky wasn't running gets its own button at the next login", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		-- Copied in /macro on a computer without Clicky (or with it disabled): WoW saves it to
		-- the account as it is.
		table.insert(world.account.macros, { name = "Illusion 2", body = world.macros[1].body })
		local original = CodeOf(world.macros[1].body)
		local later = Finishes(function() return NextLogin(world) end, "logging in")
		local codes = Codes(later)
		ok(#codes == 2 and AllDifferent(codes), "each macro clicks its own button")
		eq(codes[1], original, "the original keeps its own")
	end)

	it("12. Copy a macro: two copies arriving at login each get their own button", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		table.insert(world.account.macros, { name = "Illusion 2", body = world.macros[1].body })
		table.insert(world.account.macros, { name = "Illusion 3", body = world.macros[1].body })
		local later = Finishes(function() return NextLogin(world) end, "logging in")
		local codes = Codes(later)
		ok(#codes == 3 and AllDifferent(codes), "each macro clicks its own button")
	end)

	it("12. Copy a macro: a 0.4.0 macro and its copy, separated before they convert, get different codes", function()
		local world = World({ macros = {
			{ name = "Illusion", icon = 1001, body = V040_PIRATE_HAT },
			{ name = "Illusion 2", icon = 1001, body = V040_PIRATE_HAT } } })
		world.bars[1], world.bars[2] = world.macros[1], world.macros[2]
		local first = ExpectConverted(world, 1, { 0, 3 })
		local second = ExpectConverted(world, 2, { 0, 3 })
		ok(first ~= second, "each macro clicks its own button")
		list(UsedToys(world, 1), { PIRATE, HAT })
		list(UsedToys(world, 2), { PIRATE, HAT })
	end)

	it("12. Copy a macro: 0.4.0's ids with a leading zero are ids of their own, and convert too", function()
		local zero = V040_PIRATE_HAT:gsub("ClickyP1;ClickySet1", "ClickyP01;ClickySet01")
		local world = World({ macros = {
			{ name = "Illusion", icon = 1001, body = V040_PIRATE_HAT },
			{ name = "Zed", icon = 1001, body = zero } } })
		Finishes(function() world:Fire("UPDATE_MACROS") end, "syncing")
		local first = ExpectConverted(world, 1, { 0, 3 })
		local second = ExpectConverted(world, 2, { 0, 3 })
		ok(first ~= second, "each macro clicks its own button")
	end)

	it("12. Copy a macro: copies arriving at login don't take a code another macro clicks", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		MakeMacro(world, ORB, "Orb")
		table.insert(world.account.macros, { name = "Orb 2", body = world.macros[2].body })
		local later = Finishes(function() return NextLogin(world) end, "logging in")
		local codes = Codes(later)
		ok(#codes == 3 and AllDifferent(codes), "each macro clicks its own button")
	end)

	-- Hand edits the checksum is meant to catch (Codec.lua: "a hand-edited line then reads
	-- as damaged rather than as other toys"; journey 11: "It never uses toys that weren't put in it").
	local function RealisticData(ns)
		-- 40 toys in a row out of 1,000: runs of zero bits, so "A" (0) characters in the toys.
		local positions = {}
		for i = 1, 40 do positions[i] = 100 + i end
		return ns.EncodeToys(positions), positions
	end

	it("11. Can't be read: the first character typed as another format never reads as other toys", function()
		local ns = World().ns
		local data, positions = RealisticData(ns)
		local alphabet = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
		local header = alphabet:find(data:sub(1, 1), 1, true) - 1
		local r = header % 8
		for version = 0, 7 do
			local edited = alphabet:sub(version * 8 + r + 1, version * 8 + r + 1) .. data:sub(2)
			local d = ns.DecodeToys(edited)
			ok(d == nil or table.concat(d.positions, ",") == table.concat(positions, ","),
				"format " .. version .. " reads as other toys: " .. (d and table.concat(d.positions, ",") or ""))
		end
	end)

	it("11. Can't be read: one character deleted or added never reads as other toys", function()
		local ns = World().ns
		local data, positions = RealisticData(ns)
		local want = table.concat(positions, ",")
		for i = 2, #data - 1 do
			for _, edited in ipairs({ data:sub(1, i - 1) .. data:sub(i + 1), data:sub(1, i - 1) .. "A" .. data:sub(i) }) do
				local d = ns.DecodeToys(edited)
				ok(d == nil or table.concat(d.positions, ",") == want,
					("character %d deleted or an A added there reads as %s"):format(i, d and table.concat(d.positions, ",") or ""))
			end
		end
	end)

	it("11. Can't be read: right-clicking it on a bar says why, as a click does", function()
		local world = World()
		local ns = world.ns
		local data = ns.EncodeToys({ 0, 1 })
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
		assert(world.ns.SetToy(Macro(world, "Costumes"), ORB, false))
		world:PressBar(2, "RightButton")
		ok(DrawerOpen(world, "Costumes"), "its own drawer opened")
		list(DrawerToys(world, "Costumes"), { PIRATE })
		ok(not DrawerOpen(world, "Illusion"), "not the original's")
	end)

end)
