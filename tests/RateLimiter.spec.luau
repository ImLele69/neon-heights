--!strict

local shim = require("./robloxshim")
local t = require("./harness")

local env = shim.newEnv()
local RateLimiter = env.requireServer("RateLimiter")

local USER = 12345

local function fresh(): number
	RateLimiter.clear(USER)
	return 1000
end

t.describe("RateLimiter", function()
	t.test("the first calls go through", function()
		local now = fresh()
		for i = 1, 8 do
			t.ok(RateLimiter.check(USER, "BuyModule", now), "call " .. i .. " rejected")
		end
	end)

	t.test("once the bucket is empty it blocks", function()
		local now = fresh()
		for _ = 1, 8 do
			RateLimiter.check(USER, "BuyModule", now)
		end
		t.ok(not RateLimiter.check(USER, "BuyModule", now), "the ninth has to be rejected")
	end)

	t.test("the bucket refills over time", function()
		local now = fresh()
		for _ = 1, 8 do
			RateLimiter.check(USER, "BuyModule", now)
		end
		t.ok(not RateLimiter.check(USER, "BuyModule", now))
		t.ok(
			RateLimiter.check(USER, "BuyModule", now + 1),
			"after a second it has to go through again"
		)
	end)

	t.test("refill doesn't go past capacity", function()
		local now = fresh()
		RateLimiter.check(USER, "BuyModule", now)
		-- an hour of waiting must not give more than capacity tokens
		local later = now + 3600
		local passed = 0
		for _ = 1, 50 do
			if RateLimiter.check(USER, "BuyModule", later) then
				passed += 1
			end
		end
		t.eq(passed, 8)
	end)

	t.test("actions have separate buckets", function()
		local now = fresh()
		for _ = 1, 8 do
			RateLimiter.check(USER, "BuyModule", now)
		end
		t.ok(not RateLimiter.check(USER, "BuyModule", now))
		t.ok(RateLimiter.check(USER, "Ascend", now), "Ascend must not be affected by BuyModule")
	end)

	t.test("players have separate buckets", function()
		local now = fresh()
		RateLimiter.clear(999)
		for _ = 1, 8 do
			RateLimiter.check(USER, "BuyModule", now)
		end
		t.ok(not RateLimiter.check(USER, "BuyModule", now))
		t.ok(RateLimiter.check(999, "BuyModule", now), "another user must not be blocked")
		RateLimiter.clear(999)
	end)

	t.test("an unknown action uses the default instead of always passing", function()
		local now = fresh()
		local passed = 0
		for _ = 1, 20 do
			if RateLimiter.check(USER, "AzioneMaiVista", now) then
				passed += 1
			end
		end
		t.ok(passed <= 5, "a new remote must not be left unlimited, passed " .. passed)
	end)

	t.test("a clock going backwards doesn't give free tokens", function()
		local now = fresh()
		for _ = 1, 8 do
			RateLimiter.check(USER, "BuyModule", now)
		end
		t.ok(
			not RateLimiter.check(USER, "BuyModule", now - 500),
			"going back in time doesn't refill"
		)
	end)

	t.test("clear forgets the player", function()
		local now = fresh()
		for _ = 1, 8 do
			RateLimiter.check(USER, "BuyModule", now)
		end
		t.ok(not RateLimiter.check(USER, "BuyModule", now))
		RateLimiter.clear(USER)
		t.ok(RateLimiter.check(USER, "BuyModule", now), "after clear it has to start full")
	end)

	t.test("sensitive actions are tighter than purchases", function()
		-- ascending or redeeming aren't burst actions
		t.ok(RateLimiter._limits.Ascend.capacity < RateLimiter._limits.BuyModule.capacity)
		t.ok(RateLimiter._limits.Ascend.refill < RateLimiter._limits.BuyModule.refill)
	end)

	t.test("every game remote has an explicit limit", function()
		local Remotes = { "BuyModule", "Ascend", "ClaimDaily", "ClaimCrate", "RedeemCode" }
		for _, name in Remotes do
			t.ok(RateLimiter._limits[name] ~= nil, "missing limit for " .. name)
		end
	end)
end)

return t.finish()
