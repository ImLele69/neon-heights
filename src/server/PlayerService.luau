--!strict

-- the only place that mutates profiles. the client sends intents, never values: every handler
-- checks again with Economy before granting anything, because the copy of Economy running on the
-- client is under the player's control

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Remotes = require(Shared.Remotes)
local Quests = require(Shared.Quests)
local Rewards = require(Shared.Rewards)
local Sectors = require(Shared.Sectors)

local DataService = require(script.Parent.DataService)
local RateLimiter = require(script.Parent.RateLimiter)

type BigNum = BigNum.BigNum
type Profile = DataService.Profile

local PlayerService = {}

local ownedPasses: { [number]: { [string]: boolean } } = {}
local lastTick: { [number]: number } = {}

local function passes(userId: number): Economy.Multipliers
	local owned = ownedPasses[userId] or {}
	return {
		doubleCredits = owned.doubleCredits,
		extraDroppers = owned.extraDroppers,
	}
end

function PlayerService.hasPass(userId: number, name: string): boolean
	local owned = ownedPasses[userId]
	return owned ~= nil and owned[name] == true
end

-- MarketplaceService can fail or be slow. an error here must not block joining, we retry on the
-- next join
local function loadPasses(player: Player)
	local owned: { [string]: boolean } = {}
	for name, info in Config.GAMEPASSES do
		if info.id == 0 then
			continue
		end
		local ok, result = pcall(function()
			return MarketplaceService:UserOwnsGamePassAsync(player.UserId, info.id)
		end)
		if ok then
			owned[name] = result
		else
			warn(
				string.format(
					"[PlayerService] couldn't check gamepass %s: %s",
					name,
					tostring(result)
				)
			)
		end
	end
	ownedPasses[player.UserId] = owned
end

local function notify(player: Player, kind: string, payload: any)
	Remotes.event("Notify"):FireClient(player, kind, payload)
end

PlayerService.notify = notify

-- a gamepass bought mid session has to work right away, ShopService calls this instead of waiting
-- for the next join
function PlayerService.refreshPasses(player: Player)
	task.spawn(loadPasses, player)
end

-- quests are recomputed from day and userId, so here we only need to keep progress in sync with the
-- current day
local function questProgress(p: Profile, now: number): any
	local day = Rewards.dayIndex(now)
	local progress = Quests.rollOver(p.quests, day)
	p.quests = progress
	return progress
end

-- the state sent to the client is already serialized: no live BigNums on the wire, and no internal
-- fields like the session lock
local function buildState(player: Player): any?
	local p = DataService.get(player.UserId)
	if not p then
		return nil
	end
	local now = os.time()
	local m = passes(player.UserId)
	return {
		credits = p.credits,
		earnedTotal = p.earnedTotal,
		data = p.data,
		ascensions = p.ascensions,
		modules = p.modules,
		dailyStreak = p.dailyStreak,
		lastDailyClaim = p.lastDailyClaim,
		boostUntil = p.boostUntil,
		boostMult = p.boostMult,
		cosmetics = p.cosmetics,
		incomePerSecond = BigNum.serialize(Economy.incomePerSecond(p, now, m)),
		multiplier = Economy.totalMultiplier(p, now, m),
		highestSector = Economy.highestSector(p),
		canAscend = Economy.canAscend(p),
		passes = ownedPasses[player.UserId] or {},
		daily = Rewards.dailyState(p.lastDailyClaim, p.dailyStreak, now),
		crate = Rewards.crateState(p.lastCrate, now, p.dataUpgrades),
		quests = Quests.daily(p, player.UserId, Rewards.dayIndex(now), questProgress(p, now), now),
		dataUpgrades = p.dataUpgrades,
		dataUnlocked = Economy.sectorUnlocked(p, Sectors.DATA_SECTOR),
		serverTime = now,
	}
end

local function pushState(player: Player)
	local state = buildState(player)
	if state then
		Remotes.event("StateSync"):FireClient(player, state)
	end
end

PlayerService.pushState = pushState

local function grant(p: Profile, amount: BigNum)
	if BigNum.isZero(amount) then
		return
	end
	p.credits = BigNum.serialize(BigNum.add(BigNum.deserialize(p.credits), amount))
	p.earnedTotal = BigNum.serialize(BigNum.add(BigNum.deserialize(p.earnedTotal), amount))
end

PlayerService.grant = grant

local function onJoin(player: Player)
	loadPasses(player)

	local p = DataService.load(player.UserId)
	if not p then
		player:Kick("Couldn't load your save. Try again in a minute.")
		return
	end

	local now = os.time()
	local m = passes(player.UserId)
	local offline = Economy.offlineEarnings(
		p,
		p.lastSeen,
		now,
		ownedPasses[player.UserId] and ownedPasses[player.UserId].offlineExtended,
		m
	)
	if not BigNum.isZero(offline.credits) then
		grant(p, offline.credits)
		notify(player, "offline", {
			credits = BigNum.serialize(offline.credits),
			seconds = offline.cappedSeconds,
			hitCap = offline.hitCap,
		})
	end

	p.lastSeen = now
	lastTick[player.UserId] = now
	pushState(player)
end

local function onLeave(player: Player)
	-- lastSeen gets stamped by DataService.release. the player might already be gone here,
	-- PlayerRemoving order isn't guaranteed
	RateLimiter.clear(player.UserId)
	ownedPasses[player.UserId] = nil
	lastTick[player.UserId] = nil
end

-- anyone who wants to react to a purchase registers here. it exists because the visual side lives
-- in PlotService, which already depends on this module: without the callback it'd be a circular
-- dependency
local purchaseListeners: { (Player, string, number) -> () } = {}

function PlayerService.onPurchase(fn: (Player, string, number) -> ())
	table.insert(purchaseListeners, fn)
end

-- the one place that buys a module. both the remote and the ProximityPrompt go through here: two
-- copies of the same rule would drift apart, and one of them would be the wrong one
function PlayerService.buyModule(player: Player, moduleId: any, silent: boolean?): boolean
	if type(moduleId) ~= "string" then
		return false
	end
	if not RateLimiter.check(player.UserId, "BuyModule", os.clock()) then
		return false
	end
	local p = DataService.get(player.UserId)
	if not p then
		return false
	end

	local check = Economy.canBuyModule(p, moduleId)
	if not check.ok or not check.cost then
		if not silent then
			notify(player, "denied", { reason = check.reason })
		end
		return false
	end

	p.credits = BigNum.serialize(BigNum.sub(BigNum.deserialize(p.credits), check.cost))
	p.modules[moduleId] = check.newLevel

	local level = check.newLevel :: number
	for _, fn in purchaseListeners do
		task.spawn(fn, player, moduleId, level)
	end

	pushState(player)
	notify(player, "bought", { moduleId = moduleId, level = level })
	return true
end

local function handleBuyModule(player: Player, moduleId: any)
	PlayerService.buyModule(player, moduleId)
end

local function bumpQuest(player: Player, field: string, amount: number)
	local p = DataService.get(player.UserId)
	if not p then
		return
	end
	local progress = questProgress(p, os.time())
	progress[field] = (progress[field] or 0) + amount
end

local function bumpQuestEarn(p: Profile, amount: BigNum)
	local progress = questProgress(p, os.time())
	progress.earn = BigNum.serialize(BigNum.add(BigNum.deserialize(progress.earn), amount))
end

local function handleClaimQuest(player: Player, questId: any)
	if not RateLimiter.check(player.UserId, "ClaimQuest", os.clock()) then
		return
	end
	local p = DataService.get(player.UserId)
	if not p then
		return
	end
	local now = os.time()
	local progress = questProgress(p, now)
	local list = Quests.daily(p, player.UserId, Rewards.dayIndex(now), progress, now)
	local r = Quests.claim(p, list, questId, now)
	if not r.ok or not r.credits then
		notify(player, "denied", { reason = r.reason })
		return
	end

	progress.claimed[questId] = true
	grant(p, r.credits)
	DataService.save(player.UserId, false)
	pushState(player)
	notify(player, "quest", {
		label = r.label,
		credits = BigNum.serialize(r.credits),
	})
end

local function handleBuyDataUpgrade(player: Player, upgradeId: any)
	if not RateLimiter.check(player.UserId, "BuyDataUpgrade", os.clock()) then
		return
	end
	if type(upgradeId) ~= "string" then
		return
	end
	local p = DataService.get(player.UserId)
	if not p then
		return
	end
	if not Economy.sectorUnlocked(p, Sectors.DATA_SECTOR) then
		notify(player, "denied", { reason = "archive not unlocked" })
		return
	end

	local def = Sectors.DATA_UPGRADES_BY_ID[upgradeId]
	if not def then
		return
	end
	local level = p.dataUpgrades[upgradeId] or 0
	if level >= def.maxLevel then
		notify(player, "denied", { reason = "already maxed" })
		return
	end
	local cost = Sectors.dataUpgradeCost(def, level)
	if p.data < cost then
		notify(player, "denied", { reason = "not enough data" })
		return
	end

	p.data -= cost
	p.dataUpgrades[upgradeId] = level + 1
	DataService.save(player.UserId, false)
	pushState(player)
	notify(player, "dataUpgrade", { name = def.name, level = level + 1 })
end

local function handleClaimDaily(player: Player)
	if not RateLimiter.check(player.UserId, "ClaimDaily", os.clock()) then
		return
	end
	local p = DataService.get(player.UserId)
	if not p then
		return
	end
	local now = os.time()
	local state = Rewards.dailyState(p.lastDailyClaim, p.dailyStreak, now)
	if not state.available then
		notify(player, "denied", { reason = "come back tomorrow" })
		return
	end

	local g = Rewards.dailyGrant(p, state.rewardIndex, now)
	p.dailyStreak = state.nextStreak
	p.lastDailyClaim = now
	if g.credits then
		grant(p, g.credits)
	end
	if g.boostMult and g.boostSeconds then
		local b = Rewards.applyBoost(p, g.boostMult, g.boostSeconds, now)
		p.boostUntil, p.boostMult = b.boostUntil, b.boostMult
	end
	if g.cosmetic then
		p.cosmetics[g.cosmetic] = true
	end

	-- save right away: a daily reward lost in a crash is a streak day the player can't get back
	DataService.save(player.UserId, false)
	pushState(player)
	notify(player, "daily", {
		streak = state.nextStreak,
		label = g.label,
		credits = if g.credits then BigNum.serialize(g.credits) else nil,
	})
end

local function handleClaimCrate(player: Player)
	if not RateLimiter.check(player.UserId, "ClaimCrate", os.clock()) then
		return
	end
	local p = DataService.get(player.UserId)
	if not p then
		return
	end
	local now = os.time()
	if not Rewards.crateState(p.lastCrate, now, p.dataUpgrades).available then
		notify(player, "denied", { reason = "crate not ready" })
		return
	end

	local g = Rewards.crateGrant(p, now, math.random())
	p.lastCrate = now
	questProgress(p, now).crate += 1
	if g.credits then
		grant(p, g.credits)
	end
	pushState(player)
	notify(player, "crate", {
		label = g.label,
		credits = if g.credits then BigNum.serialize(g.credits) else nil,
	})
end

local function handleRedeemCode(player: Player, raw: any)
	if not RateLimiter.check(player.UserId, "RedeemCode", os.clock()) then
		return
	end
	local p = DataService.get(player.UserId)
	if not p then
		return
	end
	local now = os.time()
	local r = Rewards.redeemCode(p, p.redeemedCodes, raw, now)
	if not r.ok or not r.grant then
		notify(player, "denied", { reason = r.reason })
		return
	end

	local g = r.grant
	p.redeemedCodes[g.label] = true
	if g.credits then
		grant(p, g.credits)
	end
	if g.boostMult and g.boostSeconds then
		local b = Rewards.applyBoost(p, g.boostMult, g.boostSeconds, now)
		p.boostUntil, p.boostMult = b.boostUntil, b.boostMult
	end
	DataService.save(player.UserId, false)
	pushState(player)
	notify(player, "code", {
		label = g.label,
		credits = if g.credits then BigNum.serialize(g.credits) else nil,
	})
end

local function handleAscend(player: Player)
	if not RateLimiter.check(player.UserId, "Ascend", os.clock()) then
		return
	end
	local p = DataService.get(player.UserId)
	if not p then
		return
	end
	if not Economy.canAscend(p) then
		notify(player, "denied", { reason = "threshold not reached" })
		return
	end

	local result = Economy.applyAscend(p)
	questProgress(p, os.time()).ascend += 1
	p.ascensions = result.ascensions
	p.modules = result.modules
	p.credits = result.credits
	-- save immediately: a crash right after ascending would refund the reset without the multiplier
	DataService.save(player.UserId, false)
	pushState(player)
	notify(player, "ascended", { ascensions = result.ascensions, multiplier = result.multiplier })
end

-- income is credited at intervals instead of every frame: less work, and above all a single place
-- where time can jump
function PlayerService.tick(now: number)
	for _, player in Players:GetPlayers() do
		local p = DataService.get(player.UserId)
		if not p then
			continue
		end
		local last = lastTick[player.UserId] or now
		local delta = math.clamp(now - last, 0, 60)
		lastTick[player.UserId] = now
		if delta <= 0 then
			continue
		end
		local rate = Economy.incomePerSecond(p, now, passes(player.UserId))
		local earned = BigNum.mulScalar(rate, delta)
		grant(p, earned)
		bumpQuestEarn(p, earned)

		-- data accrues with time, not income. it's the only progression you can't speed up by buying
		-- credits
		p.data += Sectors.dataGained(
			p.playtime,
			delta,
			Economy.sectorUnlocked(p, Sectors.DATA_SECTOR)
		)
		p.playtime += delta
	end
end

function PlayerService.start()
	Remotes.init()

	Remotes.event("BuyModule").OnServerEvent:Connect(handleBuyModule)
	Remotes.event("Ascend").OnServerEvent:Connect(handleAscend)
	Remotes.event("ClaimDaily").OnServerEvent:Connect(handleClaimDaily)
	Remotes.event("ClaimCrate").OnServerEvent:Connect(handleClaimCrate)
	Remotes.event("RedeemCode").OnServerEvent:Connect(handleRedeemCode)
	Remotes.event("ClaimQuest").OnServerEvent:Connect(handleClaimQuest)
	Remotes.event("BuyDataUpgrade").OnServerEvent:Connect(handleBuyDataUpgrade)

	PlayerService.onPurchase(function(player: Player)
		bumpQuest(player, "buy", 1)
	end)

	Remotes.fn("GetState").OnServerInvoke = function(player: Player)
		if not RateLimiter.check(player.UserId, "GetState", os.clock()) then
			return nil
		end
		return buildState(player)
	end

	Players.PlayerAdded:Connect(onJoin)
	Players.PlayerRemoving:Connect(onLeave)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end

	task.spawn(function()
		while true do
			task.wait(1)
			PlayerService.tick(os.time())
		end
	end)

	-- the full state goes to the client rarely, the numbers that change all the time get interpolated
	-- client side
	task.spawn(function()
		while true do
			task.wait(3)
			for _, player in Players:GetPlayers() do
				pushState(player)
			end
		end
	end)
end

return PlayerService
