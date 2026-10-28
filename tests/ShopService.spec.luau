--!strict

-- granting products is the one place where a bug costs the player real money. here we check what we
-- can without MarketplaceService

local shim = require("./robloxshim")
local t = require("./harness")

local env = shim.newEnv()
local Config = env.requireShared("Config")
local ShopService = env.requireServer("ShopService")

t.describe("Shop: id map", function()
	t.test("products not created yet stay out of the map", function()
		-- with id 0 they'd all collapse onto the same key, and the first purchase would trigger a random
		-- one
		t.eq(ShopService._productById[0], nil)
		t.eq(ShopService._passById[0], nil)
	end)

	t.test("right now every id is zero, so the maps are empty", function()
		local n = 0
		for _ in ShopService._productById do
			n += 1
		end
		for _ in ShopService._passById do
			n += 1
		end
		t.eq(n, 0, "some id has been set, update this test")
	end)

	t.test("every product in Config has the fields the code expects", function()
		for name, info in Config.PRODUCTS do
			t.ok(type(info.id) == "number", name .. " without an id")
			local usable = info.scaleSeconds ~= nil
				or info.mult ~= nil
				or name == "instantAscend"
				or name == "fillCrate"
			t.ok(usable, name .. " can't be granted by grantProduct")
		end
	end)

	t.test("every gamepass in Config has an id", function()
		for name, info in Config.GAMEPASSES do
			t.ok(type(info.id) == "number", name .. " without an id")
		end
	end)

	t.test("timed products declare duration and multiplier", function()
		local boost = Config.PRODUCTS.boost15
		t.ok(boost.mult > 1)
		t.ok(boost.seconds > 0)
	end)

	t.test("credit packs grow in size", function()
		t.ok(Config.PRODUCTS.creditsS.scaleSeconds < Config.PRODUCTS.creditsM.scaleSeconds)
		t.ok(Config.PRODUCTS.creditsM.scaleSeconds < Config.PRODUCTS.creditsL.scaleSeconds)
	end)
end)

t.describe("Shop: receipt key safety", function()
	-- the key is "<PurchaseId>_<PlayerId>" and the cleanup on leave matches on the suffix: if it only
	-- compared the trailing digits user 42 would also delete 142's receipts and their next purchase
	-- would be granted twice
	local function suffixMatches(key: string, userId: number): boolean
		local suffix = "_" .. userId
		return string.sub(key, -#suffix) == suffix
	end

	t.test("a shorter id doesn't hit the longer one", function()
		t.ok(not suffixMatches("abc_142", 42))
		t.ok(suffixMatches("abc_42", 42))
	end)

	t.test("identical ids match", function()
		t.ok(suffixMatches("xyz_999999_7", 7))
		t.ok(suffixMatches("p_7", 7))
	end)

	t.test("the cleanup in ShopService uses the full suffix", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/ShopService.luau")
		t.ok(
			string.find(src, 'local suffix = "_" %.%. player%.UserId') ~= nil,
			"the granted cleanup doesn't use the full suffix anymore"
		)
	end)
end)

t.describe("Shop: the receipt handler", function()
	local function sourceOf(fnName: string): string
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/ShopService.luau")
		local body = string.match(src, "local function " .. fnName .. ".-\nend\n")
		assert(body, "function not found: " .. fnName)
		return body
	end

	t.test("only confirms after a successful save", function()
		-- if it confirmed first a crash would leave the player charged and empty handed
		local body = sourceOf("processReceipt")
		local savePos = string.find(body, "DataService%.save")
		local grantPos = string.find(body, "granted%[key%] = true")
		t.ok(savePos ~= nil and grantPos ~= nil, "processReceipt changed")
		t.ok((savePos :: number) < (grantPos :: number), "it confirms before saving")
	end)

	t.test("an already granted purchase isn't repeated", function()
		local body = sourceOf("processReceipt")
		t.ok(
			string.find(body, "if granted%[key%] then") ~= nil,
			"missing the idempotency check, Roblox can deliver the same receipt again"
		)
	end)

	t.test("an unknown product doesn't get confirmed", function()
		local body = sourceOf("processReceipt")
		t.ok(string.find(body, "unknown product") ~= nil)
	end)

	t.test("instant ascend doesn't charge if it isn't possible", function()
		local body = sourceOf("grantProduct")
		t.ok(
			string.find(body, "if not Economy%.canAscend") ~= nil,
			"instantAscend would charge without granting anything"
		)
	end)
end)

return t.finish()
