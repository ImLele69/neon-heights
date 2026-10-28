--!strict

-- past 2^53 doubles lose integer precision, and a tycoon gets there in a few hours. values here are
-- {m, e} with m always in [1, 10) (or exactly 0)

export type BigNum = { m: number, e: number }

local BigNum = {}

local SUFFIXES = {
	"",
	"K",
	"M",
	"B",
	"T",
	"aa",
	"ab",
	"ac",
	"ad",
	"ae",
	"af",
	"ag",
	"ah",
	"ai",
	"aj",
	"ak",
	"al",
	"am",
	"an",
	"ao",
	"ap",
	"aq",
	"ar",
	"as",
	"at",
	"au",
	"av",
	"aw",
	"ax",
	"ay",
	"az",
}

local function normalize(m: number, e: number): BigNum
	if m == 0 then
		return { m = 0, e = 0 }
	end
	local sign = if m < 0 then -1 else 1
	m = math.abs(m)
	local shift = math.floor(math.log10(m))
	m = m / 10 ^ shift
	e += shift
	-- log10 on edge values can return 10.000000001 or 0.9999999
	if m >= 10 then
		m /= 10
		e += 1
	elseif m < 1 then
		m *= 10
		e -= 1
	end
	return { m = sign * m, e = e }
end

function BigNum.new(m: number, e: number?): BigNum
	return normalize(m, e or 0)
end

function BigNum.fromNumber(n: number): BigNum
	return normalize(n, 0)
end

function BigNum.toNumber(a: BigNum): number
	return a.m * 10 ^ a.e
end

function BigNum.isZero(a: BigNum): boolean
	return a.m == 0
end

function BigNum.add(a: BigNum, b: BigNum): BigNum
	if a.m == 0 then
		return { m = b.m, e = b.e }
	end
	if b.m == 0 then
		return { m = a.m, e = a.e }
	end
	-- past 16 orders of magnitude the smaller addend vanishes into the mantissa
	local diff = a.e - b.e
	if diff > 16 then
		return { m = a.m, e = a.e }
	elseif diff < -16 then
		return { m = b.m, e = b.e }
	end
	if diff >= 0 then
		return normalize(a.m + b.m / 10 ^ diff, a.e)
	end
	return normalize(b.m + a.m / 10 ^ -diff, b.e)
end

function BigNum.sub(a: BigNum, b: BigNum): BigNum
	return BigNum.add(a, { m = -b.m, e = b.e })
end

function BigNum.mul(a: BigNum, b: BigNum): BigNum
	if a.m == 0 or b.m == 0 then
		return { m = 0, e = 0 }
	end
	return normalize(a.m * b.m, a.e + b.e)
end

function BigNum.mulScalar(a: BigNum, k: number): BigNum
	if a.m == 0 or k == 0 then
		return { m = 0, e = 0 }
	end
	return normalize(a.m * k, a.e)
end

function BigNum.div(a: BigNum, b: BigNum): BigNum
	assert(b.m ~= 0, "division by zero")
	if a.m == 0 then
		return { m = 0, e = 0 }
	end
	return normalize(a.m / b.m, a.e - b.e)
end

function BigNum.compare(a: BigNum, b: BigNum): number
	if a.m == 0 and b.m == 0 then
		return 0
	end
	local sa = if a.m < 0 then -1 elseif a.m > 0 then 1 else 0
	local sb = if b.m < 0 then -1 elseif b.m > 0 then 1 else 0
	if sa ~= sb then
		return if sa < sb then -1 else 1
	end
	if a.e ~= b.e then
		local bigger = a.e > b.e
		if sa < 0 then
			bigger = not bigger
		end
		return if bigger then 1 else -1
	end
	if a.m == b.m then
		return 0
	end
	return if a.m > b.m then 1 else -1
end

function BigNum.gte(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) >= 0
end

function BigNum.lt(a: BigNum, b: BigNum): boolean
	return BigNum.compare(a, b) < 0
end

function BigNum.max(a: BigNum, b: BigNum): BigNum
	return if BigNum.compare(a, b) >= 0 then a else b
end

function BigNum.min(a: BigNum, b: BigNum): BigNum
	return if BigNum.compare(a, b) <= 0 then a else b
end

function BigNum.format(a: BigNum): string
	if a.m == 0 then
		return "0"
	end
	local sign = if a.m < 0 then "-" else ""
	local m, e = math.abs(a.m), a.e

	if e < 3 then
		local n = m * 10 ^ e
		if e >= 0 and n == math.floor(n) then
			return sign .. string.format("%d", n)
		end
		return sign .. string.format("%.1f", n)
	end

	local tier = math.floor(e / 3)
	local shown = m * 10 ^ (e % 3)
	local suffix = SUFFIXES[tier + 1]
	if not suffix then
		return sign .. string.format("%.2fe%d", m, e)
	end
	if shown >= 100 then
		return sign .. string.format("%.0f%s", shown, suffix)
	elseif shown >= 10 then
		return sign .. string.format("%.1f%s", shown, suffix)
	end
	return sign .. string.format("%.2f%s", shown, suffix)
end

-- serialization for the DataStore: two numbers, not a string to parse
function BigNum.serialize(a: BigNum): { number }
	return { a.m, a.e }
end

function BigNum.deserialize(t: { number }?): BigNum
	if type(t) ~= "table" or type(t[1]) ~= "number" or type(t[2]) ~= "number" then
		return { m = 0, e = 0 }
	end
	if t[1] ~= t[1] or t[2] ~= t[2] then -- NaN from a corrupted save
		return { m = 0, e = 0 }
	end
	return normalize(t[1], t[2])
end

BigNum.ZERO = { m = 0, e = 0 } :: BigNum
BigNum.ONE = { m = 1, e = 0 } :: BigNum

return BigNum
