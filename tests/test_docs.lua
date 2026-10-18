-- README.md's player-facing facts, checked against what Clicky actually does: each fact is read
-- out of README.md and compared with the real addon running on stubbed game state
-- (tests/wow.lua), so changing either one without the other fails here.

local wow = require("wow")

local function eq(actual, expected, what) assert.are.equal(expected, actual, what) end

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
	it("Limits: toys per macro", function()
		local cap = tonumber(Says("\n%- (%d+) toys per macro", "the toys-per-macro limit"))
		local world = World()
		eq(cap, world.ns.MACRO_TOY_CAP, "README's toys per macro")
	end)

	it("Adding and removing toys: a macro with too many lines of its own", function()
		local message = Says('adding one says "([^"]+)"', "the too-long message"):gsub("%s+", " ")
		local toys = {}
		for i = 1, 300 do toys[i] = { id = 1000 + i } end
		local world = wow.New({ toys = toys })
		local m = assert(world.ns.MakeMacro("Illusion", toys[1].id))
		local body = world.macros[1].body
		world:EditMacroInUI(1, nil, body .. "\n/say " .. ("x"):rep(255 - #body - 6))
		local ok, err = world.ns.SetToy(m, toys[300].id, true)
		eq(ok, nil, "refused")
		eq(err, message, "README's message")
	end)

	it("Limits: macro name length", function()
		local limit = tonumber(Says("Macro names up to (%d+) characters", "the macro name limit"))
		local truncate = World().ns.TruncateMacroName
		eq(#truncate(("x"):rep(limit)), limit, "a name of README's length is kept whole")
		eq(#truncate(("x"):rep(limit + 1)), limit, "a longer name is cut to README's length")
	end)

	it("Slash commands: the table lists exactly the commands /clicky handles", function()
		local world = World()
		world.env.SetCollectionsJournalShown = function() world.toyBoxOpened = true end
		-- What /clicky prints for a command it doesn't handle.
		world:Slash("/clicky no-such-command")
		local unknown = table.concat(world.prints, "\n")
		assert(unknown ~= "", "an unknown command prints help")

		local listed = {}
		for command in Section("Slash commands"):gmatch("\n| `(/clicky[^`]*)` |") do
			listed[#listed + 1] = command
			world.prints, world.toyBoxOpened = {}, nil
			world:Slash(command)
			assert(table.concat(world.prints, "\n") ~= unknown or world.toyBoxOpened,
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

	it("Troubleshooting: the message when no toys are usable", function()
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

	it("Troubleshooting: an unreadable macro's toy count", function()
		local mark = Says('greyed out with "([^"]+)" for its toy count', "the unreadable count mark")
		local world = World()
		world:CreateMacroInUI("Broken", "/click ClickySet4\n#clicky broken")
		local count
		for _, row in ipairs(world.ns.PanelRows()) do
			if row.kind == "macro" and row.macro.name == "Broken" then count = row.count end
		end
		eq(count, mark, "the panel's count for a macro it can't read")
	end)

	it("Adding and removing toys: the toy menu's entry labels", function()
		local add = Says("you'll%s+see %*%*([^*]+)%*%* followed by each%s+macro's name", "the Add to label")
		local remove = Says("or %*%*([^*]+)%*%* for macros the toy is already in", "the Remove from label")
		local world = World()
		local m = assert(world.ns.MakeMacro("Illusion", PIRATE))
		eq(world.ns.ToyMenuEntries(ORB)[1].label, add .. " " .. m.name, "a toy not in the macro")
		eq(world.ns.ToyMenuEntries(PIRATE)[1].label, remove .. " " .. m.name, "a toy in the macro")
	end)

	it("Favorites: always at the top of the panel", function()
		local name = Says("\n### (%w+)\n\n%1 is always at the top of the panel", "where Favorites is")
		local world = World()
		assert(world.ns.MakeMacro("Illusion", PIRATE))
		local first = world.ns.PanelRows()[1]
		eq(first.kind, "macro", "the panel's first row")
		eq(first.macro.name, name, "the panel's first macro")
	end)
end)
