--!strict

local shim = require("./robloxshim")
local t = require("./harness")

local env = shim.newEnv()
local BigNum = env.requireShared("BigNum")
local Config = env.requireShared("Config")
local Economy = env.requireShared("Economy")
local Sectors = env.requireShared("Sectors")

local NOW = 1_700_000_000

local function allMax(sector: number): { [string]: number }
	local mods: { [string]: number } = {}
	for _, def in Config.MODULES do
		if def.sector == sector then
			mods[def.id] = Config.MAX_MODULE_LEVEL
		end
	end
	return mods
end

t.describe("Sector 2: refiner", function()
	t.test("no module, no bonus", function()
		t.near(Sectors.refineryBonus({}), 1)
	end)

	t.test("the bonus grows with level", function()
		local a = Sectors.refineryBonus({ [Sectors.REFINERY_MODULE] = 1 })
		local b = Sectors.refineryBonus({ [Sectors.REFINERY_MODULE] = 10 })
		t.ok(b > a)
		t.near(a, 1 + Sectors.REFINERY_PER_LEVEL)
	end)

	t.test("at max level it stays reasonable", function()
		-- sector bonuses multiply with each other and with ascension: a single one going past 2x would
		-- squash the whole curve
		local max = Sectors.refineryBonus({ [Sectors.REFINERY_MODULE] = Config.MAX_MODULE_LEVEL })
		t.ok(max > 1.1, "bonus too weak to be noticed: " .. max)
		t.ok(max <= 2, "bonus too strong, run tools/simulate.luau again: " .. max)
	end)
end)

t.describe("Sector 4: data", function()
	t.test("it doesn't accrue while the sector is locked", function()
		t.eq(Sectors.dataAtPlaytime(99999, false), 0)
		t.eq(Sectors.dataGained(1000, 600, false), 0)
	end)

	t.test("it accrues with playtime", function()
		t.eq(Sectors.dataAtPlaytime(600, true), 10)
		t.eq(Sectors.dataAtPlaytime(30, true), 0)
	end)

	t.test("unlocking the sector doesn't give data for the time before", function()
		-- dataAtPlaytime gives the absolute total: using it instead of dataGained would suddenly give ten
		-- hours of data to whoever unlocks
		t.eq(Sectors.dataGained(36000, 60, true), 1)
	end)

	t.test("accrual doesn't lose data on irregular ticks", function()
		local playtime, data = 0.0, 0
		local deltas = { 0.3, 2.7, 1.1, 0.9, 5.0 }
		local i, total = 1, 0.0
		while total < 3600 do
			local d = deltas[i]
			i = i % #deltas + 1
			data += Sectors.dataGained(playtime, d, true)
			playtime += d
			total += d
		end
		t.eq(data, 60, "an hour has to give 60 data however it's split")
	end)

	t.test("a negative delta doesn't remove data", function()
		t.eq(Sectors.dataGained(1000, -50, true), 0)
	end)

	t.test("cost grows with level", function()
		local def = Sectors.DATA_UPGRADES[1]
		t.ok(Sectors.dataUpgradeCost(def, 5) > Sectors.dataUpgradeCost(def, 0))
	end)

	t.test("every upgrade has a cap", function()
		for _, u in Sectors.DATA_UPGRADES do
			t.ok(u.maxLevel > 0 and u.maxLevel <= 20, u.id .. " has a weird cap")
			t.ok(type(u.describe(3)) == "string", u.id .. " can't describe itself")
		end
	end)

	t.test("bonuses start neutral", function()
		local b = Sectors.dataBonuses(nil)
		t.near(b.yieldMult, 1)
		t.eq(b.offlineBonusHours, 0)
		t.eq(b.crateSpeedup, 0)
	end)

	t.test("forged levels get clamped", function()
		local b = Sectors.dataBonuses({ yield = 9999, offline = 9999, crate = 9999 })
		local atMax = Sectors.dataBonuses({ yield = 20, offline = 8, crate = 10 })
		t.near(b.yieldMult, atMax.yieldMult)
		t.eq(b.offlineBonusHours, atMax.offlineBonusHours)
		t.near(b.crateSpeedup, atMax.crateSpeedup)
	end)

	t.test("negative levels don't remove bonus", function()
		local b = Sectors.dataBonuses({ yield = -50 })
		t.near(b.yieldMult, 1)
	end)

	t.test("data extends the offline cap", function()
		local base = {
			credits = BigNum.serialize(BigNum.ZERO),
			earnedTotal = BigNum.serialize(BigNum.ZERO),
			modules = { [Config.SEED_MODULE] = Config.SEED_LEVEL },
			ascensions = 0,
			boostUntil = 0,
			boostMult = 1,
			data = 0,
		}
		local withData = table.clone(base)
		withData.dataUpgrades = { offline = 4 }

		local a = Economy.offlineEarnings(base, NOW - 100 * 3600, NOW)
		local b = Economy.offlineEarnings(withData, NOW - 100 * 3600, NOW)
		t.eq(a.cappedSeconds, Config.OFFLINE_CAP_HOURS * 3600)
		t.eq(b.cappedSeconds, (Config.OFFLINE_CAP_HOURS + 4) * 3600)
	end)
end)

t.describe("Sector 4: bonuses reach where they're needed", function()
	local Rewards = env.requireShared("Rewards")

	t.test("the Frequency upgrade really shortens the wait", function()
		-- crateSpeedup was computed but not wired up: the upgrade could be bought and did nothing
		local base = Rewards.crateState(NOW, NOW, nil)
		local fast = Rewards.crateState(NOW, NOW, { crate = 10 })
		t.ok(fast.secondsRemaining < base.secondsRemaining, "the upgrade doesn't change the wait")
	end)

	t.test("at max it halves the wait", function()
		local base = Rewards.crateState(NOW, NOW, nil)
		local fast = Rewards.crateState(NOW, NOW, { crate = 10 })
		t.near(fast.secondsRemaining, base.secondsRemaining * 0.5, 0.01)
	end)

	t.test("with no upgrades the wait is the one in Config", function()
		t.eq(Rewards.crateState(NOW, NOW, nil).secondsRemaining, Config.CRATE_INTERVAL)
	end)
end)

t.describe("Sector 6: fusions", function()
	t.test("an incomplete sector doesn't fuse", function()
		t.eq(#Sectors.fusedSectors({}), 0)
		local almost = allMax(1)
		almost.s1_m1 = Config.MAX_MODULE_LEVEL - 1
		t.eq(#Sectors.fusedSectors(almost), 0)
	end)

	t.test("a maxed sector fuses", function()
		local fused = Sectors.fusedSectors(allMax(1))
		t.eq(#fused, 1)
		t.eq(fused[1], 1)
	end)

	t.test("the bonus grows with fusions", function()
		t.near(Sectors.fusionMultiplier({}), 1)
		t.near(Sectors.fusionMultiplier(allMax(1)), 1 + Sectors.FUSION_BONUS)
	end)

	t.test("all sectors fused give the max", function()
		local all: { [string]: number } = {}
		for _, def in Config.MODULES do
			all[def.id] = Config.MAX_MODULE_LEVEL
		end
		t.eq(#Sectors.fusedSectors(all), #Config.SECTORS)
		t.near(Sectors.fusionMultiplier(all), 1 + #Config.SECTORS * Sectors.FUSION_BONUS)
	end)
end)

t.describe("Sector bonuses inside Economy", function()
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

	t.test("a clean profile stays at multiplier 1", function()
		t.near(Economy.totalMultiplier(profile(), NOW), 1)
	end)

	t.test("the refiner goes into the multiplier", function()
		local mods = { [Config.SEED_MODULE] = Config.SEED_LEVEL, [Sectors.REFINERY_MODULE] = 10 }
		local m = Economy.totalMultiplier(profile({ modules = mods }), NOW)
		t.near(m, Sectors.refineryBonus(mods))
	end)

	t.test("data goes into the multiplier", function()
		local ups = { yield = 10 }
		local m = Economy.totalMultiplier(profile({ dataUpgrades = ups }), NOW)
		t.near(m, Sectors.dataBonuses(ups).yieldMult)
	end)

	t.test("bonuses compound instead of adding up", function()
		local mods = allMax(1)
		mods[Sectors.REFINERY_MODULE] = 10
		local ups = { yield = 4 }
		local p = profile({ modules = mods, ascensions = 2, dataUpgrades = ups })
		local expected = Config.ascendMultiplier(2)
			* Sectors.refineryBonus(mods)
			* Sectors.fusionMultiplier(mods)
			* Sectors.dataBonuses(ups).yieldMult
		t.near(Economy.totalMultiplier(p, NOW), expected)
	end)

	t.test("bonuses really raise income", function()
		local base = Economy.incomePerSecond(profile(), NOW)
		local boosted = Economy.incomePerSecond(profile({ dataUpgrades = { yield = 20 } }), NOW)
		t.ok(BigNum.compare(boosted, base) > 0)
	end)
end)

return t.finish()
