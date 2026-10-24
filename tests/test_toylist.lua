-- ToyList.lua only grows at the end (tests/check_toylist.py, which tests/run.sh also runs against
-- every tag the commit contains), and tools/update_toys.py keeps it that way. Both are Python, so these tests run
-- them on small lists written to temporary files.

local function Write(text)
	local path = os.tmpname()
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	return path
end

local function ListFile(ids)
	local lines = { "-- header", "local _, ns = ...", "ns.TOY_IDS = {" }
	for _, id in ipairs(ids) do lines[#lines + 1] = "\t" .. id .. "," end
	lines[#lines + 1] = "}\n"
	return Write(table.concat(lines, "\n"))
end

-- Runs a command; returns whether it succeeded, and what it printed.
local function Run(command)
	local pipe = assert(io.popen(command .. " 2>&1; echo exit=$?"))
	local out = pipe:read("*a")
	pipe:close()
	return out:match("exit=0\n$") ~= nil, out
end

local function Check(old, new)
	local a, b = ListFile(old), ListFile(new)
	local passed, out = Run(("python3 tests/check_toylist.py --old %s --new %s"):format(a, b))
	os.remove(a)
	os.remove(b)
	return passed, out
end

describe("ToyList.lua", function()
	it("only grows at the end: appended toys pass", function()
		assert.is_true((Check({ 5, 9, 7 }, { 5, 9, 7 })), "the same list")
		assert.is_true((Check({ 5, 9, 7 }, { 5, 9, 7, 2, 40 })), "new toys at the end, in any order")
		assert.is_true((Check({}, { 5, 9 })), "the first list")
	end)

	it("only grows at the end: a toy removed, moved or inserted is refused with the place", function()
		local passed, out = Check({ 5, 9, 7 }, { 5, 9 })
		assert.is_false(passed)
		assert.is_truthy(out:find("shrank from 3 to 2", 1, true), out)
		passed, out = Check({ 5, 9, 7 }, { 5, 7, 9 })
		assert.is_false(passed)
		assert.is_truthy(out:find("place 1 held item 9 and now holds 7", 1, true), out)
		assert.is_false((Check({ 5, 9, 7 }, { 3, 5, 9, 7 })), "a toy inserted at the start moves every other")
		passed, out = Check({ 5, 9 }, { 5, 9, 11, 5 })
		assert.is_false(passed)
		assert.is_truthy(out:find("item 5 is listed twice", 1, true), out)
	end)

	it("compares item IDs, not text", function()
		local a = Write("ns.TOY_IDS = {\n\t5,\n\t9,\n}\n")
		local b = Write("-- another header\nns.TOY_IDS = {\n\t5,\n\t9,\n\t12,\n}\n")
		assert.is_true((Run(("python3 tests/check_toylist.py --old %s --new %s"):format(a, b))))
		os.remove(a)
		os.remove(b)
	end)

	it("the shipped list is as the check reads it, and doesn't repeat a toy", function()
		local ns = {}
		assert(loadfile("ToyList.lua"))("Clicky", ns)
		local file = assert(io.open("ToyList.lua"))
		local text = file:read("*a")
		file:close()
		local _, lines = text:gsub("\n\t%d+,", "")
		assert.are.equal(#ns.TOY_IDS, lines, "every ID line is read")
		local seen = {}
		for _, id in ipairs(ns.TOY_IDS) do
			assert.is_nil(seen[id], id .. " is listed twice")
			seen[id] = true
		end
		local passed, out = Run("python3 tests/check_toylist.py --old ToyList.lua --new ToyList.lua")
		assert.is_true(passed, out)
		assert.is_truthy(out:find(("%d toys"):format(#ns.TOY_IDS)), out)
	end)

	it("the update script appends new toys sorted, keeps toys the game dropped, and changes nothing otherwise", function()
		local function Merge(listed, inGame)
			local code = ("import sys; sys.path.insert(0, 'tools'); import update_toys as u; "
				.. "ids, added, missing = u.merge(%s, %s); print(ids, added, missing)"):format(listed, inGame)
			local passed, out = Run(("python3 -c %q"):format(code))
			assert.is_true(passed, out)
			return (out:gsub("exit=0\n$", ""):gsub("\n$", ""))
		end
		assert.are.equal("[5, 9, 7, 2, 40] [2, 40] []", Merge("[5, 9, 7]", "{40, 2, 5, 9, 7}"))
		assert.are.equal("[5, 9, 7] [] [9]", Merge("[5, 9, 7]", "{5, 7}"), "a toy the game dropped keeps its place")
		assert.are.equal("[2, 5, 9] [2, 5, 9] []", Merge("[]", "{9, 5, 2}"), "the first list is sorted")
		-- Writing the shipped list again, for the same build, gives the same file.
		local passed, out = Run(("python3 -c %q"):format(
			"import sys; sys.path.insert(0, 'tools'); import update_toys as u; "
			.. "t = open('ToyList.lua').read(); "
			.. "assert u.render(u.read_ids(t), u.read_build(t)) == t; print('same')"))
		assert.is_true(passed, out)
		assert.is_truthy(out:find("same", 1, true), out)
	end)
end)
