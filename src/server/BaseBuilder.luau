--!strict

-- builds a player's platform out of primitives only. no imported meshes: color, Neon and lights do
-- all the work, so the game doesn't depend on assets that need uploading and moderation

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Config = require(Shared.Config)

local BaseBuilder = {}

-- bases sit on a grid: far enough apart not to feel crammed, close enough to bump into each other
-- (seeing other people's progress is half of the competitive push)
local PLOT_SPACING = 220
local PLOT_SIZE = Vector3.new(120, 4, 120)
local SECTOR_HEIGHT = 34

local plots: { [number]: Model } = {}
local plotIndex: { [number]: number } = {}
local nextIndex = 0

local function part(props: { [string]: any }): BasePart
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	return p
end

local function glow(parent: BasePart, color: Color3, brightness: number, range: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Brightness = brightness
	light.Range = range
	light.Parent = parent
end

local function plotOrigin(index: number): CFrame
	-- square spiral, bases stay compact instead of stretching into a line
	local ring = math.floor((math.sqrt(index) + 1) / 2)
	local side = index - (2 * ring - 1) ^ 2
	local x, z
	if ring == 0 then
		x, z = 0, 0
	else
		local len = 2 * ring
		local leg = math.floor(side / len)
		local pos = side % len
		if leg == 0 then
			x, z = ring, -ring + pos + 1
		elseif leg == 1 then
			x, z = ring - pos - 1, ring
		elseif leg == 2 then
			x, z = -ring, ring - pos - 1
		else
			x, z = -ring + pos + 1, -ring
		end
	end
	return CFrame.new(x * PLOT_SPACING, 0, z * PLOT_SPACING)
end

local function buildFloor(model: Model, origin: CFrame, sector: Config.SectorDef, level: number)
	local y = (level - 1) * SECTOR_HEIGHT

	part({
		Name = string.format("Slab%d", level),
		Size = PLOT_SIZE,
		CFrame = origin * CFrame.new(0, y, 0),
		Color = Color3.fromRGB(18, 20, 30),
		Material = Enum.Material.Metal,
		Parent = model,
	})

	-- the glowing edge is what makes a base readable from far away and recognizable in the thumbnail
	local halfX = PLOT_SIZE.X / 2
	local halfZ = PLOT_SIZE.Z / 2
	local edges = {
		{ Vector3.new(PLOT_SIZE.X, 1.2, 2), Vector3.new(0, 2.6, -halfZ) },
		{ Vector3.new(PLOT_SIZE.X, 1.2, 2), Vector3.new(0, 2.6, halfZ) },
		{ Vector3.new(2, 1.2, PLOT_SIZE.Z), Vector3.new(-halfX, 2.6, 0) },
		{ Vector3.new(2, 1.2, PLOT_SIZE.Z), Vector3.new(halfX, 2.6, 0) },
	}
	for i, e in edges do
		local strip = part({
			Name = string.format("Edge%d_%d", level, i),
			Size = e[1],
			CFrame = origin * CFrame.new(e[2] + Vector3.new(0, y, 0)),
			Color = sector.color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = model,
		})
		if i == 1 then
			glow(strip, sector.color, 2, 40)
		end
	end

	for _, corner in
		{
			Vector3.new(-1, 0, -1),
			Vector3.new(1, 0, -1),
			Vector3.new(-1, 0, 1),
			Vector3.new(1, 0, 1),
		}
	do
		local pillar = part({
			Name = "Pillar",
			Size = Vector3.new(4, SECTOR_HEIGHT, 4),
			CFrame = origin
				* CFrame.new(corner.X * (halfX - 3), y + SECTOR_HEIGHT / 2, corner.Z * (halfZ - 3)),
			Color = sector.accent,
			Material = Enum.Material.Metal,
			Parent = model,
		})
		local cap = part({
			Name = "PillarCap",
			Size = Vector3.new(5, 1.5, 5),
			CFrame = pillar.CFrame * CFrame.new(0, SECTOR_HEIGHT / 2, 0),
			Color = sector.color,
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = model,
		})
		glow(cap, sector.color, 3, 30)
	end

	local sign = Instance.new("Part")
	sign.Name = "SectorSign"
	sign.Anchored = true
	sign.CanCollide = false
	sign.Transparency = 1
	sign.Size = Vector3.new(20, 6, 1)
	sign.CFrame = origin * CFrame.new(0, y + 12, -halfZ + 1)
	sign.Parent = model

	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Back
	gui.CanvasSize = Vector2.new(400, 120)
	gui.AlwaysOnTop = false
	gui.Parent = sign

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.Text = string.upper(sector.name)
	label.TextColor3 = sector.color
	label.TextScaled = true
	label.Parent = gui
end

-- bought modules become physical objects: progress has to show on the base, not just in UI numbers
local function moduleAnchor(model: Model, origin: CFrame, def: Config.ModuleDef, index: number)
	local sector = Config.SECTORS[def.sector]
	local y = (def.sector - 1) * SECTOR_HEIGHT
	local col = (index - 1) % 4
	local row = math.floor((index - 1) / 4)

	local base = part({
		Name = "Module_" .. def.id,
		Size = Vector3.new(10, 3, 10),
		CFrame = origin * CFrame.new(-36 + col * 24, y + 3.5, -30 + row * 24),
		Color = Color3.fromRGB(26, 28, 40),
		Material = Enum.Material.Metal,
		Transparency = 0.35,
		Parent = model,
	})

	local core = part({
		Name = "Core",
		Size = Vector3.new(4, 4, 4),
		CFrame = base.CFrame * CFrame.new(0, 4, 0),
		Color = sector.color,
		Material = Enum.Material.Neon,
		Transparency = 0.55,
		CanCollide = false,
		Parent = model,
	})
	core:SetAttribute("ModuleId", def.id)
	core:SetAttribute("Locked", true)

	local prompt = Instance.new("ProximityPrompt")
	prompt.ActionText = "Buy"
	prompt.ObjectText = def.name
	prompt.HoldDuration = 0
	prompt.MaxActivationDistance = 14
	prompt.RequiresLineOfSight = false
	prompt.Parent = core

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Price"
	billboard.Size = UDim2.fromScale(8, 2)
	billboard.StudsOffset = Vector3.new(0, 4, 0)
	billboard.AlwaysOnTop = true
	billboard.Parent = core

	local text = Instance.new("TextLabel")
	text.Name = "Label"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.fromRGB(255, 255, 255)
	text.TextStrokeTransparency = 0.4
	text.TextScaled = true
	text.Text = def.name
	text.Parent = billboard
end

function BaseBuilder.build(player: Player): Model
	local existing = plots[player.UserId]
	if existing then
		return existing
	end

	local index = nextIndex
	nextIndex += 1
	plotIndex[player.UserId] = index

	local origin = plotOrigin(index)
	local model = Instance.new("Model")
	model.Name = "Plot_" .. player.UserId
	model:SetAttribute("OwnerId", player.UserId)

	for _, sector in Config.SECTORS do
		buildFloor(model, origin, sector, sector.index)
	end

	local perSector: { [number]: number } = {}
	for _, def in Config.MODULES do
		local n = (perSector[def.sector] or 0) + 1
		perSector[def.sector] = n
		moduleAnchor(model, origin, def, n)
	end

	local spawnPad = part({
		Name = "SpawnPad",
		Size = Vector3.new(14, 1, 14),
		CFrame = origin * CFrame.new(0, 3, 44),
		Color = Color3.fromRGB(0, 229, 255),
		Material = Enum.Material.Neon,
		Parent = model,
	})
	glow(spawnPad, Color3.fromRGB(0, 229, 255), 4, 24)

	model.Parent = workspace
	plots[player.UserId] = model
	return model
end

function BaseBuilder.plotFor(userId: number): Model?
	return plots[userId]
end

function BaseBuilder.originFor(userId: number): CFrame?
	local index = plotIndex[userId]
	if not index then
		return nil
	end
	return plotOrigin(index)
end

function BaseBuilder.destroy(userId: number)
	local model = plots[userId]
	if model then
		model:Destroy()
	end
	plots[userId] = nil
	plotIndex[userId] = nil
end

-- without a SpawnLocation Roblox spawns the character at 0,0,0, which is empty here: you fall
-- before the server has even finished building the base. this platform is also the lobby, where the
-- leaderboards are.
--
-- it stays off the plot grid: the first plot is centered on the origin and 120 wide, so a lobby at
-- z=-40 would end up inside it
local LOBBY_Z = -120
local function buildLobby()
	if workspace:FindFirstChild("Lobby") then
		return
	end

	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"

	local floor = part({
		Name = "LobbyFloor",
		Size = Vector3.new(90, 4, 90),
		CFrame = CFrame.new(0, 0, LOBBY_Z),
		Color = Color3.fromRGB(14, 12, 30),
		Material = Enum.Material.Metal,
		Parent = lobby,
	})

	for i, edge in
		{
			{ Vector3.new(90, 1.4, 2.5), Vector3.new(0, 2.7, -45) },
			{ Vector3.new(90, 1.4, 2.5), Vector3.new(0, 2.7, 45) },
			{ Vector3.new(2.5, 1.4, 90), Vector3.new(-45, 2.7, 0) },
			{ Vector3.new(2.5, 1.4, 90), Vector3.new(45, 2.7, 0) },
		}
	do
		local strip = part({
			Name = "LobbyEdge" .. i,
			Size = edge[1],
			CFrame = floor.CFrame * CFrame.new(edge[2]),
			Color = Color3.fromRGB(0, 229, 255),
			Material = Enum.Material.Neon,
			CanCollide = false,
			Parent = lobby,
		})
		if i == 1 then
			glow(strip, Color3.fromRGB(0, 229, 255), 3, 60)
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(16, 1, 16)
	spawn.CFrame = CFrame.new(0, 3, LOBBY_Z)
	spawn.Color = Color3.fromRGB(255, 0, 190)
	spawn.Material = Enum.Material.Neon
	spawn.Duration = 0
	spawn.Parent = lobby
	glow(spawn, Color3.fromRGB(255, 0, 190), 5, 30)

	lobby.Parent = workspace
end

function BaseBuilder.start()
	buildLobby()

	Players.PlayerRemoving:Connect(function(player)
		BaseBuilder.destroy(player.UserId)
	end)
end

BaseBuilder._plotOrigin = plotOrigin
BaseBuilder.PLOT_SPACING = PLOT_SPACING
BaseBuilder.LOBBY_Z = LOBBY_Z
BaseBuilder.SECTOR_HEIGHT = SECTOR_HEIGHT

return BaseBuilder
