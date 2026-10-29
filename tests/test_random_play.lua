-- Fixed-seed random sequences of what a player does (see CLAUDE.md, Tests). Each step is checked
-- against Clicky's own results: macro bodies, button attributes, the grid's buttons, errors.

local wow = require("wow")

local function Toys()
	local toys = {}
	for i = 1, 30 do
		toys[i] = { id = 100 + i, name = ("Toy %02d"):format(i), icon = 1000 + i, favorite = i % 7 == 0 }
	end
	return toys
end

-- Spells and items the player has some of: known or not, with a cooldown or not, in the bags,
-- worn or not there, some of them items that can be worn; some spells in a flyout, one passive.
local function Spells()
	local spells = {}
	for i = 1, 6 do
		spells[i] = { id = i, name = ("Spell %d"):format(i), icon = 5000 + i, known = i % 3 ~= 0,
			flyout = i % 2 == 0 and 7 or nil, passive = i == 5 }
	end
	return spells
end

local function Items()
	local items = {}
	for i = 1, 6 do
		items[i] = { id = i, name = ("Item %d"):format(i), icon = 6000 + i, count = i % 4, equippable = i % 3 == 0 }
	end
	return items
end

-- Clicky's list: the toys, then the spells and items; a macro can hold any of them.
local function EntryList()
	local list = {}
	for i = 1, 30 do list[#list + 1] = 100 + i end
	for i = 1, 6 do list[#list + 1] = "s" .. i end
	for i = 1, 6 do list[#list + 1] = "i" .. i end
	return list
end

local function Run(seed, steps)
	math.randomseed(seed)
	local list = EntryList()
	local world = wow.New({ toys = Toys(), spells = Spells(), items = Items(), toyList = list })
	local ns = world.ns
	-- Whether the player has the entry, from the game's own state.
	local function Has(key)
		if type(key) == "number" then return world.toys[key].owned end
		local id = tonumber(key:sub(2))
		if key:sub(1, 1) == "s" then return world.spells[id].known end
		return world.items[id].count > 0 or world.items[id].equipped
	end
	local function Worn(key)
		return type(key) == "string" and key:sub(1, 1) == "i" and world.items[tonumber(key:sub(2))].equippable
	end
	local function ByText(a, b) return tostring(a) < tostring(b) end
	world:LoadCollections()
	world:OpenToyBox()
	local log = {}
	local function L(s) log[#log + 1] = s end
	local function Pick(t) return t[math.random(#t)] end
	local function RandomKey() return Pick(list) end
	local function Clicky()
		local out = {}
		for _, m in ipairs(ns.GetMacros()) do if not m.builtin then out[#out + 1] = m end end
		return out
	end
	local names = { "Alpha", "Beta", "Gamma", "Delta", "Eps", "Zeta", "Eta", "Theta" }
	local function Check(where)
		-- no Lua errors
		assert(#world.luaErrors == 0, where .. ": lua error " .. tostring(world.luaErrors[1]))
		if world.combat then return end
		-- every macro with a data line is a Clicky macro with the right toys, distinct ids
		local seen = {}
		for _, m in ipairs(world.macros) do
			local id = m.body:match("Clicky(" .. ("[BCDFGHJKLMNPQRSTVWXZ]"):rep(4) .. ")%f[%W]")
			local data = m.body:match("\n#clicky (%S+)")
			if id and data and id ~= "FVRT" then
				assert(not seen[id], where .. ": two macros share " .. id .. "\n" .. table.concat(log, "\n"))
				seen[id] = m
				local rt = ns.GetMacro(id)
				assert(rt, where .. ": no runtime macro for " .. id .. " " .. m.name .. "\n" .. table.concat(log, "\n"))
				assert(rt.name == m.name, where .. ": name " .. rt.name .. " vs " .. m.name)
				local d = ns.DecodePlaces(data)
				if not d then
					assert(rt.state ~= "ready" and not rt.entries, where .. ": damaged macro reads as toys\n" .. table.concat(log, "\n"))
				else
				local want = {}
				for _, p in ipairs(d.positions) do want[world.toyList[p + 1]] = true end
				for itemID in pairs(want) do
					assert(rt.entries and rt.entries[itemID], where .. ": " .. m.name .. " lost toy " .. itemID .. "\n" .. table.concat(log, "\n"))
				end
				for itemID in pairs(rt.entries or {}) do
					assert(want[itemID], where .. ": " .. m.name .. " gained toy " .. itemID)
				end
				end
				-- the button exists and is set up
				assert(rt.button, where .. ": no button for " .. id .. "\n" .. table.concat(log, "\n"))
				assert(rt.button:GetAttribute("useOnKeyDown") == false, where .. ": button not set up for " .. id)
				local drawer = ns.GetDrawer(id)
				assert(drawer, where .. ": no drawer for " .. id)
			end
		end
		-- every runtime macro has a record
		for _, rt in ipairs(Clicky()) do
			assert(seen[rt.id], where .. ": runtime macro " .. rt.name .. " " .. rt.id .. " without a macro\n" .. table.concat(log, "\n"))
		end
	end
	local grid = world.env.ClickyGrid
	-- What a plain click on an entry's button sets: its type, and the attribute that type reads.
	local function ActionOf(key)
		if type(key) == "number" then return "toy", "toy", key end
		local id = tonumber(key:sub(2))
		if key:sub(1, 1) == "s" then return "spell", "spell", id end
		return "item", "item", "item:" .. id
	end
	-- The spells and items the grid should list, from the game's state: the spells in the spellbook
	-- (not passive, known), the items in the bags or worn, as the search allows (the filters are the
	-- toys' only).
	local function Expected(text)
		local want = { spells = {}, items = {} }
		text = world.env.strtrim(text):lower()
		local function Add(set, key, name)
			if text == "" or name:lower():find(text, 1, true) then set[key] = true end
		end
		for id, spell in pairs(world.spells) do
			if spell.known and not spell.passive then Add(want.spells, "s" .. id, spell.name) end
		end
		for id, item in pairs(world.items) do
			if item.count > 0 or item.worn then Add(want.items, "i" .. id, item.name) end
		end
		return want
	end
	local TABS = { toys = 1, spells = 2, items = 3 }
	local function GridChecks(where)
		for i, b in ipairs(grid.buttons) do
			if b:IsShown() then
				assert(b.entry, where .. ": shown button without an entry")
				local t1 = b:GetAttribute("type1")
				if t1 then
					local action, attribute, value = ActionOf(b.entry)
					assert(t1 == action and b:GetAttribute(attribute) == value,
						where .. ": button shows " .. tostring(b.entry) .. " uses " .. t1 .. " " .. tostring(b:GetAttribute(attribute)))
				end
				assert(b.icon.texture == ns.EntryIcon(b.entry), where .. ": icon mismatch on button " .. i)
			else
				assert(b:GetAttribute("type1") == nil and b:GetAttribute("toy") == nil and b:GetAttribute("spell") == nil
					and b:GetAttribute("item") == nil, where .. ": hidden button with action")
			end
		end
		if not world.combat and not next(world.mouse) then
			-- after a redraw the buttons show GridView of the rows of GridSections
			local entries = world:GridFilterMenu()
			local f = { collected = entries[1].isSelected(), uncollected = entries[2].isSelected(), usableOnly = entries[3].isSelected() }
			local sections = ns.GridSections(f, grid.search:GetText())
			local want = Expected(grid.search:GetText())
			for _, section in ipairs({ sections[2], sections[3] }) do
				local got = {}
				for _, key in ipairs(section.keys) do got[key] = true end
				local expected = want[section.name]
				for key in pairs(got) do assert(expected[key], where .. ": the grid lists " .. key .. " under " .. section.name) end
				for key in pairs(expected) do assert(got[key], where .. ": the grid lacks " .. key .. " under " .. section.name) end
			end
			local state = ns.GetGridState()
			local shownTab = TABS[state:match("showing (%a+),")]
			for i, section in ipairs(sections) do
				local title = ({ "Toys", "Spells", "Items" })[i]
				assert(grid.Tabs[i].text == ("%s (%d)"):format(title, #section.keys),
					where .. ": tab " .. tostring(grid.Tabs[i].text) .. " for " .. #section.keys .. " " .. section.name)
			end
			assert(grid.filterButton:IsShown() == (shownTab == 1), where .. ": the filter button is on the Toys tab only")
			local rows = ns.GridRows(sections[shownTab], 12)
			local first = tonumber(state:match("top row (%d+) of"))
			local view = ns.GridView(rows, first)
			local wantKeys = {}
			for _, e in ipairs(view) do for _, key in ipairs(e.row.keys) do wantKeys[#wantKeys + 1] = key end end
			local got = {}
			for _, b in ipairs(grid.buttons) do if b:IsShown() then got[#got + 1] = b.entry end end
			assert(#wantKeys == #got, where .. ": grid shows " .. #got .. " entries, wants " .. #wantKeys .. " " .. state)
			for i = 1, #wantKeys do assert(wantKeys[i] == got[i], where .. ": grid entry " .. i .. " is " .. tostring(got[i]) .. " wants " .. tostring(wantKeys[i])) end
			-- each shown button's click
			for _, b in ipairs(grid.buttons) do
				if b:IsShown() then
					local owned = Has(b.entry)
					local wrapped = type(b.entry) == "number" and world.env.C_ToyBoxInfo.NeedsFanfare(b.entry)
					local expectType = owned and not wrapped and ActionOf(b.entry) or nil
					assert(b:GetAttribute("type1") == expectType, where .. ": button " .. tostring(b.entry) .. " type1 " .. tostring(b:GetAttribute("type1")) .. " owned " .. tostring(owned) .. " wrapped " .. tostring(wrapped))
				end
			end
		end
	end
	local ops = {
		function()
			if world.combat or #world.macros == 0 then return end
			local i = math.random(#world.macros)
			local m = world.macros[i]
			local kind = math.random(4)
			if kind == 1 then
				L("add lines to " .. m.name)
				world:EditMacroInUI(i, nil, m.body .. "\n/say " .. ("x"):rep(math.random(100)))
			elseif kind == 2 then
				L("corrupt " .. m.name)
				local at = m.body:find("#clicky ", 1, true)
				if at then
					local b = m.body
					local c = at + 8 + math.random(3)
					world:EditMacroInUI(i, nil, b:sub(1, c - 1) .. (b:sub(c, c) == "A" and "B" or "A") .. b:sub(c + 1))
				end
			elseif kind == 3 then
				L("remove data line of " .. m.name)
				world:EditMacroInUI(i, nil, (m.body:gsub("\n#clicky [^\n]*", "")))
			else
				L("pickup " .. m.name)
				local mm = ns.GetMacro(m.body:match("Clicky(" .. ("[BCDFGHJKLMNPQRSTVWXZ]"):rep(4) .. ")%f[%W]") or "")
				if mm then ns.PickupMacro(mm) end
			end
		end,
		function()
			L("favorites op")
			local k = math.random(3)
			if k == 1 then ns.PickupMacro(ns.GetMacro(ns.FAVORITES_ID))
			elseif k == 2 then ns.RenameMacro(ns.GetMacro(ns.FAVORITES_ID), Pick(names))
			else ns.DeleteMacro(ns.GetMacro(ns.FAVORITES_ID)) end
			world:TakeErrors()
		end,
		function()
			local ents = world:GridFilterMenu()
			local e = Pick(ents)
			L("filter " .. e.text)
			e.toggle()
		end,
		function()
			local texts = { "", "Toy 1", "toy 2", "3", "zzz", "Toy 07", " Toy 1 " }
			local t = Pick(texts)
			L("search '" .. t .. "'")
			grid.search:SetText(t)
		end,
		function()
			local i = math.random(3)
			L("tab " .. i)
			if grid:IsVisible() then grid.Tabs[i].scripts.OnClick(grid.Tabs[i], "LeftButton", false) end
		end,
		function()
			local d = Pick({ -1, 1 })
			L("wheel " .. d)
			if grid:IsVisible() then world:MouseWheel(grid, d) end
		end,
		function()
			local shown = {}
			if not grid:IsVisible() then return end
			for _, b in ipairs(grid.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
			if #shown == 0 then return end
			local b = Pick(shown)
			local before = #world.used
			local wornBefore = #world.equipped
			L("grid click " .. tostring(b.entry) .. (world.combat and " (combat)" or ""))
			world:MouseClick(b)
			local used = world.used[before + 1]
			if used then assert(used == b.entry, "grid click used " .. tostring(used) .. " shows " .. tostring(b.entry)) end
			-- An item that can be worn and isn't is worn instead of used.
			if #world.equipped > wornBefore then assert(world.equipped[#world.equipped] == tonumber(tostring(b.entry):sub(2))) end
			world:TakeErrors()
		end,
		function()
			local shown = {}
			if not grid:IsVisible() then return end
			for _, b in ipairs(grid.buttons) do if b:IsShown() then shown[#shown + 1] = b end end
			if #shown == 0 then return end
			local b = Pick(shown)
			L("grid right click " .. tostring(b.entry))
			world:MouseClick(b, "RightButton")
		end,
		function()
			local id = 100 + math.random(30)
			L("star " .. id)
			world.env.C_ToyBox.SetIsFavorite(id, not world.toys[id].favorite)
			ns.Changed()
		end,
		function()
			local i = math.random(6)
			if math.random(2) == 1 then
				local spell = world.spells[i]
				spell.known, spell.cooldown = math.random(3) > 1, math.random(3) == 1 and 30 or 0
				L("spell " .. i .. " known " .. tostring(spell.known) .. " cooldown " .. spell.cooldown)
				world:Fire("SPELLS_CHANGED")
			else
				local item = world.items[i]
				item.count, item.equipped = math.random(0, 2), item.equippable and math.random(2) == 1
				item.worn = item.equipped and 10 + i or nil
				item.cooldown = math.random(3) == 1 and 30 or 0
				L("item " .. i .. " count " .. item.count .. " worn " .. tostring(item.equipped))
				world:Fire("BAG_UPDATE_DELAYED")
			end
		end,
		function()
			local c = Clicky()
			if #c == 0 then return end
			local m = Pick(c)
			local d = ns.GetDrawer(m.id)
			if not d or not d.frame:IsShown() then return end
			local button = d.buttons[math.random(math.max(1, d.frame:GetAttribute("count") or 0))]
			if not button or not button:IsShown() or not button.entry then return end
			local key, before, wornBefore = button.entry, #world.used, #world.equipped
			local toWear = Worn(key) and not world.items[tonumber(key:sub(2))].equipped
			L("drawer click " .. m.name .. " " .. key)
			button:Click("LeftButton", false)
			world:TakeErrors()
			-- An item that can be worn and isn't is worn instead of used (the game's item action).
			if toWear then
				assert(#world.equipped == wornBefore + 1 and #world.used == before, "the drawer should wear " .. key)
			else
				assert(#world.equipped == wornBefore and #world.used == before + 1 and world.used[#world.used] == key,
					"the drawer should use " .. key .. "\n" .. table.concat(log, "\n"))
			end
		end,
		function()
			local id = 100 + math.random(30)
			if world.toys[id].owned then
				L("unlearn " .. id)
				world.toys[id].owned = false
			else
				L("learn " .. id)
				world:LearnToy({ id = id, fanfare = math.random(2) == 1 })
			end
			world:Fire("TOYS_UPDATED", id, false)
		end,
		function()
			local id = 100 + math.random(30)
			local b
			for _, x in ipairs(grid.buttons) do if x:IsShown() and x.itemID == id then b = x end end
			if b then L("hover " .. id); b:GetScript("OnEnter")(b) end
		end,
		function()
			L("hold mouse")
			local shown
			for _, x in ipairs(grid.buttons) do if x:IsShown() then shown = x break end end
			if shown and grid:IsVisible() and not next(world.mouse) then world:HoldMouse(shown) end
		end,
		function()
			L("release mouse")
			for button in pairs(world.mouse) do
				local shown
				for _, x in ipairs(grid.buttons) do if x:IsShown() then shown = x break end end
				if shown and grid:IsVisible() then world:ReleaseMouse(shown, button) else world.mouse[button] = nil end
			end
		end,
		function()
			L("close/open toybox")
			if grid:IsVisible() then world:CloseToyBox() else world:OpenToyBox() end
		end,
		function()
			local name = Pick(names) .. math.random(3)
			L("make " .. name)
			ns.MakeMacro(name, RandomKey())
		end,
		function()
			local c = Clicky()
			if #c == 0 then return end
			local m, id = Pick(c), RandomKey()
			local on = math.random(2) == 1
			L("settoy " .. m.name .. " " .. id .. " " .. tostring(on))
			ns.SetEntry(m, id, on)
		end,
		function()
			local c = Clicky()
			if #c == 0 then return end
			local m = Pick(c)
			local name = Pick(names) .. math.random(3)
			L("rename " .. m.name .. " -> " .. name)
			ns.RenameMacro(m, name)
		end,
		function()
			local c = Clicky()
			if #c == 0 then return end
			local m = Pick(c)
			L("delete " .. m.name)
			ns.DeleteMacro(m)
		end,
		function()
			if world.combat then return end
			L("combat")
			local expect = {}
			for _, m in pairs({ns.GetMacro(ns.FAVORITES_ID), unpack(Clicky())}) do
				if m.button and m.setUp then
					local c = ns.GetCandidates(m, true)
					table.sort(c, ByText)
					expect[m] = c
				end
			end
			world:EnterCombat()
			for m, c in pairs(expect) do
				local got = {}
				for i = 1, m.button:GetAttribute("readycount") or 0 do got[i] = m.button:GetAttribute("ready" .. i) end
				table.sort(got, ByText)
				assert(table.concat(got, ",") == table.concat(c, ","), "ready list of " .. m.name .. ": " .. table.concat(got, ",") .. " vs " .. table.concat(c, ",") .. "\n" .. table.concat(log, "\n"))
				local d = ns.GetDrawer(m.id)
				assert(d.frame:GetAttribute("count") == #ns.GetMacroEntries(m), "drawer of " .. m.name .. " not filled at combat start")
			end
		end,
		function()
			if not world.combat then return end
			L("leave combat")
			world:LeaveCombat()
		end,
		function()
			if world.combat or #world.macros == 0 then return end
			local src = Pick(world.macros)
			local name = Pick(names) .. "c" .. math.random(3)
			L("copy in /macro " .. src.name .. " as " .. name)
			if #world.macros < 120 then world:CreateMacroInUI(name, src.body) end
		end,
		function()
			if world.combat or #world.macros == 0 then return end
			local i = math.random(#world.macros)
			local name = Pick(names) .. "r" .. math.random(3)
			L("rename in /macro #" .. i .. " " .. world.macros[i].name .. " -> " .. name)
			world:EditMacroInUI(i, name)
		end,
		function()
			if world.combat or #world.macros == 0 then return end
			local i = math.random(#world.macros)
			L("delete in /macro #" .. i .. " " .. world.macros[i].name)
			table.remove(world.macros, i)
			world:Fire("UPDATE_MACROS")
		end,
		function()
			if world.combat or #world.macros == 0 then return end
			math.random(#world.macros) -- keeps each seed's sequence
			-- a player's own macro
			L("own macro")
			world:CreateMacroInUI("Own" .. math.random(5), "/cast Fireball")
		end,
		function()
			world:Advance(math.random() * 2)
		end,
		function()
			L("enter world")
			world:Fire("PLAYER_ENTERING_WORLD", false, false)
		end,
		function()
			local id = 100 + math.random(30)
			world.toys[id].favorite = not world.toys[id].favorite
			world:Fire("TOYS_UPDATED", id, false)
		end,
		function()
			local c = Clicky()
			c[#c + 1] = ns.GetMacro(ns.FAVORITES_ID)
			local m = Pick(c)
			if not m.button then return end
			local before, wornBefore = #world.used, #world.equipped
			local ready = {}
			for i = 1, m.button:GetAttribute("readycount") or 0 do ready[m.button:GetAttribute("ready" .. i)] = true end
			L("press " .. m.name .. (world.combat and " (combat)" or ""))
			m.button:Click("LeftButton", false)
			world:TakeErrors()
			assert(#world.equipped == wornBefore, "a click wore an item\n" .. table.concat(log, "\n"))
			local used = world.used[before + 1]
			if used then
				assert(not Worn(used), "a click used " .. used .. ", which only the drawer uses\n" .. table.concat(log, "\n"))
				assert(m.button:GetAttribute("entry") == used, "the button holds " .. tostring(m.button:GetAttribute("entry")) .. " used " .. used)
				if world.combat then
					assert(ready[used], "combat used " .. used .. " not ready\n" .. table.concat(log, "\n"))
				else
					assert(Has(used), "used " .. used .. " that the player doesn't have")
					assert(ns.MacroEntries(m)[used], "used " .. used .. " that isn't in " .. m.name .. "\n" .. table.concat(log, "\n"))
				end
			end
		end,
		function()
			local c = Clicky()
			if #c == 0 then return end
			local m = Pick(c)
			local d = ns.GetDrawer(m.id)
			if d then
				L("open drawer " .. m.name)
				d.opener:Click("RightButton", false)
				world:TakeErrors()
				if not world.combat then
					local owned = #ns.GetMacroEntries(m)
					assert(d.frame:GetAttribute("count") == owned, "drawer holds " .. tostring(d.frame:GetAttribute("count")) .. " owned " .. owned .. "\n" .. table.concat(log, "\n"))
				end
			end
		end,
	}
	for step = 1, steps do
		local op = Pick(ops)
		op()
		world:TakeErrors()
		Check("step " .. step)
		if grid:IsVisible() then
			if not world.combat and not next(world.mouse) then world:Advance(1) end
			GridChecks("step " .. step .. " grid\n" .. table.concat(log, "\n"))
		end
	end
	if world.combat then world:LeaveCombat() end
	for button in pairs(world.mouse) do world.mouse[button] = nil end
	world:Advance(5)
	Check("end")
	if grid:IsVisible() then GridChecks("end\n" .. table.concat(log, "\n")) end
end

describe("fuzz", function()
	for seed = 1, 40 do
		it("seed " .. seed, function() Run(seed, 150) end)
	end
end)
