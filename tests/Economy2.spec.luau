--!strict

-- money rules. besides the normal cases this is where the exploits are: everything a hostile client
-- would try to send the server

local shim = require("./robloxshim")
local t = require("./harness")

local env = shim.newEnv()
local BigNum = env.requireShared("BigNum")
local Config = env.requireShared("Config")
local Economy = env.requireShared("Economy")

local NOW = 1_000_000

local function profile(over: { [string]: any }?): any
	local p = {
		credits = BigNum.serialize(BigNum.ZERO),
		earnedTotal = BigNum.serialize(BigNum.ZERO),
		modules = { [Config.SEED_MODULE] = Config.SEED_LEVEL },
		ascensions = 0,
		boostUntil = 0,
		boostMult = 1,
		data = 0,
	}
	if over then
		for k, v in over do
			p[k] = v
		end
	end
	return p
end

local function withCredits(n: any): any
	return profile({ credits = BigNum.serialize(n) })
end

t.describe("Economy: multipliers", function()
	t.test("a new profile has multiplier 1", function()
		t.near(Economy.totalMultiplier(profile(), NOW), 1)
	end)

	t.test("ascensions compound", function()
		t.near(Economy.totalMultiplier(profile({ ascensions = 2 }), NOW), 1.25 ^ 2)
	end)

	t.test("the boost only counts while active", function()
		local p = profile({ boostUntil = NOW + 100, boostMult = 2 })
		t.near(Economy.totalMultiplier(p, NOW), 2)
		t.near(Economy.totalMultiplier(p, NOW + 200), 1)
	end)

	t.test("an expired boost with a high mult doesn't count", function()
		local p = profile({ boostUntil = NOW - 1, boostMult = 10 })
		t.near(Economy.totalMultiplier(p, NOW), 1)
	end)

	t.test("the 2x gamepass multiplies with the rest", function()
		local p = profile({ ascensions = 1, boostUntil = NOW + 10, boostMult = 2 })
		t.near(Economy.totalMultiplier(p, NOW, { doubleCredits = true }), 1.25 * 2 * 2)
	end)
end)

t.describe("Economy: income", function()
	t.test("the seed profile already earns something", function()
		t.ok(BigNum.toNumber(Economy.incomePerSecond(profile(), NOW)) > 0)
	end)

	t.test("a profile with no modules earns zero", function()
		t.ok(BigNum.isZero(Economy.incomePerSecond(profile({ modules = {} }), NOW)))
	end)

	t.test("a level 0 module doesn't earn", function()
		local p = profile({ modules = { s1_m1 = 0 } })
		t.ok(BigNum.isZero(Economy.incomePerSecond(p, NOW)))
	end)

	t.test("made up modules are ignored", function()
		local base = Economy.incomePerSecond(profile(), NOW)
		local p = profile({
			modules = { [Config.SEED_MODULE] = Config.SEED_LEVEL, modulo_falso = 9999 },
		})
		t.eq(BigNum.compare(Economy.incomePerSecond(p, NOW), base), 0)
	end)

	t.test("more levels earn more", function()
		local a = Economy.incomePerSecond(profile({ modules = { s1_m1 = 1 } }), NOW)
		local b = Economy.incomePerSecond(profile({ modules = { s1_m1 = 5 } }), NOW)
		t.ok(BigNum.gte(b, a))
		t.ok(BigNum.compare(b, a) > 0)
	end)
end)

t.describe("Economy: sectors", function()
	t.test("sector 1 is always open", function()
		t.ok(Economy.sectorUnlocked(profile(), 1))
	end)

	t.test("the others need the total earned", function()
		t.ok(not Economy.sectorUnlocked(profile(), 3))
		local rich = profile({ earnedTotal = BigNum.serialize(BigNum.new(1, 12)) })
		t.ok(Economy.sectorUnlocked(rich, 3))
	end)

	t.test("spending doesn't lock a sector again", function()
		-- earnedTotal never goes down, on purpose
		local p = profile({
			earnedTotal = BigNum.serialize(BigNum.new(1, 12)),
			credits = BigNum.serialize(BigNum.ZERO),
		})
		t.ok(Economy.sectorUnlocked(p, 3))
	end)

	t.test("an out of range index doesn't blow up", function()
		t.ok(not Economy.sectorUnlocked(profile(), 99))
		t.ok(not Economy.sectorUnlocked(profile(), 0))
		t.ok(not Economy.sectorUnlocked(profile(), -1))
	end)

	t.test("highestSector follows the total", function()
		t.eq(Economy.highestSector(profile()), 1)
		local p = profile({ earnedTotal = BigNum.serialize(BigNum.new(1, 20)) })
		t.eq(Economy.highestSector(p), #Config.SECTORS)
	end)
end)

t.describe("Economy: purchases (exploit surface)", function()
	t.test("a made up id gets rejected", function()
		local r = Economy.canBuyModule(profile(), "made_up_module")
		t.ok(not r.ok)
		t.eq(r.reason, "no such module")
	end)

	t.test("a non string id doesn't crash", function()
		t.ok(not Economy.canBuyModule(profile(), 42 :: any).ok)
		t.ok(not Economy.canBuyModule(profile(), {} :: any).ok)
	end)

	t.test("can't buy in a locked sector, not even with the money", function()
		local p = withCredits(BigNum.new(1, 30))
		local r = Economy.canBuyModule(p, "s6_m8")
		t.ok(not r.ok)
		t.eq(r.reason, "sector locked")
	end)

	t.test("no credits, no purchase", function()
		local r = Economy.canBuyModule(profile(), "s1_m2")
		t.ok(not r.ok)
		t.eq(r.reason, "not enough credits")
		t.ok(r.cost ~= nil, "has to say how much it costs")
	end)

	t.test("the exact cost is enough", function()
		local price = Config.moduleCost(Config.MODULES_BY_ID.s1_m2, 0)
		local r = Economy.canBuyModule(withCredits(price), "s1_m2")
		t.ok(r.ok, "the exact cost has to be enough")
	end)

	t.test("one credit short isn't enough", function()
		local price = Config.moduleCost(Config.MODULES_BY_ID.s1_m2, 0)
		local p = withCredits(BigNum.sub(price, BigNum.ONE))
		t.ok(not Economy.canBuyModule(p, "s1_m2").ok)
	end)

	t.test("max level blocks the purchase", function()
		local p = withCredits(BigNum.new(1, 30))
		p.modules.s1_m1 = Config.MAX_MODULE_LEVEL
		local r = Economy.canBuyModule(p, "s1_m1")
		t.ok(not r.ok)
		t.eq(r.reason, "max level")
	end)

	t.test("a forged level past the cap stays blocked", function()
		local p = withCredits(BigNum.new(1, 30))
		p.modules.s1_m1 = 99999
		t.ok(not Economy.canBuyModule(p, "s1_m1").ok)
	end)

	t.test("cost grows with level", function()
		local p = withCredits(BigNum.new(1, 30))
		local c0 = Economy.moduleCost(p, "s1_m1")
		p.modules.s1_m1 = 10
		local c10 = Economy.moduleCost(p, "s1_m1")
		t.ok(BigNum.compare(c10, c0) > 0)
	end)
end)

t.describe("Economy: offline", function()
	t.test("zero time, zero credits", function()
		local r = Economy.offlineEarnings(profile(), NOW, NOW)
		t.ok(BigNum.isZero(r.credits))
		t.eq(r.seconds, 0)
	end)

	t.test("a clock going backwards doesn't give free credits", function()
		-- lastSeen in the future: happens if the client lies or the system clock jumps
		local r = Economy.offlineEarnings(profile(), NOW + 10000, NOW)
		t.eq(r.seconds, 0)
		t.ok(BigNum.isZero(r.credits))
	end)

	t.test("an hour offline earns", function()
		local r = Economy.offlineEarnings(profile(), NOW - 3600, NOW)
		t.ok(BigNum.toNumber(r.credits) > 0)
		t.eq(r.cappedSeconds, 3600)
		t.ok(not r.hitCap)
	end)

	t.test("past the cap it truncates and says so", function()
		local r = Economy.offlineEarnings(profile(), NOW - 100 * 3600, NOW)
		t.eq(r.cappedSeconds, Config.OFFLINE_CAP_HOURS * 3600)
		t.ok(r.hitCap, "it has to report the cap, it's the gamepass hook")
	end)

	t.test("the gamepass extends the cap", function()
		local base = Economy.offlineEarnings(profile(), NOW - 100 * 3600, NOW, false)
		local ext = Economy.offlineEarnings(profile(), NOW - 100 * 3600, NOW, true)
		t.eq(ext.cappedSeconds, Config.OFFLINE_CAP_HOURS_GAMEPASS * 3600)
		t.ok(BigNum.compare(ext.credits, base.credits) > 0)
	end)

	t.test("offline earns less than online for the same time", function()
		local p = profile()
		local online = BigNum.mulScalar(Economy.incomePerSecond(p, NOW), 3600)
		local offline = Economy.offlineEarnings(p, NOW - 3600, NOW).credits
		t.ok(BigNum.compare(offline, online) < 0)
	end)

	t.test("the boost doesn't tick while offline", function()
		-- otherwise you'd buy a boost and log off
		local p = profile({ boostUntil = NOW + 99999, boostMult = 10 })
		local withBoost = Economy.offlineEarnings(p, NOW - 3600, NOW).credits
		local without = Economy.offlineEarnings(profile(), NOW - 3600, NOW).credits
		t.eq(BigNum.compare(withBoost, without), 0)
	end)
end)

t.describe("Economy: ascension", function()
	t.test("can't ascend below the threshold", function()
		t.ok(not Economy.canAscend(profile()))
	end)

	t.test("right at the threshold you can ascend", function()
		local p = profile({ earnedTotal = BigNum.serialize(Config.ASCEND_REQUIREMENT) })
		t.ok(Economy.canAscend(p))
	end)

	t.test("resets modules and credits, bumps the counter", function()
		local p = profile({
			ascensions = 2,
			credits = BigNum.serialize(BigNum.new(9, 20)),
			modules = { s1_m1 = 20, s3_m4 = 15 },
		})
		local r = Economy.applyAscend(p)
		t.eq(r.ascensions, 3)
		t.eq(r.modules.s3_m4, nil)
		t.eq(r.modules[Config.SEED_MODULE], Config.SEED_LEVEL)
		t.ok(BigNum.isZero(BigNum.deserialize(r.credits)))
	end)

	t.test("the multiplier grows with every ascension", function()
		t.ok(
			Economy.applyAscend(profile({ ascensions = 4 })).multiplier > Config.ascendMultiplier(4)
		)
	end)

	t.test("sectors stay open after ascending", function()
		-- earnedTotal isn't touched, on purpose: starting over in a locked world would be a punishment
		local r = Economy.applyAscend(profile())
		t.eq(r.credits[1], 0)
		local after = profile({
			earnedTotal = BigNum.serialize(BigNum.new(1, 20)),
			modules = r.modules,
			ascensions = r.ascensions,
		})
		t.eq(Economy.highestSector(after), #Config.SECTORS)
	end)
end)

t.describe("Economy: credit packs", function()
	t.test("they scale with current income", function()
		local poor = profile()
		local rich = profile({ modules = { s1_m1 = 25, s1_m2 = 25 } })
		local a = Economy.productCreditValue(poor, NOW, 3600)
		local b = Economy.productCreditValue(rich, NOW, 3600)
		t.ok(BigNum.compare(b, a) > 0, "whoever produces more has to get more")
	end)

	t.test("a profile with no income still gets something", function()
		-- a real purchase can never give zero
		local empty = profile({ modules = {} })
		local v = Economy.productCreditValue(empty, NOW, 3600)
		t.ok(BigNum.toNumber(v) > 0, "a purchase must never give zero")
	end)

	t.test("more time, more credits", function()
		local p = profile()
		local s = Economy.productCreditValue(p, NOW, 600)
		local l = Economy.productCreditValue(p, NOW, 14400)
		t.ok(BigNum.compare(l, s) > 0)
	end)
end)

t.describe("Economy: next goal", function()
	t.test("a new profile aims for a module", function()
		local g = Economy.nextGoal(profile())
		t.eq(g.kind, "module")
		t.ok(g.progress >= 0 and g.progress <= 1)
	end)

	t.test("progress stays in [0,1] even with absurd credits", function()
		local g = Economy.nextGoal(withCredits(BigNum.new(1, 40)))
		t.ok(g.progress >= 0 and g.progress <= 1, "progress out of range: " .. g.progress)
	end)

	t.test("with everything unlocked it aims for ascension", function()
		local p = withCredits(BigNum.new(1, 40))
		p.earnedTotal = BigNum.serialize(BigNum.new(1, 40))
		for _, def in Config.MODULES do
			p.modules[def.id] = Config.MAX_MODULE_LEVEL
		end
		t.eq(Economy.nextGoal(p).kind, "ascend")
	end)

	t.test("the goal always has a label", function()
		for _, p in { profile(), withCredits(BigNum.new(1, 12)) } do
			local g = Economy.nextGoal(p)
			t.ok(type(g.label) == "string" and #g.label > 0, "empty label")
		end
	end)
end)

return t.finish()
