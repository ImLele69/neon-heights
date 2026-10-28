--!strict

-- prints the progression curve of a typical session, to see if the timings fit the windows in
-- docs/DESIGN.md without opening Studio
--   lune run tools/simulate.luau [hours] [ascensions]

local process = require("@lune/process")
local shim = require("../tests/robloxshim")
local BigNum = shim.requireShared("BigNum")
local Config = shim.requireShared("Config")
local Economy = shim.requireShared("Economy")

local hours = tonumber(process.args[1]) or 4
local ascensions = tonumber(process.args[2]) or 0

local function hms(s: number): string
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	if h > 0 then
		return string.format("%dh%02dm", h, m)
	end
	return string.format("%dm%02ds", m, math.floor(s % 60))
end

local levels: { [string]: number } = { [Config.SEED_MODULE] = Config.SEED_LEVEL }
local credits = BigNum.ZERO
local total = BigNum.ZERO
local purchases = 0
local unlocked: { [number]: number } = { [1] = 0 }
local gaps: { number } = {}
local lastBuy = 0
local ascendAt: number? = nil

local DT = 1
local seconds = math.floor(hours * 3600)

print(
	string.format(
		"\nNeon Heights simulation, %gh, %d ascensions (x%.2f)\n",
		hours,
		ascensions,
		Config.ascendMultiplier(ascensions)
	)
)
print(string.format("%-9s %12s %12s %8s %s", "time", "credits", "total", "modules", "event"))

local function row(elapsed: number, event: string)
	print(
		string.format(
			"%-9s %12s %12s %8d %s",
			hms(elapsed),
			BigNum.format(credits),
			BigNum.format(total),
			purchases,
			event
		)
	)
end

for elapsed = DT, seconds, DT do
	-- goes through Economy, not Config, so the simulation also sees sector bonuses, which are part of
	-- the real curve
	local rate = Economy.incomePerSecond({
		credits = BigNum.serialize(credits),
		earnedTotal = BigNum.serialize(total),
		modules = levels,
		ascensions = ascensions,
		boostUntil = 0,
		boostMult = 1,
		data = 0,
	}, 0)
	local income = BigNum.mulScalar(rate, DT)
	credits = BigNum.add(credits, income)
	total = BigNum.add(total, income)

	for _, sector in Config.SECTORS do
		if not unlocked[sector.index] and BigNum.gte(total, sector.unlockTotal) then
			unlocked[sector.index] = elapsed
			row(elapsed, string.format("SECTOR %d: %s", sector.index, sector.name))
		end
	end

	if not ascendAt and BigNum.gte(total, Config.ASCEND_REQUIREMENT) then
		ascendAt = elapsed
		row(elapsed, "ASCENSION available")
	end

	local bestId, bestCost, bestRatio = nil, nil, -1
	for _, def in Config.MODULES do
		if not unlocked[def.sector] then
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
		local ratio = BigNum.toNumber(
			BigNum.div(BigNum.mulScalar(def.baseIncome, 1 / def.dropInterval), cost)
		)
		if ratio > bestRatio then
			bestId, bestCost, bestRatio = def.id, cost, ratio
		end
	end

	if bestId and bestCost then
		credits = BigNum.sub(credits, bestCost)
		levels[bestId] = (levels[bestId] or 0) + 1
		purchases += 1
		table.insert(gaps, elapsed - lastBuy)
		lastBuy = elapsed
	end
end

row(seconds, "end")

local sum = 0
for _, g in gaps do
	sum += g
end
local avgGap = if #gaps > 0 then sum / #gaps else 0

-- the average gap between purchases is the most important retention metric in the genre: past 3
-- minutes the player gets bored and quits
print("")
print(string.format("total purchases    %d", purchases))
print(string.format("average gap        %.1fs", avgGap))
print(
	string.format(
		"max gap            %s",
		hms(if #gaps > 0 then math.max(table.unpack(gaps)) else 0)
	)
)
print(string.format(
	"sectors unlocked   %d / 6",
	(function()
		local n = 0
		for _ in unlocked do
			n += 1
		end
		return n
	end)()
))
print(string.format("ascension          %s", if ascendAt then hms(ascendAt) else "not reached"))

print("\ndesign windows:")
-- what hurts is the long hole, not a high frequency: an average gap under the minimum is a generous
-- game, not a flaw. we check the max, which is the moment the player gets bored and quits
local maxGap = if #gaps > 0 then math.max(table.unpack(gaps)) else 0
print(string.format("  average gap   < 3min     %s", if avgGap <= 190 then "ok" else "OUT"))
print(string.format("  max gap       < 4min     %s", if maxGap <= 240 then "ok" else "OUT"))
for i = 2, 6 do
	local at = unlocked[i]
	print(string.format("  sector %d      20-40min   %s", i, if at then hms(at) else "not reached"))
end
print(
	string.format(
		"  ascension     2-5h       %s",
		if ascendAt then hms(ascendAt) else "not reached"
	)
)
print("")
