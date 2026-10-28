--!strict

-- the session lock and reconcile are where player saves get lost. they have to be verified without
-- a real DataStore

local shim = require("./robloxshim")
local t = require("./harness")

local env = shim.newEnv()
local Config = env.requireShared("Config")
local BigNum = env.requireShared("BigNum")
local DataService = env.requireServer("DataService")

local NOW = env.now()
local STALE = DataService.LOCK_STALE_SECONDS

t.describe("DataService: default profile", function()
	t.test("starts with the seed module already leveled", function()
		local p = DataService._defaultProfile()
		t.eq(p.modules[Config.SEED_MODULE], Config.SEED_LEVEL)
	end)

	t.test("starts at zero credits", function()
		local p = DataService._defaultProfile()
		t.eq(BigNum.compare(BigNum.deserialize(p.credits), BigNum.ZERO), 0)
		t.eq(p.ascensions, 0)
		t.eq(p.dailyStreak, 0)
	end)

	t.test("is tagged with the current version", function()
		t.eq(DataService._defaultProfile().version, DataService.PROFILE_VERSION)
	end)
end)

t.describe("DataService: lock", function()
	t.test("a never seen profile is free", function()
		t.ok(DataService._lockIsFree(nil))
		t.ok(DataService._lockIsFree({}))
	end)

	t.test("our own lock is free (rejoining the same server)", function()
		t.ok(DataService._lockIsFree({ sessionJobId = "JOB_A", sessionStamp = NOW }))
	end)

	t.test("a fresh lock from another server is taken", function()
		t.ok(not DataService._lockIsFree({ sessionJobId = "JOB_B", sessionStamp = NOW }))
	end)

	t.test("a crashed server's lock can be stolen", function()
		t.ok(DataService._lockIsFree({ sessionJobId = "JOB_B", sessionStamp = NOW - STALE - 1 }))
	end)

	t.test("right at the boundary the lock is still taken", function()
		t.ok(not DataService._lockIsFree({ sessionJobId = "JOB_B", sessionStamp = NOW - STALE }))
	end)

	t.test("a corrupted stamp doesn't lock the profile forever", function()
		t.ok(DataService._lockIsFree({ sessionJobId = "JOB_B", sessionStamp = "dunno" }))
		t.ok(DataService._lockIsFree({ sessionJobId = "JOB_B" }))
	end)

	t.test("the stale window is longer than autosave", function()
		-- if it were shorter we'd steal the lock from a live server
		t.ok(
			STALE > Config.AUTOSAVE_INTERVAL,
			string.format("stale %ds <= autosave %ds", STALE, Config.AUTOSAVE_INTERVAL)
		)
	end)
end)

t.describe("DataService: reconcile", function()
	t.test("non table input goes back to the default", function()
		t.eq(DataService._reconcile(nil).ascensions, 0)
		t.eq(DataService._reconcile("broken").ascensions, 0)
		t.eq(DataService._reconcile(42).ascensions, 0)
	end)

	t.test("keeps valid fields", function()
		local p = DataService._reconcile({
			ascensions = 7,
			data = 300,
			dailyStreak = 4,
			playtime = 9999,
		})
		t.eq(p.ascensions, 7)
		t.eq(p.data, 300)
		t.eq(p.dailyStreak, 4)
		t.eq(p.playtime, 9999)
	end)

	t.test("fields of the wrong type go back to the default", function()
		local p = DataService._reconcile({
			ascensions = "lots",
			data = {},
			dailyStreak = false,
		})
		t.eq(p.ascensions, 0)
		t.eq(p.data, 0)
		t.eq(p.dailyStreak, 0)
	end)

	t.test("drops modules gone from Config", function()
		local p = DataService._reconcile({
			modules = { s1_m1 = 5, modulo_rimosso = 12, s2_m3 = 2 },
		})
		t.eq(p.modules.s1_m1, 5)
		t.eq(p.modules.s2_m3, 2)
		t.eq(p.modules.modulo_rimosso, nil)
	end)

	t.test("clamps levels past the max", function()
		local p = DataService._reconcile({ modules = { s1_m1 = 9999 } })
		t.eq(p.modules.s1_m1, Config.MAX_MODULE_LEVEL)
	end)

	t.test("clamps negative levels", function()
		local p = DataService._reconcile({ modules = { s1_m1 = -5 } })
		t.eq(p.modules.s1_m1, 0)
	end)

	t.test("truncates fractional levels", function()
		local p = DataService._reconcile({ modules = { s1_m1 = 3.7 } })
		t.eq(p.modules.s1_m1, 3)
	end)

	t.test("a save with no valid modules falls back to the seed", function()
		local p = DataService._reconcile({ modules = { tutto_sbagliato = 4 } })
		t.eq(p.modules[Config.SEED_MODULE], Config.SEED_LEVEL)
	end)

	t.test("credits survive the round trip", function()
		local large = BigNum.new(4.2, 31)
		local p = DataService._reconcile({ credits = BigNum.serialize(large) })
		local back = BigNum.deserialize(p.credits)
		t.eq(back.e, large.e)
		t.near(back.m, large.m)
	end)

	t.test("corrupted credits don't spread NaN", function()
		local p = DataService._reconcile({ credits = "not a number" })
		local c = BigNum.deserialize(p.credits)
		t.ok(c.m == c.m, "NaN in credits")
	end)

	t.test("keeps the lock fields for the caller", function()
		local p = DataService._reconcile({ sessionJobId = "JOB_C", sessionStamp = 123 })
		t.eq(p.sessionJobId, "JOB_C")
		t.eq(p.sessionStamp, 123)
	end)

	t.test("keeps cosmetics and redeemed codes", function()
		local p = DataService._reconcile({
			cosmetics = { aura_streak = true },
			redeemedCodes = { LAUNCH = true },
		})
		t.ok(p.cosmetics.aura_streak)
		t.ok(p.redeemedCodes.LAUNCH)
	end)
end)

t.describe("DataService: player leaving", function()
	t.test("release doesn't leave the profile in loaded", function()
		-- regression test for a race: save yields, and meanwhile get() returned a profile already on its
		-- way out
		local src = (function()
			local fs = require("@lune/fs")
			return fs.readFile("src/server/DataService.luau")
		end)()
		local releaseBody = string.match(src, "function DataService%.release.-\nend")
		t.ok(releaseBody ~= nil, "release not found")
		local nilPos = string.find(releaseBody :: string, "loaded%[userId%] = nil")
		local savePos = string.find(releaseBody :: string, "DataService%.save")
		t.ok(nilPos ~= nil and savePos ~= nil, "release changed, update the test")
		t.ok(
			(nilPos :: number) < (savePos :: number),
			"the profile has to leave loaded before save, which yields"
		)
	end)

	t.test("save can still write a profile on its way out", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/DataService.luau")
		t.ok(
			string.find(src, "loaded%[userId%] or releasedSnapshot%[userId%]") ~= nil,
			"save has to be able to read the snapshot during release"
		)
	end)
end)

return t.finish()
