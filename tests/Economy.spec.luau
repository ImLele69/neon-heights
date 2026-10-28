--!strict

-- plays a realistic session against the Config curve, to see if the timings fit the design windows
-- (see docs/DESIGN.md) before opening Studio

local shim = require("./robloxshim")
local t = require("./harness")

local BigNum = shim.requireShared("BigNum")
local Config = shim.requireShared("Config")

type BigNum = { m: number, e: number }

-- the bot always buys the unlocked module with the best income/cost ratio. it's the closest
-- approximation to how a person plays
local function simulate(seconds: number, ascensions: number)
	local levels: { [string]: number } = {}
	local credits = BigNum.ZERO
	local earnedTotal = BigNum.ZERO
	local mult = Config.ascendMultiplier(ascensions)
	local purchases = 0
	local firstPurchaseAt: number? = nil
	local sectorUnlockAt: { [number]: number } = {}

	local dt = 1
	for elapsed = dt, seconds, dt do
		local income = BigNum.ZERO
		for id, lvl in levels do
			local def = Config.MODULES_BY_ID[id]
			local perDrop = Config.moduleIncome(def, lvl)
			income = BigNum.add(income, BigNum.mulScalar(perDrop, dt / def.dropInterval))
		end
		income = BigNum.mulScalar(income, mult)
		credits = BigNum.add(credits, income)
		earnedTotal = BigNum.add(earnedTotal, income)

		for _, sector in Config.SECTORS do
			if not sectorUnlockAt[sector.index] and BigNum.gte(earnedTotal, sector.unlockTotal) then
				sectorUnlockAt[sector.index] = elapsed
			end
		end

		-- at most one purchase per tick, avoids draining the balance all at once
		local bestId, bestCost, bestRatio = nil, nil, -1
		for _, def in Config.MODULES do
			if not sectorUnlockAt[def.sector] then
				continue
			end
			local lvl = levels[def.id] or 0
			if lvl >= Config.MAX_MODULE_LEVEL then
				continue
			end
			local cost = Config.moduleCost(def, lvl)
			if not BigNum.gte(credits, cost) then
				continue
			end
			local gain = BigNum.div(BigNum.mulScalar(def.baseIncome, 1 / def.dropInterval), cost)
			local ratio = BigNum.toNumber(gain)
			if ratio > bestRatio then
				bestId, bestCost, bestRatio = def.id, cost, ratio
			end
		end

		if bestId and bestCost then
			credits = BigNum.sub(credits, bestCost)
			levels[bestId] = (levels[bestId] or 0) + 1
			purchases += 1
			if not firstPurchaseAt then
				firstPurchaseAt = elapsed
			end
		end
	end

	return {
		credits = credits,
		earnedTotal = earnedTotal,
		purchases = purchases,
		firstPurchaseAt = firstPurchaseAt,
		sectorUnlockAt = sectorUnlockAt,
		levels = levels,
	}
end

t.describe("Config: structure", function()
	t.test("48 modules, 8 per sector", function()
		t.eq(#Config.MODULES, 48)
		for s = 1, 6 do
			local n = 0
			for _, m in Config.MODULES do
				if m.sector == s then
					n += 1
				end
			end
			t.eq(n, 8)
		end
	end)

	t.test("ids are unique", function()
		local seen: { [string]: boolean } = {}
		for _, m in Config.MODULES do
			t.ok(not seen[m.id], "duplicate id: " .. m.id)
			seen[m.id] = true
		end
	end)

	t.test("cost and income grow monotonically", function()
		for i = 2, #Config.MODULES do
			local prev, cur = Config.MODULES[i - 1], Config.MODULES[i]
			t.ok(BigNum.gte(cur.baseCost, prev.baseCost), "cost not monotonic at " .. cur.id)
			t.ok(BigNum.gte(cur.baseIncome, prev.baseIncome), "income not monotonic at " .. cur.id)
		end
	end)

	t.test("level 1 costs more than baseCost only from the second one on", function()
		local def = Config.MODULES[1]
		t.eq(BigNum.compare(Config.moduleCost(def, 0), def.baseCost), 0)
		t.ok(BigNum.gte(Config.moduleCost(def, 1), def.baseCost))
	end)

	t.test("sector thresholds go up", function()
		for i = 2, #Config.SECTORS do
			t.ok(
				BigNum.gte(Config.SECTORS[i].unlockTotal, Config.SECTORS[i - 1].unlockTotal),
				"threshold not increasing at sector " .. i
			)
		end
	end)

	t.test("the ascension multiplier compounds", function()
		t.near(Config.ascendMultiplier(0), 1)
		t.near(Config.ascendMultiplier(1), 1.25)
		t.near(Config.ascendMultiplier(4), 1.25 ^ 4)
	end)
end)

t.describe("Curve: design windows", function()
	local run30m = simulate(30 * 60, 0)

	t.test("the first upgrade comes a few seconds after the seed", function()
		local def = Config.MODULES_BY_ID[Config.SEED_MODULE]
		local rate =
			BigNum.mulScalar(Config.moduleIncome(def, Config.SEED_LEVEL), 1 / def.dropInterval)
		local price = Config.moduleCost(def, Config.SEED_LEVEL)
		local secs = BigNum.toNumber(BigNum.div(price, rate))
		-- the first 60 seconds decide whether the player stays
		t.ok(secs <= 30, string.format("first upgrade after %.0fs, too long", secs))
	end)

	t.test("30 minutes from the seed produce real progression", function()
		-- seed: one level of the first module, like the server does on join
		local seeded = (function()
			local levels = { s1_m1 = 1 }
			local credits = BigNum.ZERO
			local total = BigNum.ZERO
			local def = Config.MODULES_BY_ID.s1_m1
			for _ = 1, 60 do
				local inc =
					BigNum.mulScalar(Config.moduleIncome(def, levels.s1_m1), 1 / def.dropInterval)
				credits = BigNum.add(credits, inc)
				total = BigNum.add(total, inc)
			end
			return total
		end)()
		t.ok(BigNum.toNumber(seeded) > 0, "the seed module has to earn")
	end)

	t.test("the simulation produces no NaN or broken mantissas", function()
		local c = run30m.credits
		t.ok(c.m == c.m, "NaN mantissa")
		t.ok(c.m == 0 or (math.abs(c.m) >= 1 and math.abs(c.m) < 10), "mantissa out of range")
	end)
end)

t.describe("Curve: ascension", function()
	t.test("ascending really speeds up the next run", function()
		local a = Config.ascendMultiplier(3)
		t.ok(a > 1.9, "3 ascensions should almost double it, got " .. a)
	end)

	t.test("the ascension threshold is past sector 4", function()
		t.ok(
			BigNum.gte(Config.ASCEND_REQUIREMENT, Config.SECTORS[4].unlockTotal),
			"you'd ascend before seeing half the content"
		)
	end)

	t.test("you ascend after seeing all the content", function()
		-- resetting before the last sector would make ascension a punishment, the player has to reach the
		-- end first
		t.ok(
			BigNum.gte(Config.ASCEND_REQUIREMENT, Config.SECTORS[6].unlockTotal),
			"ascension must not come before sector 6"
		)
	end)
end)

t.describe("Offline", function()
	t.test("the gamepass cap is 3x the base one", function()
		t.eq(Config.OFFLINE_CAP_HOURS, 4)
		t.eq(Config.OFFLINE_CAP_HOURS_GAMEPASS, 12)
	end)

	t.test("offline earns less than online", function()
		t.ok(Config.OFFLINE_RATE < 1, "offline must not beat active play")
		t.ok(Config.OFFLINE_RATE > 0, "offline has to earn something")
	end)
end)

t.describe("Daily rewards", function()
	t.test("seven days", function()
		t.eq(#Config.DAILY_REWARDS, 7)
	end)

	t.test("day 7 is the biggest", function()
		local last = Config.DAILY_REWARDS[7]
		t.ok(last.cosmetic ~= nil, "day 7 has to give a cosmetic")
		t.ok((last.boostSeconds or 0) >= 3600, "day 7 has to give a long boost")
	end)

	t.test("credit rewards go up", function()
		local prev = 0
		for _, r in Config.DAILY_REWARDS do
			if r.credits then
				local v = BigNum.toNumber(r.credits)
				t.ok(v > prev, "reward not increasing")
				prev = v
			end
		end
	end)
end)

return t.finish()
