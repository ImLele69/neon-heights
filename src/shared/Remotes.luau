--!strict

-- one single place where remote names are written: if client and server typed them by hand a typo
-- would be a silent bug

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Remotes = {}

Remotes.EVENTS = {
	"BuyModule",
	"Ascend",
	"ClaimDaily",
	"ClaimCrate",
	"RedeemCode",
	"ClaimQuest",
	"OpenShop",
	"BuyDataUpgrade",
	"StateSync",
	"Notify",
}

Remotes.FUNCTIONS = {
	"GetState",
}

local folder: Folder

-- the server creates, the client waits. order matters or the client starts before the remotes exist
local function ensureFolder(): Folder
	if folder then
		return folder
	end
	if RunService:IsServer() then
		local existing = ReplicatedStorage:FindFirstChild("Remotes")
		if existing then
			folder = existing :: Folder
			return folder
		end
		local created = Instance.new("Folder")
		created.Name = "Remotes"
		created.Parent = ReplicatedStorage
		folder = created
		return folder
	end
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
	return folder
end

function Remotes.init()
	assert(RunService:IsServer(), "Remotes.init must only be called by the server")
	local f = ensureFolder()
	for _, name in Remotes.EVENTS do
		if not f:FindFirstChild(name) then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = f
		end
	end
	for _, name in Remotes.FUNCTIONS do
		if not f:FindFirstChild(name) then
			local fn = Instance.new("RemoteFunction")
			fn.Name = name
			fn.Parent = f
		end
	end
end

function Remotes.event(name: string): RemoteEvent
	return ensureFolder():WaitForChild(name) :: RemoteEvent
end

function Remotes.fn(name: string): RemoteFunction
	return ensureFolder():WaitForChild(name) :: RemoteFunction
end

return Remotes
