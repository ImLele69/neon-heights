--!strict

-- gamepasses and dev products. ids in Config are 0 until the products exist on the Roblox site: an
-- id of 0 is skipped everywhere, so the game runs the same before and after they're created.
--
-- ProcessReceipt is the one place in the game where a bug costs the player real money: if it
-- doesn't return PurchaseGranted Roblox retries and charges the player again. so: grant, save, and
-- only confirm after a successful save

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Shared = ReplicatedStorage:WaitForChild("Shared")
local Remotes = require(Shared.Remotes)
local Config = require(Shared.Config)
local Economy = require(Shared.Economy)
local Rewards = require(Shared.Rewards)

local DataService = require(script.Parent.DataService)
local PlayerService = require(script.Parent.PlayerService)
local RateLimiter = require(script.Parent.RateLimiter)

local ShopService = {}

-- reverse id to name map, built once. ids of 0 stay out, otherwise every product not created yet
-- would collapse onto the same key and the first purchase would trigger a random one
local productById: { [number]: string } = {}
for name, info in Config.PRODUCTS do
	if info.id ~= 0 then
		productById[info.id] = name
	end
end

local passById: { [number]: string } = {}
for name, info in Config.GAMEPASSES do
	if info.id ~= 0 then
		passById[info.id] = name
	end
end

local function grantProduct(player: Player, productName: string): boolean
	local p = DataService.get(player.UserId)
	if not p then
		return false
	end
	local info = Config.PRODUCTS[productName]
	if not info then
		return false
	end
	local now = os.time()

	if productName == "boost15" then
		local b = Rewards.applyBoost(p, info.mult, info.seconds, now)
		p.boostUntil, p.boostMult = b.boostUntil, b.boostMult
	elseif info.scaleSeconds then
		local amount = Economy.productCreditValue(p, now, info.scaleSeconds)
		PlayerService.grant(p, amount)
	elseif productName == "instantAscend" then
		if not Economy.canAscend(p) then
			-- nothing to grant, better not to charge at all
			return false
		end
		local result = Economy.applyAscend(p)
		p.ascensions = result.ascensions
		p.modules = result.modules
		p.credits = result.credits
	elseif productName == "fillCrate" then
		p.lastCrate = 0
	else
		return false
	end

	return true
end

-- the receipt handler has to be idempotent: Roblox can deliver the same purchase more than once,
-- and granting it twice would hand out free currency
local granted: { [string]: boolean } = {}

local function processReceipt(receipt: any): Enum.ProductPurchaseDecision
	local key = string.format("%s_%d", tostring(receipt.PurchaseId), receipt.PlayerId)
	if granted[key] then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end

	local player = Players:GetPlayerByUserId(receipt.PlayerId)
	if not player then
		-- the player left, NotProcessedYet makes it retry when they're back
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local productName = productById[receipt.ProductId]
	if not productName then
		warn(string.format("[Shop] unknown product: %d", receipt.ProductId))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	local ok, applied = pcall(grantProduct, player, productName)
	if not ok or not applied then
		warn(string.format("[Shop] grant failed for %s: %s", productName, tostring(applied)))
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	-- only confirm after the save went through: if the server died now the player would have paid for
	-- nothing
	if not DataService.save(player.UserId, false) then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end

	granted[key] = true
	PlayerService.pushState(player)
	PlayerService.notify(player, "purchase", { product = productName })
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

-- a gamepass bought during the session has to work right away, not on the next join
local function onPassPurchased(player: Player, passId: number, wasPurchased: boolean)
	if not wasPurchased then
		return
	end
	local name = passById[passId]
	if not name then
		return
	end
	PlayerService.refreshPasses(player)
	PlayerService.pushState(player)
	PlayerService.notify(player, "pass", { pass = name })
end

function ShopService.promptProduct(player: Player, productName: string)
	local info = Config.PRODUCTS[productName]
	if not info or info.id == 0 then
		PlayerService.notify(player, "denied", { reason = "not available yet" })
		return
	end
	MarketplaceService:PromptProductPurchase(player, info.id)
end

function ShopService.promptPass(player: Player, passName: string)
	local info = Config.GAMEPASSES[passName]
	if not info or info.id == 0 then
		PlayerService.notify(player, "denied", { reason = "not available yet" })
		return
	end
	MarketplaceService:PromptGamePassPurchase(player, info.id)
end

function ShopService.start()
	MarketplaceService.ProcessReceipt = processReceipt

	-- the client only says which product it wants. the prompt and the price are decided by the server
	-- from Config, or a modified client could open the prompt for a different product than the one
	-- shown
	Remotes.event("OpenShop").OnServerEvent:Connect(function(player: Player, kind: any, name: any)
		if not RateLimiter.check(player.UserId, "OpenShop", os.clock()) then
			return
		end
		if type(kind) ~= "string" or type(name) ~= "string" then
			return
		end
		if kind == "product" then
			ShopService.promptProduct(player, name)
		elseif kind == "pass" then
			ShopService.promptPass(player, name)
		end
	end)
	MarketplaceService.PromptGamePassPurchaseFinished:Connect(onPassPurchased)

	-- match on the full "_<id>" suffix: comparing just the trailing digits would make user 42 delete
	-- user 142's keys too
	Players.PlayerRemoving:Connect(function(player)
		local suffix = "_" .. player.UserId
		for key in granted do
			if string.sub(key, -#suffix) == suffix then
				granted[key] = nil
			end
		end
	end)
end

ShopService._productById = productById
ShopService._passById = passById
ShopService._grantProduct = grantProduct

return ShopService
