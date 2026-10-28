--!strict

-- money rules, without touching Roblox. every function takes a profile and returns what should
-- happen without applying it, so the same logic is testable from the CLI and the server stays the
-- only one mutating state.
--
-- the client can import this module to show prices and forecasts, but its copy doesn't count: the
-- server recomputes everything before granting

local BigNum = require(script.Parent.BigNum)
local Config = require(script.Parent.Config)
local Sectors = require(script.Parent.Sectors)

type BigNum = BigNum.BigNum

export type ProfileLike = {
	credits: { number },
	earnedTotal: { number },
	modules: { [string]: number },
	ascensions: number,
	boostUntil: number,
	boostMult: number,
	data: number,
	dataUpgrades: { [string]: number }?,
}

export type Multipliers = {
	doubleCredits: boolean?,
	extraDroppers: boolean?,
}

local Economy = {}

function Economy.credits(p: ProfileLike): BigNum
	return BigNum.deserialize(p.credits)
end

function Economy.earnedTotal(p: ProfileLike): BigNum
	return BigNum.deserialize(p.earnedTotal)
end

function Economy.moduleLevel(p: ProfileLike, id: string): number
	return p.modules[id] or 0
end

-- a sector is unlocked by total earned, which never goes down, so spending doesn't lock a sector
-- you've already seen
function Economy.sectorUnlocked(p: ProfileLike, sectorIndex: number): boolean
	local sector = Config.SECTORS[sectorIndex]
	if not sector then
		return false
	end
	return BigNum.gte(Economy.earnedTotal(p), sector.unlockTotal)
end

function Economy.highestSector(p: ProfileLike): number
	local highest = 1
	for i = 1, #Config.SECTORS do
		if Economy.sectorUnlocked(p, i) then
			highest = i
		end
	end
	return highest
end

function Economy.boostActive(p: ProfileLike, now: number): boolean
	return p.boostUntil > now and p.boostMult > 1
end

-- every multiplier in one place: if they were summed all over the code it'd be impossible to tell
-- why a player earns what they earn
function Economy.totalMultiplier(p: ProfileLike, now: number, m: Multipliers?): number
	local mult = Config.ascendMultiplier(p.ascensions)
	mult *= Sectors.totalMultiplier(p.modules, p.dataUpgrades)
	if Economy.boostActive(p, now) then
		mult *= p.boostMult
	end
	if m and m.doubleCredits then
		mult *= Config.GAMEPASSES.doubleCredits.mult
	end
	return mult
end

-- credits per second, multipliers applied. it's the number shown in the UI and the one used for
-- offline earnings
function Economy.incomePerSecond(p: ProfileLike, now: number, m: Multipliers?): BigNum
	local total = BigNum.ZERO
	for id, level in p.modules do
		local def = Config.MODULES_BY_ID[id]
		if not def or level <= 0 then
			continue
		end
		local perDrop = Config.moduleIncome(def, level)
		total = BigNum.add(total, BigNum.mulScalar(perDrop, 1 / def.dropInterval))
	end
	return BigNum.mulScalar(total, Economy.totalMultiplier(p, now, m))
end

function Economy.moduleCost(p: ProfileLike, id: string): BigNum?
	local def = Config.MODULES_BY_ID[id]
	if not def then
		return nil
	end
	return Config.moduleCost(def, Economy.moduleLevel(p, id))
end

export type PurchaseCheck = {
	ok: boolean,
	reason: string?,
	cost: BigNum?,
	newLevel: number?,
}

-- the server calls this before granting any purchase. the client calls it to disable buttons, but
-- its answer means nothing
function Economy.canBuyModule(p: ProfileLike, id: string): PurchaseCheck
	local def = Config.MODULES_BY_ID[id]
	if not def then
		return { ok = false, reason = "no such module" }
	end
	if not Economy.sectorUnlocked(p, def.sector) then
		return { ok = false, reason = "sector locked" }
	end
	local level = Economy.moduleLevel(p, id)
	if level >= Config.MAX_MODULE_LEVEL then
		return { ok = false, reason = "max level" }
	end
	local cost = Config.moduleCost(def, level)
	if not BigNum.gte(Economy.credits(p), cost) then
		return { ok = false, reason = "not enough credits", cost = cost }
	end
	return { ok = true, cost = cost, newLevel = level + 1 }
end

function Economy.canAscend(p: ProfileLike): boolean
	return BigNum.gte(Economy.earnedTotal(p), Config.ASCEND_REQUIREMENT)
end

-- how many credits being away is worth. the cap is also the gamepass hook: whoever stays away long
-- sees how much they lost to the cap, and has a reason to buy the extension
export type OfflineResult = {
	seconds: number,
	cappedSeconds: number,
	credits: BigNum,
	hitCap: boolean,
}

function Economy.offlineEarnings(
	p: ProfileLike,
	lastSeen: number,
	now: number,
	extendedCap: boolean?,
	m: Multipliers?
): OfflineResult
	local elapsed = math.max(0, now - lastSeen)
	local capHours = if extendedCap
		then Config.OFFLINE_CAP_HOURS_GAMEPASS
		else Config.OFFLINE_CAP_HOURS
	capHours += Sectors.dataBonuses(p.dataUpgrades).offlineBonusHours
	local capSeconds = capHours * 3600
	local counted = math.min(elapsed, capSeconds)

	-- the boost must not tick while the player is offline
	local rate = Economy.incomePerSecond({
		credits = p.credits,
		earnedTotal = p.earnedTotal,
		modules = p.modules,
		ascensions = p.ascensions,
		boostUntil = 0,
		boostMult = 1,
		data = p.data,
		dataUpgrades = p.dataUpgrades,
	}, now, m)

	return {
		seconds = elapsed,
		cappedSeconds = counted,
		credits = BigNum.mulScalar(rate, counted * Config.OFFLINE_RATE),
		hitCap = elapsed > capSeconds,
	}
end

-- credit packs are sold as "this much playtime", not a fixed amount: a fixed amount is useless to a
-- beginner and ridiculous for someone who's ahead. it scales with current income
function Economy.productCreditValue(
	p: ProfileLike,
	now: number,
	scaleSeconds: number,
	m: Multipliers?
): BigNum
	local rate = Economy.incomePerSecond(p, now, m)
	if BigNum.isZero(rate) then
		-- a brand new profile must not get zero from a real purchase
		return BigNum.mulScalar(BigNum.new(Config.FIRST_COST, 0), scaleSeconds / 60)
	end
	return BigNum.mulScalar(rate, scaleSeconds)
end

export type AscendResult = {
	ascensions: number,
	modules: { [string]: number },
	credits: { number },
	multiplier: number,
}

-- ascending resets modules and credits but not earnedTotal: that's the memory of what you've
-- already seen, and resetting it would lock the sectors again
function Economy.applyAscend(p: ProfileLike): AscendResult
	local ascensions = p.ascensions + 1
	return {
		ascensions = ascensions,
		modules = { [Config.SEED_MODULE] = Config.SEED_LEVEL },
		credits = BigNum.serialize(BigNum.ZERO),
		multiplier = Config.ascendMultiplier(ascensions),
	}
end

-- progress towards the next milestone, for the always on screen bar. without a visible goal the
-- player doesn't know what they're going for and quits
export type NextGoal = {
	kind: "module" | "sector" | "ascend",
	label: string,
	progress: number,
	cost: BigNum?,
}

function Economy.nextGoal(p: ProfileLike): NextGoal
	local credits = Economy.credits(p)

	local bestId, bestCost = nil, nil
	for _, def in Config.MODULES do
		if not Economy.sectorUnlocked(p, def.sector) then
			continue
		end
		if Economy.moduleLevel(p, def.id) >= Config.MAX_MODULE_LEVEL then
			continue
		end
		local cost = Config.moduleCost(def, Economy.moduleLevel(p, def.id))
		if not bestCost or BigNum.lt(cost, bestCost) then
			bestId, bestCost = def.id, cost
		end
	end

	if bestId and bestCost and BigNum.lt(credits, bestCost) then
		return {
			kind = "module",
			label = Config.MODULES_BY_ID[bestId].name,
			progress = math.clamp(BigNum.toNumber(BigNum.div(credits, bestCost)), 0, 1),
			cost = bestCost,
		}
	end

	local highest = Economy.highestSector(p)
	local nextSector = Config.SECTORS[highest + 1]
	if nextSector then
		local earned = Economy.earnedTotal(p)
		return {
			kind = "sector",
			label = nextSector.name,
			progress = math.clamp(
				BigNum.toNumber(BigNum.div(earned, nextSector.unlockTotal)),
				0,
				1
			),
			cost = nextSector.unlockTotal,
		}
	end

	local earned = Economy.earnedTotal(p)
	return {
		kind = "ascend",
		label = "Ascension",
		progress = math.clamp(BigNum.toNumber(BigNum.div(earned, Config.ASCEND_REQUIREMENT)), 0, 1),
		cost = Config.ASCEND_REQUIREMENT,
	}
end

return Economy
