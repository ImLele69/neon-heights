--!strict

-- three quests a day, deterministic from the day and the userId: no need to save which ones were
-- assigned, they get recomputed. we only save progress, the one thing the server can't work out by
-- itself.
--
-- targets scale with how far ahead the player is, or by day three "earn 10,000 credits" would
-- already be done when assigned

local BigNum = require(script.Parent.BigNum)
local Config = require(script.Parent.Config)
local Economy = require(script.Parent.Economy)

type BigNum = BigNum.BigNum

local Quests = {}

Quests.PER_DAY = 3

export type QuestKind = "earn" | "buy" | "ascend" | "crate"

export type QuestDef = {
	id: string,
	kind: QuestKind,
	target: number,
	label: string,
	rewardMinutes: number,
}

-- we need a choice that's stable per player and day, not real randomness: math.random would change
-- on every server restart and quests would reshuffle under the player's hands.
--
-- multiplying and taking the modulo isn't enough, the bits don't mix and adjacent days land in the
-- same bucket. it needs an xorshift
local function hash(a: number, b: number): number
	local h = bit32.bxor(a * 0x9E3779B1, b * 0x85EBCA77)
	h = bit32.bxor(h, bit32.rshift(h, 15))
	h = (h * 0x2545F491) % 0x100000000
	h = bit32.bxor(h, bit32.rshift(h, 13))
	h = (h * 0x27220A95) % 0x100000000
	h = bit32.bxor(h, bit32.rshift(h, 16))
	return h / 0x100000000
end

local TEMPLATES: { { kind: QuestKind, base: number, label: string, minutes: number } } = {
	{ kind = "buy", base = 8, label = "Buy %d modules", minutes = 12 },
	{ kind = "buy", base = 15, label = "Buy %d modules", minutes = 20 },
	{ kind = "earn", base = 60, label = "Earn %s credits", minutes = 15 },
	{ kind = "earn", base = 180, label = "Earn %s credits", minutes = 25 },
	{ kind = "crate", base = 2, label = "Open %d crates", minutes = 18 },
	{ kind = "ascend", base = 1, label = "Ascend %dx", minutes = 40 },
}

-- earn quests are expressed in seconds of current production, so they stay equally hard at every
-- stage of progression
local function earnTarget(p: Economy.ProfileLike, seconds: number, now: number): BigNum
	local rate = Economy.incomePerSecond(p, now)
	local floor = BigNum.mulScalar(BigNum.new(Config.FIRST_COST, 0), seconds / 10)
	return BigNum.max(BigNum.mulScalar(rate, seconds), floor)
end

export type Quest = {
	id: string,
	kind: QuestKind,
	label: string,
	target: number,
	targetBig: BigNum?,
	progress: number,
	progressBig: BigNum?,
	complete: boolean,
	claimed: boolean,
	rewardMinutes: number,
}

export type Progress = {
	day: number,
	buy: number,
	crate: number,
	ascend: number,
	earn: { number },
	claimed: { [string]: boolean },
}

function Quests.emptyProgress(day: number): Progress
	return {
		day = day,
		buy = 0,
		crate = 0,
		ascend = 0,
		earn = BigNum.serialize(BigNum.ZERO),
		claimed = {},
	}
end

-- yesterday's progress doesn't count for today's quests
function Quests.rollOver(progress: Progress?, day: number): Progress
	if not progress or type(progress) ~= "table" or progress.day ~= day then
		return Quests.emptyProgress(day)
	end
	return progress
end

-- three distinct templates per day: picking with repetition would give the same quest twice, which
-- looks like a bug even when it isn't
local function pickTemplates(userId: number, day: number): { number }
	local pool = {}
	for i = 1, #TEMPLATES do
		table.insert(pool, i)
	end
	local picked = {}
	for n = 1, Quests.PER_DAY do
		local r = hash(userId + n * 7919, day)
		local idx = math.floor(r * #pool) + 1
		idx = math.clamp(idx, 1, #pool)
		table.insert(picked, pool[idx])
		table.remove(pool, idx)
	end
	return picked
end

function Quests.daily(
	p: Economy.ProfileLike,
	userId: number,
	day: number,
	progress: Progress,
	now: number
): { Quest }
	local out: { Quest } = {}
	for slot, templateIndex in pickTemplates(userId, day) do
		local tpl = TEMPLATES[templateIndex]
		local id = string.format("d%d_s%d", day, slot)

		if tpl.kind == "earn" then
			local target = earnTarget(p, tpl.base, now)
			local done = BigNum.deserialize(progress.earn)
			table.insert(out, {
				id = id,
				kind = tpl.kind,
				label = string.format(tpl.label, BigNum.format(target)),
				target = 0,
				targetBig = target,
				progress = 0,
				progressBig = done,
				complete = BigNum.gte(done, target),
				claimed = progress.claimed[id] == true,
				rewardMinutes = tpl.minutes,
			})
		else
			local done = if tpl.kind == "buy"
				then progress.buy
				elseif tpl.kind == "crate" then progress.crate
				else progress.ascend
			table.insert(out, {
				id = id,
				kind = tpl.kind,
				label = string.format(tpl.label, tpl.base),
				target = tpl.base,
				progress = done,
				complete = done >= tpl.base,
				claimed = progress.claimed[id] == true,
				rewardMinutes = tpl.minutes,
			})
		end
	end
	return out
end

export type ClaimResult = {
	ok: boolean,
	reason: string?,
	credits: BigNum?,
	label: string?,
}

function Quests.claim(
	p: Economy.ProfileLike,
	quests: { Quest },
	questId: any,
	now: number
): ClaimResult
	if type(questId) ~= "string" then
		return { ok = false, reason = "invalid quest" }
	end
	for _, q in quests do
		if q.id ~= questId then
			continue
		end
		if q.claimed then
			return { ok = false, reason = "already claimed" }
		end
		if not q.complete then
			return { ok = false, reason = "not completed yet" }
		end
		local rate = Economy.incomePerSecond(p, now)
		local amount = BigNum.mulScalar(rate, q.rewardMinutes * 60)
		local floor = BigNum.mulScalar(BigNum.new(Config.FIRST_COST, 0), q.rewardMinutes)
		return { ok = true, credits = BigNum.max(amount, floor), label = q.label }
	end
	return { ok = false, reason = "no such quest" }
end

Quests._hash = hash
Quests._templates = TEMPLATES

return Quests
