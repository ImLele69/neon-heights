--!strict

-- keeps the base in sync with the profile: lights up bought modules, updates prices on the signs
-- and turns ProximityPrompts into purchases

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)

local BaseBuilder = require(script.Parent.BaseBuilder)
local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)

local PlotService = {}

local LOCKED_TRANSPARENCY = 0.75
local OWNED_TRANSPARENCY = 0.1

local function cores(model: Model): { BasePart }
	local found: { BasePart } = {}
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") and d:GetAttribute("ModuleId") then
			table.insert(found, d)
		end
	end
	return found
end

local function styleCore(
	core: BasePart,
	def: Config.ModuleDef,
	level: number,
	cost: BigNum.BigNum?,
	affordable: boolean
)
	local sector = Config.SECTORS[def.sector]
	local owned = level > 0
	core:SetAttribute("Locked", not owned)
	core.Transparency = if owned then OWNED_TRANSPARENCY else LOCKED_TRANSPARENCY
	core.Color = if owned
		then sector.color
		elseif affordable then sector.color:Lerp(Color3.new(1, 1, 1), 0.35)
		else Color3.fromRGB(70, 74, 92)

	-- higher modules grow, so the base of someone who's ahead shows from far away
	local scale = 4 + math.min(level, Config.MAX_MODULE_LEVEL) * 0.22
	core.Size = Vector3.new(scale, scale, scale)

	local billboard = core:FindFirstChild("Price")
	local label = billboard and billboard:FindFirstChild("Label")
	if label and label:IsA("TextLabel") then
		if level >= Config.MAX_MODULE_LEVEL then
			label.Text = string.format("%s\nMAX", def.name)
			label.TextColor3 = sector.color
		elseif cost then
			label.Text = string.format("%s  Lv %d\n%s", def.name, level, BigNum.format(cost))
			label.TextColor3 = if affordable
				then Color3.fromRGB(255, 255, 255)
				else Color3.fromRGB(150, 155, 175)
		end
	end

	local prompt = core:FindFirstChildOfClass("ProximityPrompt")
	if prompt then
		prompt.Enabled = level < Config.MAX_MODULE_LEVEL
		prompt.ObjectText = def.name
		prompt.ActionText = if level > 0 then "Upgrade" else "Buy"
	end
end

function PlotService.refresh(player: Player)
	local model = BaseBuilder.plotFor(player.UserId)
	local p = DataService.get(player.UserId)
	if not model or not p then
		return
	end
	local credits = Economy.credits(p)

	for _, core in cores(model) do
		local id = core:GetAttribute("ModuleId") :: string
		local def = Config.MODULES_BY_ID[id]
		if not def then
			continue
		end
		local unlocked = Economy.sectorUnlocked(p, def.sector)
		local level = Economy.moduleLevel(p, id)
		local cost = Config.moduleCost(def, level)
		styleCore(core, def, level, cost, unlocked and BigNum.gte(credits, cost))

		local prompt = core:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Enabled = unlocked and level < Config.MAX_MODULE_LEVEL
		end
	end
end

-- purchase effect: without immediate feedback a purchase doesn't "land", and most of the reward
-- feeling is right here
local function purchasePop(core: BasePart)
	local sector = core:GetAttribute("ModuleId")
	if not sector then
		return
	end
	local flash = core.Size
	core.Size = flash * 1.5
	TweenService
		:Create(core, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Size = flash,
		})
		:Play()

	local ring = Instance.new("Part")
	ring.Anchored = true
	ring.CanCollide = false
	ring.Shape = Enum.PartType.Cylinder
	ring.Size = Vector3.new(0.4, 2, 2)
	ring.CFrame = core.CFrame * CFrame.Angles(0, 0, math.rad(90))
	ring.Color = core.Color
	ring.Material = Enum.Material.Neon
	ring.Parent = workspace
	TweenService
		:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), {
			Size = Vector3.new(0.4, 26, 26),
			Transparency = 1,
		})
		:Play()
	task.delay(0.55, function()
		ring:Destroy()
	end)
end

-- confetti on purchase. they're real parts with physics: few and short lived, or on a full server
-- they become the first performance problem
local function confetti(origin: CFrame, color: Color3)
	for _ = 1, 10 do
		local bit = Instance.new("Part")
		bit.Size = Vector3.new(0.6, 0.6, 0.6)
		bit.CFrame = origin * CFrame.new(math.random(-2, 2), math.random(0, 3), math.random(-2, 2))
		bit.Color = if math.random() < 0.5 then color else Color3.fromHSV(math.random(), 0.9, 1)
		bit.Material = Enum.Material.Neon
		bit.CanCollide = false
		bit.Anchored = false
		bit.Parent = workspace
		bit.AssemblyLinearVelocity =
			Vector3.new(math.random(-14, 14), math.random(18, 30), math.random(-14, 14))
		task.delay(1.4, function()
			bit:Destroy()
		end)
	end
end

local function onPrompt(core: BasePart, player: Player)
	local model = BaseBuilder.plotFor(player.UserId)
	if not model or not core:IsDescendantOf(model) then
		-- hands off another player's base
		return
	end
	local id = core:GetAttribute("ModuleId")
	if type(id) ~= "string" then
		return
	end
	-- rate limit, validation and credit spending all live in PlayerService.buyModule, only the visual
	-- effect is left here
	if PlayerService.buyModule(player, id) then
		purchasePop(core)
		confetti(core.CFrame, core.Color)
	end
end

local function bindPrompts(player: Player, model: Model)
	for _, core in cores(model) do
		local prompt = core:FindFirstChildOfClass("ProximityPrompt")
		if prompt then
			prompt.Triggered:Connect(function(triggering: Player)
				if triggering == player then
					onPrompt(core, player)
				end
			end)
		end
	end
end

local function onJoin(player: Player)
	local model = BaseBuilder.build(player)
	bindPrompts(player, model)

	local origin = BaseBuilder.originFor(player.UserId)
	if origin then
		local spawnAt = origin * CFrame.new(0, 6, 44)

		-- WaitForChild yields: if the initial placement ran inline, CharacterAdded would be hooked
		-- afterwards, and a respawn in between would leave the player falling into the void
		local function place(character: Model)
			task.spawn(function()
				local root = character:WaitForChild("HumanoidRootPart", 10)
				if root and root:IsA("BasePart") then
					root.CFrame = spawnAt
				end
			end)
		end

		player.CharacterAdded:Connect(place)
		if player.Character then
			place(player.Character)
		end
	end

	PlotService.refresh(player)
end

-- a core that sits still goes unnoticed. they all spin together from a single loop, a
-- BodyAngularVelocity per module would be 48 physics objects per player
local function animateCores()
	local t = 0
	RunService.Heartbeat:Connect(function(dt: number)
		t += dt
		for _, player in Players:GetPlayers() do
			local model = BaseBuilder.plotFor(player.UserId)
			if not model then
				continue
			end
			for _, core in cores(model) do
				local home = core:GetAttribute("HomeY")
				if type(home) ~= "number" then
					home = core.Position.Y
					core:SetAttribute("HomeY", home)
				end
				local owned = core:GetAttribute("Locked") ~= true
				local speed = if owned then 1.6 else 0.5
				local bob = if owned then math.sin(t * 2 + core.Position.X) * 0.45 else 0
				local pos = Vector3.new(core.Position.X, (home :: number) + bob, core.Position.Z)
				core.CFrame = CFrame.new(pos) * CFrame.Angles(0, t * speed, math.rad(15))
			end
		end
	end)
end

-- auto-collect (gamepass): buys the cheapest module by itself when the player can afford it. it's
-- convenience, not power, the player would have bought it anyway, we just save them the walk
local function autoCollect()
	while true do
		task.wait(2)
		for _, player in Players:GetPlayers() do
			if not PlayerService.hasPass(player.UserId, "autoCollect") then
				continue
			end
			local p = DataService.get(player.UserId)
			if not p then
				continue
			end
			local credits = Economy.credits(p)
			local bestId, bestCost = nil, nil
			for _, def in Config.MODULES do
				if not Economy.sectorUnlocked(p, def.sector) then
					continue
				end
				local level = Economy.moduleLevel(p, def.id)
				if level >= Config.MAX_MODULE_LEVEL then
					continue
				end
				local cost = Config.moduleCost(def, level)
				if BigNum.gte(credits, cost) and (not bestCost or BigNum.lt(cost, bestCost)) then
					bestId, bestCost = def.id, cost
				end
			end
			if bestId then
				PlayerService.buyModule(player, bestId, true)
			end
		end
	end
end

function PlotService.start()
	animateCores()
	task.spawn(autoCollect)

	PlayerService.onPurchase(function(player: Player)
		PlotService.refresh(player)
	end)

	Players.PlayerAdded:Connect(onJoin)
	for _, player in Players:GetPlayers() do
		task.spawn(onJoin, player)
	end

	-- the "you can afford it" color has to follow credits as they go up
	task.spawn(function()
		while true do
			task.wait(1.5)
			for _, player in Players:GetPlayers() do
				PlotService.refresh(player)
			end
		end
	end)
end

return PlotService
