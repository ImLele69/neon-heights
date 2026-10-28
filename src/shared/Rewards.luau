--!strict

-- daily, crates and codes. pure logic like Economy: it decides, it doesn't apply.
--
-- rewards aren't a fixed amount but a multiple of current income. a fixed amount is huge for a
-- beginner and ridiculous for someone who's ahead, and in the second case the reward stops being a
-- reason to come back

local BigNum = require(script.Parent.BigNum)
local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)
local Sectors = require(script.Parent.Sectors)

type BigNum = BigNum.BigNum

local Rewards = {}

local DAY = 86400

-- the day is computed in UTC: using the server's local time would mean the streak changes depending
-- on which region you land on
function Rewards.dayIndex(timestamp: number): number
	return math.floor(timestamp / DAY)
end

export type DailyState = {
	available: boolean,
	streak: number,
	nextStreak: number,
	secondsUntilNext: number,
	rewardIndex: number,
}

-- the streak goes up by one day and resets if you skip one. the reset is the real lever of the
-- system, the reward is worth much less than the fear of losing seven days in a row
function Rewards.dailyState(lastClaim: number, streak: number, now: number): DailyState
	local today = Rewards.dayIndex(now)
	local lastDay = if lastClaim > 0 then Rewards.dayIndex(lastClaim) else -1

	local available = today > lastDay
	local nextStreak: number
	if lastDay < 0 or today - lastDay > 1 then
		nextStreak = 1
	elseif today - lastDay == 1 then
		nextStreak = streak + 1
	else
		nextStreak = streak
	end

	local cycle = #Config.DAILY_REWARDS
	local rewardIndex = ((nextStreak - 1) % cycle) + 1

	return {
		available = available,
		streak = streak,
		nextStreak = nextStreak,
		secondsUntilNext = math.max(0, (today + 1) * DAY - now),
		rewardIndex = rewardIndex,
	}
end

export type Grant = {
	credits: BigNum?,
	boostMult: number?,
	boostSeconds: number?,
	cosmetic: string?,
	label: string,
}

-- credit rewards in Config are absolute amounts, only good at the start. past a certain income
-- they're worth more as "this many minutes of production", so we take the larger of the two and the
-- reward always makes sense
local DAILY_MINUTES = { 5, 10, 20, 30, 45, 60, 120 }

function Rewards.dailyGrant(p: Economy.ProfileLike, rewardIndex: number, now: number): Grant
	local def = Config.DAILY_REWARDS[rewardIndex]
	if not def then
		return { label = "nothing" }
	end

	local grant: Grant = {
		boostMult = def.boostMult,
		boostSeconds = def.boostSeconds,
		cosmetic = def.cosmetic,
		label = def.label,
	}

	if def.credits then
		local minutes = DAILY_MINUTES[rewardIndex] or 10
		local rate = Economy.incomePerSecond(p, now)
		local scaled = BigNum.mulScalar(rate, minutes * 60)
		grant.credits = BigNum.max(def.credits, scaled)
	end

	return grant
end

export type CrateState = {
	available: boolean,
	secondsRemaining: number,
}

function Rewards.crateState(
	lastCrate: number,
	now: number,
	dataUpgrades: { [string]: number }?
): CrateState
	local elapsed = now - lastCrate
	-- a lastCrate in the future (clock jump) must not lock the crate
	if elapsed < 0 then
		return { available = true, secondsRemaining = 0 }
	end
	local interval = Config.CRATE_INTERVAL * (1 - Sectors.dataBonuses(dataUpgrades).crateSpeedup)
	local remaining = interval - elapsed
	return {
		available = remaining <= 0,
		secondsRemaining = math.max(0, remaining),
	}
end

-- a crate is worth a few minutes of production, with some variance that makes it interesting to
-- open. the guaranteed minimum is for people who just joined and have almost no income
Rewards.CRATE_MIN_MINUTES = 3
Rewards.CRATE_MAX_MINUTES = 8

function Rewards.crateGrant(p: Economy.ProfileLike, now: number, roll: number): Grant
	local t = math.clamp(roll, 0, 1)
	local minutes = Rewards.CRATE_MIN_MINUTES
		+ (Rewards.CRATE_MAX_MINUTES - Rewards.CRATE_MIN_MINUTES) * t
	local rate = Economy.incomePerSecond(p, now)
	local amount = BigNum.mulScalar(rate, minutes * 60)
	local floor = BigNum.mulScalar(BigNum.new(Config.FIRST_COST, 0), minutes)
	return {
		credits = BigNum.max(amount, floor),
		label = string.format("Crate: %.0f minutes", minutes),
	}
end

-- codes live here because publishing a new one shouldn't need touching the server code
export type CodeDef = {
	minutes: number?,
	boostMult: number?,
	boostSeconds: number?,
	expiresAt: number?,
}

Rewards.CODES = {
	LAUNCH = { minutes = 30 },
	NEON = { minutes = 15 },
	BRAINROT = { boostMult = 2, boostSeconds = 1800 },
} :: { [string]: any }

export type CodeResult = {
	ok: boolean,
	reason: string?,
	grant: Grant?,
}

function Rewards.redeemCode(
	p: Economy.ProfileLike,
	redeemed: { [string]: boolean },
	raw: any,
	now: number
): CodeResult
	if type(raw) ~= "string" then
		return { ok = false, reason = "invalid code" }
	end
	-- players type with random caps and paste spaces
	local code = string.upper((string.gsub(raw, "%s", "")))
	if #code == 0 or #code > 32 then
		return { ok = false, reason = "invalid code" }
	end

	local def = Rewards.CODES[code]
	if not def then
		return { ok = false, reason = "no such code" }
	end
	if redeemed[code] then
		return { ok = false, reason = "already redeemed" }
	end
	if def.expiresAt and now > def.expiresAt then
		return { ok = false, reason = "code expired" }
	end

	local grant: Grant = { label = code }
	if def.minutes then
		local rate = Economy.incomePerSecond(p, now)
		local amount = BigNum.mulScalar(rate, def.minutes * 60)
		local floor = BigNum.mulScalar(BigNum.new(Config.FIRST_COST, 0), def.minutes)
		grant.credits = BigNum.max(amount, floor)
	end
	grant.boostMult = def.boostMult
	grant.boostSeconds = def.boostSeconds

	return { ok = true, grant = grant }
end

-- an active boost gets extended instead of replaced: replacing it would punish whoever redeems one
-- while another is running
export type BoostState = { boostUntil: number, boostMult: number }

function Rewards.applyBoost(
	current: BoostState,
	mult: number,
	seconds: number,
	now: number
): BoostState
	if mult <= 1 or seconds <= 0 then
		return { boostUntil = current.boostUntil, boostMult = current.boostMult }
	end
	local active = current.boostUntil > now and current.boostMult > 1
	if not active then
		return { boostUntil = now + seconds, boostMult = mult }
	end
	if mult > current.boostMult then
		-- the stronger boost wins, and the old one's leftover time is added on
		return { boostUntil = now + seconds + (current.boostUntil - now), boostMult = mult }
	end
	return { boostUntil = current.boostUntil + seconds, boostMult = current.boostMult }
end

return Rewards
