-- ToyList.lua only grows at the end (tests/check_toylist.py, which tests/run.sh also runs against
-- every tag the commit contains), and tools/update_toys.py keeps it that way. Both are Python, so these tests run
-- them on small lists written to temporary files. An entry is a toy's item ID, or "s<spell ID>" or
-- "i<item ID>".

local function Write(text)
	local path = os.tmpname()
	local f = assert(io.open(path, "w"))
	f:write(text)
	f:close()
	return path
end

local function ListFile(ids)
	local lines = { "-- header", "local _, ns = ...", "ns.TOY_IDS = {" }
	for _, id in ipairs(ids) do
		lines[#lines + 1] = type(id) == "string" and ('\t"' .. id .. '",') or ("\t" .. id .. ",")
	end
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
		assert.is_truthy(out:find("place 1 held toy 9 and now holds toy 7", 1, true), out)
		assert.is_false((Check({ 5, 9, 7 }, { 3, 5, 9, 7 })), "a toy inserted at the start moves every other")
		passed, out = Check({ 5, 9 }, { 5, 9, 11, 5 })
		assert.is_false(passed)
		assert.is_truthy(out:find("toy 5 is listed twice", 1, true), out)
	end)

	it("compares entries, not text", function()
		local a = Write("ns.TOY_IDS = {\n\t5,\n\t9,\n}\n")
		local b = Write("-- another header\nns.TOY_IDS = {\n\t5,\n\t9,\n\t12,\n}\n")
		assert.is_true((Run(("python3 tests/check_toylist.py --old %s --new %s"):format(a, b))))
		os.remove(a)
		os.remove(b)
	end)

	it("the shipped list is as the check reads it, and doesn't repeat an entry", function()
		local ns = {}
		assert(loadfile("ToyList.lua"))("Clicky", ns)
		local file = assert(io.open("ToyList.lua"))
		local text = file:read("*a")
		file:close()
		local _, lines = text:gsub('\n\t"?[si]?%d+"?,', "")
		assert.are.equal(#ns.TOY_IDS, lines, "every entry line is read")
		local seen = {}
		for _, id in ipairs(ns.TOY_IDS) do
			assert.is_nil(seen[id], id .. " is listed twice")
			seen[id] = true
		end
		local passed, out = Run("python3 tests/check_toylist.py --old ToyList.lua --new ToyList.lua")
		assert.is_true(passed, out)
		assert.is_truthy(out:find(("%d entries"):format(#ns.TOY_IDS)), out)
	end)

	it("the update script writes the shipped list again as it is", function()
		local passed, out = Run(("python3 -c %q"):format(
			"import sys; sys.path.insert(0, 'tools'); import update_toys as u; "
			.. "t = open('ToyList.lua').read(); "
			.. "assert u.render(u.read_entries(t), u.read_build(t), u.read_hidden(t)) == t; print('same')"))
		assert.is_true(passed, out)
		assert.is_truthy(out:find("same", 1, true), out)
	end)

	it("only grows at the end: spells and items appended to a list of toys pass", function()
		assert.is_true((Check({ 5, 9 }, { 5, 9, "s7", "i8", "s3" })), "an old toy-only list")
		assert.is_true((Check({ 5, "s7", "i8" }, { 5, "s7", "i8", "i2" })), "a list with spells and items")
		assert.is_true((Check({ 5 }, { 5, "s5", "i5" })), "the same number as a toy, a spell and an item")
	end)

	it("only grows at the end: a spell or item moved, removed or inserted is refused with its place", function()
		local passed, out = Check({ 5, "s7", "i8" }, { 5, "i8", "s7" })
		assert.is_false(passed)
		assert.is_truthy(out:find("place 1 held spell 7 and now holds item 8", 1, true), out)
		passed, out = Check({ 5, "s7", "i8" }, { 5, "s7" })
		assert.is_false(passed)
		assert.is_truthy(out:find("shrank from 3 to 2", 1, true), out)
		passed, out = Check({ 5, "s7" }, { 5, "i7" })
		assert.is_false(passed)
		assert.is_truthy(out:find("place 1 held spell 7 and now holds item 7", 1, true), out)
		passed, out = Check({ 5, "s7", "i8" }, { 5, "s6", "s7", "i8" })
		assert.is_false(passed)
		assert.is_truthy(out:find("place 1 held spell 7 and now holds spell 6", 1, true), out)
		passed, out = Check({ 5, "i8" }, { 5, "i8", "s7", "s7" })
		assert.is_false(passed)
		assert.is_truthy(out:find("spell 7 is listed twice (second time at place 3)", 1, true), out)
		passed, out = Check({ 5 }, { 5, "i8", "i8" })
		assert.is_false(passed)
		assert.is_truthy(out:find("item 8 is listed twice", 1, true), out)
	end)

	it("the update script appends toys, then spells, then items, each sorted, and keeps what the game dropped", function()
		local function Merge(listed, inGame)
			local code = ("import sys; sys.path.insert(0, 'tools'); import update_toys as u; "
				.. "ids, added, missing = u.merge(%s, %s); print(ids, added, missing)"):format(listed, inGame)
			local passed, out = Run(("python3 -c %q"):format(code))
			assert.is_true(passed, out)
			return (out:gsub("exit=0\n$", ""):gsub("\n$", ""))
		end
		local eq = assert.are.equal
		eq("[('', 5), ('s', 3), ('', 2), ('', 40), ('s', 1), ('s', 7), ('i', 4), ('i', 8)] "
			.. "[('', 2), ('', 40), ('s', 1), ('s', 7), ('i', 4), ('i', 8)] []",
			Merge("[('', 5), ('s', 3)]",
				"{('i', 8), ('s', 7), ('', 40), ('i', 4), ('s', 1), ('', 2), ('', 5), ('s', 3)}"),
			"toys, spells, items, in ID order after what is listed")
		eq("[('', 5), ('s', 3), ('i', 8)] [] [('s', 3)]",
			Merge("[('', 5), ('s', 3), ('i', 8)]", "{('', 5), ('i', 8)}"), "a dropped spell keeps its place")
		eq("[('', 5), ('', 9), ('s', 4), ('i', 4)] [('', 5), ('', 9), ('s', 4), ('i', 4)] []",
			Merge("[]", "{('i', 4), ('s', 4), ('', 9), ('', 5)}"), "the first list: the same ID as a toy, spell and item")
	end)

	it("the update script reads the game's tables, lists the spells skill lines, specializations, talents and PvP talents teach, keeps the items with a Use: effect less the toys, and a second run changes nothing", function()
		local script = Write([==[
import sys
sys.path.insert(0, "tools")
import update_toys as u
CSV = {
    "Toy": 'SourceText_lang,ID,ItemID,Flags,SourceTypeEnum\n"Drop, rare",1,5,4,1\nVendor,2,40,6,1\n',
    "SkillLineAbility": "ID,SkillLine,Spell\n1,7,300\n2,7,0\n3,7,100\n4,8,300\n",
    "SpecializationSpells": "Description_lang,ID,SpecID,SpellID,OverridesSpellID,DisplayOrder\n,1,256,200,300,0\n,2,256,100,0,1\n",
    "TraitDefinition": "OverrideName_lang,ID,SpellID,OverridesSpellID,VisibleSpellID\n,1,400,0,0\n,2,0,0,500\n,3,410,200,0\n",
    "PvpTalent": "Description_lang,ID,SpellID\n,1,600\n,2,0\n",
    "ItemXItemEffect": "ID,ItemEffectID,ItemID\n1,1,5\n2,2,900\n3,3,0\n4,4,700\n5,5,900\n6,6,9\n7,7,800\n8,8,600\n",
    "ItemEffect": "ID,LegacySlotIndex,TriggerType,SpellID\n1,0,0,1\n2,0,0,2\n3,0,0,3\n4,0,0,4\n5,0,1,5\n6,0,0,6\n7,0,1,7\n8,0,0,8\n",
    "Spell": 'ID,NameSubtext_lang,Description_lang,AuraDescription_lang\n2,,"Returns you home, [fast].",\n8,,"$?s436341[Restores health.\nMust remain seated.][]",\n',
}
def get(url):
    assert url.endswith("?build=1.2.3"), url
    return CSV[url.split("/db2/")[1].split("/")[0]]
u.get = get
u.live_build = lambda: "1.2.3"
u.LIST_PATH = sys.argv[1]
u.main()
text = open(u.LIST_PATH).read()
u.main()
assert open(u.LIST_PATH).read() == text
print(u.read_entries(text))
print("hidden", sorted(u.read_hidden(text)))
]==])
		-- 9 and s77 have left the game; 9 is still an item with a use, and stays listed as a toy only.
		-- 40's Flags have the 2 bit (6 is 2 and 4): it is in TOY_HIDDEN; 5's are 4 alone: it isn't.
		-- s200 is a specialization's own spell, s400 a talent, s500 the spell a talent shows as, s600 a
		-- PvP talent; the spell IDs of 0 are empty columns, not spells.
		-- 800's only effect is an "Equip:" one (TriggerType 1): nothing to use, so it isn't listed. 600's
		-- use is shown only to a character who knows spell 436341 (the Earthen's gem eating): not listed.
		local list = ListFile({ 9, 5, "s77" })
		local passed, out = Run(("python3 -I %s %s"):format(script, list))
		os.remove(script)
		os.remove(list)
		assert.is_true(passed, out)
		assert.is_truthy(out:find("2 toys (1 listed only when owned), 7 spells, 2 items in the game; 13 listed", 1, true), out)
		assert.is_truthy(out:find("hidden [40]", 1, true), out)
		assert.is_truthy(out:find("added 1 toys, 7 spells, 2 items: 40, s100, s200, s300, s400, s410, s500, s600, i700, i900", 1, true), out)
		assert.is_truthy(out:find("kept: 1 toys, 1 spells, 0 items: 9, s77", 1, true), out)
		assert.is_truthy(out:find("[('', 9), ('', 5), ('s', 77), ('', 40), ('s', 100), ('s', 200), ('s', 300), ('s', 400), ('s', 410), ('s', 500), ('s', 600), ('i', 700), ('i', 900)]", 1, true), out)
	end)

	it("the update script stops, writing nothing, when a table comes back empty", function()
		local script = Write([==[
import sys
sys.path.insert(0, "tools")
import update_toys as u
CSV = {
    "Toy": "SourceText_lang,ID,ItemID,Flags,SourceTypeEnum\nVendor,1,5,0,1\n",
    "SkillLineAbility": "ID,SkillLine,Spell\n1,7,300\n",
    "SpecializationSpells": "ID,SpellID,OverridesSpellID\n1,301,0\n",
    "TraitDefinition": "ID,SpellID,OverridesSpellID,VisibleSpellID\n1,302,0,0\n",
    "PvpTalent": "ID,SpellID\n1,303\n",
    "ItemXItemEffect": "ID,ItemEffectID,ItemID\n1,1,900\n",
    "ItemEffect": "ID,LegacySlotIndex,TriggerType,SpellID\n1,0,0,1\n",
    "Spell": "ID,NameSubtext_lang,Description_lang,AuraDescription_lang\n1,,Hi,\n",
}
CSV[sys.argv[2]] = CSV[sys.argv[2]].split("\n")[0] + "\n"
u.get = lambda url: CSV[url.split("/db2/")[1].split("/")[0]]
u.live_build = lambda: "1.2.3"
u.LIST_PATH = sys.argv[1]
u.main()
]==])
		for tableName, says in pairs({ Toy = "has no toys", SkillLineAbility = "SkillLineAbility table for build 1.2.3 has no spells",
			SpecializationSpells = "SpecializationSpells table for build 1.2.3 has no spells",
			TraitDefinition = "TraitDefinition table for build 1.2.3 has no spells",
			PvpTalent = "PvpTalent table for build 1.2.3 has no spells",
			ItemXItemEffect = "has no items", ItemEffect = "has no items" }) do
			local list = ListFile({ 5 })
			local before = io.open(list):read("*a")
			local passed, out = Run(("python3 -I %s %s %s"):format(script, list, tableName))
			local after = io.open(list):read("*a")
			os.remove(list)
			assert.is_false(passed, tableName .. ": " .. out)
			assert.is_truthy(out:find(says, 1, true), out)
			assert.are.equal(before, after, tableName .. ": the list is left as it was")
		end
		os.remove(script)
	end)
end)
