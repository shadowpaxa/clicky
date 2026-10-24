-- How a macro's toys are written into its "#clicky" line. Nothing here touches the game, so all of
-- it is on ns, for the other files and the offline tests:
--   ns.MACRO_TOY_CAP
--   ns.EncodeToys(positions)          -> data (format 5)
--   ns.DecodeToys(data)               -> { format (4 or 5), positions }, and for format 4 also
--                                        highest, count, checks
--                                        | nil, "newer" | "damaged"
--   ns.CheckNumbers(itemIDs)          -> checks    format 4: remove before the first full release
--   ns.SameChecks(a, b)                            format 4: remove before the first full release
--
-- A macro stores its toys as positions (0-based) in Clicky's toy list (ToyList.lua), which only
-- grows at the end, so a toy's position never changes.
--
-- data = one header character (format version * 8 + Rice parameter r), then a bit string six
-- bits per character in base64's alphabet (no "|", WoW's escape character, and no spaces): the
-- positions as Rice-coded gaps, then two checksum characters. Gaps are p1 and p(i) - p(i-1) - 1;
-- each is q = gap >> r one-bits, a zero, then gap's low r bits. The last character before the
-- checksum is padded with one-bits, which read as an unfinished gap and end the list. A position
-- past the end of the reader's toy list means the macro holds a toy it doesn't know yet (a newer
-- list), which Macros.lua reads as a newer version.
--
-- Format 4 (written by 0.4.0, read only to convert it; formats 1 to 3 read as damaged) put,
-- after the header, the highest item ID of the game's toys then (21 bits), their count (12 bits)
-- and CHECK_COUNT check numbers of them (21 bits each) before the positions. Check number j is
-- the sum over every item ID x in the list of x^j mod CHECK_PRIME. The positions were in the
-- game's toys sorted by item ID, so Macros.lua reads a format 4 macro only if the toys now,
-- up to its highest ID, give exactly its count and check numbers.
-- Lua 5.1's numbers are doubles, exact to 2^53, and there are no bitwise operators. Every
-- product here multiplies two numbers below 2^21, so it stays below 2^42 and is exact.
--
-- The fixed rule every macro follows: at most MACRO_TOY_CAP = 150 toys, guaranteed to fit while
-- the toy list has up to 12,501 toys. The arithmetic (tests/test_journeys.lua checks it):
--   255 body characters, minus the /click line (a fixed 36 characters), the newline
--   and "#clicky ", leave 210 data characters. The header and the two checksum characters leave
--   207 for the positions = 1242 bits. A k-toy macro over N toys takes at most
--   k * (r + 1) + floor((N - k) / 2^r) bits with Rice parameter r (the encoder picks the best r).
--   With r = 6, 150 toys over 12,501 take 150 * 7 + floor(12351 / 64) = 1050 + 192 = 1242 bits.

local _, ns = ...

local MACRO_TOY_CAP = 150
local CHECK_COUNT = 16
local CHECK_PRIME = 2097143 -- the largest prime below 2^21
local CHECK_BITS = 21
local COUNT_BITS = 12
local HIGHEST_BITS = 21
local FORMAT_VERSION = 5
local OLD_FORMAT_VERSION = 4
local MAX_RICE = 7
-- Format 4's header character and the numbers before the positions.
local OLD_PREFIX_CHARS = 1 + math.ceil((HIGHEST_BITS + COUNT_BITS + CHECK_COUNT * CHECK_BITS) / 6)

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
-- Check numbers (format 4: remove before the first full release).

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

-- positions: sorted, distinct, 0-based.
local function EncodeToys(positions)
	local best, bestBits = 0, RiceBits(positions, 0)
	for r = 1, MAX_RICE do
		local bits = RiceBits(positions, r)
		if bits < bestBits then
			best, bestBits = r, bits
		end
	end
	local bits = {}
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
	if type(data) ~= "string" or #data < 3 then
		return nil, "damaged"
	end
	local first = VALUE[data:byte(1)]
	if not first then
		return nil, "damaged"
	end
	local version, r = math.floor(first / 8), first % 8
	if version > FORMAT_VERSION then
		return nil, "newer"
	elseif version < OLD_FORMAT_VERSION then
		return nil, "damaged"
	end
	local body = data:sub(1, -3)
	if (version == OLD_FORMAT_VERSION and #body < OLD_PREFIX_CHARS) or Checksum(body) ~= data:sub(-2) then
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
	local d, at = { format = version }, 1
	if version == OLD_FORMAT_VERSION then
		d.highest, at = ReadNumber(bits, at, HIGHEST_BITS)
		d.count, at = ReadNumber(bits, at, COUNT_BITS)
		d.checks = {}
		for j = 1, CHECK_COUNT do
			d.checks[j], at = ReadNumber(bits, at, CHECK_BITS)
			if d.checks[j] >= CHECK_PRIME then
				return nil, "damaged"
			end
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
		if d.count and prev >= d.count then
			return nil, "damaged"
		end
		positions[#positions + 1] = prev
	end
	d.positions = positions
	return d
end

ns.MACRO_TOY_CAP = MACRO_TOY_CAP
ns.CheckNumbers = CheckNumbers
ns.SameChecks = SameChecks
ns.EncodeToys = EncodeToys
ns.DecodeToys = DecodeToys
