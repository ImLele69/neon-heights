--!strict

-- the spiral that lays out the bases is pure geometry, so it's testable. if it's wrong two players
-- end up on the same base, better to find out here than with real players inside

local t = require("./harness")

local PLOT_SPACING = 220

-- copy of the function in BaseBuilder, there it's wrapped in Roblox code the test doesn't need. if
-- either one changes, the last test flags it
local function plotOrigin(index: number): (number, number)
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
	return x * PLOT_SPACING, z * PLOT_SPACING
end

t.describe("Plot grid", function()
	t.test("the first plot is at the origin", function()
		local x, z = plotOrigin(0)
		t.eq(x, 0)
		t.eq(z, 0)
	end)

	t.test("no position repeats", function()
		-- a Roblox server tops out around ~50 players, we go wider here
		local seen: { [string]: number } = {}
		for i = 0, 199 do
			local x, z = plotOrigin(i)
			local key = string.format("%d:%d", x, z)
			t.ok(seen[key] == nil, string.format("plots %d and %d overlap", seen[key] or -1, i))
			seen[key] = i
		end
	end)

	t.test("bases never touch", function()
		local positions = {}
		for i = 0, 99 do
			local x, z = plotOrigin(i)
			table.insert(positions, { x = x, z = z })
		end
		for i = 1, #positions do
			for j = i + 1, #positions do
				local dx = math.abs(positions[i].x - positions[j].x)
				local dz = math.abs(positions[i].z - positions[j].z)
				t.ok(
					dx >= PLOT_SPACING or dz >= PLOT_SPACING,
					string.format("plots %d and %d too close", i - 1, j - 1)
				)
			end
		end
	end)

	t.test("the layout stays compact instead of stretching", function()
		-- if it degenerated into a line the fiftieth player would be eleven thousand studs from the first
		local maxDist = 0
		for i = 0, 49 do
			local x, z = plotOrigin(i)
			maxDist = math.max(maxDist, math.max(math.abs(x), math.abs(z)))
		end
		t.ok(
			maxDist <= PLOT_SPACING * 4,
			string.format("too spread out: %d studs from the center", maxDist)
		)
	end)

	t.test("positions are exact multiples of the spacing", function()
		for i = 0, 60 do
			local x, z = plotOrigin(i)
			t.eq(x % PLOT_SPACING, 0)
			t.eq(z % PLOT_SPACING, 0)
		end
	end)

	t.test("the formula is the same one in BaseBuilder", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/BaseBuilder.luau")
		t.ok(
			string.find(src, "local ring = math.floor%(%(math.sqrt%(index%) %+ 1%) / 2%)") ~= nil,
			"the spiral in BaseBuilder changed, update this test too"
		)
		t.ok(
			string.find(src, "local PLOT_SPACING = " .. PLOT_SPACING) ~= nil,
			"PLOT_SPACING doesn't match the test anymore"
		)
	end)
end)

t.describe("Lobby and plots don't overlap", function()
	-- the lobby holds the SpawnLocation: if it fell inside the first plot the player would spawn in
	-- the middle of someone else's base, or inside a wall. the first plot is centered on the origin
	local PLOT_HALF = 120 / 2
	local LOBBY_HALF = 90 / 2
	local LOBBY_Z = -120

	t.test("the lobby is outside the first plot", function()
		local plotEdge = -PLOT_HALF
		local lobbyEdge = LOBBY_Z + LOBBY_HALF
		t.ok(
			lobbyEdge < plotEdge,
			string.format("lobby up to z=%d, plot from z=%d: they overlap", lobbyEdge, plotEdge)
		)
	end)

	t.test("the values in the code are the ones the test assumes", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/BaseBuilder.luau")
		-- the fourth argument is `plain`: the minus in -120 would be a quantifier in a Lua pattern
		t.ok(
			string.find(src, "local LOBBY_Z = " .. LOBBY_Z, 1, true) ~= nil,
			"LOBBY_Z changed in BaseBuilder, check the distances again"
		)
		t.ok(
			string.find(src, "Size = Vector3%.new%(90, 4, 90%)") ~= nil,
			"the lobby changed size, check the distances again"
		)
	end)

	t.test("totems are behind the lobby, not on the plots", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/Leaderboard.luau")
		t.ok(
			string.find(src, "BaseBuilder%.LOBBY_Z %- 60") ~= nil,
			"totems don't follow the lobby anymore, they could end up on a plot"
		)
	end)

	t.test("there's a SpawnLocation, or you spawn in the void", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/BaseBuilder.luau")
		t.ok(
			string.find(src, 'Instance%.new%("SpawnLocation"%)') ~= nil,
			"without a SpawnLocation Roblox spawns you at 0,0,0, where there's nothing"
		)
	end)
end)

t.describe("The character gets placed on the base", function()
	t.test("CharacterAdded is hooked before the initial placement", function()
		-- place() yields on WaitForChild: if the initial placement ran inline a respawn in between
		-- wouldn't be caught and the player would keep falling
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/PlotService.luau")
		local connectPos = string.find(src, "player%.CharacterAdded:Connect%(place%)")
		local initialPos = string.find(src, "if player%.Character then")
		t.ok(connectPos ~= nil and initialPos ~= nil, "onJoin changed")
		t.ok(
			(connectPos :: number) < (initialPos :: number),
			"CharacterAdded has to be hooked before the initial placement"
		)
	end)

	t.test("placement doesn't block onJoin", function()
		local fs = require("@lune/fs")
		local src = fs.readFile("src/server/PlotService.luau")
		local body = string.match(src, "local function place.-\n\t\tend")
		t.ok(body ~= nil, "place not found")
		t.ok(
			string.find(body :: string, "task%.spawn") ~= nil,
			"place yields inline and blocks the rest of onJoin"
		)
	end)
end)

return t.finish()
