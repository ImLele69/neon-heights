--!strict

-- persistence with a session lock. without it a player hopping between two servers (or rejoining
-- before the old one saved) duplicates credits or loses the session, it's the most expensive bug in
-- the genre.
--
-- ProfileService does this and more. this is the minimal version with no dependencies, because the
-- data model is small and I want to test it with Lune

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Sectors = require(Shared.Sectors)
local BigNum = require(Shared.BigNum)

type BigNum = BigNum.BigNum

export type Profile = {
	version: number,
	credits: { number },
	earnedTotal: { number },
	data: number,
	ascensions: number,
	modules: { [string]: number },
	lastSeen: number,
	dailyStreak: number,
	lastDailyClaim: number,
	lastCrate: number,
	quests: any,
	dataUpgrades: { [string]: number },
	boostUntil: number,
	boostMult: number,
	cosmetics: { [string]: boolean },
	redeemedCodes: { [string]: boolean },
	playtime: number,
	-- lock
	sessionJobId: string?,
	sessionStamp: number?,
}

local PROFILE_VERSION = 1

-- if a server crashes the lock stays written: after this long it's considered dead and gets stolen.
-- must be longer than the autosave interval, or we'd steal the lock from a live server
local LOCK_STALE_SECONDS = 300
local LOCK_RETRY_ATTEMPTS = 5
local LOCK_RETRY_DELAY = 4

local store = DataStoreService:GetDataStore("NeonHeights_Profiles_v1")

local DataService = {}

local loaded: { [number]: Profile } = {}
local releasing: { [number]: boolean } = {}
-- keeps the profile around for the final save only, after it left `loaded`
local releasedSnapshot: { [number]: Profile } = {}

local function defaultProfile(): Profile
	return {
		version = PROFILE_VERSION,
		credits = BigNum.serialize(BigNum.ZERO),
		earnedTotal = BigNum.serialize(BigNum.ZERO),
		data = 0,
		ascensions = 0,
		modules = { [Config.SEED_MODULE] = Config.SEED_LEVEL },
		lastSeen = os.time(),
		dailyStreak = 0,
		lastDailyClaim = 0,
		lastCrate = 0,
		quests = false,
		dataUpgrades = {},
		boostUntil = 0,
		boostMult = 1,
		cosmetics = {},
		redeemedCodes = {},
		playtime = 0,
	}
end

-- an old save must never crash the server: every missing field goes back to the default instead of
-- spreading nil into the game
local function reconcile(raw: any): Profile
	local base = defaultProfile()
	if type(raw) ~= "table" then
		return base
	end
	local p: Profile = base
	p.credits = if type(raw.credits) == "table" then raw.credits else base.credits
	p.earnedTotal = if type(raw.earnedTotal) == "table" then raw.earnedTotal else base.earnedTotal
	p.data = if type(raw.data) == "number" then raw.data else 0
	p.ascensions = if type(raw.ascensions) == "number" then raw.ascensions else 0
	p.lastSeen = if type(raw.lastSeen) == "number" then raw.lastSeen else os.time()
	p.dailyStreak = if type(raw.dailyStreak) == "number" then raw.dailyStreak else 0
	p.lastDailyClaim = if type(raw.lastDailyClaim) == "number" then raw.lastDailyClaim else 0
	p.lastCrate = if type(raw.lastCrate) == "number" then raw.lastCrate else 0
	p.quests = if type(raw.quests) == "table" then raw.quests else false

	if type(raw.dataUpgrades) == "table" then
		local ups: { [string]: number } = {}
		for id, lvl in raw.dataUpgrades do
			local def = Sectors.DATA_UPGRADES_BY_ID[id]
			if def and type(lvl) == "number" then
				ups[id] = math.clamp(math.floor(lvl), 0, def.maxLevel)
			end
		end
		p.dataUpgrades = ups
	end
	p.boostUntil = if type(raw.boostUntil) == "number" then raw.boostUntil else 0
	p.boostMult = if type(raw.boostMult) == "number" then raw.boostMult else 1
	p.playtime = if type(raw.playtime) == "number" then raw.playtime else 0

	if type(raw.modules) == "table" then
		local mods: { [string]: number } = {}
		for id, lvl in raw.modules do
			-- drop modules removed by a Config update
			if type(id) == "string" and type(lvl) == "number" and Config.MODULES_BY_ID[id] then
				mods[id] = math.clamp(math.floor(lvl), 0, Config.MAX_MODULE_LEVEL)
			end
		end
		if next(mods) then
			p.modules = mods
		end
	end

	if type(raw.cosmetics) == "table" then
		p.cosmetics = raw.cosmetics
	end
	if type(raw.redeemedCodes) == "table" then
		p.redeemedCodes = raw.redeemedCodes
	end

	p.sessionJobId = raw.sessionJobId
	p.sessionStamp = raw.sessionStamp
	return p
end

local function key(userId: number): string
	return "p_" .. userId
end

local function lockIsFree(p: any): boolean
	if type(p) ~= "table" or not p.sessionJobId then
		return true
	end
	if p.sessionJobId == game.JobId then
		return true
	end
	local stamp = tonumber(p.sessionStamp) or 0
	return os.time() - stamp > LOCK_STALE_SECONDS
end

-- UpdateAsync is the only atomic way to take the lock. GetAsync + SetAsync leaves a window where
-- two servers both think they own it
local function tryAcquire(userId: number): Profile?
	local acquired: Profile? = nil
	local ok, err = pcall(function()
		store:UpdateAsync(key(userId), function(raw)
			if not lockIsFree(raw) then
				return nil -- cancel the write, the lock belongs to someone else
			end
			local p = reconcile(raw)
			p.sessionJobId = game.JobId
			p.sessionStamp = os.time()
			acquired = p
			return p
		end)
	end)
	if not ok then
		warn(string.format("[DataService] UpdateAsync failed for %d: %s", userId, tostring(err)))
		return nil
	end
	return acquired
end

function DataService.load(userId: number): Profile?
	if loaded[userId] then
		return loaded[userId]
	end
	for attempt = 1, LOCK_RETRY_ATTEMPTS do
		local p = tryAcquire(userId)
		if p then
			loaded[userId] = p
			return p
		end
		if attempt < LOCK_RETRY_ATTEMPTS then
			task.wait(LOCK_RETRY_DELAY)
		end
	end
	warn(string.format("[DataService] couldn't get the lock for %d", userId))
	return nil
end

function DataService.get(userId: number): Profile?
	return loaded[userId]
end

function DataService.save(userId: number, release: boolean?): boolean
	local p = loaded[userId] or releasedSnapshot[userId]
	if not p then
		return false
	end
	p.lastSeen = os.time()
	local ok, err = pcall(function()
		store:UpdateAsync(key(userId), function(raw)
			-- if another server stole the lock our state is stale, better to lose this save than overwrite
			-- theirs
			if type(raw) == "table" and raw.sessionJobId and raw.sessionJobId ~= game.JobId then
				local stamp = tonumber(raw.sessionStamp) or 0
				if os.time() - stamp <= LOCK_STALE_SECONDS then
					return nil
				end
			end
			local snapshot = table.clone(p)
			if release then
				snapshot.sessionJobId = nil
				snapshot.sessionStamp = nil
			else
				snapshot.sessionJobId = game.JobId
				snapshot.sessionStamp = os.time()
			end
			return snapshot
		end)
	end)
	if not ok then
		warn(string.format("[DataService] save failed for %d: %s", userId, tostring(err)))
		return false
	end
	return true
end

function DataService.release(userId: number)
	if releasing[userId] then
		return
	end
	releasing[userId] = true
	-- the profile leaves `loaded` right away: save yields, and meanwhile get() would hand out a
	-- profile that's already on its way out
	local p = loaded[userId]
	loaded[userId] = nil
	if p then
		p.lastSeen = os.time()
		releasedSnapshot[userId] = p
		DataService.save(userId, true)
		releasedSnapshot[userId] = nil
	end
	releasing[userId] = nil
end

function DataService.start()
	Players.PlayerRemoving:Connect(function(player)
		DataService.release(player.UserId)
	end)

	-- BindToClose has ~30s of budget. save in parallel, not in sequence, or a full server won't make
	-- it
	game:BindToClose(function()
		if RunService:IsStudio() then
			return
		end
		local pending = 0
		for userId in loaded do
			pending += 1
			task.spawn(function()
				DataService.release(userId)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)

	task.spawn(function()
		while true do
			task.wait(Config.AUTOSAVE_INTERVAL)
			for userId in loaded do
				task.spawn(DataService.save, userId, false)
			end
		end
	end)
end

-- exposed for tests: lock and reconcile logic is where data gets lost, and it has to be checkable
-- without a real DataStore
DataService._reconcile = reconcile
DataService._lockIsFree = lockIsFree
DataService._defaultProfile = defaultProfile
DataService.LOCK_STALE_SECONDS = LOCK_STALE_SECONDS
DataService.PROFILE_VERSION = PROFILE_VERSION

return DataService
