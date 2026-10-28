--!strict

-- the mechanics that make one sector different from another. without them the six sectors are the
-- same game repainted, and players figure that out around the third one.
--
-- only the pure economy ones are here, testable without playing: the refiner, data and fusions.
-- energy (sector 3) and low gravity (sector 5) depend on how it feels to move around and need
-- playtesting before they get written

local BigNum = require(script.Parent.BigNum)
local Config = require(script.Parent.Config)

type BigNum = BigNum.BigNum

local Sectors = {}

-- sector 2: the refiner. every level raises the value of what goes down the conveyor. it's a
-- separate multiplier from ascension because you buy it and lose it on reset, and it has to feel
-- different
Sectors.REFINERY_MODULE = "s2_m3"
Sectors.REFINERY_PER_LEVEL = 0.02

function Sectors.refineryBonus(modules: { [string]: number }): number
	local level = modules[Sectors.REFINERY_MODULE] or 0
	return 1 + level * Sectors.REFINERY_PER_LEVEL
end

-- sector 4: data. a secondary currency that accrues with playtime instead of income, so it can't be
-- sped up by buying credits: it's the only progression the player pays for just by being there
Sectors.DATA_SECTOR = 4
Sectors.DATA_PER_MINUTE = 1

-- how much data `playtimeSeconds` of play are worth in total. callers use the DIFFERENCE between
-- two moments: the absolute total would hand everyone who unlocks the sector all the data for the
-- time played before
function Sectors.dataAtPlaytime(playtimeSeconds: number, sectorUnlocked: boolean): number
	if not sectorUnlocked then
		return 0
	end
	return math.floor(math.max(0, playtimeSeconds) / 60 * Sectors.DATA_PER_MINUTE)
end

-- data earned over an interval. this is the one the tick should call
function Sectors.dataGained(playtimeBefore: number, delta: number, sectorUnlocked: boolean): number
	if not sectorUnlocked or delta <= 0 then
		return 0
	end
	return Sectors.dataAtPlaytime(playtimeBefore + delta, true)
		- Sectors.dataAtPlaytime(playtimeBefore, true)
end

export type DataUpgrade = {
	id: string,
	name: string,
	cost: number,
	maxLevel: number,
	describe: (level: number) -> string,
}

-- data upgrades survive ascension: they're the slow progression that makes every reset a bit
-- lighter than the last one
Sectors.DATA_UPGRADES = {
	{
		id = "yield",
		name = "Yield",
		cost = 40,
		maxLevel = 20,
		describe = function(level: number): string
			return string.format("+%d%% credits", level * 2.5)
		end,
	},
	{
		id = "offline",
		name = "Memory",
		cost = 60,
		maxLevel = 8,
		describe = function(level: number): string
			return string.format("+%d h offline", level)
		end,
	},
	{
		id = "crate",
		name = "Frequency",
		cost = 50,
		maxLevel = 10,
		describe = function(level: number): string
			return string.format("-%d%% crate wait", level * 5)
		end,
	},
} :: { DataUpgrade }

Sectors.DATA_UPGRADES_BY_ID = (function()
	local byId: { [string]: DataUpgrade } = {}
	for _, u in Sectors.DATA_UPGRADES do
		byId[u.id] = u
	end
	return byId
end)()

-- cost goes up, or twenty levels would all get bought at once right after unlocking the sector
function Sectors.dataUpgradeCost(def: DataUpgrade, level: number): number
	return math.floor(def.cost * 1.35 ^ level)
end

export type DataBonuses = {
	yieldMult: number,
	offlineBonusHours: number,
	crateSpeedup: number,
}

function Sectors.dataBonuses(upgrades: { [string]: number }?): DataBonuses
	local u = upgrades or {}
	local yield = math.clamp(u.yield or 0, 0, 20)
	local offline = math.clamp(u.offline or 0, 0, 8)
	local crate = math.clamp(u.crate or 0, 0, 10)
	return {
		yieldMult = 1 + yield * 0.025,
		offlineBonusHours = offline,
		crateSpeedup = crate * 0.05,
	}
end

-- sector 6: fusions. eight modules of the same sector all maxed out fuse into a permanent bonus.
-- it's the goal that gives a reason to level the modules you'd otherwise ignore
Sectors.FUSION_BONUS = 0.08

function Sectors.fusedSectors(modules: { [string]: number }): { number }
	local fused: { number } = {}
	for _, sector in Config.SECTORS do
		local complete = true
		for _, def in Config.MODULES do
			if def.sector ~= sector.index then
				continue
			end
			if (modules[def.id] or 0) < Config.MAX_MODULE_LEVEL then
				complete = false
				break
			end
		end
		if complete then
			table.insert(fused, sector.index)
		end
	end
	return fused
end

function Sectors.fusionMultiplier(modules: { [string]: number }): number
	return 1 + #Sectors.fusedSectors(modules) * Sectors.FUSION_BONUS
end

-- every sector bonus in a single multiplier, so Economy has one place to call and nobody can forget
-- one
function Sectors.totalMultiplier(
	modules: { [string]: number },
	dataUpgrades: { [string]: number }?
): number
	return Sectors.refineryBonus(modules)
		* Sectors.fusionMultiplier(modules)
		* Sectors.dataBonuses(dataUpgrades).yieldMult
end

return Sectors
