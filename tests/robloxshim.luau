--!strict
-- #selene: allow(global_usage)

-- the modules are written to run inside Roblox: they use `script.Parent`, `game:GetService` and
-- Roblox types. to test the logic from the CLI those globals get replaced. it only covers what the
-- modules actually touch

local fs = require("@lune/fs")
local luau = require("@lune/luau")

local shim = {}

-- Enum is a bottomless pit, here it's enough that `Enum.Whatever.Thing` returns a stable comparable
-- value, not the real one
local function makeEnum()
	local cache: { [string]: any } = {}
	return setmetatable({}, {
		__index = function(_, category: string)
			if not cache[category] then
				cache[category] = setmetatable({}, {
					__index = function(self, item: string)
						local v = { EnumType = category, Name = item }
						rawset(self, item, v)
						return v
					end,
				})
			end
			return cache[category]
		end,
	})
end

-- geometry constructors are only here because modules call them while building the scene. tests
-- look at logic, not coordinates
local function makeVector3()
	local V = {}
	local mt = { __index = V }
	function V.new(x: number?, y: number?, z: number?)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, mt)
	end
	return V
end

local function makeVector2()
	local V = {}
	local mt = { __index = V }
	function V.new(x: number?, y: number?)
		return setmetatable({ X = x or 0, Y = y or 0 }, mt)
	end
	V.zero = V.new(0, 0)
	return V
end

local function makeUDim2()
	local U = {}
	local mt = { __index = U }
	local function make(sx, ox, sy, oy)
		return setmetatable({
			X = { Scale = sx, Offset = ox },
			Y = { Scale = sy, Offset = oy },
		}, mt)
	end
	function U.new(sx: number?, ox: number?, sy: number?, oy: number?)
		return make(sx or 0, ox or 0, sy or 0, oy or 0)
	end
	function U.fromOffset(x: number?, y: number?)
		return make(0, x or 0, 0, y or 0)
	end
	function U.fromScale(x: number?, y: number?)
		return make(x or 0, 0, y or 0, 0)
	end
	return U
end

local function makeUDim()
	local U = {}
	function U.new(scale: number?, offset: number?)
		return { Scale = scale or 0, Offset = offset or 0 }
	end
	return U
end

local function makeCFrame()
	local C = {}
	local mt = {
		__index = C,
		__mul = function(a: any, _b: any)
			return a
		end,
	}
	function C.new(x: number?, y: number?, z: number?)
		return setmetatable({ X = x or 0, Y = y or 0, Z = z or 0 }, mt)
	end
	function C.Angles()
		return C.new(0, 0, 0)
	end
	return C
end

-- Instance.new returns a table that accepts any property and keeps track of children: enough for
-- scene code to run without errors while the logic next to it gets tested
local function makeInstanceNew()
	local function newInstance(className: string): any
		local children: { any } = {}
		local inst
		inst = setmetatable({
			ClassName = className,
			Name = className,
			_children = children,
		}, {
			__index = function(_, k: string)
				if k == "Parent" then
					return nil
				end
				return function() end
			end,
			__newindex = function(self, k: string, v: any)
				rawset(self, k, v)
				if k == "Parent" and type(v) == "table" and v._children then
					table.insert(v._children, self)
				end
			end,
		})
		return inst
	end
	return newInstance
end

local function makeColor3()
	local Color3 = {}
	function Color3.fromRGB(r: number, g: number, b: number)
		return { R = r / 255, G = g / 255, B = b / 255 }
	end
	function Color3.new(r: number, g: number, b: number)
		return { R = r, G = g, B = b }
	end
	return Color3
end

-- fs.readFile is async and can't run inside __index, so all the sources get read up front and the
-- proxies only work on strings already in memory
local function readDirSources(dir: string): { [string]: string }
	local sources: { [string]: string } = {}
	if not fs.isDir(dir) then
		return sources
	end
	for _, entry in fs.readDir(dir) do
		local name = string.match(entry, "^(.+)%.luau$")
		if name then
			sources[name] = fs.readFile(dir .. "/" .. entry)
		end
	end
	return sources
end

export type Env = {
	requireShared: (string) -> any,
	requireServer: (string) -> any,
	jobId: (string) -> (),
	now: (number?) -> number,
	setNow: (number) -> (),
}

-- every call makes an isolated world: two tests must not share module state or the clock
function shim.newEnv(): Env
	local shared = readDirSources("src/shared")
	local server = readDirSources("src/server")
	local cache: { [string]: any } = {}
	local jobId = "JOB_A"
	local fakeTime = 1_000_000

	local self: Env

	local function load(dir: string, sources: { [string]: string }, modName: string): any
		local cacheKey = dir .. "/" .. modName
		if cache[cacheKey] then
			return cache[cacheKey]
		end
		local source = sources[modName]
		assert(source, "module not found: " .. cacheKey)

		local parentProxy = setmetatable({}, {
			__index = function(_, childName: string)
				return load(dir, sources, childName)
			end,
		})

		local sharedFolder = setmetatable({}, {
			__index = function(_, childName: string)
				return load("src/shared", shared, childName)
			end,
		})

		local services: { [string]: any } = {
			ReplicatedStorage = setmetatable({ Shared = sharedFolder }, {
				__index = function(_, k: string)
					if k == "WaitForChild" then
						return function()
							return sharedFolder
						end
					end
					return nil
				end,
			}),
			DataStoreService = {
				GetDataStore = function()
					return {
						UpdateAsync = function() end,
						GetAsync = function() end,
						SetAsync = function() end,
					}
				end,
				GetOrderedDataStore = function()
					return {
						SetAsync = function() end,
						GetSortedAsync = function()
							return {
								GetCurrentPage = function()
									return {}
								end,
							}
						end,
					}
				end,
			},
			Players = {
				PlayerRemoving = { Connect = function() end },
				PlayerAdded = { Connect = function() end },
				GetPlayers = function()
					return {}
				end,
				GetNameFromUserIdAsync = function()
					return "Player"
				end,
			},
			RunService = {
				IsStudio = function()
					return false
				end,
				Heartbeat = { Connect = function() end },
				RenderStepped = { Connect = function() end },
			},
			TweenService = {
				Create = function()
					return { Play = function() end, Completed = { Connect = function() end } }
				end,
			},
			MarketplaceService = {},
		}

		local gameProxy = setmetatable({}, {
			__index = function(_, k: string)
				if k == "JobId" then
					return jobId
				end
				if k == "GetService" then
					return function(_, name: string)
						return services[name] or {}
					end
				end
				if k == "BindToClose" then
					return function() end
				end
				return nil
			end,
		})

		local osProxy = setmetatable({
			time = function()
				return fakeTime
			end,
		}, { __index = os })

		local env = setmetatable({
			script = { Parent = parentProxy, Name = modName },
			game = gameProxy,
			workspace = { _children = {} },
			Color3 = makeColor3(),
			Enum = makeEnum(),
			Vector2 = makeVector2(),
			Vector3 = makeVector3(),
			UDim = makeUDim(),
			UDim2 = makeUDim2(),
			CFrame = makeCFrame(),
			Instance = { new = makeInstanceNew() },
			ColorSequence = {
				new = function(...)
					return { ... }
				end,
			},
			TweenInfo = {
				new = function(...)
					return { ... }
				end,
			},
			os = osProxy,
			warn = function() end,
			task = {
				wait = function() end,
				spawn = function() end,
			},
			require = function(target: any)
				return target
			end,
		}, { __index = _G })

		local fn = luau.load(source, { debugName = cacheKey .. ".luau", environment = env })
		local result = fn()
		cache[cacheKey] = result
		return result
	end

	self = {
		requireShared = function(name: string)
			return load("src/shared", shared, name)
		end,
		requireServer = function(name: string)
			return load("src/server", server, name)
		end,
		jobId = function(id: string)
			jobId = id
		end,
		now = function(v: number?): number
			if v then
				fakeTime = v
			end
			return fakeTime
		end,
		setNow = function(v: number)
			fakeTime = v
		end,
	}
	return self
end

-- shortcut for tests that only want one shared module
function shim.requireShared(name: string): any
	return shim.newEnv().requireShared(name)
end

return shim
