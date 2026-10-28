--!strict

local BigNum = require("../src/shared/BigNum")
local t = require("./harness")

local N = BigNum.fromNumber

t.describe("BigNum", function()
	t.test("normalizes the mantissa into [1,10)", function()
		local a = BigNum.new(1234, 0)
		t.eq(a.e, 3)
		t.near(a.m, 1.234)
	end)

	t.test("round trip on small numbers", function()
		for _, n in { 0, 1, 7, 99, 1000, 123456, 2 ^ 40 } do
			t.near(BigNum.toNumber(N(n)), n)
		end
	end)

	t.test("adds with close exponents", function()
		t.near(BigNum.toNumber(BigNum.add(N(1500), N(2500))), 4000)
	end)

	t.test("add ignores negligible addends", function()
		local big = BigNum.new(1, 40)
		local r = BigNum.add(big, N(5))
		t.eq(r.e, 40)
		t.near(r.m, 1)
	end)

	t.test("zero is neutral", function()
		t.eq(BigNum.compare(BigNum.add(N(42), BigNum.ZERO), N(42)), 0)
		t.eq(BigNum.compare(BigNum.add(BigNum.ZERO, N(42)), N(42)), 0)
	end)

	t.test("subtracting down to zero", function()
		local r = BigNum.sub(N(100), N(100))
		t.ok(math.abs(BigNum.toNumber(r)) < 1e-9, "expected ~0")
	end)

	t.test("multiplying adds the exponents", function()
		local r = BigNum.mul(BigNum.new(2, 10), BigNum.new(3, 15))
		t.eq(r.e, 25)
		t.near(r.m, 6)
	end)

	t.test("division undoes multiplication", function()
		local a, b = BigNum.new(7.3, 22), BigNum.new(1.9, 8)
		local r = BigNum.div(BigNum.mul(a, b), b)
		t.eq(r.e, a.e)
		t.near(r.m, a.m)
	end)

	t.test("compare orders across exponents", function()
		t.eq(BigNum.compare(BigNum.new(1, 30), BigNum.new(9, 29)), 1)
		t.eq(BigNum.compare(BigNum.new(9, 29), BigNum.new(1, 30)), -1)
		t.eq(BigNum.compare(N(5), N(5)), 0)
	end)

	t.test("compare handles negatives", function()
		t.eq(BigNum.compare(N(-5), N(5)), -1)
		t.eq(BigNum.compare(N(-1000), N(-10)), -1)
		t.eq(BigNum.compare(N(-10), N(-1000)), 1)
	end)

	t.test("gte right at the price", function()
		local price = BigNum.new(1.5, 6)
		t.ok(BigNum.gte(BigNum.new(1.5, 6), price), "the exact amount has to be enough")
		t.ok(not BigNum.gte(BigNum.new(1.49, 6), price), "less must not be enough")
	end)

	t.test("format on small values", function()
		t.eq(BigNum.format(BigNum.ZERO), "0")
		t.eq(BigNum.format(N(7)), "7")
		t.eq(BigNum.format(N(999)), "999")
	end)

	t.test("format uses suffixes", function()
		t.eq(BigNum.format(N(1000)), "1.00K")
		t.eq(BigNum.format(N(15500)), "15.5K")
		t.eq(BigNum.format(N(999000)), "999K")
		t.eq(BigNum.format(N(1e6)), "1.00M")
		t.eq(BigNum.format(BigNum.new(1, 15)), "1.00aa")
	end)

	t.test("format keeps the sign", function()
		t.eq(BigNum.format(N(-2500)), "-2.50K")
	end)

	t.test("serializes and reads back", function()
		local a = BigNum.new(3.7, 41)
		local r = BigNum.deserialize(BigNum.serialize(a))
		t.eq(r.e, a.e)
		t.near(r.m, a.m)
	end)

	t.test("deserialize survives corrupted input", function()
		t.eq(BigNum.compare(BigNum.deserialize(nil), BigNum.ZERO), 0)
		t.eq(BigNum.compare(BigNum.deserialize({} :: any), BigNum.ZERO), 0)
		t.eq(BigNum.compare(BigNum.deserialize({ "x", 2 } :: any), BigNum.ZERO), 0)
		t.eq(BigNum.compare(BigNum.deserialize({ 0 / 0, 3 }), BigNum.ZERO), 0)
	end)

	t.test("long accumulation doesn't blow up", function()
		-- 2000 purchases at 1.18 growth: the real case of a long session
		local total = BigNum.ZERO
		local cost = N(100)
		for _ = 1, 2000 do
			total = BigNum.add(total, cost)
			cost = BigNum.mulScalar(cost, 1.18)
		end
		t.ok(total.m == total.m, "NaN mantissa")
		t.ok(total.e > 100, "expected a huge total, e=" .. total.e)
		t.ok(total.m >= 1 and total.m < 10, "mantissa out of range: " .. total.m)
	end)
end)

return t.finish()
