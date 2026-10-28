--!strict

local shim = require("./robloxshim")
local t = require("./harness")

local env = shim.newEnv()
local BigNum = env.requireShared("BigNum")
local Config = env.requireShared("Config")
local Quests = env.requireShared("Quests")

local NOW = 1_700_000_000
local DAY = 19676
local USER = 424242

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

local function questsFor(p: any, day: number, progress: any)
	return Quests.daily(p, USER, day, progress, NOW)
end

t.describe("Quests: assignment", function()
	t.test("three quests a day", function()
		local q = questsFor(profile(), DAY, Quests.emptyProgress(DAY))
		t.eq(#q, Quests.PER_DAY)
	end)

	t.test("they're deterministic: same day, same quests", function()
		-- they get recomputed instead of saved, so they have to match even after a server restart
		local a = questsFor(profile(), DAY, Quests.emptyProgress(DAY))
		local b = questsFor(profile(), DAY, Quests.emptyProgress(DAY))
		for i = 1, #a do
			t.eq(a[i].id, b[i].id)
			t.eq(a[i].kind, b[i].kind)
		end
	end)

	t.test("they change day by day", function()
		local seenIds: { [string]: boolean } = {}
		local different = 0
		for d = DAY, DAY + 12 do
			local q = questsFor(profile(), d, Quests.emptyProgress(d))
			local signature = ""
			for _, item in q do
				signature ..= item.kind .. ","
			end
			if not seenIds[signature] then
				seenIds[signature] = true
				different += 1
			end
		end
		t.ok(different > 1, "quests never change from day to day")
	end)

	t.test("different players get different quests", function()
		local a = Quests.daily(profile(), 111, DAY, Quests.emptyProgress(DAY), NOW)
		local b = Quests.daily(profile(), 999999, DAY, Quests.emptyProgress(DAY), NOW)
		local same = true
		for i = 1, #a do
			if a[i].kind ~= b[i].kind or a[i].target ~= b[i].target then
				same = false
				break
			end
		end
		t.ok(not same, "two players got exactly the same quests")
	end)

	t.test("no duplicate quest on the same day", function()
		for d = DAY, DAY + 30 do
			local q = questsFor(profile(), d, Quests.emptyProgress(d))
			local seen: { [string]: boolean } = {}
			for _, item in q do
				local signature = item.kind .. ":" .. item.label
				t.ok(not seen[signature], "duplicate quest on day " .. d)
				seen[signature] = true
			end
		end
	end)

	t.test("ids are unique within the day", function()
		local q = questsFor(profile(), DAY, Quests.emptyProgress(DAY))
		local seen: { [string]: boolean } = {}
		for _, item in q do
			t.ok(not seen[item.id], "duplicate id: " .. item.id)
			seen[item.id] = true
		end
	end)
end)

t.describe("Quests: scaled targets", function()
	t.test("whoever is ahead gets higher earn targets", function()
		-- a fixed target would already be done when assigned
		local poor = profile()
		local rich = profile({ modules = { s4_m8 = 20 } })
		local found = false
		for d = DAY, DAY + 20 do
			local qp = Quests.daily(poor, USER, d, Quests.emptyProgress(d), NOW)
			local qr = Quests.daily(rich, USER, d, Quests.emptyProgress(d), NOW)
			for i = 1, #qp do
				if qp[i].kind == "earn" and qp[i].targetBig and qr[i].targetBig then
					t.ok(BigNum.compare(qr[i].targetBig, qp[i].targetBig) > 0)
					found = true
				end
			end
			if found then
				break
			end
		end
		t.ok(found, "no earn quest found in twenty days")
	end)

	t.test("a profile with no income still has a positive target", function()
		local empty = profile({ modules = {} })
		for d = DAY, DAY + 20 do
			for _, q in Quests.daily(empty, USER, d, Quests.emptyProgress(d), NOW) do
				if q.targetBig then
					t.ok(BigNum.toNumber(q.targetBig) > 0, "zero target")
				end
			end
		end
	end)
end)

t.describe("Quests: progress", function()
	t.test("yesterday's progress doesn't count today", function()
		local yesterday = Quests.emptyProgress(DAY)
		yesterday.buy = 50
		local thisDay = Quests.rollOver(yesterday, DAY + 1)
		t.eq(thisDay.day, DAY + 1)
		t.eq(thisDay.buy, 0)
	end)

	t.test("today's progress survives", function()
		local p = Quests.emptyProgress(DAY)
		p.buy = 4
		t.eq(Quests.rollOver(p, DAY).buy, 4)
	end)

	t.test("corrupted progress starts over clean", function()
		t.eq(Quests.rollOver(nil, DAY).day, DAY)
		t.eq(Quests.rollOver("broken" :: any, DAY).buy, 0)
	end)

	t.test("a quest completes when the target is reached", function()
		local progress = Quests.emptyProgress(DAY)
		progress.buy = 999
		progress.crate = 999
		progress.ascend = 999
		progress.earn = BigNum.serialize(BigNum.new(1, 30))
		for _, q in questsFor(profile(), DAY, progress) do
			t.ok(q.complete, "quest not completed: " .. q.label)
		end
	end)

	t.test("a freshly assigned quest isn't complete", function()
		local q = questsFor(profile(), DAY, Quests.emptyProgress(DAY))
		for _, item in q do
			t.ok(not item.complete, "quest already complete when assigned: " .. item.label)
		end
	end)
end)

t.describe("Quests: claiming", function()
	local function completed()
		local progress = Quests.emptyProgress(DAY)
		progress.buy = 999
		progress.crate = 999
		progress.ascend = 999
		progress.earn = BigNum.serialize(BigNum.new(1, 30))
		return progress
	end

	t.test("a complete quest can be claimed", function()
		local p = profile()
		local q = questsFor(p, DAY, completed())
		local r = Quests.claim(p, q, q[1].id, NOW)
		t.ok(r.ok)
		t.ok(BigNum.toNumber(r.credits) > 0)
	end)

	t.test("an incomplete quest can't be claimed", function()
		local p = profile()
		local q = questsFor(p, DAY, Quests.emptyProgress(DAY))
		local r = Quests.claim(p, q, q[1].id, NOW)
		t.ok(not r.ok)
		t.eq(r.reason, "not completed yet")
	end)

	t.test("can't claim twice", function()
		local p = profile()
		local progress = completed()
		local q = questsFor(p, DAY, progress)
		progress.claimed[q[1].id] = true
		local q2 = questsFor(p, DAY, progress)
		local r = Quests.claim(p, q2, q2[1].id, NOW)
		t.ok(not r.ok)
		t.eq(r.reason, "already claimed")
	end)

	t.test("a made up id gets rejected", function()
		local p = profile()
		local q = questsFor(p, DAY, completed())
		t.ok(not Quests.claim(p, q, "fake_quest", NOW).ok)
		t.ok(not Quests.claim(p, q, 42 :: any, NOW).ok)
		t.ok(not Quests.claim(p, q, nil :: any, NOW).ok)
	end)

	t.test("the reward scales with income", function()
		local poor = profile()
		local rich = profile({ modules = { s4_m8 = 20 } })
		local qp = questsFor(poor, DAY, completed())
		local qr = questsFor(rich, DAY, completed())
		local a = Quests.claim(poor, qp, qp[1].id, NOW)
		local b = Quests.claim(rich, qr, qr[1].id, NOW)
		t.ok(BigNum.compare(b.credits, a.credits) > 0)
	end)
end)

return t.finish()
