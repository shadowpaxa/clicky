-- README.md's player-facing facts, checked against what Clicky actually does: each fact is read
-- out of README.md and compared with the real addon running on stubbed game state
-- (tests/wow.lua), so changing either one without the other fails here.

local wow = require("wow")

local function eq(actual, expected, what) assert.are.equal(expected, actual, what) end
local function truthy(value, what) assert.is_truthy(value, what) end

local function ReadReadme()
	local file = assert(io.open("README.md", "r"))
	local text = file:read("*a")
	file:close()
	return text
end
local README = ReadReadme()

-- The README's text matching pattern's captures; fails if the README no longer says it.
local function Says(pattern, what)
	local found = { README:match(pattern) }
	assert(found[1], ("README.md no longer states %s (pattern %q)"):format(what, pattern))
	return unpack(found)
end

local PIRATE, ORB = 101, 102

local function World()
	return wow.New({ toys = {
		{ id = PIRATE, name = "Pirate's Costume", icon = 1001 },
		{ id = ORB, name = "Orb of Deception", icon = 1002 },
	} })
end

-- The section of the README under a "## heading", up to the next one.
local function Section(heading)
	return Says("\n## " .. heading .. "\n(.-)\n## ", "a " .. heading .. " section")
end

describe("README.md", function()
	it("Good to know: the macro menu renames, deletes and opens /macro", function()
		Says("rename it, delete it, or open it in `/macro` to edit it%.", "what the macro menu does")
		local world = World()
		local m = assert(world.ns.MakeMacro("Illusion", PIRATE))
		world.ns.OpenMacroMenu(world.env.UIParent, m)
		local labels = {}
		for _, entry in ipairs(world.menu.entries) do labels[entry.text] = true end
		truthy(labels["Rename"] and labels[world.env.DELETE] and labels["Open in /macro"], "the menu has those entries")
		world:ChooseMenuEntry("Open in /macro")
		eq(world.env.MacroFrame:GetSelectedIndex(), 1, "and the last opens /macro on the macro")
	end)

	it("Good to know: an item of an open macro has Use as icon for its macro", function()
		local label = Says("choose%s+%*%*([^*]-) Illusion%*%*%s+%(with%s+your%s+macro's%s+name%)",
			"the menu entry that changes a macro's icon")
		local world = World()
		local ns = world.ns
		local m = assert(ns.MakeMacro("Illusion", PIRATE))
		assert(ns.SetEntry(m, ORB, true))
		local entryRow
		for _, row in ipairs(ns.PanelRows()) do
			if row.kind == "entry" and row.key == ORB then entryRow = row end
		end
		truthy(entryRow and entryRow.macro == m, "the panel lists the item under its macro")
		ns.OpenMacroEntryMenu(world.env.UIParent, entryRow.macro, entryRow.key)
		world:ChooseMenuEntry(label .. " Illusion")
		eq(world.macros[1].icon, 1002, "choosing it gives the macro that item's icon")
	end)

	it("Limits: items per macro", function()
		local cap = tonumber(Says("\n%- (%d+) items per macro", "the items-per-macro limit"))
		local world = World()
		eq(cap, world.ns.MACRO_ENTRY_CAP, "README's items per macro")
	end)

	it("Limits: macro name length", function()
		local limit = tonumber(Says("Macro names up to (%d+) characters%. A longer name is cut short%.",
			"the macro name limit, and that a longer name is cut"))
		local truncate = World().ns.TruncateMacroName
		eq(#truncate(("x"):rep(limit)), limit, "a name of README's length is kept whole")
		eq(#truncate(("x"):rep(limit + 1)), limit, "a longer name is cut to README's length")
	end)

	it("Limits: general macro slots", function()
		local slots = tonumber(Says("\n%- (%d+) general macros, shared by your whole account", "the general macro limit"))
		local world = World()
		eq(slots, world.env.Constants.MacroConsts.MAX_ACCOUNT_MACROS, "README's general macro slots")
		local macros = {}
		for i = 1, slots do macros[i] = { name = "m" .. i, body = "/say " .. i } end
		local full = wow.New({ macros = macros, toys = { { id = PIRATE } } })
		eq((full.ns.MakeMacro("Illusion", PIRATE)), nil, "one more is refused")
		Says("Full%? Delete%s+one you don't use in `/macro`%.", "what to do when they're full")
		full.env.DeleteMacro(1)
		full:Fire("UPDATE_MACROS")
		truthy(full.ns.MakeMacro("Illusion", PIRATE), "with one deleted in /macro, the macro is made")
	end)

	it("Slash commands: the table lists exactly the commands /clicky handles", function()
		local world = World()
		-- What /clicky prints for a command it doesn't handle.
		world:Slash("/clicky no-such-command")
		local unknown = table.concat(world.prints, "\n")
		assert(unknown ~= "", "an unknown command prints help")

		local listed = {}
		for command in Section("Slash commands"):gmatch("\n| `(/clicky[^`]*)` |") do
			listed[#listed + 1] = command
			world.prints, world.journal = {}, nil
			world:Slash(command)
			assert(table.concat(world.prints, "\n") ~= unknown or world.journal,
				("README lists %s, but /clicky doesn't handle it"):format(command))
		end
		assert(#listed > 0, "README's slash command table has no commands")

		-- Every subcommand Commands.lua dispatches on is in the table.
		local file = assert(io.open("Commands.lua", "r"))
		local source = file:read("*a")
		file:close()
		local inReadme = {}
		for _, command in ipairs(listed) do inReadme[command] = true end
		local handled = 0
		for sub in source:gmatch('msg == "([^"]*)"') do
			handled = handled + 1
			local command = sub == "" and "/clicky" or ("/clicky " .. sub)
			assert(inReadme[command], ("/clicky handles %q, but README's table doesn't list it"):format(command))
		end
		assert(handled > 0, "found no commands in Commands.lua")
	end)

	it("Troubleshooting: the message when no items are usable, and Favorites saying toys", function()
		local phrase = Says('say "([^"]+)" and the macro\'s%s+name', "the no-usable-toys message")
		local world = World()
		local m = assert(world.ns.MakeMacro("Illusion", PIRATE))
		world.ns.PickupMacro(m)
		world.bars[1], world.cursor = assert(world.cursor, "nothing picked up"), nil
		world.toys[PIRATE].usable = false
		world:PressBar(1)
		local errors = world:TakeErrors()
		local shown = errors[#errors] or ""
		eq(shown:sub(1, #phrase + 1 + #m.name), phrase .. " " .. m.name, "README's message, then the macro's name")
	end)

	it("Troubleshooting: the message for a Favorites with no usable toy says toys", function()
		Says('%(Favorites says "toys"%)', "Favorites saying toys")
		local world = World()
		world.env.C_ToyBox.SetIsFavorite(PIRATE, true)
		world.toys[PIRATE].usable = false
		world.ns.Sync("test")
		eq(world.ns.NoEntriesMessage(world.ns.GetMacro(world.ns.FAVORITES_ID)), "No usable toys in Favorites.")
	end)

	it("Wearable items: a click never picks gear; the drawer wears it, and uses it once worn", function()
		Says("A click on a macro never picks gear that can be worn", "a click never picking gear")
		Says("if%s+you%s+aren't%s+wearing%s+it,%s+the%s+first%s+click%s+puts%s+it%s+on,%s+and%s+after%s+that%s+clicks%s+use%s+it", "the drawer wearing gear")
		local world = wow.New({
			items = { { id = 600, name = "Cloak of Teleport", equippable = true } },
			toyList = { "i600" },
		})
		local m = assert(world.ns.MakeMacro("Portal", "i600"))
		world.ns.PickupMacro(m)
		world.bars[1], world.cursor = world.cursor, nil
		world:PressBar(1)
		eq(#world.equipped + #world.used, 0, "a click picks nothing")
		world:TakeErrors()
		world:PressBar(1, "RightButton")
		local drawer = world.ns.GetDrawer(m.id)
		drawer.buttons[1]:Click("LeftButton", false)
		assert.are.same({ 600 }, world.equipped, "the drawer wears it")
		drawer.buttons[1]:Click("LeftButton", false)
		assert.are.same({ "i600" }, world.used, "and uses it once it is worn")
	end)

	it("Troubleshooting: an unreadable macro's item count", function()
		local mark = Says('greyed out with "([^"]+)" for its item count', "the unreadable count mark")
		local world = World()
		world:CreateMacroInUI("Broken", "/click ClickyBCDF\n#clicky broken")
		local count
		for _, row in ipairs(world.ns.PanelRows()) do
			if row.kind == "macro" and row.macro.name == "Broken" then count = row.count end
		end
		eq(count, mark, "the panel's count for a macro it can't read")
	end)

	it("Troubleshooting: the two reasons a macro can't be read", function()
		local newer = Says('\n%- "([^"]+)": update Clicky%.', "the newer-version reason")
		local damaged = Says('\n%- "([^"]+)": its `#clicky` line was changed', "the damaged reason")
		local world = World()
		local data = world.ns.EncodePlaces({ 0 })
		world:CreateMacroInUI("Future", world.ns.NewBody("FTRX", world.ns.MarkFormat(data, 2)))
		world:CreateMacroInUI("Broken", "/click ClickyBCDF\n#clicky broken")
		local function Reason(name)
			for _, m in ipairs(world.ns.GetMacros()) do
				if m.name == name then return world.ns.Unreadable(m) or "" end
			end
			return ""
		end
		eq(Reason("Future"):sub(1, #newer), newer, "README's start of the reason, for a newer Clicky's macro")
		eq(Reason("Broken"):sub(1, #damaged), damaged, "README's start of the reason, for a changed line")
	end)

	it("Getting started: the entry menu's label", function()
		local add = Says("choose %*%*([^*]+)%*%*,%s+and%s+name%s+the", "the entry menu's new-macro label")
		local world = World()
		local function Texts()
			local texts = {}
			for _, entry in ipairs(world.menu.entries) do texts[entry.text or ""] = true end
			return texts
		end
		world.ns.OpenEntryMenu(world.env.UIParent, PIRATE)
		assert(Texts()[add], "the entry menu has README's " .. add)
	end)

	it("Good to know: a tab each for toys, mounts, pets, spells and items; the filters on Toys, not Spells", function()
		local toys, mounts, pets, spells, items = Says("a tab each for%s+%*%*([^*]+)%*%*,%s+%*%*([^*]+)%*%*,%s+%*%*([^*]+)%*%*,%s+"
			.. "%*%*([^*]+)%*%* and%s+%*%*([^*]+)%*%*", "the grid's tabs")
		Says("Toys,%s+Mounts%s+and%s+Pets%s+have%s+their%s+own%s+%*%*Filter%*%*%s+menus", "the filters on those tabs")
		local world = wow.New({
			toys = { { id = PIRATE, name = "Pirate's Costume" } },
			spells = { { id = 500, name = "Path of the Fire" } },
			items = { { id = 600, name = "Hearth Ring" } },
			mounts = { { id = 6, name = "Brown Horse" } },
			pets = { { guid = "BattlePet-0-000000000001", species = 40, display = 300, name = "Cat" } },
			toyList = { PIRATE, "s500", "i600", "m6", "p40:300" },
		})
		world:LoadCollections()
		world:OpenToyBox()
		local grid = world.env.ClickyGrid
		local labels = {}
		for i, tab in ipairs(grid.Tabs) do labels[i] = tab.text:match("^(%a+)") end
		assert.are.same({ toys, mounts, pets, spells, items }, labels, "the tabs, in README's order")
		for i, filtered in ipairs({ true, true, true, false, false }) do
			grid.Tabs[i].scripts.OnClick(grid.Tabs[i])
			eq(grid.filterButton:IsShown(), filtered, labels[i] .. "'s Filter menu")
		end
	end)

	it("Pets: a click doesn't pick the pet you already have out, and prefers a starred one", function()
		Says("never%s+the%s+one%s+that's%s+already%s+out", "the pet that's out isn't picked")
		Says("a%s+starred%s+one%s+first", "a starred pet first")
		local cat1, cat2 = "BattlePet-0-000000000001", "BattlePet-0-000000000002"
		local world = wow.New({
			pets = { { guid = cat1, species = 40, display = 300 }, { guid = cat2, species = 40, display = 300, favorite = true } },
			toyList = { "p40:300" },
		})
		local m = assert(world.ns.MakeMacro("Laser", "p40:300"))
		eq(select(3, world.ns.EntryAction("p40:300")), "/summonpet " .. cat2, "the starred one")
		world.summonedPet = cat2
		eq(select(3, world.ns.EntryAction("p40:300")), "/summonpet " .. cat1, "not the one out")
		world.summonedPet = cat1
		world:Pet(cat2).summonable = false
		assert.are.same(world.ns.GetCandidates(m, true), {}, "with only the pet that's out to summon, a click has nothing")
	end)

	it("Installation: the WoW it's for, Midnight being the .toc's Interface 12", function()
		Says("Clicky%s+is%s+for%s+World%s+of%s+Warcraft%s+Retail%s+%(Midnight%)", "Retail (Midnight)")
		local toc = assert(io.open("Clicky.toc", "r"))
		local interface = toc:read("*a"):match("## Interface: (%d+)")
		toc:close()
		eq(interface and interface:sub(1, 2), "12", "the .toc's Interface is Midnight's (12.x)")
	end)

	it("Slash commands: /clicky debug's Trace box", function()
		local label = Says("Tick%s+%*%*([^*]+)%*%*%s+in%s+it", "the debug window's Trace box")
		local world = World()
		world:Slash("/clicky debug")
		local text = world.env.ClickyDebug.trace.Text:GetText()
		eq(text:sub(1, #label + 1), label .. ":", "the box's label starts with README's")
	end)

	it("Getting started: the panel's title", function()
		local title = Says("the%s+%*%*([^*]+)%*%*%s+panel%s+beside%s+it", "the panel's title")
		local world = World()
		world:LoadCollections()
		eq(world.env.ClickyPanel.TitleContainer.TitleText:GetText(), title, "README's title")
	end)

	it("The grid: the search finds tooltip words, which Blizzard's searches don't", function()
		Says("words%s+in%s+the%s+tooltip", "the tooltip search")
		local word = "rested"
		local world = wow.New({ toys = { { id = PIRATE, name = "Pirate's Costume" }, { id = ORB, name = "Orb" } } })
		world.toys[PIRATE].tooltip = "Use: " .. word:upper() .. " experience is gained faster."
		world:LoadCollections()
		world:OpenToyBox()
		world.env.ClickyGridSearch:SetText(word)
		local shown = {}
		for _, button in ipairs(world.env.ClickyGrid.buttons) do
			if button:IsShown() then shown[#shown + 1] = button.entry end
		end
		assert.are.same({ PIRATE }, shown, "a word in its tooltip finds it")
	end)

	-- Full links into the public repo, so README pasted as Wago's description shows them too.
	it("Pictures: each one's file exists and its alt text says what it shows", function()
		local n = 0
		for alt, url in README:gmatch("!%[([^%]]*)%]%(([^)]+)%)") do
			n = n + 1
			truthy(alt:match("%S"), ("%s has alt text"):format(url))
			local path = url:match("^https://raw%.githubusercontent%.com/shadowpaxa/clicky/main/(.+)$")
			truthy(path, ("%s is a full link into the repo"):format(url))
			local file = path and io.open(path, "rb")
			truthy(file, ("%s exists"):format(path))
			if file then file:close() end
		end
		truthy(n > 0, "README has pictures")
	end)

	-- A player's own macro runs /click as Blizzard's SlashCommands.lua does: a left click when no
	-- button is named, whichever button the macro itself was clicked with.
	it("Using Clicky in other macros: the copied line picks on either click; with P it opens the drawer", function()
		local label = Says("choose%s+%*%*([^*]+)%*%*%s+to%s+get%s+a%s+line", "the menu entry that copies the line")
		local code = ("[BCDFGHJKLMNPQRSTVWXZ]"):rep(4)
		local random = Says("a%s+line%s+like%s+`(/click Clicky" .. code .. ")`", "the copied line's form")
		local drawer = Says("%(`(/click ClickyP" .. code .. ")`%)%s+and%s+it%s+opens%s+the%s+drawer",
			"the drawer's line")
		eq(drawer, (random:gsub("^/click Clicky", "/click ClickyP")), "README's drawer line is its random line with P")

		local world = World()
		local m = assert(world.ns.MakeMacro("Illusion", PIRATE))
		world.ns.OpenMacroMenu(world.env.UIParent, m)
		world:ChooseMenuEntry(label)
		local line = world.dialog:GetEditBox():GetText()
		world.dialog:Hide()
		truthy(line:match("^/click Clicky" .. code .. "$"), "the menu gives a line of README's form")

		world.bars[1] = world:CreateMacroInUI("Random", line)
		world:PressBar(1, "RightButton")
		eq(world:LastUsed(), PIRATE, "a right-click on your own macro uses an item")
		eq(world.ns.GetDrawer(m.id).frame:IsShown(), false, "and doesn't open the drawer")

		world.bars[2] = world:CreateMacroInUI("Pick", (line:gsub("^/click Clicky", "/click ClickyP")))
		local used = #world.used
		world:PressBar(2)
		truthy(world.ns.GetDrawer(m.id).frame:IsShown(), "a left click on your own macro with P opens the drawer")
		eq(#world.used, used, "and uses nothing")
		assert.are.same({}, world:TakeErrors())
	end)

	it("Troubleshooting ends with where to get help: Wago's comments", function()
		local troubleshooting = Section("Troubleshooting")
		truthy(troubleshooting:match("Leave a comment on%s+%[Clicky's Wago page%]%(https://addons%.wago%.io/addons/clicky%)%.%s*$"),
			"the last entry")
	end)
end)
