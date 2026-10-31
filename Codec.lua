-- How a macro's entries are written into its "#clicky" line. Nothing here touches the game, so all of
-- it is on ns, for the other files and the offline tests:
--   ns.MACRO_ENTRY_CAP                  how many entries a macro holds
--   ns.EncodePlaces(positions)          -> data (format 6); the positions of a macro's entries
--   ns.DecodePlaces(data)               -> { positions } | nil, "newer" | "damaged"
--
-- A macro stores its entries (toys, spells, items, mounts, pets) as positions (0-based) in Clicky's list
-- (ToyList.lua), which only grows at the end, so an entry's position never changes.
--
-- data = characters in base64's alphabet (no "|", WoW's escape character, and no spaces), each a
-- number from 0 to 63. Format 6: the first is 48, the second the Rice parameter r (0 to 15), then
-- a bit string six bits per character: the positions as Rice-coded gaps, then two checksum
-- characters. Gaps are p1 and p(i) - p(i-1) - 1; each is q = gap >> r one-bits, a zero, then
-- gap's low r bits. The last character before the checksum is padded with one-bits, which read as
-- an unfinished gap and end the list. A position past the end of the reader's list means the
-- macro holds an entry it doesn't know yet (a newer list), which Macros.lua reads as a newer version.
--
-- A first character above 48 is a later format (48 + n is format 6 + n; 63 is format 21 and any
-- after it), which reads as newer. Every other first character reads as damaged.
-- Lua 5.1's numbers are doubles, exact to 2^53, and there are no bitwise operators.
--
-- The fixed rule every macro follows: at most MACRO_ENTRY_CAP = 100 entries, guaranteed to fit while
-- the list has up to 140,387 places. The arithmetic (tests/test_journeys.lua checks it):
--   255 body characters, minus the /click line (a fixed 36 characters), the newline
--   and "#clicky ", leave 210 data characters. The two header and two checksum characters leave
--   206 for the positions = 1236 bits. A k-entry macro over N places takes at most
--   k * (r + 1) + floor((N - k) / 2^r) bits with Rice parameter r (the encoder picks the best r).
--   With r = 10, 100 entries over 140,387 places take 100 * 11 + floor(140287 / 1024) = 1100 + 136
--   = 1236 bits.

local _, ns = ...

local MACRO_ENTRY_CAP = 100
local FORMAT_6 = 48 -- the first character's value
local MAX_RICE = 15

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
-- line then reads as damaged rather than as other entries.
local function Checksum(data)
	local a, b = 0, 0
	for i = 1, #data do
		a = (a + (VALUE[data:byte(i)] or 0)) % 64
		b = (b + a) % 64
	end
	return CHAR[a] .. CHAR[b]
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
local function EncodePlaces(positions)
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
	local out = { CHAR[FORMAT_6], CHAR[best] }
	for i = 1, #bits, 6 do
		out[#out + 1] = CHAR[(ReadNumber(bits, i, 6))]
	end
	local data = table.concat(out)
	return data .. Checksum(data)
end

local function DecodePlaces(data)
	if type(data) ~= "string" or #data < 3 then
		return nil, "damaged"
	end
	local first = VALUE[data:byte(1)]
	if not first then
		return nil, "damaged"
	elseif first > FORMAT_6 then
		return nil, "newer"
	elseif first < FORMAT_6 then
		return nil, "damaged"
	end
	local r = VALUE[data:byte(2)]
	if not r or r > MAX_RICE then
		return nil, "damaged"
	end
	local body = data:sub(1, -3)
	if Checksum(body) ~= data:sub(-2) then
		return nil, "damaged"
	end
	local bits = {}
	for i = 3, #body do
		local v = VALUE[body:byte(i)]
		if not v then
			return nil, "damaged"
		end
		PushNumber(bits, v, 6)
	end
	local positions, prev, at, n = {}, -1, 1, #bits
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
		positions[#positions + 1] = prev
	end
	return { positions = positions }
end

ns.MACRO_ENTRY_CAP = MACRO_ENTRY_CAP
ns.EncodePlaces = EncodePlaces
ns.DecodePlaces = DecodePlaces
