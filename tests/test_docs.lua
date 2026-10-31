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
	it("Limits: items per macro", function()
		local cap = tonumber(Says("\n%- (%d+) items per macro", "the items-per-macro limit"))
		local world = World()
		eq(cap, world.ns.MACRO_ENTRY_CAP, "README's items per macro")
	end)

	it("Troubleshooting: a macro with too many lines of its own", function()
		local message = Says('adding one says "([^"]+)"', "the too-long message"):gsub("%s+", " ")
		local toys = {}
		for i = 1, 300 do toys[i] = { id = 1000 + i } end
		local world = wow.New({ toys = toys })
		local m = assert(world.ns.MakeMacro("Illusion", toys[1].id))
		local body = world.macros[1].body
		world:EditMacroInUI(1, nil, body .. "\n/say " .. ("x"):rep(255 - #body - 6))
		local ok, err = world.ns.SetEntry(m, toys[300].id, true)
		eq(ok, nil, "refused")
		eq(err, message, "README's message")
	end)

	it("Limits: macro name length", function()
		local limit = tonumber(Says("Macro names up to (%d+) characters", "the macro name limit"))
		local truncate = World().ns.TruncateMacroName
		eq(#truncate(("x"):rep(limit)), limit, "a name of README's length is kept whole")
		eq(#truncate(("x"):rep(limit + 1)), limit, "a longer name is cut to README's length")
	end)

	it("Limits and Troubleshooting: general macro slots, and the message when they're full", function()
		local slots = tonumber(Says("\n%- (%d+) general macros, shared by your whole account", "the general macro limit"))
		local message = Says('Making another%s+says "([^"]+)"', "the full-slots message"):gsub("%s+", " ")
		local world = World()
		eq(slots, world.env.Constants.MacroConsts.MAX_ACCOUNT_MACROS, "README's general macro slots")
		local macros = {}
		for i = 1, slots do macros[i] = { name = "m" .. i, body = "/say " .. i } end
		local full = wow.New({ macros = macros, toys = { { id = PIRATE } } })
		local ok, err = full.ns.MakeMacro("Illusion", PIRATE)
		eq(ok, nil, "refused")
		eq(err, message, "README's message")
	end)

	it("Troubleshooting: the message when a macro is full", function()
		local example = Says('adding one more says "([^"]+)" with your macro\'s name', "the full-macro message")
			:gsub("%s+", " ")
		local toys = {}
		for i = 1, 101 do toys[i] = { id = 1000 + i } end
		local world = wow.New({ toys = toys })
		local m = assert(world.ns.MakeMacro("Illusion", toys[1].id))
		for i = 2, 100 do assert(world.ns.SetEntry(m, toys[i].id, true)) end
		local ok, err = world.ns.SetEntry(m, toys[101].id, true)
		eq(ok, nil, "refused")
		eq(err, example, "README's message, for a macro called Illusion")
	end)

	it("Troubleshooting: the message for a change in combat", function()
		local message = Says('A change says "([^"]+)"', "the combat refusal")
		local world = World()
		local m = assert(world.ns.MakeMacro("Illusion", PIRATE))
		world:EnterCombat()
		local ok, err = world.ns.SetEntry(m, ORB, true)
		eq(ok, nil, "refused")
		eq(err, message, "README's message")
	end)

	it("Troubleshooting: the message for dragging a macro in combat", function()
		local message = Says('in a fight says "([^"]+)"; drag it once the fight ends', "the drag refusal")
		local world = World()
		local m = assert(world.ns.MakeMacro("Illusion", PIRATE))
		world:EnterCombat()
		world.ns.PickupMacro(m)
		assert.are.same({ message }, world:TakeErrors(), "README's message")
		eq(world.cursor, nil, "nothing picked up")
	end)

	it("Troubleshooting: the message for a name another macro has", function()
		local phrase = Says('says "([^"]+)" and its name', "the duplicate-name message")
		local world = World()
		assert(world.ns.MakeMacro("Illusion", PIRATE))
		local ok, err = world.ns.MakeMacro("Illusion", ORB)
		eq(ok, nil, "refused")
		eq(err, phrase .. " Illusion.", "README's message, then the name")
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
		local phrase = Says('you\'ll%s+see "([^"]+)" and the macro\'s%s+name', "the no-usable-toys message")
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
		Says("clicking it there wears it if it isn't worn, and uses it once it is", "the drawer wearing gear")
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
		world:CreateMacroInUI("Future", world.ns.NewBody("FTRX", "x" .. data:sub(2)))
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

	it("Getting started, Renaming and deleting, Using a macro's items: the menus' labels", function()
		local add = Says("choose %*%*([^*]+)%*%*,%s+and%s+name%s+the", "the entry menu's new-macro label")
		local rename = Says("choose %*%*([^*]+)%*%* or %*%*[^*]+%*%*%. Deleting", "the macro menu's rename label")
		local copy = Says("choose %*%*([^*]+)%*%* and copy the line", "the macro menu's copy label")
		local world = World()
		local function Texts()
			local texts = {}
			for _, entry in ipairs(world.menu.entries) do texts[entry.text or ""] = true end
			return texts
		end
		world.ns.OpenEntryMenu(world.env.UIParent, PIRATE)
		assert(Texts()[add], "the entry menu has README's " .. add)
		local m = assert(world.ns.MakeMacro("Illusion", PIRATE))
		world.ns.OpenMacroMenu(world.env.UIParent, m)
		local texts = Texts()
		assert(texts[rename], "the macro menu has README's " .. rename)
		assert(texts[copy], "the macro menu has README's " .. copy)
	end)

	it("Adding and removing items: the menu's checkboxes", function()
		local title = Says("Under%s+%*%*([^*]+)%*%*[^,]*,[^,]*,%s+each%s+macro%s+has%s+a%s+checkbox%s+with%s+its%s+name,%s+ticked%s+if%s+the%s+item%s+is%s+in%s+it",
			"the macros' checkboxes")
		local world = World()
		local m = assert(world.ns.MakeMacro("Illusion", PIRATE))
		-- The menu's entries after its title, from the real menu: { text, ticked } per checkbox.
		local function Menu(itemID)
			world.ns.OpenEntryMenu(world.env.UIParent, itemID)
			local titles, boxes = {}, {}
			for _, entry in ipairs(world.menu.entries) do
				if entry.kind == "CreateTitle" then titles[#titles + 1] = entry.text end
				if entry.kind == "CreateCheckbox" then boxes[#boxes + 1] = { entry.text, entry.args[1]() } end
			end
			return titles, boxes
		end
		local titles, boxes = Menu(ORB)
		eq(titles[1], title, "README's title above them")
		assert.are.same({ { m.name, false } }, boxes, "a checkbox with the macro's name, not ticked: the toy isn't in it")
		assert.are.same({ { m.name, true } }, select(2, Menu(PIRATE)), "ticked: the toy is in it")
	end)

	it("In combat: /clicky says it can't open the Toy Box", function()
		local message = Says('`/clicky` in combat says "([^"]+)"', "the message for /clicky in combat")
		local world = World()
		world:Slash("/clicky")
		eq(world.journal.tab, world.env.COLLECTIONS_JOURNAL_TAB_INDEX_TOYS, "out of combat it opens the Toy Box tab")
		world.journal = nil
		world:EnterCombat()
		world:Slash("/clicky")
		eq(world.journal, nil, "in combat it doesn't ask the game to show the window")
		assert.are.same({ message }, world:TakeErrors(), "README's message")
	end)

	it("The grid: it starts with collected toys only", function()
		Says("[Ii]t%s+starts%s+with%s+collected%s+toys%s+only", "the grid's starting filters")
		local filters = World().ns.DefaultGridFilters("toys")
		eq(filters.collected, true, "collected toys shown")
		eq(filters.uncollected, false, "toys not collected hidden")
		eq(filters.usableOnly, false, "not only usable toys")
	end)

	it("The grid: a tab each for toys, mounts, pets, spells and items with its count; the filters on Toys; Favorites stays toys only", function()
		local toys, mounts, pets, spells, items = Says("with a tab each for%s+%*%*([^*]+)%*%*,%s+%*%*([^*]+)%*%*,%s+%*%*([^*]+)%*%*,%s+"
			.. "%*%*([^*]+)%*%* and%s+%*%*([^*]+)%*%*", "the grid's tabs")
		local example = Says("Each tab says how many it lists, as %*%*([^*]+)%*%*", "a tab's count")
		Says("Favorites%s+stays%s+toys%s+only", "Favorites stays toys only")
		Says("Spells%s+and%s+items%s+have%s+no%s+Set%s+Favorite", "no star on spells and items")
		Says("On%s+the%s+Toys%s+tab,%s+the%s+%*%*Filter%*%*%s+menu", "the filters on the Toys tab")
		Says("Favorites'%s+toys%s+have%s+their%s+star%s+instead", "no check mark for Favorites")
		Says("Not%s+Collected%s+lists%s+the%s+same%s+toys%s+as%s+the%s+Toy%s+Box's%s+own%s+Not%s+Collected", "Not Collected as in the Toy Box")
		local world = wow.New({
			toys = { { id = PIRATE, name = "Pirate's Costume", favorite = true }, { id = ORB, name = "Orb", owned = false } },
			spells = { { id = 500, name = "Path of the Fire" } },
			items = { { id = 600, name = "Hearth Ring" } },
			mounts = { { id = 6, name = "Brown Horse" } },
			pets = { { guid = "BattlePet-0-000000000001", species = 40, display = 300, name = "Cat" } },
			toyList = { PIRATE, ORB, "s500", "i600", "m6", "p40:300" },
			toyHidden = { [ORB] = true },
		})
		world:LoadCollections()
		world:OpenToyBox()
		local grid = world.env.ClickyGrid
		eq(example:match("^(%a+) %(%d+%)$"), toys, "README's example is a tab's label")
		local labels = {}
		for i, tab in ipairs(grid.Tabs) do labels[i] = tab.text end
		assert.are.same({ toys .. " (1)", mounts .. " (1)", pets .. " (1)", spells .. " (1)", items .. " (1)" }, labels,
			"the tabs, each with its count")
		world:GridFilterMenu()[2].toggle()
		eq(grid.Tabs[1].text, toys .. " (1)", "Not Collected: not a toy the Toy Box leaves out")
		truthy(grid.filterButton:IsShown(), "the filters on the Toys tab")
		grid.Tabs[4].scripts.OnClick(grid.Tabs[4])
		truthy(not grid.filterButton:IsShown(), "and not on Spells")
		local favorite
		grid.Tabs[1].scripts.OnClick(grid.Tabs[1])
		for _, button in ipairs(grid.buttons) do
			if button.entry == PIRATE then favorite = button end
		end
		truthy(favorite.star:IsShown() and not favorite.check:IsShown(), "a favorite has its star, not a check mark")
		local ns = world.ns
		local fav = ns.GetMacro(ns.FAVORITES_ID)
		eq((ns.SetEntry(fav, "s500", true)), nil, "Favorites takes no spell")
		eq((ns.SetEntry(fav, "m6", true)), nil, "nor a mount")
		ns.OpenEntryMenu(world.env.UIParent, "s500")
		for _, entry in ipairs(world.menu.entries) do
			assert(entry.text ~= world.env.BATTLE_PET_FAVORITE, "a spell's menu has no star")
		end
	end)

	it("Pets: a click doesn't pick the pet you already have out, and prefers a starred one", function()
		Says("A%s+click%s+summons%s+one%s+that%s+isn't%s+out:%s+summoning%s+the%s+pet%s+you%s+already%s+have%s+out",
			"the pet that's out isn't picked")
		Says("A%s+click%s+summons%s+a%s+starred%s+one%s+first", "a starred pet first")
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
		local title = Says("the%s+Clicky%s+panel,%s+titled%s+%*%*([^*]+)%*%*", "the panel's title")
		local world = World()
		world:LoadCollections()
		eq(world.env.ClickyPanel.TitleContainer.TitleText:GetText(), title, "README's title")
	end)

	it("The grid: the search finds tooltip words, which Blizzard's searches don't", function()
		local word = Says('or any words in the tooltip: "(%a+)" finds', "the tooltip search")
		local world = wow.New({ toys = { { id = PIRATE, name = "Pirate's Costume" }, { id = ORB, name = "Orb" } } })
		world.toys[PIRATE].tooltip = "Use: " .. word:upper() .. " experience is gained faster."
		world:LoadCollections()
		world:OpenToyBox()
		world.env.ClickyGridSearch:SetText(word)
		local shown = {}
		for _, button in ipairs(world.env.ClickyGrid.buttons) do
			if button:IsShown() then shown[#shown + 1] = button.entry end
		end
		assert.are.same({ PIRATE }, shown, "README's example word finds it in the tooltip")
	end)

	it("Favorites: always at the top of the panel", function()
		local name = Says("\n### (%w+)\n\n%1 is always at the top of the panel", "where Favorites is")
		local world = World()
		assert(world.ns.MakeMacro("Illusion", PIRATE))
		local first = world.ns.PanelRows()[1]
		eq(first.kind, "macro", "the panel's first row")
		eq(first.macro.name, name, "the panel's first macro")
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

	it("Troubleshooting ends with where to get help: Wago's comments", function()
		local troubleshooting = Section("Troubleshooting")
		truthy(troubleshooting:match("Leave a comment on %[Clicky's Wago page%]%(https://addons%.wago%.io/addons/clicky%)%.%s*$"),
			"the last entry")
	end)
end)
