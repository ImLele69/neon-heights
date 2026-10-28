--!strict

-- OrderedDataStore only takes 64-bit integers but credits go up to 10^30. we store a scaled log: if
-- the conversion is wrong the board sorts badly and nobody notices until it's public

local shim = require("./robloxshim")
local t = require("./harness")

local env = shim.newEnv()
local BigNum = env.requireShared("BigNum")
local Leaderboard = env.requireServer("Leaderboard")

local toScore = Leaderboard._toScore
local MAX_I64 = 9.22e18

t.describe("Leaderboard: scores", function()
	t.test("zero stays zero", function()
		t.eq(toScore(BigNum.ZERO), 0)
	end)

	t.test("order is kept across the whole scale", function()
		local values = {
			BigNum.new(1, 0),
			BigNum.new(5, 0),
			BigNum.new(1, 3),
			BigNum.new(9.9, 5),
			BigNum.new(1, 6),
			BigNum.new(4.2, 12),
			BigNum.new(1, 20),
			BigNum.new(7, 29),
		}
		for i = 2, #values do
			t.ok(
				toScore(values[i]) > toScore(values[i - 1]),
				string.format(
					"order broken between %s and %s",
					BigNum.format(values[i - 1]),
					BigNum.format(values[i])
				)
			)
		end
	end)

	t.test("tells apart close values in the same order of magnitude", function()
		t.ok(toScore(BigNum.new(1.1, 9)) > toScore(BigNum.new(1.0, 9)))
		t.ok(toScore(BigNum.new(9.9, 9)) > toScore(BigNum.new(9.8, 9)))
	end)

	t.test("the score fits in a 64-bit integer", function()
		for _, v in { BigNum.new(1, 0), BigNum.new(1, 100), BigNum.new(9.99, 299) } do
			local s = toScore(v)
			t.ok(s >= 0 and s < MAX_I64, "score out of range: " .. s)
			t.eq(s, math.floor(s), "OrderedDataStore wants an integer")
		end
	end)

	t.test("absurd values get clamped instead of blowing up", function()
		local s = toScore(BigNum.new(1, 9999))
		t.ok(s > 0 and s < MAX_I64, "missed clamp: " .. s)
		t.eq(s, math.floor(s))
	end)

	t.test("a negative value doesn't produce NaN", function()
		local s = toScore(BigNum.new(-5, 10))
		t.ok(s == s, "NaN in the score")
		t.ok(s >= 0, "a negative score would break the ordering")
	end)

	t.test("the round trip stays in the same order of magnitude", function()
		for _, v in { BigNum.new(1, 6), BigNum.new(4.2, 12), BigNum.new(7, 24) } do
			local back = Leaderboard._fromScore(toScore(v))
			local expected = BigNum.format(v)
			-- precision gets lost, but the suffix has to stay the same
			local backSuffix = string.match(back, "%a+$") or ""
			local expectedSuffix = string.match(expected, "%a+$") or ""
			t.eq(backSuffix, expectedSuffix)
		end
	end)
end)

t.describe("Leaderboard: config", function()
	t.test("three boards with distinct keys", function()
		t.eq(#Leaderboard.BOARDS, 3)
		local seen: { [string]: boolean } = {}
		for _, b in Leaderboard.BOARDS do
			t.ok(not seen[b.key], "duplicate key: " .. b.key)
			seen[b.key] = true
		end
	end)

	t.test("every board can extract and show its own value", function()
		local p = {
			credits = BigNum.serialize(BigNum.ZERO),
			earnedTotal = BigNum.serialize(BigNum.new(5, 9)),
			modules = {},
			ascensions = 4,
			boostUntil = 0,
			boostMult = 1,
			data = 0,
			playtime = 7200,
		}
		for _, b in Leaderboard.BOARDS do
			local v = b.value(p)
			t.ok(type(v) == "number", b.key .. " doesn't produce a number")
			t.ok(v == v, b.key .. " produces NaN")
			t.ok(type(b.display(v)) == "string", b.key .. " can't format")
		end
	end)

	t.test("an empty profile doesn't break any board", function()
		local empty = {
			credits = BigNum.serialize(BigNum.ZERO),
			earnedTotal = BigNum.serialize(BigNum.ZERO),
			modules = {},
			ascensions = 0,
			boostUntil = 0,
			boostMult = 1,
			data = 0,
			playtime = 0,
		}
		for _, b in Leaderboard.BOARDS do
			t.eq(b.value(empty), 0)
		end
	end)
end)

return t.finish()
