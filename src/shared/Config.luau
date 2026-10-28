--!strict

-- every number that drives the balance lives here. tuning happens in this file and against
-- retention data, not scattered around the code

local BigNum = require(script.Parent.BigNum)

type BigNum = BigNum.BigNum

export type ModuleDef = {
	id: string,
	name: string,
	sector: number,
	baseCost: BigNum,
	baseIncome: BigNum, -- credits per drop
	dropInterval: number, -- seconds between drops
}

export type SectorDef = {
	index: number,
	name: string,
	color: Color3,
	accent: Color3,
	unlockTotal: BigNum, -- total credits earned to unlock it
}

local Config = {}

Config.COST_GROWTH = 1.18
Config.MAX_MODULE_LEVEL = 25

-- the first purchases have to stay a few seconds apart: that's the window where the player decides
-- whether to stay. the seed module already starts at SEED_LEVEL so the first upgrade is almost
-- immediate
Config.FIRST_COST = 25
Config.SEED_MODULE = "s1_m1"
Config.SEED_LEVEL = 3

-- the conveyor is the performance bottleneck, every credit is a physical part. past this cap
-- credits pile up abstractly and get dumped into the collector
Config.MAX_CONVEYOR_PARTS = 60
Config.CONVEYOR_SPEED = 14

Config.ASCEND_REQUIREMENT = BigNum.new(1.1, 16)
Config.ASCEND_MULT_PER = 0.25

Config.OFFLINE_CAP_HOURS = 4
Config.OFFLINE_CAP_HOURS_GAMEPASS = 12
Config.OFFLINE_RATE = 0.5 -- offline earns half of online

Config.CRATE_INTERVAL = 15 * 60
Config.AUTOSAVE_INTERVAL = 120

Config.DAILY_REWARDS = {
	{ credits = BigNum.new(5, 3), label = "5K credits" },
	{ credits = BigNum.new(2, 4), label = "20K credits" },
	{ credits = BigNum.new(1, 5), label = "100K credits" },
	{ boostMult = 2, boostSeconds = 900, label = "Boost 2x 15min" },
	{ credits = BigNum.new(1, 6), label = "1M credits" },
	{ credits = BigNum.new(1, 7), label = "10M credits" },
	{ cosmetic = "aura_streak", boostMult = 2, boostSeconds = 3600, label = "Aura + Boost 1h" },
}

Config.SECTORS = {
	{
		index = 1,
		name = "Foundation",
		color = Color3.fromRGB(0, 229, 255),
		accent = Color3.fromRGB(0, 120, 160),
		unlockTotal = BigNum.ZERO,
	},
	{
		index = 2,
		name = "Refinery",
		color = Color3.fromRGB(255, 0, 200),
		accent = Color3.fromRGB(140, 0, 110),
		unlockTotal = BigNum.new(6.9, 5),
	},
	{
		index = 3,
		name = "Reactor",
		color = Color3.fromRGB(170, 255, 0),
		accent = Color3.fromRGB(90, 140, 0),
		unlockTotal = BigNum.new(1.5, 8),
	},
	{
		index = 4,
		name = "Archive",
		color = Color3.fromRGB(255, 176, 0),
		accent = Color3.fromRGB(150, 100, 0),
		unlockTotal = BigNum.new(2.45, 10),
	},
	{
		index = 5,
		name = "Orbit",
		color = Color3.fromRGB(170, 90, 255),
		accent = Color3.fromRGB(90, 40, 150),
		unlockTotal = BigNum.new(1.2, 12),
	},
	{
		index = 6,
		name = "Singularity",
		color = Color3.fromRGB(255, 250, 230),
		accent = Color3.fromRGB(200, 170, 90),
		unlockTotal = BigNum.new(4.2, 13),
	},
} :: { SectorDef }

-- eight modules per sector. cost and income grow at the same pace across sectors so the new sector
-- is always the right purchase as soon as you unlock it
local function buildModules(): { ModuleDef }
	local mods: { ModuleDef } = {}
	local names = {
		"Dropper",
		"Conveyor",
		"Compressor",
		"Amplifier",
		"Synthesizer",
		"Resonator",
		"Converter",
		"Core",
	}
	for s = 1, #Config.SECTORS do
		local sector = Config.SECTORS[s]
		for i, base in names do
			local tier = (s - 1) * #names + (i - 1)
			table.insert(mods, {
				id = string.format("s%d_m%d", s, i),
				name = string.format("%s %s", sector.name, base),
				sector = s,
				baseCost = BigNum.mulScalar(BigNum.new(Config.FIRST_COST, 0), 2.6 ^ tier),
				baseIncome = BigNum.mulScalar(BigNum.ONE, 2.35 ^ tier),
				dropInterval = math.max(0.8, 2 - tier * 0.04),
			})
		end
	end
	return mods
end

Config.MODULES = buildModules()

Config.MODULES_BY_ID = (function()
	local byId: { [string]: ModuleDef } = {}
	for _, m in Config.MODULES do
		byId[m.id] = m
	end
	return byId
end)()

function Config.moduleCost(def: ModuleDef, level: number): BigNum
	return BigNum.mulScalar(def.baseCost, Config.COST_GROWTH ^ level)
end

function Config.moduleIncome(def: ModuleDef, level: number): BigNum
	if level <= 0 then
		return BigNum.ZERO
	end
	return BigNum.mulScalar(def.baseIncome, level)
end

function Config.ascendMultiplier(ascensions: number): number
	return (1 + Config.ASCEND_MULT_PER) ^ ascensions
end

Config.GAMEPASSES = {
	doubleCredits = { id = 0, mult = 2 },
	autoCollect = { id = 0 },
	offlineExtended = { id = 0 },
	extraDroppers = { id = 0, slots = 2 },
	vipAura = { id = 0 },
	sectorTeleport = { id = 0 },
}

Config.PRODUCTS = {
	boost15 = { id = 0, mult = 2, seconds = 900 },
	creditsS = { id = 0, scaleSeconds = 600 },
	creditsM = { id = 0, scaleSeconds = 3600 },
	creditsL = { id = 0, scaleSeconds = 14400 },
	instantAscend = { id = 0 },
	fillCrate = { id = 0 },
}

return Config
