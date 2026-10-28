--!strict

local shim = require("./robloxshim")
local t = require("./harness")

local env = shim.newEnv()
local BigNum = env.requireShared("BigNum")
local Config = env.requireShared("Config")
local Economy = env.requireShared("Economy")
local Rewards = env.requireShared("Rewards")

local DAY = 86400
-- a moment in the middle of the day, so we don't trip on the boundaries
local NOW = 1_700_000_000 - (1_700_000_000 % DAY) + DAY / 2

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

t.describe("Rewards: daily", function()
	t.test("a new player can claim right away", function()
		local s = Rewards.dailyState(0, 0, NOW)
		t.ok(s.available)
		t.eq(s.nextStreak, 1)
	end)

	t.test("can't claim twice on the same day", function()
		local s = Rewards.dailyState(NOW, 1, NOW + 3600)
		t.ok(not s.available)
	end)

	t.test("the next day the streak goes up", function()
		local s = Rewards.dailyState(NOW, 3, NOW + DAY)
		t.ok(s.available)
		t.eq(s.nextStreak, 4)
	end)

	t.test("skipping a day resets the streak", function()
		local s = Rewards.dailyState(NOW, 6, NOW + DAY * 2)
		t.ok(s.available)
		t.eq(s.nextStreak, 1, "losing the streak is the lever of the system")
	end)

	t.test("a long absence starts again from one", function()
		local s = Rewards.dailyState(NOW, 7, NOW + DAY * 60)
		t.eq(s.nextStreak, 1)
	end)

	t.test("the streak loops past day seven", function()
		local s = Rewards.dailyState(NOW, 7, NOW + DAY)
		t.eq(s.nextStreak, 8)
		t.eq(s.rewardIndex, 1, "day eight starts over from the first reward")
	end)

	t.test("the reward index stays in range", function()
		for streak = 0, 30 do
			local s = Rewards.dailyState(NOW, streak, NOW + DAY)
			t.ok(
				s.rewardIndex >= 1 and s.rewardIndex <= #Config.DAILY_REWARDS,
				"index out of range: " .. s.rewardIndex
			)
		end
	end)

	t.test("the countdown never goes past 24 hours", function()
		local s = Rewards.dailyState(NOW, 1, NOW)
		t.ok(s.secondsUntilNext > 0 and s.secondsUntilNext <= DAY)
	end)

	t.test("the day seven reward gives a cosmetic and a boost", function()
		local g = Rewards.dailyGrant(profile(), 7, NOW)
		t.ok(g.cosmetic ~= nil)
		t.ok((g.boostSeconds or 0) >= 3600)
	end)

	t.test("the reward scales with income for players who are ahead", function()
		local poor = Rewards.dailyGrant(profile(), 3, NOW)
		local rich = Rewards.dailyGrant(profile({ modules = { s4_m8 = 20 } }), 3, NOW)
		t.ok(
			BigNum.compare(rich.credits, poor.credits) > 0,
			"a fixed reward would be ridiculous for players who are ahead"
		)
	end)

	t.test("the reward never goes below the Config value", function()
		local g = Rewards.dailyGrant(profile({ modules = {} }), 5, NOW)
		t.ok(BigNum.gte(g.credits, Config.DAILY_REWARDS[5].credits))
	end)

	t.test("a made up index doesn't crash", function()
		t.ok(Rewards.dailyGrant(profile(), 99, NOW) ~= nil)
		t.ok(Rewards.dailyGrant(profile(), 0, NOW) ~= nil)
	end)
end)

t.describe("Rewards: crates", function()
	t.test("the first crate is available right away", function()
		t.ok(Rewards.crateState(0, NOW).available)
	end)

	t.test("once opened the timer starts", function()
		local s = Rewards.crateState(NOW, NOW)
		t.ok(not s.available)
		t.eq(s.secondsRemaining, Config.CRATE_INTERVAL)
	end)

	t.test("after the interval it's available again", function()
		t.ok(Rewards.crateState(NOW, NOW + Config.CRATE_INTERVAL).available)
	end)

	t.test("a timestamp in the future doesn't lock the crate forever", function()
		t.ok(Rewards.crateState(NOW + 99999, NOW).available)
	end)

	t.test("the value changes with the roll", function()
		local p = profile()
		local low = Rewards.crateGrant(p, NOW, 0)
		local high = Rewards.crateGrant(p, NOW, 1)
		t.ok(BigNum.compare(high.credits, low.credits) > 0)
	end)

	t.test("an out of range roll gets clamped", function()
		local p = profile()
		local a = Rewards.crateGrant(p, NOW, -5)
		local b = Rewards.crateGrant(p, NOW, 0)
		t.eq(BigNum.compare(a.credits, b.credits), 0)
	end)

	t.test("players with no income still get something", function()
		local g = Rewards.crateGrant(profile({ modules = {} }), NOW, 0.5)
		t.ok(BigNum.toNumber(g.credits) > 0)
	end)
end)

t.describe("Rewards: codes", function()
	t.test("a valid code works", function()
		local r = Rewards.redeemCode(profile(), {}, "LAUNCH", NOW)
		t.ok(r.ok)
		t.ok(r.grant ~= nil)
	end)

	t.test("caps and spaces don't matter", function()
		t.ok(Rewards.redeemCode(profile(), {}, "  launch ", NOW).ok)
		t.ok(Rewards.redeemCode(profile(), {}, "LaUnCh", NOW).ok)
	end)

	t.test("a code that doesn't exist gets rejected", function()
		local r = Rewards.redeemCode(profile(), {}, "FREEMONEY", NOW)
		t.ok(not r.ok)
		t.eq(r.reason, "no such code")
	end)

	t.test("can't redeem twice", function()
		local r = Rewards.redeemCode(profile(), { LAUNCH = true }, "LAUNCH", NOW)
		t.ok(not r.ok)
		t.eq(r.reason, "already redeemed")
	end)

	t.test("non string input doesn't crash", function()
		t.ok(not Rewards.redeemCode(profile(), {}, 42, NOW).ok)
		t.ok(not Rewards.redeemCode(profile(), {}, {}, NOW).ok)
		t.ok(not Rewards.redeemCode(profile(), {}, nil, NOW).ok)
	end)

	t.test("a huge string gets rejected without processing it", function()
		local r = Rewards.redeemCode(profile(), {}, string.rep("A", 10000), NOW)
		t.ok(not r.ok)
		t.eq(r.reason, "invalid code")
	end)

	t.test("an empty string gets rejected", function()
		t.ok(not Rewards.redeemCode(profile(), {}, "", NOW).ok)
		t.ok(not Rewards.redeemCode(profile(), {}, "   ", NOW).ok)
	end)

	t.test("an expired code doesn't work", function()
		Rewards.CODES.OLDCODE = { minutes = 10, expiresAt = NOW - 1 }
		local r = Rewards.redeemCode(profile(), {}, "OLDCODE", NOW)
		t.ok(not r.ok)
		t.eq(r.reason, "code expired")
		Rewards.CODES.OLDCODE = nil
	end)

	t.test("a boost code doesn't give credits and vice versa", function()
		local boost = Rewards.redeemCode(profile(), {}, "BRAINROT", NOW)
		t.ok(boost.grant.boostMult ~= nil)
		t.eq(boost.grant.credits, nil)
	end)
end)

t.describe("Rewards: boost", function()
	local function state(until_: number, mult: number)
		return { boostUntil = until_, boostMult = mult }
	end

	t.test("a boost on a clean profile starts now", function()
		local r = Rewards.applyBoost(state(0, 1), 2, 900, NOW)
		t.eq(r.boostMult, 2)
		t.eq(r.boostUntil, NOW + 900)
	end)

	t.test("two equal boosts add up instead of replacing each other", function()
		local r = Rewards.applyBoost(state(NOW + 600, 2), 2, 900, NOW)
		t.eq(r.boostMult, 2)
		t.eq(r.boostUntil, NOW + 600 + 900, "leftover time isn't lost")
	end)

	t.test("a stronger boost wins and takes the leftover time with it", function()
		local r = Rewards.applyBoost(state(NOW + 600, 2), 4, 900, NOW)
		t.eq(r.boostMult, 4)
		t.eq(r.boostUntil, NOW + 900 + 600)
	end)

	t.test("a weaker boost doesn't lower the active one", function()
		local r = Rewards.applyBoost(state(NOW + 600, 4), 2, 900, NOW)
		t.eq(r.boostMult, 4, "a weak boost must not downgrade the strong one")
	end)

	t.test("an expired boost gets replaced", function()
		local r = Rewards.applyBoost(state(NOW - 10, 8), 2, 900, NOW)
		t.eq(r.boostMult, 2)
		t.eq(r.boostUntil, NOW + 900)
	end)

	t.test("nonsense values change nothing", function()
		local before = state(NOW + 100, 3)
		t.eq(Rewards.applyBoost(before, 1, 900, NOW).boostMult, 3)
		t.eq(Rewards.applyBoost(before, 5, 0, NOW).boostMult, 3)
		t.eq(Rewards.applyBoost(before, 0, -5, NOW).boostMult, 3)
	end)

	t.test("the applied boost is visible to Economy", function()
		local r = Rewards.applyBoost(state(0, 1), 3, 900, NOW)
		local p = profile({ boostUntil = r.boostUntil, boostMult = r.boostMult })
		t.near(Economy.totalMultiplier(p, NOW), 3)
	end)
end)

return t.finish()
