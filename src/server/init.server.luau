--!strict

-- order matters: remotes must exist before a client looks for them, and profiles must load before
-- anything tries to read them

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)

local BaseBuilder = require(script.BaseBuilder)
local DataService = require(script.DataService)
local Leaderboard = require(script.Leaderboard)
local PlayerService = require(script.PlayerService)
local PlotService = require(script.PlotService)
local ShopService = require(script.ShopService)

-- the look is almost all here: dark background, high bloom and pushed saturation are what make Neon
-- pop, and the thumbnail is half the marketing
local function setupLighting()
	Lighting.Ambient = Color3.fromRGB(18, 18, 32)
	Lighting.OutdoorAmbient = Color3.fromRGB(22, 24, 44)
	Lighting.Brightness = 1.4
	Lighting.ClockTime = 0
	Lighting.GeographicLatitude = 0
	Lighting.FogColor = Color3.fromRGB(8, 8, 18)
	Lighting.FogStart = 180
	Lighting.FogEnd = 900
	Lighting.EnvironmentDiffuseScale = 0.2
	Lighting.EnvironmentSpecularScale = 0.4

	local existing = Lighting:FindFirstChildOfClass("BloomEffect")
	if not existing then
		local bloom = Instance.new("BloomEffect")
		bloom.Intensity = 1.1
		bloom.Size = 32
		bloom.Threshold = 0.9
		bloom.Parent = Lighting
	end

	if not Lighting:FindFirstChildOfClass("ColorCorrectionEffect") then
		local cc = Instance.new("ColorCorrectionEffect")
		cc.Saturation = 0.35
		cc.Contrast = 0.16
		cc.TintColor = Color3.fromRGB(235, 240, 255)
		cc.Parent = Lighting
	end

	if not Lighting:FindFirstChildOfClass("SunRaysEffect") then
		local rays = Instance.new("SunRaysEffect")
		rays.Intensity = 0.05
		rays.Spread = 0.4
		rays.Parent = Lighting
	end
end

setupLighting()

-- remotes must exist before a client looks for them, and whoever listens to PlayerAdded has to
-- register before PlayerService: PlayerService processes the players already in the server, and
-- anyone subscribing later misses them
Remotes.init()

DataService.start()
BaseBuilder.start()
PlotService.start()
PlayerService.start()
Leaderboard.start()
ShopService.start()
