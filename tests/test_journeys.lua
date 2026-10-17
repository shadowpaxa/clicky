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
local NEW_TOY = 150 -- sorts between the others, so learning it moves later toys' positions

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

-- The same account logging in again: on the same computer (its saved data) or another (none).
local function NextLogin(world, options)
	options = options or {}
	options.account = world.account
	return wow.New(options)
end

local COMBAT = "Can't change macros in combat."
local FULL = "Your general macros are full. Delete one in /macro and try again."
local UNREADABLE = "Clicky can't read this macro's toys. Delete it and make it again."
local NEWER = "This macro was saved by a newer version of Clicky. Update Clicky to use it."
local function Lost(n)
	return ("Clicky can't work out which toys this macro holds: %d toys were added to the game since "
		.. "it was saved, more than the 16 it can catch up on. Delete it and make it again."):format(n)
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

describe("journeys", function()
	it("1. Discover macros: the panel lists Favorites, collapsed, and the hint", function()
		local world = World()
		list(PanelTexts(world), { "Favorites", "Right-click a toy, then Add to new macro..." })
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
		world:FailHere(PIRATE)
		world:PressBar(1)
		world:PressBar(1)
		eq(world:LastError(), "No usable toys in Illusion.")
		world:ChangeZone()
		world:PressBar(1)
		eq(world:LastUsed(), PIRATE, "a new zone gives a failed toy another chance")
	end)

	it("2. Dress up: a UI error long after a click doesn't count against the toy", function()
		local world = World()
		world:Fire("UI_ERROR_MESSAGE", 0, "secret") -- before any click: nothing to blame
		MakeMacro(world, PIRATE, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world:PressBar(1)
		eq(world:LastUsed(), PIRATE)
		world:Advance(2) -- past the one-second window
		world:Fire("UI_ERROR_MESSAGE", 0, "secret")
		world:PressBar(1)
		eq(#world.used, 2, "picked again")
		eq(world:LastUsed(), PIRATE)
		eq(world:LastError(), nil, "no \"No usable toys\"")
	end)

	it("2. Dress up: a toy on the global cooldown is still picked", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world.toys[ORB].cooldown = 0.5 -- GetItemCooldown reports a 1.5-second duration: the GCD
		list(UsedToys(world, 1), { PIRATE, ORB })
	end)

	it("2. Dress up: does nothing in combat", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world:EnterCombat()
		world:PressBar(1)
		eq(#world.used, 0, "no toy in combat")
		world:LeaveCombat()
		world:PressBar(1)
		eq(world:LastUsed(), PIRATE, "works again after combat")
	end)

	it("2. Dress up: a /click without [nocombat] in combat uses the lined-up toy and changes nothing", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		-- The player's own macro (or a key binding) clicks the button in combat, when its
		-- attributes are locked.
		world.bars[1] = world:CreateMacroInUI("Mine", "/click ClickySet1")
		local linedUp = world.env.ClickySet1:GetAttribute("toy")
		world:EnterCombat()
		world:PressBar(1)
		eq(world:LastUsed(), linedUp, "the toy lined up before combat")
		world:LeaveCombat()
		list(UsedToys(world, 1), { PIRATE, ORB }, "picks again after combat")
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
		ok(macro.body:find("^/click %[nocombat%] ClickySet1\n#clicky "), "its /click line, then its toys: " .. macro.body)
	end)

	it("3. Make a macro: names are cut to 16 characters, on a character boundary", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion modification")
		eq(world.macros[1].name, "Illusion modific")
		has(PanelTexts(world), "Illusion modific")
		eq(world.ns.TruncateMacroName("Illusion modifié"), "Illusion modifi", "\"é\" would be bytes 16-17")
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
		eq(ns.SetDataLine("#showtooltip\n/click [nocombat] ClickySet1\n/say hi", "abc"),
			"#showtooltip\n/click [nocombat] ClickySet1\n#clicky abc\n/say hi")
		eq(ns.SetDataLine("#showtooltip\n/click [nocombat] ClickySet1\n#clicky old\n/say hi", "abc"),
			"#showtooltip\n/click [nocombat] ClickySet1\n#clicky abc\n/say hi", "an existing one is replaced in place")
	end)

	it("4. Add toys: the 150-toy cap fits in one macro while the game has up to 2,900 toys", function()
		local ns = World().ns
		eq(ns.MACRO_TOY_CAP, 150)
		eq(ns.TOY_BOUND, 2900)
		eq(ns.CATCH_UP_LIMIT, 16)
		eq(ns.CHECK_COUNT, 16)
		eq(ns.CHECK_PRIME, 2097143)
		-- Codec.lua's arithmetic.
		eq(#ns.ClickLine(150), 30, "the /click line with a three-digit id")
		local dataChars = ns.MACRO_BODY_LIMIT - 30 - 1 - #"#clicky "
		eq(dataChars, 216)
		eq(dataChars * 6, 1296)
		eq(150 * 5 + math.floor(2750 / 16), 921, "the worst case's positions with Rice parameter 4")
		ok(6 + 21 + 12 + 16 * 21 + 921 <= 1296, "header, highest, count, check numbers and positions fit")
		-- The longest check numbers there are, so nothing depends on their values.
		local checks = {}
		for j = 1, 16 do checks[j] = ns.CHECK_PRIME - 1 end
		local highest = ns.CHECK_PRIME - 1
		local function Longest(toys, k)
			-- The longest encoding for k toys out of the game's toys: one gap as big as it can be
			-- (Codec.lua's bound), and the same toys spread evenly for good measure.
			local tail, spread = {}, {}
			for i = 1, k do
				tail[i] = toys - k + i - 1
				spread[i] = math.floor((i - 1) * toys / k)
			end
			local a = ns.NewBody(150, assert(ns.EncodeToys(highest, toys, checks, tail)))
			local b = ns.NewBody(150, assert(ns.EncodeToys(highest, toys, checks, spread)))
			return math.max(#a, #b)
		end
		for toys = 1, ns.TOY_BOUND do
			local k = math.min(ns.MACRO_TOY_CAP, toys)
			local length = Longest(toys, k)
			if length > ns.MACRO_BODY_LIMIT then
				error(("%d toys out of %d take %d characters"):format(k, toys, length))
			end
		end
		for k = 0, ns.MACRO_TOY_CAP do
			ok(Longest(ns.TOY_BOUND, k) <= ns.MACRO_BODY_LIMIT, k .. " toys")
		end
		ok(Longest(ns.TOY_BOUND, 151) > ns.MACRO_BODY_LIMIT, "the cap is what fits")
	end)

	it("4. Add toys: the toys read back exactly, whatever the collection", function()
		local ns = World().ns
		math.randomseed(7)
		for _ = 1, 300 do
			local owned = math.random(1, 4095)
			local highest = math.random(1, ns.CHECK_PRIME - 1)
			local k = math.random(0, math.min(ns.MACRO_TOY_CAP, owned))
			local pick, positions = {}, {}
			while #positions < k do
				local p = math.random(0, owned - 1)
				if not pick[p] then
					pick[p] = true
					positions[#positions + 1] = p
				end
			end
			table.sort(positions)
			local checks = {}
			for j = 1, 16 do checks[j] = math.random(0, ns.CHECK_PRIME - 1) end
			local got = assert(ns.DecodeToys(assert(ns.EncodeToys(highest, owned, checks, positions))))
			eq(got.highest, highest)
			eq(got.count, owned)
			list(got.checks, checks)
			list(got.positions, positions)
		end
		local zeros = {}
		for j = 1, 16 do zeros[j] = 0 end
		local good = ns.EncodeToys(300, 6, zeros, { 0, 1 })
		eq(#good, 63, "the header character, 62 characters of highest, count and check numbers, then the toys")
		list({ ns.DecodeToys(good:sub(1, 62)) }, { nil, "damaged" }, "too short")
		list({ ns.DecodeToys(good:sub(1, 30) .. "|" .. good:sub(32)) }, { nil, "damaged" }, "not the alphabet")
		list({ ns.DecodeToys("g" .. good:sub(2)) }, { nil, "newer" }, "a newer format")
		list({ ns.DecodeToys("I" .. good:sub(2)) }, { nil, "damaged" }, "an unreleased build's format")
		list({ ns.DecodeToys("Q" .. good:sub(2)) }, { nil, "damaged" }, "the other unreleased format")
		list({ ns.DecodeToys(ns.EncodeToys(300, 2, zeros, { 0, 5 })) }, { nil, "damaged" }, "a position past the count")
		local tooBig = { 2 ^ 21 - 1 }
		for j = 2, 16 do tooBig[j] = 0 end
		list({ ns.DecodeToys(ns.EncodeToys(300, 6, tooBig, { 0 })) }, { nil, "damaged" }, "a check number past the prime")
		list(ns.CheckNumbers({ 1, 2, 3 }), ns.CheckNumbers({ 3, 1, 2 }), "check numbers don't depend on order")
		ok(not ns.SameChecks(ns.CheckNumbers({ 1, 2, 3 }), ns.CheckNumbers({ 1, 2, 4 })), "they depend on the toys")
	end)

	it("10. A patch adds toys: the toys added since are worked out exactly, or not at all", function()
		local ns = World().ns
		math.randomseed(11)
		-- Item IDs like the game's (toys go up to about 286,660).
		local pool, seen = {}, {}
		while #pool < 3017 do
			local id = math.random(1, 286660)
			if not seen[id] then
				seen[id] = true
				pool[#pool + 1] = id
			end
		end
		local function Shuffled()
			local t = { unpack(pool) }
			for i = #t, 2, -1 do
				local j = math.random(i)
				t[i], t[j] = t[j], t[i]
			end
			return t
		end
		local function Sorted(t)
			t = { unpack(t) }
			table.sort(t)
			return t
		end
		for _ = 1, 150 do
			local t = Shuffled()
			local n, m = math.random(1, 1200), math.random(0, 16)
			local before, now = {}, {}
			for i = 1, n do before[i], now[i] = t[i], t[i] end
			for i = n + 1, n + m do now[#now + 1] = t[i] end
			local learned = assert(ns.FindLearned(now, ns.CheckNumbers(now), n, ns.CheckNumbers(before)))
			list(Sorted(learned), Sorted({ unpack(t, n + 1, n + m) }), "the toys added since")
		end
		for _ = 1, 150 do
			-- Toys missing as well as added: refused.
			local t = Shuffled()
			local n = math.random(20, 1200)
			local drop = math.random(1, 10)
			local before, now = {}, {}
			for i = 1, n do before[i] = t[i] end
			for i = drop + 1, n + drop + math.random(0, 16) do now[#now + 1] = t[i] end
			eq(ns.FindLearned(now, ns.CheckNumbers(now), n, ns.CheckNumbers(before)), nil, "never other toys")
		end
		local before, now = {}, {}
		for i = 1, 100 do before[i], now[i] = pool[i], pool[i] end
		for i = 101, 117 do now[i] = pool[i] end
		eq(ns.FindLearned(now, ns.CheckNumbers(now), 100, ns.CheckNumbers(before)), nil, "17 is too many")
		-- A worst case: 3,000 toys, 16 of them added since.
		local big, all = {}, Sorted({ unpack(pool, 1, 3000) })
		for i = 1, 2984 do big[i] = pool[i] end
		local learned = assert(ns.FindLearned(all, ns.CheckNumbers(all), 2984, ns.CheckNumbers(big)))
		list(Sorted(learned), Sorted({ unpack(pool, 2985, 3000) }), "16 out of 3,000")
		eq(ns.FindLearned(before, ns.CheckNumbers(before), 117, ns.CheckNumbers(now)), nil, "fewer toys than before")
	end)

	it("13. A patch takes toys out: one or two are worked out exactly, more are refused", function()
		local ns = World().ns
		math.randomseed(12)
		local pool, seen = {}, {}
		while #pool < 1300 do
			local id = math.random(1, 286660)
			if not seen[id] then
				seen[id] = true
				pool[#pool + 1] = id
			end
		end
		local function Sorted(t)
			t = { unpack(t) }
			table.sort(t)
			return t
		end
		local function Case(n, m)
			local before, now, gone = {}, {}, {}
			for i = 1, n do before[i] = pool[i] end
			for i = 1, n - m do now[i] = pool[i] end
			for i = n - m + 1, n do gone[#gone + 1] = pool[i] end
			return before, now, gone
		end
		for _ = 1, 200 do
			local before, now, gone = Case(math.random(20, 1200), math.random(1, 2))
			local found = assert(ns.FindRemoved(now, ns.CheckNumbers(now), #before, ns.CheckNumbers(before)))
			list(Sorted(found), Sorted(gone), "one or two solved for directly")
		end
		local before, now = Case(500, 3)
		eq(ns.FindRemoved(now, ns.CheckNumbers(now), 500, ns.CheckNumbers(before)), nil, "three is too many")
		for _ = 1, 100 do
			-- Gone and added since: refused, never other toys.
			local b, n = Case(math.random(20, 1200), 2)
			n[#n + 1] = pool[1250]
			eq(ns.FindRemoved(n, ns.CheckNumbers(n), #b, ns.CheckNumbers(b)), nil, "never other toys")
		end
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
		world.ns.expanded[0] = true
		list(PanelTexts(world), { "Favorites", "  Fairy Wings", "  Treasure Chest", "Illusion",
			"  Gnomish Gravity Well", "  Orb of Deception", "  Pirate's Costume" })
	end)

	it("5. See a macro: macros start closed each session", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		list(PanelTexts(NextLogin(world, { saved = world:Saved() })), { "Favorites", "Illusion" })
	end)

	it("5. See a macro: a macro that gets a deleted macro's id starts closed", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion") -- id 1, open when made
		MakeMacro(world, HAT, "Hats")
		world.env.DeleteMacro(1)
		world:CreateMacroInUI("Hats 2", world:FindMacroByName("Hats").body)
		ok(world:FindMacroByName("Hats 2").body:find("ClickySet1%f[%D]"), "the copy took id 1")
		list(PanelTexts(world), { "Favorites", "Hats", "  Pirate Hat", "Hats 2" })
	end)

	it("5. See a macro: Favorites lists the starred toys, however they were starred", function()
		local world = World()
		world.ns.expanded[0] = true
		world.env.C_ToyBox.SetIsFavorite(PIRATE, true)
		list(PanelTexts(world), { "Favorites", "  Fairy Wings", "  Pirate's Costume", "  Treasure Chest",
			"Right-click a toy, then Add to new macro..." })
	end)

	it("5. See a macro: an open macro with no toys says how to add them", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		assert(world.ns.SetToy(m, PIRATE, false))
		world.env.C_ToyBox.SetIsFavorite(WINGS, false)
		world.env.C_ToyBox.SetIsFavorite(CHEST, false)
		world.ns.expanded[0] = true
		list(PanelTexts(world), { "Favorites", "Star toys in the Toy Box to add them.", "Illusion",
			"Right-click toys in the Toy Box to add them." })
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
		eq(world.macros[1].name, "Clicky")
		eq(world.macros[1].body, "/click [nocombat] ClickyButton")
		world:PressBar(1)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "used a favorite")

		local macros = {}
		for i = 1, 120 do macros[i] = { name = "m" .. i, body = "/say " .. i } end
		local full = World({ macros = macros })
		full.ns.PickupMacro(full.ns.favorites)
		eq(full.cursor, nil, "nothing to drop")
		list(full:TakeErrors(), { FULL })
	end)

	it("7. Put a macro on a bar: Favorites uses the existing Clicky macro", function()
		local world = World({ macros = { { name = "Clicky", icon = "x", body = "/click [nocombat] ClickyButton" } } })
		PutOnBar(world, "Favorites", 1)
		eq(#world.macros, 1, "no second macro")
		world:PressBar(1)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "used a favorite")
	end)

	it("7. Put a macro on a bar: a macro named Clicky doesn't take over Favorites", function()
		local world = World()
		MakeMacro(world, PIRATE, "Clicky")
		PutOnBar(world, "Clicky", 1)
		PutOnBar(world, "Favorites", 2)
		eq(#world.macros, 2, "Favorites gets its own macro")
		world:PressBar(2)
		ok(world:LastUsed() == WINGS or world:LastUsed() == CHEST, "the Favorites button uses a favorite")
		world:PressBar(1)
		eq(world:LastUsed(), PIRATE)
	end)

	it("7. Put a macro on a bar: a player's macro with more than Favorites' line isn't Favorites'", function()
		local mine = "/click [nocombat] ClickyButton\n/say Party time!"
		local world = World({ macros = { { name = "Party", icon = "x", body = mine } } })
		world.ns.PickupMacro(world.ns.favorites)
		eq(#world.macros, 2, "Favorites gets its own macro")
		eq(world.cursor, world.macros[2])
		eq(world.macros[2].body, "/click [nocombat] ClickyButton")
		eq(world.macros[1].body, mine, "the player's macro is untouched")
	end)

	it("8. Rename: the bar button keeps working; a taken name is refused", function()
		local world = World()
		MakeMacro(world, PIRATE, "Ilusion")
		MakeMacro(world, HAT, "Hats")
		PutOnBar(world, "Ilusion", 1)
		assert(world.ns.RenameMacro(Macro(world, "Ilusion"), "Illusion"))
		eq(world.macros[1].name, "Illusion", "the macro is renamed")
		has(PanelTexts(world), "Illusion")
		world:PressBar(1)
		eq(world:LastUsed(), PIRATE)
		list({ world.ns.RenameMacro(Macro(world, "Hats"), "illusion") }, { nil, "There's already a macro called Illusion." })
	end)

	it("8. Delete: removes the macro and empties its button", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		assert(world.ns.DeleteMacro(Macro(world, "Illusion")))
		list(PanelTexts(world), { "Favorites", "Right-click a toy, then Add to new macro..." })
		eq(#world.macros, 0, "the macro is gone")
		eq(world.env.ClickySet1:GetAttribute("type"), nil, "its button is emptied")
	end)

	it("8. Delete: never touches a macro the player wrote", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		world:CreateMacroInUI("Mine", "/say hi\n/click ClickySet1")
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
		list(PanelTexts(world), { "Favorites", "Right-click a toy, then Add to new macro..." })
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
		list(world:TakeErrors(), { COMBAT }, "pick up")
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
		local back = NextLogin(laptop, { saved = desktop:Saved() })
		list(UsedToys(back, 1), { PIRATE, ORB, GNOME }, "changes made on the laptop come back")
	end)

	it("9. Another computer: the macro is there before the toys have loaded, and works once they have", function()
		local desktop = World()
		MakeMacro(desktop, PIRATE, "Illusion")
		PutOnBar(desktop, "Illusion", 1)
		local before = desktop.macros[1].body
		local laptop = NextLogin(desktop, { toysLoading = true })
		eq(PanelRow(laptop, "Illusion").unreadable, nil, "readable: the list comes from the game's data")
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
		-- A toy learned while Clicky isn't running changes nothing either.
		world.toys[ORB].owned = false
		local laptop = NextLogin(world)
		list(UsedToys(laptop, 1), { PIRATE, HAT }, "another computer reads it")
		eq(laptop.macros[1].body, before)
		AddTo(laptop, NEW_TOY, "Illusion")
		list(UsedToys(laptop, 1, 60), { PIRATE, NEW_TOY, HAT })
	end)

	it("10. A patch adds toys: new toys after the last are ignored; the macro is re-saved for them", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, HAT, "Illusion")
		PutOnBar(world, "Illusion", 1)
		local before = world.macros[1].body
		local ids = {}
		for i = 1, 40 do ids[i] = 399 + i end -- a patch's worth, all after the last toy
		PatchAdds(world, ids)
		local later = NextLogin(world)
		list(UsedToys(later, 1), { PIRATE, HAT })
		ok(later.macros[1].body ~= before, "re-saved for the new list")
		list(UsedToys(NextLogin(later), 1), { PIRATE, HAT })
	end)

	it("10. A patch adds toys: old items turned into toys are caught up on, up to 16", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, HAT, "Illusion")
		PutOnBar(world, "Illusion", 1)
		local ids = {}
		for i = 1, 16 do ids[i] = 109 + i end -- between Gnomish Gravity Well and Pirate Hat
		PatchAdds(world, ids)
		local later = NextLogin(world)
		list(UsedToys(later, 1), { PIRATE, HAT }, "all 16 worked out")
		list(PanelToys(later, "Illusion"), { "Pirate Hat", "Pirate's Costume" })
		for i = 1, 16 do ids[i] = 125 + i end
		PatchAdds(later, ids)
		list(UsedToys(NextLogin(later), 1), { PIRATE, HAT }, "16 more after it was re-saved")
	end)

	it("10. A patch adds toys: 17 inside a macro's list is too many; the macro says so", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		PutOnBar(world, "Illusion", 1)
		local before = world.macros[1].body
		local ids = {}
		for i = 1, 17 do ids[i] = 110 + i end
		PatchAdds(world, ids)
		local later = NextLogin(world)
		ExpectUnreadable(later, "Illusion", Lost(17), 1)
		eq(later.macros[1].body, before, "left as it is")
		assert(later.ns.DeleteMacro(Macro(later, "Illusion")))
		MakeMacro(later, PIRATE, "Illusion")
		PutOnBar(later, "Illusion", 1)
		list(UsedToys(later, 1), { PIRATE }, "made again, it works")
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

	it("13. A patch takes one or two toys out of the game: macros keep working without them", function()
		for _, gone in ipairs({ { HAT }, { HAT, GNOME } }) do
			local world = World()
			MakeMacro(world, PIRATE, "Illusion")
			AddTo(world, HAT, "Illusion")
			MakeMacro(world, CHEST, "Loot")
			PutOnBar(world, "Illusion", 1)
			local before = world.macros[1].body
			for _, id in ipairs(gone) do world:RemoveToyFromGame(id) end
			local later = NextLogin(world)
			list(UsedToys(later, 1), { PIRATE }, #gone .. " gone")
			list(PanelToys(later, "Loot"), { "Treasure Chest" }, "other macros work")
			ok(later.macros[1].body ~= before, "re-saved without them")
			list(UsedToys(NextLogin(later), 1), { PIRATE })
		end
	end)

	it("13. A patch takes three toys out of the game: a macro saved before can't be read", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, HAT, "Illusion")
		PutOnBar(world, "Illusion", 1)
		for _, id in ipairs({ ORB, GNOME, WINGS }) do world:RemoveToyFromGame(id) end
		ExpectUnreadable(NextLogin(world), "Illusion", UNREADABLE, 1)
	end)

	it("11. Can't be read: a damaged macro never loads toys, says so, and can be renamed or deleted", function()
		local world = World()
		local ns = world.ns
		local toyList = ns.GetToyList()
		-- The right list, but a position past its end.
		world.bars[1] = world:CreateMacroInUI("Broken",
			ns.NewBody(4, ns.EncodeToys(toyList.highest, #toyList.ids, toyList.checks, { 0, 40 })))
		ExpectUnreadable(world, "Broken", UNREADABLE, 1)
		world.bars[2] = world:CreateMacroInUI("Cut",
			ns.NewBody(5, ns.EncodeToys(toyList.highest, #toyList.ids, toyList.checks, { 0 }):sub(1, 40)))
		world:PressBar(2)
		eq(#world.used, 0, "a cut-off line loads nothing either")
		assert(ns.RenameMacro(Macro(world, "Broken"), "Fixed later"))
		eq(world.macros[1].name, "Fixed later", "it can be renamed")
		assert(ns.DeleteMacro(Macro(world, "Fixed later")))
		eq(#world.macros, 1, "it can be deleted")
	end)

	it("11. Can't be read: a macro saved by a newer Clicky says to update", function()
		local world = World()
		local ns = world.ns
		local toyList = ns.GetToyList()
		local data = ns.EncodeToys(toyList.highest, #toyList.ids, toyList.checks, { 0 })
		world:CreateMacroInUI("Future", ns.NewBody(4, "g" .. data:sub(2)))
		ExpectUnreadable(world, "Future", NEWER)
	end)

	it("11. Can't be read: a macro the player breaks in /macro can't be changed", function()
		local world = World()
		local m = MakeMacro(world, PIRATE, "Illusion")
		world:EditMacroInUI(1, nil, "/click [nocombat] ClickySet1\n#clicky broken")
		list({ world.ns.SetToy(m, ORB, true) }, { nil, UNREADABLE })
		eq(world.macros[1].body, "/click [nocombat] ClickySet1\n#clicky broken", "left as it is")
	end)

	it("12. Copy a macro: pasted on another account, it works there too", function()
		local desktop = World()
		MakeMacro(desktop, PIRATE, "Illusion")
		AddTo(desktop, ORB, "Illusion")
		local other = World() -- another account: its own macros and collection, the same game
		other.toys[ORB].owned = false
		other.bars[1] = other:CreateMacroInUI("Pasted", desktop.macros[1].body)
		list(UsedToys(other, 1), { PIRATE }, "the toys this account owns")
		list(PanelToys(other, "Pasted"), { "Pirate's Costume" })
	end)

	it("12. Copy a macro: the copy gets its own button and its own toys from then on", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		AddTo(world, ORB, "Illusion")
		PutOnBar(world, "Illusion", 1)
		world.bars[2] = world:CreateMacroInUI("Illusion 2", world.macros[1].body)
		ok(world.macros[2].body:find("ClickySet2"), "the copy clicks a button of its own: " .. world.macros[2].body)
		ok(world.macros[1].body:find("ClickySet1%f[%D]"), "the original keeps its /click line")
		list(UsedToys(world, 2), { PIRATE, ORB }, "the copy has the same toys")
		assert(world.ns.SetToy(Macro(world, "Illusion 2"), ORB, false))
		list(UsedToys(world, 2), { PIRATE })
		list(UsedToys(world, 1), { PIRATE, ORB }, "the original is unchanged")
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
		local world = World()
		for i = 1, 9 do MakeMacro(world, PIRATE, "M" .. i) end
		-- Padded with the player's own lines to the 255 characters /macro allows: id 10 won't fit.
		world:EditMacroInUI(1, nil, world.macros[1].body .. "\n/say " .. ("x"):rep(255))
		eq(#world.macros[1].body, 255)
		local copy = world.macros[1].body
		world:CreateMacroInUI("M1 copy", copy)
		world:Slash("/clicky debug")
		local message = "|cff33ff99Clicky|r: M1 copy clicks the same button as another macro and couldn't get its own. "
			.. "That macro is too long to update. Remove your own lines from it in /macro."
		local times = 0
		for _, line in ipairs(world.prints) do
			if line == message then times = times + 1 end
		end
		eq(times, 1, "printed once, though every sync tries again")
		has(world.prints, "|cff33ff99Clicky|r: waiting: copies to separate: 1")
		eq(world:FindMacroByName("M1 copy").body, copy, "left as it is")
	end)

	it("12. Copy a macro: a re-save and a copy made in combat wait for combat to end", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		PutOnBar(world, "Illusion", 1)
		PatchAdds(world, { 400 }) -- after its toys: it reads, then is re-saved for the new list
		local later = NextLogin(world, { combat = true })
		local before = later.macros[1].body
		later.bars[2] = later:CreateMacroInUI("Illusion 2", before)
		later:Slash("/clicky debug")
		has(later.prints, "|cff33ff99Clicky|r: waiting: buttons to make: 2, copies to separate: 1, macros to re-save: 1")
		eq(later.macros[1].body, before, "nothing written in combat")
		eq(later.macros[2].body, before)
		later:LeaveCombat()
		ok(later.macros[1].body ~= before, "re-saved")
		ok(later.macros[1].body:find("ClickySet1%f[%D]"), "the original keeps its button")
		ok(later.macros[2].body:find("ClickySet2%f[%D]"), "the copy has its own: " .. later.macros[2].body)
		eq(later:PressBar(1) and later:LastUsed(), PIRATE)
		eq(later:PressBar(2) and later:LastUsed(), PIRATE)
		eq(#later.used, 2)
		later.prints = {}
		later:Slash("/clicky debug")
		has(later.prints, "|cff33ff99Clicky|r: waiting: nothing")
	end)

	-- Every format Clicky has ever written into a player's macros, exactly as written. Macros
	-- live in players' games, so each must keep reading as it did; a new format version needs a
	-- sample here before this test passes.
	local WRITTEN_FORMATS = {
		-- Format 2 (owned-toy positions), from a real macro: 17 toys, 801 owned when saved.
		[2] = { data = "VMhdL+KjPj1LMuzFu5uxoPoDjB0KLAmpJpdBLlTQMp0+Y5c+G4JPocUlgq7//aAWAHFARPXj4VwPCPH",
			count = 801, positions = { 410, 411, 434, 435, 443, 449, 450, 468, 484, 508, 548, 615, 676, 680, 747, 763, 771 } },
		-- Format 3: Pirate's Costume and Pirate Hat out of the test's six toys, up to item 300.
		[3] = { data = "YAAlgAwAPxGLWZkHzieCBNLWI3kaW85vYmpr/ir2Xv55+LVKiUvhpguo/vw3XSjf",
			highest = 300, count = 6, positions = { 0, 3 } },
	}

	it("Saved macros: every format Clicky has written still reads exactly as it did", function()
		local ns = World().ns
		local newest = 0
		for version, sample in pairs(WRITTEN_FORMATS) do
			local d = assert(ns.DecodeToys(sample.data), "format " .. version .. " no longer reads")
			eq(d.count, sample.count, "format " .. version)
			eq(d.highest, sample.highest, "format " .. version)
			list(d.positions, sample.positions, "format " .. version)
			newest = math.max(newest, version)
		end
		local current = ns.EncodeToys(300, 6, ns.CheckNumbers({ 1 }), {})
		local version = math.floor((("ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"):find(current:sub(1, 1), 1, true) - 1) / 8)
		eq(newest, version, "the format Clicky writes now has a sample here")
	end)

	-- A development build saved macros as format 2: positions among the player's own toys.
	local function LegacyBody(world, id, toys)
		local ns = world.ns
		local owned = {}
		for _, t in ipairs(Toys()) do
			if world.toys[t.id] and world.toys[t.id].owned then owned[#owned + 1] = t.id end
		end
		table.sort(owned)
		local positions = {}
		for i, itemID in ipairs(owned) do
			for _, wanted in ipairs(toys) do
				if itemID == wanted then positions[#positions + 1] = i - 1 end
			end
		end
		return ns.NewBody(id, ns.EncodeLegacyToys(#owned, ns.CheckNumbers(owned), positions))
	end

	it("Upgrade: a macro saved by the earlier build is read and re-saved", function()
		local world = World()
		local legacy = LegacyBody(world, 1, { PIRATE, HAT })
		world.bars[1] = world:CreateMacroInUI("Hearthstone", legacy)
		list(UsedToys(world, 1), { PIRATE, HAT })
		ok(world.macros[1].body ~= legacy, "re-saved in the current format")
		list(UsedToys(NextLogin(world), 1), { PIRATE, HAT }, "and read as that from then on")
	end)

	it("Upgrade: an earlier build's macro waits for the player's toys to load", function()
		local world = World()
		local legacy = LegacyBody(world, 1, { PIRATE, HAT })
		local later = NextLogin(world, { toysLoading = true })
		later.bars[1] = later:CreateMacroInUI("Hearthstone", legacy)
		eq(PanelRow(later, "Hearthstone").count, "?", "not read against a half-loaded collection")
		later:LoadToys()
		list(UsedToys(later, 1), { PIRATE, HAT }, "read once the toys have loaded")
	end)

	it("Debugging: /clicky status and debug report on macros", function()
		local world = World()
		MakeMacro(world, PIRATE, "Illusion")
		world:CreateMacroInUI("Broken", "/click [nocombat] ClickySet4\n#clicky broken")
		world:Slash("/clicky status")
		has(world.prints, "|cff33ff99Clicky|r: 6 toys owned.")
		has(world.prints, "|cff33ff99Clicky|r: Broken: " .. UNREADABLE)
		world:Slash("/clicky debug")
		local all = table.concat(world.prints, "\n")
		ok(all:find("toy list: 6 toys %(game counts 6%), highest item 300, probed item IDs 1%-50300"), all)
		ok(all:find("ms, owned: 6"), all)
		ok(all:find("holds up to 150 toys and catches up on up to 16 added %(guaranteed while the game has up to 2900 toys%)"), all)
		ok(all:find("Illusion %(ClickySet1%).-state ready, data %d+ chars saved for 6 toys up to item 300"), all)
		ok(all:find("state unreadable %(damaged%)"), all)
	end)

	it("Saved data: older data is brought up to date; data from a newer Clicky is left as it is", function()
		local ns = World().ns
		local db = { toys = { [PIRATE] = true } }
		for version = 1, ns.DB_VERSION do ns.migrations[version](db) end
		eq(db.toys, nil, "the migrations themselves")
		local unversioned = World({ saved = { toys = { [PIRATE] = true } } })
		eq(unversioned:Saved().version, unversioned.ns.DB_VERSION)
		eq(unversioned:Saved().toys, nil)
		local one = World({ saved = { version = 1, toys = { [PIRATE] = true } } })
		eq(one:Saved().version, one.ns.DB_VERSION)
		eq(one:Saved().toys, nil, "the known-toys cache is gone")
		local newer = World({ saved = { version = 99, toys = { [PIRATE] = true } } })
		eq(newer:Saved().version, 99)
		list(newer:Saved().toys, { [PIRATE] = true })
	end)

	-- The Toy Box filters are the player's own saved settings: an earlier Clicky widened and
	-- restored them, and a bad restore left a player's Toy Box empty even with Clicky disabled.
	it("Never changes the player's settings: the code calls no setting-changing function", function()
		local forbidden = { "SetCollectedShown", "SetUncollectedShown", "SetUnusableShown",
			"SetSourceTypeFilter", "SetExpansionTypeFilter", "SetAllSourceTypeFilters",
			"SetAllExpansionTypeFilters", "SetFilterString", "ForceToyRefilter", "SetDefaultFilters",
			"SetCVar", "ConsoleExec" }
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
end)
