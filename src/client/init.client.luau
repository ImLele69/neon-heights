--!strict

-- HUD. everything is big, saturated and moving: on this platform the first minute decides whether
-- the player stays, and a sober interface won't hold them. numbers still have to be readable
-- though, the player must always know what they have and what they're missing

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local BigNum = require(Shared.BigNum)
local Economy = require(Shared.Economy)
local Juice = require(Shared.Juice)
local Remotes = require(Shared.Remotes)
local Sectors = require(Shared.Sectors)

local P = Juice.PALETTE
local player = Players.LocalPlayer

local gui = Instance.new("ScreenGui")
gui.Name = "NeonHUD"
gui.ResetOnSpawn = false
gui.IgnoreGuiInset = true
gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
gui.Parent = player:WaitForChild("PlayerGui")

local mobile = UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled

local function panel(name: string, size: UDim2, pos: UDim2, anchor: Vector2): Frame
	local f = Instance.new("Frame")
	f.Name = name
	f.Size = size
	f.Position = pos
	f.AnchorPoint = anchor
	f.BackgroundColor3 = P.panel
	f.BorderSizePixel = 0
	f.Parent = gui
	Juice.corner(f, 18)
	Juice.gradient(f, P.panel, P.ink, 90)
	Juice.stroke(f, P.cyan, 3)
	return f
end

local function label(
	parent: Instance,
	name: string,
	size: UDim2,
	pos: UDim2,
	font: Enum.Font?
): TextLabel
	local l = Instance.new("TextLabel")
	l.Name = name
	l.Size = size
	l.Position = pos
	l.BackgroundTransparency = 1
	l.Font = font or Juice.FONT
	l.TextColor3 = P.white
	l.TextStrokeTransparency = 0
	l.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	l.TextScaled = true
	l.Text = ""
	l.Parent = parent
	return l
end

local function bigButton(
	name: string,
	txt: string,
	color: Color3,
	size: UDim2,
	pos: UDim2
): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = size
	b.Position = pos
	b.AnchorPoint = Vector2.new(1, 0.5)
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Juice.FONT
	b.Text = txt
	b.TextColor3 = P.white
	b.TextStrokeTransparency = 0
	b.TextStrokeColor3 = Color3.fromRGB(0, 0, 0)
	b.TextScaled = true
	b.AutoButtonColor = false
	b.Parent = gui
	Juice.corner(b, 16)
	Juice.gradient(b, color, color:Lerp(Color3.new(0, 0, 0), 0.45), 90)
	Juice.stroke(b, P.white, 3)

	b.MouseEnter:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), {
			BackgroundColor3 = color:Lerp(P.white, 0.25),
		}):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(b, TweenInfo.new(0.12), { BackgroundColor3 = color }):Play()
	end)
	b.MouseButton1Down:Connect(function()
		Juice.pop(b, 0.94, 0.1)
	end)
	return b
end

local wallet = panel("Wallet", UDim2.fromOffset(340, 108), UDim2.fromOffset(16, 16), Vector2.zero)
Juice.hardShadow(wallet, 6)
local creditsLabel =
	label(wallet, "Credits", UDim2.new(1, -24, 0, 52), UDim2.fromOffset(14, 6), Juice.FONT_NUM)
creditsLabel.TextColor3 = P.cyan
creditsLabel.TextXAlignment = Enum.TextXAlignment.Left
local rateLabel = label(wallet, "Rate", UDim2.new(1, -24, 0, 26), UDim2.fromOffset(14, 58))
rateLabel.TextColor3 = P.lime
rateLabel.TextXAlignment = Enum.TextXAlignment.Left
local multLabel = label(wallet, "Mult", UDim2.new(1, -24, 0, 24), UDim2.fromOffset(14, 82))
multLabel.TextColor3 = P.magenta
multLabel.TextXAlignment = Enum.TextXAlignment.Left

local goalWidth = if mobile then 300 else 400
local goal =
	panel("Goal", UDim2.fromOffset(goalWidth, 78), UDim2.new(0.5, 0, 1, -18), Vector2.new(0.5, 1))
Juice.hardShadow(goal, 6)
local goalLabel = label(goal, "Label", UDim2.new(1, -110, 0, 26), UDim2.fromOffset(14, 8))
goalLabel.TextXAlignment = Enum.TextXAlignment.Left
local goalPct =
	label(goal, "Pct", UDim2.fromOffset(90, 26), UDim2.new(1, -100, 0, 8), Juice.FONT_NUM)
goalPct.TextXAlignment = Enum.TextXAlignment.Right
goalPct.TextColor3 = P.amber

local barBg = Instance.new("Frame")
barBg.Size = UDim2.new(1, -28, 0, 26)
barBg.Position = UDim2.fromOffset(14, 40)
barBg.BackgroundColor3 = Color3.fromRGB(14, 12, 30)
barBg.BorderSizePixel = 0
barBg.Parent = goal
Juice.corner(barBg, 13)
Juice.stroke(barBg, Color3.fromRGB(60, 55, 110), 2)

local barFill = Instance.new("Frame")
barFill.Size = UDim2.fromScale(0, 1)
barFill.BackgroundColor3 = P.cyan
barFill.BorderSizePixel = 0
barFill.Parent = barBg
Juice.corner(barFill, 13)
local barGradient = Juice.gradient(barFill, P.cyan, P.magenta, 0)

local barText = label(barBg, "Inner", UDim2.fromScale(1, 1), UDim2.fromScale(0, 0))
barText.TextSize = 16
barText.TextScaled = false
barText.ZIndex = 3

-- buttons sit in a column on the right where the thumb reaches them on mobile, and on this platform
-- mobile is most of the players.
-- the column is centered on its real middle: anchoring it to the second button pushed it down, and
-- on short screens the last ones ended up below the edge
local BTN_W, BTN_H, GAP = 132, 54, 8
local BTN_COUNT = 7
local STACK_HEIGHT = BTN_COUNT * BTN_H + (BTN_COUNT - 1) * GAP

local function stackPos(i: number): UDim2
	local offset = -STACK_HEIGHT / 2 + (i - 0.5) * BTN_H + (i - 1) * GAP
	return UDim2.new(1, -16, 0.5, offset)
end

local btnSize = UDim2.fromOffset(BTN_W, BTN_H)
local dailyBtn = bigButton("Daily", "GIFT", P.magenta, btnSize, stackPos(1))
local crateBtn = bigButton("Crate", "CRATE", P.amber, btnSize, stackPos(2))
local codeBtn = bigButton("Codes", "CODES", P.violet, btnSize, stackPos(3))
local questBtn = bigButton("Quests", "QUESTS", P.cyan, btnSize, stackPos(4))
local shopBtn = bigButton("Shop", "SHOP", P.lime, btnSize, stackPos(5))
local dataBtn = bigButton("Data", "ARCHIVE", P.amber, btnSize, stackPos(6))
dataBtn.Visible = false
local ascendBtn = bigButton("Ascend", "ASCEND", P.hot, btnSize, stackPos(7))
ascendBtn.Visible = false

local toast =
	panel("Toast", UDim2.fromOffset(420, 110), UDim2.new(0.5, 0, 0, -140), Vector2.new(0.5, 0))
toast.Visible = false
local toastTitle =
	label(toast, "Title", UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 10), Juice.FONT_NUM)
toastTitle.TextColor3 = P.amber
local toastBody = label(toast, "Body", UDim2.new(1, -28, 0, 54), UDim2.fromOffset(14, 46))
toastBody.TextScaled = false
toastBody.TextSize = 17
toastBody.TextWrapped = true
toastBody.TextYAlignment = Enum.TextYAlignment.Top

local toastToken = 0
local function showToast(title: string, body: string, color: Color3?)
	toastToken += 1
	local mine = toastToken
	toastTitle.Text = title
	toastTitle.TextColor3 = color or P.amber
	toastBody.Text = body
	toast.Visible = true
	toast.Position = UDim2.new(0.5, 0, 0, -140)
	TweenService
		:Create(toast, TweenInfo.new(0.45, Enum.EasingStyle.Back, Enum.EasingDirection.Out), {
			Position = UDim2.new(0.5, 0, 0, 20),
		})
		:Play()
	task.delay(5, function()
		if toastToken ~= mine then
			return
		end
		local out = TweenService:Create(toast, TweenInfo.new(0.35), {
			Position = UDim2.new(0.5, 0, 0, -140),
		})
		out.Completed:Connect(function()
			if toastToken == mine then
				toast.Visible = false
			end
		end)
		out:Play()
	end)
end

local codePanel =
	panel("CodePanel", UDim2.fromOffset(360, 168), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
codePanel.Visible = false
codePanel.ZIndex = 20
local codeTitle =
	label(codePanel, "Title", UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 12), Juice.FONT_NUM)
codeTitle.Text = "CODES"
codeTitle.TextColor3 = P.violet
codeTitle.ZIndex = 21

local codeBox = Instance.new("TextBox")
codeBox.Size = UDim2.new(1, -28, 0, 46)
codeBox.Position = UDim2.fromOffset(14, 56)
codeBox.BackgroundColor3 = Color3.fromRGB(14, 12, 30)
codeBox.BorderSizePixel = 0
codeBox.Font = Juice.FONT
codeBox.PlaceholderText = "type a code"
codeBox.Text = ""
codeBox.TextColor3 = P.white
codeBox.TextScaled = true
codeBox.ClearTextOnFocus = false
codeBox.ZIndex = 21
codeBox.Parent = codePanel
Juice.corner(codeBox, 12)
Juice.stroke(codeBox, P.violet, 2)

local function smallButton(
	name: string,
	txt: string,
	color: Color3,
	textColor: Color3,
	pos: UDim2
): TextButton
	local b = Instance.new("TextButton")
	b.Name = name
	b.Size = UDim2.new(0.5, -18, 0, 42)
	b.Position = pos
	b.BackgroundColor3 = color
	b.BorderSizePixel = 0
	b.Font = Juice.FONT
	b.Text = txt
	b.TextColor3 = textColor
	b.TextScaled = true
	b.ZIndex = 21
	b.Parent = codePanel
	Juice.corner(b, 12)
	return b
end

local codeSend = smallButton("Send", "SEND", P.lime, P.ink, UDim2.fromOffset(14, 114))
local codeClose =
	smallButton("Close", "CLOSE", Color3.fromRGB(70, 66, 110), P.white, UDim2.new(0.5, 4, 0, 114))

-- quests panel: three rows with a progress bar and a claim button. rows get rebuilt on every open,
-- there are only three
local questPanel = panel(
	"QuestPanel",
	UDim2.fromOffset(380, 280),
	UDim2.fromScale(0.5, 0.5),
	Vector2.new(0.5, 0.5)
)
questPanel.Visible = false
questPanel.ZIndex = 20
local questTitle =
	label(questPanel, "Title", UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 12), Juice.FONT_NUM)
questTitle.Text = "TODAY'S QUESTS"
questTitle.TextColor3 = P.cyan
questTitle.ZIndex = 21

local questList = Instance.new("Frame")
questList.Size = UDim2.new(1, -28, 1, -104)
questList.Position = UDim2.fromOffset(14, 54)
questList.BackgroundTransparency = 1
questList.ZIndex = 21
questList.Parent = questPanel

local questLayout = Instance.new("UIListLayout")
questLayout.Padding = UDim.new(0, 8)
questLayout.Parent = questList

local questClose = Instance.new("TextButton")
questClose.Size = UDim2.new(1, -28, 0, 40)
questClose.Position = UDim2.new(0, 14, 1, -50)
questClose.BackgroundColor3 = Color3.fromRGB(70, 66, 110)
questClose.BorderSizePixel = 0
questClose.Font = Juice.FONT
questClose.Text = "CLOSE"
questClose.TextColor3 = P.white
questClose.TextScaled = true
questClose.ZIndex = 21
questClose.Parent = questPanel
Juice.corner(questClose, 12)

local function renderQuests(quests: { any }?)
	for _, child in questList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end
	if not quests then
		return
	end

	for i, q in quests do
		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 54)
		row.BackgroundColor3 = Color3.fromRGB(16, 14, 34)
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.ZIndex = 21
		row.Parent = questList
		Juice.corner(row, 10)

		local txt = Instance.new("TextLabel")
		txt.Size = UDim2.new(1, -96, 0, 24)
		txt.Position = UDim2.fromOffset(10, 4)
		txt.BackgroundTransparency = 1
		txt.Font = Juice.FONT
		txt.Text = q.label
		txt.TextColor3 = if q.claimed then P.dim else P.white
		txt.TextXAlignment = Enum.TextXAlignment.Left
		txt.TextScaled = true
		txt.ZIndex = 22
		txt.Parent = row

		local track = Instance.new("Frame")
		track.Size = UDim2.new(1, -96, 0, 14)
		track.Position = UDim2.fromOffset(10, 32)
		track.BackgroundColor3 = Color3.fromRGB(10, 9, 22)
		track.BorderSizePixel = 0
		track.ZIndex = 22
		track.Parent = row
		Juice.corner(track, 7)

		-- earn quests have a BigNum target, the others a plain counter
		local ratio: number
		if q.targetBig then
			local target = BigNum.deserialize(q.targetBig)
			local done = BigNum.deserialize(q.progressBig)
			ratio = if BigNum.isZero(target) then 0 else BigNum.toNumber(BigNum.div(done, target))
		else
			ratio = if q.target > 0 then q.progress / q.target else 0
		end
		ratio = math.clamp(ratio, 0, 1)

		local fill = Instance.new("Frame")
		fill.Size = UDim2.fromScale(ratio, 1)
		fill.BackgroundColor3 = if q.complete then P.lime else P.cyan
		fill.BorderSizePixel = 0
		fill.ZIndex = 23
		fill.Parent = track
		Juice.corner(fill, 7)

		local action = Instance.new("TextButton")
		action.Size = UDim2.fromOffset(78, 42)
		action.Position = UDim2.new(1, -86, 0, 6)
		action.BorderSizePixel = 0
		action.Font = Juice.FONT
		action.TextScaled = true
		action.ZIndex = 22
		action.Parent = row
		Juice.corner(action, 10)

		if q.claimed then
			action.Text = "DONE"
			action.BackgroundColor3 = Color3.fromRGB(46, 44, 74)
			action.TextColor3 = P.dim
		elseif q.complete then
			action.Text = "CLAIM"
			action.BackgroundColor3 = P.lime
			action.TextColor3 = P.ink
			action.MouseButton1Click:Connect(function()
				Remotes.event("ClaimQuest"):FireServer(q.id)
			end)
		else
			action.Text = string.format("%d%%", math.floor(ratio * 100))
			action.BackgroundColor3 = Color3.fromRGB(40, 38, 68)
			action.TextColor3 = P.dim
		end
	end
end

-- shop. Robux prices are the ones from the design doc: until the products exist on the site the
-- server answers "not available" and nothing happens
local SHOP_ITEMS = {
	{ kind = "pass", id = "doubleCredits", name = "CREDITS x2", price = 199, color = P.cyan },
	{ kind = "pass", id = "autoCollect", name = "AUTO-COLLECT", price = 249, color = P.magenta },
	{ kind = "pass", id = "offlineExtended", name = "OFFLINE 12H", price = 199, color = P.violet },
	{ kind = "pass", id = "vipAura", name = "AURA VIP", price = 149, color = P.amber },
	{ kind = "product", id = "boost15", name = "BOOST x2 15MIN", price = 49, color = P.lime },
	{ kind = "product", id = "creditsM", name = "CREDIT PACK", price = 249, color = P.hot },
}

local shopPanel =
	panel("ShopPanel", UDim2.fromOffset(400, 340), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
shopPanel.Visible = false
shopPanel.ZIndex = 20
local shopTitle =
	label(shopPanel, "Title", UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 12), Juice.FONT_NUM)
shopTitle.Text = "SHOP"
shopTitle.TextColor3 = P.lime
shopTitle.ZIndex = 21

local shopList = Instance.new("Frame")
shopList.Size = UDim2.new(1, -28, 1, -104)
shopList.Position = UDim2.fromOffset(14, 54)
shopList.BackgroundTransparency = 1
shopList.ZIndex = 21
shopList.Parent = shopPanel

local shopLayout = Instance.new("UIListLayout")
shopLayout.Padding = UDim.new(0, 6)
shopLayout.Parent = shopList

for i, item in SHOP_ITEMS do
	local row = Instance.new("TextButton")
	row.Size = UDim2.new(1, 0, 0, 42)
	row.BackgroundColor3 = Color3.fromRGB(16, 14, 34)
	row.BorderSizePixel = 0
	row.Font = Juice.FONT
	row.Text = ""
	row.AutoButtonColor = false
	row.LayoutOrder = i
	row.ZIndex = 21
	row.Parent = shopList
	Juice.corner(row, 10)
	Juice.stroke(row, item.color, 2)

	local nameLabel = Instance.new("TextLabel")
	nameLabel.Size = UDim2.new(1, -96, 1, 0)
	nameLabel.Position = UDim2.fromOffset(10, 0)
	nameLabel.BackgroundTransparency = 1
	nameLabel.Font = Juice.FONT
	nameLabel.Text = item.name
	nameLabel.TextColor3 = P.white
	nameLabel.TextXAlignment = Enum.TextXAlignment.Left
	nameLabel.TextScaled = true
	nameLabel.ZIndex = 22
	nameLabel.Parent = row

	local priceLabel = Instance.new("TextLabel")
	priceLabel.Size = UDim2.fromOffset(84, 30)
	priceLabel.Position = UDim2.new(1, -92, 0, 6)
	priceLabel.BackgroundColor3 = item.color
	priceLabel.BorderSizePixel = 0
	priceLabel.Font = Juice.FONT_NUM
	priceLabel.Text = tostring(item.price)
	priceLabel.TextColor3 = P.ink
	priceLabel.TextScaled = true
	priceLabel.ZIndex = 22
	priceLabel.Parent = row
	Juice.corner(priceLabel, 8)

	row.MouseButton1Click:Connect(function()
		Juice.pop(row, 1.05, 0.15)
		Remotes.event("OpenShop"):FireServer(item.kind, item.id)
	end)
end

local shopClose = Instance.new("TextButton")
shopClose.Size = UDim2.new(1, -28, 0, 40)
shopClose.Position = UDim2.new(0, 14, 1, -50)
shopClose.BackgroundColor3 = Color3.fromRGB(70, 66, 110)
shopClose.BorderSizePixel = 0
shopClose.Font = Juice.FONT
shopClose.Text = "CLOSE"
shopClose.TextColor3 = P.white
shopClose.TextScaled = true
shopClose.ZIndex = 21
shopClose.Parent = shopPanel
Juice.corner(shopClose, 12)

shopBtn.MouseButton1Click:Connect(function()
	shopPanel.Visible = not shopPanel.Visible
	if shopPanel.Visible then
		Juice.pop(shopPanel, 1.08)
	end
end)
shopClose.MouseButton1Click:Connect(function()
	shopPanel.Visible = false
end)

-- archive: data is spent on upgrades that survive ascension. only shows up once sector 4 is
-- unlocked
local dataPanel =
	panel("DataPanel", UDim2.fromOffset(380, 290), UDim2.fromScale(0.5, 0.5), Vector2.new(0.5, 0.5))
dataPanel.Visible = false
dataPanel.ZIndex = 20
local dataTitle =
	label(dataPanel, "Title", UDim2.new(1, -28, 0, 34), UDim2.fromOffset(14, 12), Juice.FONT_NUM)
dataTitle.TextColor3 = P.amber
dataTitle.ZIndex = 21

local dataList = Instance.new("Frame")
dataList.Size = UDim2.new(1, -28, 1, -104)
dataList.Position = UDim2.fromOffset(14, 54)
dataList.BackgroundTransparency = 1
dataList.ZIndex = 21
dataList.Parent = dataPanel

local dataLayout = Instance.new("UIListLayout")
dataLayout.Padding = UDim.new(0, 8)
dataLayout.Parent = dataList

local dataClose = Instance.new("TextButton")
dataClose.Size = UDim2.new(1, -28, 0, 40)
dataClose.Position = UDim2.new(0, 14, 1, -50)
dataClose.BackgroundColor3 = Color3.fromRGB(70, 66, 110)
dataClose.BorderSizePixel = 0
dataClose.Font = Juice.FONT
dataClose.Text = "CLOSE"
dataClose.TextColor3 = P.white
dataClose.TextScaled = true
dataClose.ZIndex = 21
dataClose.Parent = dataPanel
Juice.corner(dataClose, 12)

local function renderData(dataAmount: number, upgrades: { [string]: number }?)
	dataTitle.Text = string.format("ARCHIVE · %d DATA", dataAmount)
	for _, child in dataList:GetChildren() do
		if child:IsA("Frame") then
			child:Destroy()
		end
	end

	local owned = upgrades or {}
	for i, def in Sectors.DATA_UPGRADES do
		local level = owned[def.id] or 0
		local maxed = level >= def.maxLevel
		local cost = Sectors.dataUpgradeCost(def, level)

		local row = Instance.new("Frame")
		row.Size = UDim2.new(1, 0, 0, 58)
		row.BackgroundColor3 = Color3.fromRGB(16, 14, 34)
		row.BorderSizePixel = 0
		row.LayoutOrder = i
		row.ZIndex = 21
		row.Parent = dataList
		Juice.corner(row, 10)

		local nameLabel = Instance.new("TextLabel")
		nameLabel.Size = UDim2.new(1, -110, 0, 26)
		nameLabel.Position = UDim2.fromOffset(10, 5)
		nameLabel.BackgroundTransparency = 1
		nameLabel.Font = Juice.FONT
		nameLabel.Text = string.format("%s  Lv %d", def.name, level)
		nameLabel.TextColor3 = P.white
		nameLabel.TextXAlignment = Enum.TextXAlignment.Left
		nameLabel.TextScaled = true
		nameLabel.ZIndex = 22
		nameLabel.Parent = row

		local effect = Instance.new("TextLabel")
		effect.Size = UDim2.new(1, -110, 0, 22)
		effect.Position = UDim2.fromOffset(10, 31)
		effect.BackgroundTransparency = 1
		effect.Font = Juice.FONT
		effect.Text = def.describe(level)
		effect.TextColor3 = P.dim
		effect.TextXAlignment = Enum.TextXAlignment.Left
		effect.TextScaled = true
		effect.ZIndex = 22
		effect.Parent = row

		local buy = Instance.new("TextButton")
		buy.Size = UDim2.fromOffset(92, 44)
		buy.Position = UDim2.new(1, -100, 0, 7)
		buy.BorderSizePixel = 0
		buy.Font = Juice.FONT
		buy.TextScaled = true
		buy.ZIndex = 22
		buy.Parent = row
		Juice.corner(buy, 10)

		if maxed then
			buy.Text = "MAX"
			buy.BackgroundColor3 = Color3.fromRGB(46, 44, 74)
			buy.TextColor3 = P.dim
		else
			buy.Text = tostring(cost)
			local affordable = dataAmount >= cost
			buy.BackgroundColor3 = if affordable then P.amber else Color3.fromRGB(40, 38, 68)
			buy.TextColor3 = if affordable then P.ink else P.dim
			buy.MouseButton1Click:Connect(function()
				Remotes.event("BuyDataUpgrade"):FireServer(def.id)
			end)
		end
	end
end

dataClose.MouseButton1Click:Connect(function()
	dataPanel.Visible = false
end)

local state: any = nil
local localCredits = BigNum.ZERO
local localRate = BigNum.ZERO

local function applyState(new: any)
	state = new
	localCredits = BigNum.deserialize(new.credits)
	localRate = BigNum.deserialize(new.incomePerSecond)
	if questPanel.Visible then
		renderQuests(new.quests)
	end
	dataBtn.Visible = new.dataUnlocked == true
	if dataPanel.Visible then
		renderData(new.data or 0, new.dataUpgrades)
	end
end

local function formatDuration(seconds: number): string
	local s = math.max(0, math.floor(seconds))
	local h = math.floor(s / 3600)
	local m = math.floor((s % 3600) / 60)
	if h > 0 then
		return string.format("%dh %02dm", h, m)
	end
	if m > 0 then
		return string.format("%dm %02ds", m, s % 60)
	end
	return string.format("%ds", s)
end

Remotes.event("StateSync").OnClientEvent:Connect(applyState)

Remotes.event("Notify").OnClientEvent:Connect(function(kind: string, payload: any)
	if kind == "offline" then
		local amount = BigNum.format(BigNum.deserialize(payload.credits))
		local body = string.format(
			"You earned %s in %s while you were away.",
			amount,
			formatDuration(payload.seconds)
		)
		if payload.hitCap then
			body ..= " You hit the cap, extend it to keep earning for longer."
		end
		showToast("WELCOME BACK", body, P.cyan)
	elseif kind == "daily" then
		showToast(
			string.format("DAY %d", payload.streak),
			payload.label .. "  ·  come back tomorrow to keep your streak!",
			P.magenta
		)
		Juice.pop(dailyBtn, 1.3)
	elseif kind == "crate" then
		local amount = if payload.credits
			then BigNum.format(BigNum.deserialize(payload.credits))
			else "?"
		showToast("CRATE OPENED", string.format("+%s credits", amount), P.amber)
		Juice.pop(crateBtn, 1.3)
	elseif kind == "code" then
		showToast("CODE OK", payload.label .. " redeemed!", P.lime)
	elseif kind == "purchase" then
		showToast("THANKS!", "Purchase applied.", P.lime)
		Juice.shake(wallet, 6, 0.4)
	elseif kind == "pass" then
		showToast("UNLOCKED", "The perk is active right away.", P.amber)
	elseif kind == "dataUpgrade" then
		showToast(
			"ARCHIVE",
			string.format("%s is now level %d.", payload.name, payload.level),
			P.amber
		)
	elseif kind == "quest" then
		local amount = if payload.credits
			then BigNum.format(BigNum.deserialize(payload.credits))
			else "?"
		showToast("QUEST DONE", string.format("%s  +%s", payload.label, amount), P.cyan)
		Juice.pop(questBtn, 1.3)
	elseif kind == "ascended" then
		showToast(
			"ASCENSION",
			string.format("Permanent multiplier x%.2f!", payload.multiplier),
			P.hot
		)
		Juice.shake(wallet, 8, 0.6)
	elseif kind == "bought" then
		Juice.pop(creditsLabel, 1.15, 0.25)
	elseif kind == "denied" and payload and payload.reason then
		showToast("NOT YET", tostring(payload.reason), P.dim)
	end
end)

dailyBtn.MouseButton1Click:Connect(function()
	Remotes.event("ClaimDaily"):FireServer()
end)
crateBtn.MouseButton1Click:Connect(function()
	Remotes.event("ClaimCrate"):FireServer()
end)
ascendBtn.MouseButton1Click:Connect(function()
	Remotes.event("Ascend"):FireServer()
end)
dataBtn.MouseButton1Click:Connect(function()
	dataPanel.Visible = not dataPanel.Visible
	if dataPanel.Visible then
		-- draw right away instead of waiting for the next StateSync, which can show up three seconds
		-- later
		renderData(if state then state.data or 0 else 0, if state then state.dataUpgrades else nil)
		Juice.pop(dataPanel, 1.08)
	end
end)
questBtn.MouseButton1Click:Connect(function()
	questPanel.Visible = not questPanel.Visible
	if questPanel.Visible then
		renderQuests(if state then state.quests else nil)
		Juice.pop(questPanel, 1.08)
	end
end)
questClose.MouseButton1Click:Connect(function()
	questPanel.Visible = false
end)
codeBtn.MouseButton1Click:Connect(function()
	codePanel.Visible = not codePanel.Visible
	if codePanel.Visible then
		Juice.pop(codePanel, 1.1)
	end
end)
codeClose.MouseButton1Click:Connect(function()
	codePanel.Visible = false
end)

local function sendCode()
	local txt = codeBox.Text
	if #txt > 0 then
		Remotes.event("RedeemCode"):FireServer(txt)
		codeBox.Text = ""
	end
end

codeSend.MouseButton1Click:Connect(sendCode)
codeBox.FocusLost:Connect(function(enter: boolean)
	if enter then
		sendCode()
	end
end)

task.spawn(function()
	local initial = Remotes.fn("GetState"):InvokeServer()
	if initial and not state then
		applyState(initial)
	end
end)

-- an available button has to jump out, one that's waiting has to show how long is left, or the
-- player can't tell if it's worth waiting
local function styleReady(btn: TextButton, ready: boolean, baseText: string, waiting: string)
	if ready then
		btn.Text = baseText
		btn.BackgroundTransparency = 0
		btn.TextTransparency = 0
	else
		btn.Text = waiting
		btn.BackgroundTransparency = 0.45
		btn.TextTransparency = 0.25
	end
end

-- red dot on the button: without it players never open the panel and the quests might as well not
-- exist
local questBadge = Instance.new("TextLabel")
questBadge.Size = UDim2.fromOffset(28, 28)
questBadge.Position = UDim2.fromOffset(-8, -8)
questBadge.BackgroundColor3 = P.hot
questBadge.BorderSizePixel = 0
questBadge.Font = Juice.FONT_NUM
questBadge.Text = "!"
questBadge.TextColor3 = P.white
questBadge.TextScaled = true
questBadge.Visible = false
questBadge.ZIndex = 5
questBadge.Parent = questBtn
Juice.corner(questBadge, 14)
Juice.stroke(questBadge, P.white, 2)

local pulse = 0
local lastGoalKind = ""
local dailyBreathStop: (() -> ())? = nil
local crateBreathStop: (() -> ())? = nil

RunService.RenderStepped:Connect(function(dt: number)
	if not state then
		return
	end
	pulse += dt

	localCredits = BigNum.add(localCredits, BigNum.mulScalar(localRate, dt))
	creditsLabel.Text = BigNum.format(localCredits)
	rateLabel.Text = BigNum.format(localRate) .. " /sec"

	local mult = state.multiplier or 1
	if mult > 1.001 then
		multLabel.Text = string.format("x%.2f MULTIPLIER", mult)
		multLabel.TextColor3 = Color3.fromHSV((pulse * 0.25) % 1, 0.7, 1)
	else
		multLabel.Text = ""
	end

	local goalInfo = Economy.nextGoal({
		credits = BigNum.serialize(localCredits),
		earnedTotal = state.earnedTotal,
		modules = state.modules,
		ascensions = state.ascensions,
		boostUntil = state.boostUntil,
		boostMult = state.boostMult,
		data = state.data,
	})

	if goalInfo.kind ~= lastGoalKind then
		lastGoalKind = goalInfo.kind
		Juice.pop(goal, 1.06, 0.3)
	end

	goalLabel.Text = if goalInfo.kind == "sector"
		then "UNLOCK " .. string.upper(goalInfo.label)
		elseif goalInfo.kind == "ascend" then "READY TO ASCEND"
		else "NEXT: " .. string.upper(goalInfo.label)
	goalPct.Text = string.format("%d%%", math.floor(goalInfo.progress * 100))
	barText.Text = if goalInfo.cost then BigNum.format(goalInfo.cost) else ""

	barFill.Size = barFill.Size:Lerp(UDim2.fromScale(math.max(goalInfo.progress, 0.02), 1), 0.18)
	barGradient.Offset = Vector2.new((pulse * 0.35) % 1, 0)

	if goalInfo.progress >= 1 then
		local k = (math.sin(pulse * 7) + 1) / 2
		barFill.BackgroundColor3 = P.lime:Lerp(P.white, k * 0.7)
	else
		barFill.BackgroundColor3 = P.cyan
	end

	local daily = state.daily
	if daily then
		styleReady(dailyBtn, daily.available, "GIFT", formatDuration(daily.secondsUntilNext))
		if daily.available and not dailyBreathStop then
			dailyBreathStop = Juice.breathe(dailyBtn, 0.05, 1.1)
		elseif not daily.available and dailyBreathStop then
			dailyBreathStop()
			dailyBreathStop = nil
		end
	end

	local crate = state.crate
	if crate then
		styleReady(crateBtn, crate.available, "CRATE", formatDuration(crate.secondsRemaining))
		if crate.available and not crateBreathStop then
			crateBreathStop = Juice.breathe(crateBtn, 0.05, 1.1)
		elseif not crate.available and crateBreathStop then
			crateBreathStop()
			crateBreathStop = nil
		end
	end

	local ready = 0
	if state.quests then
		for _, q in state.quests do
			if q.complete and not q.claimed then
				ready += 1
			end
		end
	end
	questBadge.Visible = ready > 0
	if ready > 0 then
		questBadge.Text = tostring(ready)
		local k = 1 + math.sin(pulse * 5) * 0.12
		questBadge.Size = UDim2.fromOffset(28 * k, 28 * k)
	end

	ascendBtn.Visible = state.canAscend == true
	if ascendBtn.Visible then
		-- ascending is the biggest decision in the game, it has to scream
		local k = (math.sin(pulse * 4) + 1) / 2
		ascendBtn.BackgroundColor3 = P.hot:Lerp(P.amber, k)
	end
end)

-- countdowns keep ticking between StateSyncs, otherwise they'd look frozen for whole seconds
task.spawn(function()
	while true do
		task.wait(1)
		if state then
			local crate = state.crate
			if crate and crate.secondsRemaining > 0 then
				crate.secondsRemaining -= 1
				if crate.secondsRemaining <= 0 then
					crate.available = true
				end
			end
			local daily = state.daily
			if daily and daily.secondsUntilNext > 0 then
				daily.secondsUntilNext -= 1
			end
		end
	end
end)
