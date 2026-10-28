--!strict

-- token bucket per player and per action. a hostile client can fire a remote thousands of times a
-- second: with no limit the server spends the whole frame rejecting requests, which is already a
-- denial of service on its own.
--
-- the bucket refills over time instead of resetting on fixed windows, so an honest player clicking
-- fast doesn't get blocked

local RateLimiter = {}

export type Bucket = {
	tokens: number,
	capacity: number,
	refillPerSecond: number,
	updatedAt: number,
}

type Key = string

local buckets: { [number]: { [Key]: Bucket } } = {}

-- one purchase every ~0.4s on average with bursts of 8. a player spamming the button won't notice,
-- a bot will
local LIMITS: { [Key]: { capacity: number, refill: number } } = {
	BuyModule = { capacity = 8, refill = 2.5 },
	Ascend = { capacity = 2, refill = 0.2 },
	ClaimDaily = { capacity = 3, refill = 0.1 },
	ClaimCrate = { capacity = 3, refill = 0.2 },
	RedeemCode = { capacity = 5, refill = 0.15 },
	ClaimQuest = { capacity = 4, refill = 0.2 },
	OpenShop = { capacity = 4, refill = 0.5 },
	BuyDataUpgrade = { capacity = 6, refill = 1 },
	GetState = { capacity = 5, refill = 1 },
}

local DEFAULT = { capacity = 5, refill = 1 }

function RateLimiter.check(userId: number, key: Key, now: number): boolean
	local perUser = buckets[userId]
	if not perUser then
		perUser = {}
		buckets[userId] = perUser
	end

	local limit = LIMITS[key] or DEFAULT
	local b = perUser[key]
	if not b then
		b = {
			tokens = limit.capacity,
			capacity = limit.capacity,
			refillPerSecond = limit.refill,
			updatedAt = now,
		}
		perUser[key] = b
	end

	local elapsed = math.max(0, now - b.updatedAt)
	b.tokens = math.min(b.capacity, b.tokens + elapsed * b.refillPerSecond)
	b.updatedAt = now

	if b.tokens < 1 then
		return false
	end
	b.tokens -= 1
	return true
end

function RateLimiter.clear(userId: number)
	buckets[userId] = nil
end

RateLimiter._buckets = buckets
RateLimiter._limits = LIMITS

return RateLimiter
