-- Fixed-seed random sequences of what a player does (see CLAUDE.md, Tests). Each step is checked
-- against Clicky's own results: macro bodies, button attributes, the grid's buttons, errors.

local wow = require("wow")

local function Toys()
	local toys = {}
	for i = 1, 30 do
		toys[i] = { id = 100 + i, name = ("Toy %02d"):format(i), icon = 1000 + i }
	end
	return toys
end

local function Positions(world, body)
	local data = body:match("\n#clicky (%S+)")
	local d = data and world.ns.DecodePlaces(data)
	if not d then return nil end
	local out = {}
	for _, p in ipairs(d.positions) do out[#out + 1] = p end
	return out
end

local function Run(seed, steps)
	math.randomseed(seed)
	local newList, oldList = {}, {}
	for i = 1, 30 do newList[i] = 100 + i end
	for i = 1, 20 do oldList[i] = 100 + i end
	local a = wow.New({ toys = Toys(), toyList = newList })
	local b = wow.New({ account = a.account, toyList = oldList })
	local worlds = { a, b }
	local log = {}
	local names = { "Alpha", "Beta", "Gamma", "Delta" }
	for _ = 1, steps do
		local w = worlds[math.random(2)]
		local other = w == a and b or a
		local ns = w.ns
		local k = math.random(6)
		local macros = {}
		for _, m in ipairs(ns.GetMacros()) do if not m.builtin then macros[#macros + 1] = m end end
		if k == 1 then
			local n = names[math.random(#names)] .. math.random(3)
			log[#log + 1] = (w == a and "A" or "B") .. " make " .. n
			ns.MakeMacro(n, 100 + math.random(30))
		elseif k <= 4 and #macros > 0 then
			local m = macros[math.random(#macros)]
			local id = 100 + math.random(30)
			local on = math.random(2) == 1
			log[#log + 1] = (w == a and "A" or "B") .. " settoy " .. m.name .. " " .. id .. " " .. tostring(on)
			local state = m.state
			local bodyBefore
			for _, x in ipairs(a.macros) do if x.name == m.name then bodyBefore = x.body end end
			local ok = ns.SetEntry(m, id, on)
			if state ~= "ready" then
				assert(not ok, "changed a macro that can't be read")
				for _, x in ipairs(a.macros) do if x.name == m.name then assert(x.body == bodyBefore, "wrote an unreadable macro") end end
			end
		elseif k == 5 and #macros > 0 then
			local m = macros[math.random(#macros)]
			log[#log + 1] = (w == a and "A" or "B") .. " delete " .. m.name
			ns.DeleteMacro(m)
		else
			log[#log + 1] = (w == a and "A" or "B") .. " rename"
			if #macros > 0 then ns.RenameMacro(macros[math.random(#macros)], names[math.random(#names)] .. math.random(3)) end
		end
		other:Fire("UPDATE_MACROS")
		w:Fire("UPDATE_MACROS")
		-- invariant: B reads a macro as ready only if every toy is in its list; its toys are right
		for _, world in ipairs(worlds) do
			for _, m in ipairs(world.ns.GetMacros()) do
				if not m.builtin then
					local rec
					for _, x in ipairs(a.macros) do if x.name == m.name then rec = x end end
					assert(rec, "no record for " .. m.name .. "\n" .. table.concat(log, "\n"))
					local pos = Positions(a, rec.body)
					local limit = #world.toyList
					local tooBig = false
					for _, p in ipairs(pos or {}) do if p >= limit then tooBig = true end end
					if pos and not tooBig then
						assert(m.state == "ready", "readable macro not ready " .. m.name .. " " .. tostring(m.state) .. "\n" .. table.concat(log, "\n"))
						for _, p in ipairs(pos) do assert(m.entries[world.toyList[p + 1]], "missing toy") end
					else
						assert(m.state ~= "ready" and not m.entries, "unreadable macro reads as toys\n" .. table.concat(log, "\n"))
					end
				end
			end
		end
	end
end

describe("fuzz2", function()
	for seed = 1, 20 do
		it("seed " .. seed, function() Run(seed, 80) end)
	end
end)
