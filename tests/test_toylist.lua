-- ToyList.lua only grows at the end (tests/check_toylist.py, which tests/run.sh also runs against
-- every release tag from v1.0.0 on that the commit contains), and tools/update_toys.py keeps it
-- that way. Both are Python, so these tests run them on small lists written to temporary files.
-- An entry is a toy's item ID, or "s<spell ID>", "i<item ID>", "m<mount ID>" or
-- "p<species ID>:<display ID>".

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

	it("is checked against the release tags from v1.0.0 on, not earlier ones", function()
		-- A throwaway repository with the check, its list reader and a ToyList.lua at each tag.
		local dir = os.tmpname()
		os.remove(dir)
		local function Commit(ids, tag)
			local list = ListFile(ids)
			assert(Run(("mv %s %s/ToyList.lua && cd %s && git add -A && git -c user.name=t -c user.email=t "
				.. "commit -qm list && git tag %s"):format(list, dir, dir, tag)))
		end
		assert(Run(("mkdir -p %s/tests %s/tools && cp tests/check_toylist.py %s/tests && "
			.. "cp tools/update_toys.py %s/tools && git -C %s init -q"):format(dir, dir, dir, dir, dir)))
		Commit({ 5, 9, 7 }, "v0.9.0-alpha1")
		Commit({ 7, 5 }, "v1.0.0")
		local function CheckNow(ids)
			local list = ListFile(ids)
			assert(Run(("mv %s %s/ToyList.lua"):format(list, dir)))
			return Run(("python3 %s/tests/check_toylist.py"):format(dir))
		end
		local passed, out = CheckNow({ 7, 5, 12 })
		assert.is_true(passed, out)
		passed, out = CheckNow({ 5, 7, 12 })
		assert.is_false(passed)
		assert.is_truthy(out:find("compared with v1.0.0", 1, true), out)
		Run("rm -rf " .. dir)
	end)

	it("the shipped list is as the check reads it, and doesn't repeat an entry", function()
		local ns = {}
		assert(loadfile("ToyList.lua"))("Clicky", ns)
		local file = assert(io.open("ToyList.lua"))
		local text = file:read("*a")
		file:close()
		local _, lines = text:gsub('\n\t"?[sim]?%d+"?,', "")
		local _, pets = text:gsub('\n\t"p%d+:%d+",', "")
		lines = lines + pets
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

	it("only grows at the end: mounts and pets' looks appended pass; one moved or a look changed is refused", function()
		assert.is_true((Check({ 5, "s7", "i8" }, { 5, "s7", "i8", "m3", "p2:20", "p2:21" })), "mounts and looks after the rest")
		local passed, out = Check({ 5, "m3", "p2:20" }, { 5, "m3", "p2:21" })
		assert.is_false(passed)
		assert.is_truthy(out:find("place 2 held pet 2:20 and now holds pet 2:21", 1, true), out)
		passed, out = Check({ 5, "m3" }, { 5, "s3" })
		assert.is_false(passed)
		assert.is_truthy(out:find("place 1 held mount 3 and now holds spell 3", 1, true), out)
		passed, out = Check({ 5 }, { 5, "p2:20", "p2:20" })
		assert.is_false(passed)
		assert.is_truthy(out:find("pet 2:20 is listed twice", 1, true), out)
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

	it("the update script reads the game's tables, lists the spells skill lines, specializations, talents and PvP talents teach, keeps the items with a Use: effect less the toys, lists every mount and each look of each pet species, and a second run changes nothing", function()
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
    "Mount": 'Name_lang,SourceText_lang,ID,Flags,SourceSpellID,MountTypeID\n"Horse, brown",Vendor,6,0,458,230\nRam,Vendor,3,68,6777,424\n',
    "MountType": "ID,Type,Capability_0\n230,0,202\n424,5,203\n",
    "BattlePetSpecies": "Description_lang,ID,CreatureID,Flags,SourceTypeEnum\n,40,9001,0,2\n,7,9002,32,-1\n,8,9999,16388,4\n,9,9001,2048,0\n",
    "Creature": "ID,Name_lang,DisplayID_0,DisplayID_1,DisplayID_2,DisplayID_3\n9001,Cat,300,301,0,0\n9002,Dog,200,0,0,0\n",
    "CreatureXDisplayInfo": "ID,CreatureDisplayInfoID,Probability,OrderIndex,CreatureID\n1,300,1,0,9001\n2,305,1,4,9001\n3,0,1,0,9002\n4,500,1,0,9999\n",
    "BattlePetDisplayOverride": "ID,PlayerConditionID,CreatureDisplayInfoID,PriorityCategory,BattlePetSpeciesID\n1,5,700,0,7\n",
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
sets = u.read_hidden(text)
print("hidden", sorted(sets["TOY_HIDDEN"]), sorted(sets["MOUNT_HIDDEN"]), sorted(sets["PET_HIDDEN"]),
      "random", sorted(sets["PET_RANDOM_LOOK"]))
print("sources", sorted(sets["TOY_SOURCE"].items()), sorted(sets["PET_SOURCE"].items()),
      "mount types", sorted(sets["MOUNT_TYPE"].items()))
]==])
		-- 9 and s77 have left the game; 9 is still an item with a use, and stays listed as a toy only.
		-- 40's Flags have the 2 bit (6 is 2 and 4): it is in TOY_HIDDEN; 5's are 4 alone: it isn't. Mount 3's
		-- have 0x40 (68 is 64 and 4): MOUNT_HIDDEN. Species 7 is HideFromJournal (32), 8 HideUntilLearned
		-- (16388 is 16384 and 4): PET_HIDDEN; 9 is neither (RandomDisplay, 2048).
		-- s200 is a specialization's own spell, s400 a talent, s500 the spell a talent shows as, s600 a
		-- PvP talent; the spell IDs of 0 are empty columns, not spells.
		-- Mounts 3 and 6 by ID. Species 40's creature has two looks in the Creature table (displays 300
		-- and 301) and a fifth in CreatureXDisplayInfo (305); 7's has one; 8's creature is only in
		-- CreatureXDisplayInfo (500); species 7 has a look a player condition gives (700). Each species
		-- also has 0, its looks the list doesn't have; species 9 takes a random look each summon
		-- (Flags 2048), so 0 is its only one.
		-- 800's only effect is an "Equip:" one (TriggerType 1): nothing to use, so it isn't listed. 600's
		-- use is shown only to a character who knows spell 436341 (the Earthen's gem eating): not listed.
		local list = ListFile({ 9, 5, "s77" })
		local passed, out = Run(("python3 -I %s %s"):format(script, list))
		os.remove(script)
		os.remove(list)
		assert.is_true(passed, out)
		assert.is_truthy(out:find("2 toys (1 listed only when owned), 7 spells, 2 items, 2 mounts (1 listed only when collected), 10 pet looks (2 species listed only when owned) in the game; 25 listed", 1, true), out)
		assert.is_truthy(out:find("hidden [40] [3] [7, 8] random [9]", 1, true), out)
		-- Toys 5 and 40 come from a vendor (1); species 7 has no source (-1); mount type 230 has no
		-- flags (a ground mount), 424 has 5 (flying and dragonriding).
		assert.is_truthy(out:find("sources [(5, 1), (40, 1)] [(8, 4), (9, 0), (40, 2)] mount types [(424, 5)]", 1, true), out)
		assert.is_truthy(out:find("added 1 toys, 7 spells, 2 items, 2 mounts, 10 pet looks: 40, s100, s200, s300, s400, s410, s500, s600, i700, i900, m3, m6, p7:0, p7:200, p7:700, p8:0, p8:500, p9:0, p40:0, p40:300, p40:301, p40:305", 1, true), out)
		assert.is_truthy(out:find("kept: 1 toys, 1 spells, 0 items, 0 mounts, 0 pet looks: 9, s77", 1, true), out)
		assert.is_truthy(out:find("[('', 9), ('', 5), ('s', 77), ('', 40), ('s', 100), ('s', 200), ('s', 300), ('s', 400), ('s', 410), ('s', 500), ('s', 600), ('i', 700), ('i', 900), ('m', 3), ('m', 6), ('p', (7, 0)), ('p', (7, 200)), ('p', (7, 700)), ('p', (8, 0)), ('p', (8, 500)), ('p', (9, 0)), ('p', (40, 0)), ('p', (40, 300)), ('p', (40, 301)), ('p', (40, 305))]", 1, true), out)
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
    "Mount": "ID,Flags,SourceSpellID,MountTypeID\n6,0,458,230\n",
    "MountType": "ID,Type\n230,0\n",
    "BattlePetSpecies": "ID,CreatureID,Flags,SourceTypeEnum\n40,9001,0,0\n",
    "Creature": "ID,DisplayID_0,DisplayID_1,DisplayID_2,DisplayID_3\n9001,300,0,0,0\n",
    "CreatureXDisplayInfo": "ID,CreatureDisplayInfoID,CreatureID\n1,300,9001\n",
    "BattlePetDisplayOverride": "ID,CreatureDisplayInfoID,BattlePetSpeciesID\n1,700,40\n",
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
			ItemXItemEffect = "has no items", ItemEffect = "has no items",
			Spell = "the Spell table for build 1.2.3 is empty",
			Mount = "Mount table for build 1.2.3 has no mounts",
			MountType = "the MountType table for build 1.2.3 is empty",
			BattlePetSpecies = "build 1.2.3 has no pets: the BattlePetSpecies table is empty",
			BattlePetDisplayOverride = "build 1.2.3 has no pets: the BattlePetDisplayOverride table is empty",
			Creature = "build 1.2.3 has no pets: the Creature table is empty",
			CreatureXDisplayInfo = "build 1.2.3 has no pets: the CreatureXDisplayInfo table is empty" }) do
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
