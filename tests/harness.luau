--!strict

-- minimal runner for Lune. TestEZ runs inside Roblox, here we need to run the pure logic from the
-- CLI without Studio

local process = require("@lune/process")

local harness = {}

local passed = 0
local failed = 0

local RED = "\27[31m"
local GREEN = "\27[32m"
local DIM = "\27[2m"
local RESET = "\27[0m"

function harness.describe(name: string, body: () -> ())
	print(string.format("\n%s%s%s", DIM, name, RESET))
	body()
end

function harness.test(name: string, body: () -> ())
	local ok, err = pcall(body)
	if ok then
		passed += 1
		print(string.format("  %s✓%s %s", GREEN, RESET, name))
	else
		failed += 1
		print(string.format("  %s✗%s %s", RED, RESET, name))
		print(string.format("      %s%s%s", RED, tostring(err), RESET))
	end
end

function harness.ok(cond: boolean, msg: string?)
	if not cond then
		error(msg or "assertion failed", 2)
	end
end

function harness.eq(a: any, b: any)
	if a ~= b then
		error(string.format("expected %s, got %s", tostring(b), tostring(a)), 2)
	end
end

function harness.near(a: number, b: number, tol: number?)
	local t = tol or 1e-6
	local scale = math.max(1, math.abs(b))
	if math.abs(a - b) > t * scale then
		error(string.format("expected ~%s, got %s", tostring(b), tostring(a)), 2)
	end
end

function harness.finish(): number
	print(string.format("\n%d passed, %d failed\n", passed, failed))
	if failed > 0 then
		process.exit(1)
	end
	return 0
end

return harness
