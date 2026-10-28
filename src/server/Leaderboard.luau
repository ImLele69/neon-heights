--!strict

-- global leaderboards on OrderedDataStore, shown on three physical totems in the lobby. seeing your
-- own name on a board (or someone else's) is one of the few reasons a player comes back after
-- finishing the content

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Economy)
local Juice = require(Shared.Juice)

local BaseBuilder = require(script.Parent.BaseBuilder)
local DataService = require(script.Parent.DataService)

local Leaderboard = {}

local REFRESH_SECONDS = 90
local TOP_N = 10

-- OrderedDataStore only takes 64-bit integers while credits go up to 10^30. we store a scaled
-- logarithm: same ordering and it fits easily, at the cost of precision a leaderboard doesn't need
local LOG_SCALE = 1e6

local function toScore(value: BigNum.BigNum): number
	if BigNum.isZero(value) then
		return 0
	end
	local logValue = value.e + math.log10(math.max(math.abs(value.m), 1e-12))
	return math.floor(math.clamp(logValue, 0, 300) * LOG_SCALE)
end

local function fromScore(score: number): string
	local logValue = score / LOG_SCALE
	local e = math.floor(logValue)
	local m = 10 ^ (logValue - e)
	return BigNum.format({ m = m, e = e })
end

local BOARDS = {
	{
		key = "earned_v1",
		title = "RICHEST",
		color = Juice.PALETTE.cyan,
		value = function(p: any): number
			return toScore(Economy.earnedTotal(p))
		end,
		display = fromScore,
	},
	{
		key = "ascensions_v1",
		title = "MOST ASCENSIONS",
		color = Juice.PALETTE.magenta,
		value = function(p: any): number
			return p.ascensions
		end,
		display = function(v: number): string
			return string.format("%d", v)
		end,
	},
	{
		key = "playtime_v1",
		title = "MOST HOURS",
		color = Juice.PALETTE.lime,
		value = function(p: any): number
			return math.floor(p.playtime)
		end,
		display = function(v: number): string
			return string.format("%.1f h", v / 3600)
		end,
	},
}

local stores: { [string]: OrderedDataStore } = {}
local boards: { [string]: Frame } = {}
local nameCache: { [number]: string } = {}

local function storeFor(key: string): OrderedDataStore
	if not stores[key] then
		stores[key] = DataStoreService:GetOrderedDataStore("NeonLeaderboard_" .. key)
	end
	return stores[key]
end

local function displayName(userId: number): string
	if nameCache[userId] then
		return nameCache[userId]
	end
	local ok, name = pcall(function()
		return Players:GetNameFromUserIdAsync(userId)
	end)
	local resolved = if ok and type(name) == "string" then name else "Player"
	nameCache[userId] = resolved
	return resolved
end

local function buildTotem(index: number, board: any): Frame
	local stand = Instance.new("Part")
	stand.Name = "Totem_" .. board.key
	stand.Anchored = true
	stand.Size = Vector3.new(16, 22, 2)
	-- behind the lobby, not over the plots
	stand.CFrame = CFrame.new(-24 + (index - 1) * 24, 14, BaseBuilder.LOBBY_Z - 60)
	stand.Color = Color3.fromRGB(16, 14, 32)
	stand.Material = Enum.Material.Metal
	stand.Parent = workspace

	local light = Instance.new("PointLight")
	light.Color = board.color
	light.Brightness = 3
	light.Range = 28
	light.Parent = stand

	local surface = Instance.new("SurfaceGui")
	surface.Face = Enum.NormalId.Front
	surface.CanvasSize = Vector2.new(400, 550)
	surface.Parent = stand

	local root = Instance.new("Frame")
	root.Size = UDim2.fromScale(1, 1)
	root.BackgroundColor3 = Color3.fromRGB(12, 10, 26)
	root.BorderSizePixel = 0
	root.Parent = surface

	local title = Instance.new("TextLabel")
	title.Size = UDim2.new(1, 0, 0, 56)
	title.BackgroundTransparency = 1
	title.Font = Juice.FONT_NUM
	title.Text = board.title
	title.TextColor3 = board.color
	title.TextScaled = true
	title.Parent = root

	local list = Instance.new("Frame")
	list.Name = "List"
	list.Size = UDim2.new(1, -16, 1, -66)
	list.Position = UDim2.fromOffset(8, 60)
	list.BackgroundTransparency = 1
	list.Parent = root

	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	return list
end

local function renderRows(list: Frame, board: any, pages: DataStorePages)
	list:ClearAllChildren()
	local layout = Instance.new("UIListLayout")
	layout.Padding = UDim.new(0, 4)
	layout.Parent = list

	local page = pages:GetCurrentPage()
	if #page == 0 then
		local empty = Instance.new("TextLabel")
		empty.Size = UDim2.new(1, 0, 0, 32)
		empty.BackgroundTransparency = 1
		empty.Font = Juice.FONT
		empty.Text = "nobody yet"
		empty.TextColor3 = Juice.PALETTE.dim
		empty.TextScaled = true
		empty.Parent = list
		return
	end

	for rank, entry in page do
		local userId = tonumber(entry.key)
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 40)
		row.BackgroundColor3 = if rank <= 3
			then board.color:Lerp(Color3.fromRGB(0, 0, 0), 0.7)
			else Color3.fromRGB(20, 18, 40)
		row.BorderSizePixel = 0
		row.LayoutOrder = rank
		row.Parent = list

		local c = Instance.new("UICorner")
		c.CornerRadius = UDim.new(0, 8)
		c.Parent = row

		local who = Instance.new("TextLabel")
		who.Size = UDim2.new(0.62, -8, 1, 0)
		who.Position = UDim2.fromOffset(8, 0)
		who.BackgroundTransparency = 1
		who.Font = Juice.FONT
		who.Text = string.format("%d. %s", rank, if userId then displayName(userId) else "?")
		who.TextColor3 = if rank == 1 then Juice.PALETTE.amber else Juice.PALETTE.white
		who.TextXAlignment = Enum.TextXAlignment.Left
		who.TextScaled = true
		who.Parent = row

		local score = Instance.new("TextLabel")
		score.Size = UDim2.new(0.38, -8, 1, 0)
		score.Position = UDim2.fromScale(0.62, 0)
		score.BackgroundTransparency = 1
		score.Font = Juice.FONT_NUM
		score.Text = board.display(entry.value)
		score.TextColor3 = board.color
		score.TextXAlignment = Enum.TextXAlignment.Right
		score.TextScaled = true
		score.Parent = row
	end
end

local function publish()
	for _, board in BOARDS do
		for _, player in Players:GetPlayers() do
			local p = DataService.get(player.UserId)
			if not p then
				continue
			end
			local value = board.value(p)
			if value <= 0 then
				continue
			end
			-- a network error here must not stop the loop for everyone else
			pcall(function()
				storeFor(board.key):SetAsync(tostring(player.UserId), value)
			end)
		end
	end
end

local function refresh()
	for _, board in BOARDS do
		local list = boards[board.key]
		if not list then
			continue
		end
		local ok, pages = pcall(function()
			return storeFor(board.key):GetSortedAsync(false, TOP_N)
		end)
		if ok then
			renderRows(list, board, pages)
		end
	end
end

function Leaderboard.start()
	for i, board in BOARDS do
		boards[board.key] = buildTotem(i, board)
	end

	task.spawn(function()
		while true do
			-- publish before refresh, so whoever joins sees their score right away instead of waiting for
			-- the next round
			pcall(publish)
			pcall(refresh)
			task.wait(REFRESH_SECONDS)
		end
	end)
end

Leaderboard._toScore = toScore
Leaderboard._fromScore = fromScore
Leaderboard.BOARDS = BOARDS

return Leaderboard
