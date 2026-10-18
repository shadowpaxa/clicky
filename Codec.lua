-- How a macro's toys are written into its "#clicky" line, and how Clicky catches up when the
-- game's toy list has changed since. Nothing here touches the game, so all of it is on ns, for the
-- other files and the offline tests:
--   ns.MACRO_TOY_CAP, ns.TOY_BOUND, ns.CATCH_UP_LIMIT, ns.CHECK_COUNT, ns.CHECK_PRIME
--   ns.CheckNumbers(itemIDs)                     -> checks (CHECK_COUNT numbers)
--   ns.SameChecks(a, b)
--   ns.EncodeToys(highest, count, checks, positions) -> data
--   ns.DecodeToys(data)               -> { highest, count, checks, positions }
--                                        | nil, "newer" | "damaged"
--   ns.FindLearned(itemIDs, checks, count, stored) -> the toys added since | nil, reason
--   ns.FindRemoved(itemIDs, checks, count, stored, highest) -> the toys gone since | nil, reason
--
-- A macro stores its toys as positions (0-based) in the game's toys sorted by item ID (Toys.lua),
-- as the list stood when it was saved: the highest toy item ID then, how many toys there were,
-- and CHECK_COUNT check numbers of that list. Check number j is the sum over every item ID x in
-- the list of x^j mod CHECK_PRIME. Toys added to the game later almost always get higher item
-- IDs, so reading the macro against the toys up to its highest ID ignores them. Only an old item
-- turned into a toy lands inside that range, or a toy taken out of the game data leaves it: then
-- the list has m more (or fewer) toys, and the differences of the check numbers are the power sums
-- of those m toys. Newton's identities turn them into the polynomial whose roots are those toys;
-- trying every listed item ID finds added ones, and every item ID up to the macro's highest finds
-- removed ones. Up to CATCH_UP_LIMIT (= CHECK_COUNT) either way can be found. The result is only trusted if the list changed that way gives exactly the stored
-- check numbers; anything else is refused, never read as other toys.
--
-- Lua 5.1's numbers are doubles, exact to 2^53, and there are no bitwise operators. Every
-- product here multiplies two numbers below 2^21, so it stays below 2^42 and is exact. Item IDs must stay below CHECK_PRIME:
-- two IDs that are equal mod the prime couldn't be told apart.
--
-- data = one header character (format version * 8 + Rice parameter r), then a bit string six
-- bits per character in base64's alphabet (no "|", WoW's escape character, and no spaces): the
-- highest item ID (21 bits), the count (12 bits), the check numbers (21 bits each), then the
-- positions as Rice-coded gaps, then two checksum characters. Gaps are p1 and
-- p(i) - p(i-1) - 1; each is q = gap >> r one-bits, a zero, then gap's low r bits. The last
-- character before the checksum is padded with one-bits, which read as an unfinished gap and end
-- the list.
--
-- Formats 1 to 3 (without the checksum) read as damaged.
--
-- The fixed rule every macro follows: at most MACRO_TOY_CAP = 150 toys, guaranteed to fit while
-- the game has up to TOY_BOUND = 2,290 toys. The arithmetic
-- (tests/test_journeys.lua checks it):
--   255 body characters, minus the /click line (37 characters with a three-digit id), the newline
--   and "#clicky ", leave 209 data characters = 1254 bits. The 6-bit header, the 21-bit highest
--   ID, the 12-bit count and 16 x 21 = 336 bits of check numbers take 375 bits. A k-toy macro over
--   N toys takes at most k * (r + 1) + floor((N - k) / 2^r) bits of positions with Rice parameter
--   r (the encoder picks the best r). With r = 3, 150 toys over 2,290 take
--   150 * 4 + floor(2140 / 8) = 867 bits, and 375 + 867 + 12 for the checksum = 1254.

local _, ns = ...

local MACRO_TOY_CAP = 150
local TOY_BOUND = 2290
local CHECK_COUNT = 16
local CHECK_PRIME = 2097143 -- the largest prime below 2^21
local CHECK_BITS = 21
local COUNT_BITS = 12
local HIGHEST_BITS = 21
local FORMAT_VERSION = 4
local MAX_RICE = 7
local PREFIX_CHARS = 1 + math.ceil((HIGHEST_BITS + COUNT_BITS + CHECK_COUNT * CHECK_BITS) / 6)

local ALPHABET = "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789+/"
local CHAR, VALUE = {}, {}
for i = 1, 64 do
	CHAR[i - 1] = ALPHABET:sub(i, i)
	VALUE[ALPHABET:byte(i)] = i - 1
end

-- Two checksum characters for data (Fletcher's checksum, mod 64): the sum of the character values,
-- and the sum of the running sums, which weighs each character by its place. Changing any one
-- character changes the first, since two characters' values differ by less than 64; adding,
-- removing or swapping characters changes the second, except by a 1-in-64 chance. A hand-edited
-- line then reads as damaged rather than as other toys.
local function Checksum(data)
	local a, b = 0, 0
	for i = 1, #data do
		a = (a + (VALUE[data:byte(i)] or 0)) % 64
		b = (b + a) % 64
	end
	return CHAR[a] .. CHAR[b]
end

------------------------------------------------------------------------------------------
-- Check numbers.

local function CheckNumbers(itemIDs)
	local checks = {}
	for j = 1, CHECK_COUNT do
		checks[j] = 0
	end
	for _, x in ipairs(itemIDs) do
		local power = 1
		for j = 1, CHECK_COUNT do
			power = power * x % CHECK_PRIME
			checks[j] = (checks[j] + power) % CHECK_PRIME
		end
	end
	return checks
end

local function SameChecks(a, b)
	for j = 1, CHECK_COUNT do
		if a[j] ~= b[j] then
			return false
		end
	end
	return true
end

local function PowMod(base, e)
	local result = 1
	base = base % CHECK_PRIME
	while e > 0 do
		if e % 2 == 1 then
			result = result * base % CHECK_PRIME
		end
		base = base * base % CHECK_PRIME
		e = math.floor(e / 2)
	end
	return result
end

-- 1/k mod CHECK_PRIME for k = 1..CHECK_COUNT (Fermat: k^(p-2)).
local INVERSE = {}
for k = 1, CHECK_COUNT do
	INVERSE[k] = PowMod(k, CHECK_PRIME - 2)
end

-- The m toys' power sums -> the coefficients e(1..m) of the polynomial whose roots they are, by
-- Newton's identities: k * e(k) = sum over i = 1..k of (-1)^(i-1) * e(k-i) * sums(i).
local function Elementary(sums, m)
	local e = { [0] = 1 }
	for k = 1, m do
		local acc = 0
		for i = 1, k do
			local term = e[k - i] * sums[i] % CHECK_PRIME
			if i % 2 == 1 then
				acc = acc + term
			else
				acc = acc - term
			end
		end
		e[k] = acc % CHECK_PRIME * INVERSE[k] % CHECK_PRIME
	end
	return e
end

-- x^m - e1 x^(m-1) + e2 x^(m-2) - ..., by Horner's rule.
local function IsRoot(e, m, x)
	local v = 1
	for k = 1, m do
		local c = e[k]
		if k % 2 == 1 then
			c = CHECK_PRIME - c
		end
		v = (v * x + c) % CHECK_PRIME
	end
	return v == 0
end

-- checks plus (sign 1) or minus (sign -1) the check numbers of toys.
local function Shifted(checks, toys, sign)
	local out = {}
	for j = 1, CHECK_COUNT do
		out[j] = checks[j]
	end
	for _, x in ipairs(toys) do
		local power = 1
		for j = 1, CHECK_COUNT do
			power = power * x % CHECK_PRIME
			out[j] = (out[j] + sign * power) % CHECK_PRIME
		end
	end
	return out
end

-- itemIDs: the list now (any order) and its check numbers; count and stored: what a macro was
-- written against. Returns the toys added since, or nil and why not.
local function FindLearned(itemIDs, checks, count, stored)
	local m = #itemIDs - count
	if m < 0 then
		return nil, "fewer toys than when it was written"
	elseif m > CHECK_COUNT then
		return nil, "too many toys added since"
	end
	-- Power sums of the added toys.
	local sums = {}
	for j = 1, CHECK_COUNT do
		sums[j] = (checks[j] - stored[j]) % CHECK_PRIME
	end
	local e = Elementary(sums, m)
	-- The added toys are in the list now, so trying every listed item ID finds them.
	local learned = {}
	for _, x in ipairs(m > 0 and itemIDs or {}) do
		if IsRoot(e, m, x) then
			learned[#learned + 1] = x
		end
	end
	if #learned ~= m then
		return nil, "the check numbers don't add up"
	end
	-- The list without them must be exactly the one the macro was written against.
	if not SameChecks(Shifted(checks, learned, -1), stored) then
		return nil, "the check numbers don't match"
	end
	return learned
end

-- The other way round: the macro was written while the list had more toys, and some have been
-- taken out of the game data since. Gone toys aren't in the list any more, but their item IDs are
-- at most the highest the macro was written against, so trying every item ID up to it finds them.
-- That's one IsRoot per item ID, done once per saved list per session (Macros.lua caches it).
-- Returns the toys gone since, or nil and why not.
local function FindRemoved(itemIDs, checks, count, stored, highest)
	local m = count - #itemIDs
	if m <= 0 then
		return nil, "no fewer toys than when it was written"
	elseif m > CHECK_COUNT then
		return nil, "too many toys gone since"
	end
	local sums = {}
	for j = 1, CHECK_COUNT do
		sums[j] = (stored[j] - checks[j]) % CHECK_PRIME
	end
	local e = Elementary(sums, m)
	local gone = {}
	for x = 1, highest do
		if IsRoot(e, m, x) then
			gone[#gone + 1] = x
		end
	end
	if #gone ~= m then
		return nil, "the check numbers don't add up"
	end
	-- The list with them back must be exactly the one the macro was written against: the gone
	-- toys were solved from the first m check numbers, so a wrong guess passes only if the other
	-- CHECK_COUNT - m all match by chance.
	if not SameChecks(Shifted(checks, gone, 1), stored) then
		return nil, "the check numbers don't match"
	end
	return gone
end

------------------------------------------------------------------------------------------
-- Bits.

local function PushNumber(bits, value, width)
	for i = width - 1, 0, -1 do
		local bit = 2 ^ i
		if value >= bit then
			bits[#bits + 1] = 1
			value = value - bit
		else
			bits[#bits + 1] = 0
		end
	end
end

local function ReadNumber(bits, at, width)
	local value = 0
	for i = at, at + width - 1 do
		value = value * 2 + bits[i]
	end
	return value, at + width
end

local function RiceBits(positions, r)
	local bits, prev, step = 0, -1, 2 ^ r
	for _, p in ipairs(positions) do
		bits = bits + math.floor((p - prev - 1) / step) + 1 + r
		prev = p
	end
	return bits
end

-- highest: the list's highest item ID; count: its toys; checks: their check numbers; positions:
-- sorted, distinct, 0-based, < count.
local function EncodeToys(highest, count, checks, positions)
	local best, bestBits = 0, RiceBits(positions, 0)
	for r = 1, MAX_RICE do
		local bits = RiceBits(positions, r)
		if bits < bestBits then
			best, bestBits = r, bits
		end
	end
	local bits = {}
	PushNumber(bits, highest, HIGHEST_BITS)
	PushNumber(bits, count, COUNT_BITS)
	for j = 1, CHECK_COUNT do
		PushNumber(bits, checks[j], CHECK_BITS)
	end
	local prev, step = -1, 2 ^ best
	for _, p in ipairs(positions) do
		local gap = p - prev - 1
		for _ = 1, math.floor(gap / step) do
			bits[#bits + 1] = 1
		end
		bits[#bits + 1] = 0
		PushNumber(bits, gap % step, best)
		prev = p
	end
	while #bits % 6 ~= 0 do
		bits[#bits + 1] = 1
	end
	local out = { CHAR[FORMAT_VERSION * 8 + best] }
	for i = 1, #bits, 6 do
		out[#out + 1] = CHAR[(ReadNumber(bits, i, 6))]
	end
	local data = table.concat(out)
	return data .. Checksum(data)
end

local function DecodeToys(data)
	if type(data) ~= "string" or #data < PREFIX_CHARS then
		return nil, "damaged"
	end
	local first = VALUE[data:byte(1)]
	if not first then
		return nil, "damaged"
	end
	local version, r = math.floor(first / 8), first % 8
	if version > FORMAT_VERSION then
		return nil, "newer"
	elseif version < FORMAT_VERSION then
		return nil, "damaged"
	end
	local body = data:sub(1, -3)
	if #body < PREFIX_CHARS or Checksum(body) ~= data:sub(-2) then
		return nil, "damaged"
	end
	data = body
	local bits = {}
	for i = 2, #data do
		local v = VALUE[data:byte(i)]
		if not v then
			return nil, "damaged"
		end
		PushNumber(bits, v, 6)
	end
	local highest, at = ReadNumber(bits, 1, HIGHEST_BITS)
	local count
	count, at = ReadNumber(bits, at, COUNT_BITS)
	local checks = {}
	for j = 1, CHECK_COUNT do
		checks[j], at = ReadNumber(bits, at, CHECK_BITS)
		if checks[j] >= CHECK_PRIME then
			return nil, "damaged"
		end
	end
	local positions, prev, n = {}, -1, #bits
	while true do
		local q = 0
		while at <= n and bits[at] == 1 do
			q, at = q + 1, at + 1
		end
		if at > n then
			break -- padding, or the end of the last character
		end
		at = at + 1
		if at + r - 1 > n then
			return nil, "damaged"
		end
		local rest
		rest, at = ReadNumber(bits, at, r)
		prev = prev + 1 + q * 2 ^ r + rest
		if prev >= count then
			return nil, "damaged"
		end
		positions[#positions + 1] = prev
	end
	return { highest = highest, count = count, checks = checks, positions = positions }
end

ns.MACRO_TOY_CAP = MACRO_TOY_CAP
ns.TOY_BOUND = TOY_BOUND
ns.CATCH_UP_LIMIT = CHECK_COUNT
ns.CHECK_COUNT = CHECK_COUNT
ns.CHECK_PRIME = CHECK_PRIME
ns.CheckNumbers = CheckNumbers
ns.SameChecks = SameChecks
ns.FindLearned = FindLearned
ns.FindRemoved = FindRemoved
ns.EncodeToys = EncodeToys
ns.DecodeToys = DecodeToys
