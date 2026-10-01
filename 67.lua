--@misenthropic
--server side module for the room gen in the game 
--https://www.roblox.com/games/16146081332/THE-COMPLEX

local players = game:GetService("Players")
local replicated_storage = game:GetService("ReplicatedStorage")
local run_service = game:GetService("RunService")
local http_service = game:GetService("HttpService")

local player = players.LocalPlayer
local loaded_chunks = {}

local render_connection

local radius = 3

local function get_level(level_name)
	return require(replicated_storage.modules.levels:FindFirstChild(level_name))
end

while not replicated_storage:GetAttribute("seed") do
	replicated_storage:GetAttributeChangedSignal("seed"):Wait()
end

local seed = replicated_storage:GetAttribute("seed")

local levels_folder = workspace:FindFirstChild("levels")
	or Instance.new("Folder", workspace)
levels_folder.Name = "levels"

local function chunk_key(level_name, cx, cz)
	return level_name .. ":" .. cx .. "," .. cz
end

local function render_chunk(level_name, cx, cz)
	local level = get_level(level_name)
	
	local key = chunk_key(level_name, cx, cz)
	if loaded_chunks[key] then return end
	loaded_chunks[key] = true

	local level_folder = levels_folder:FindFirstChild(level_name)
		or Instance.new("Folder", levels_folder)
	level_folder.Name = level_name

	local chunk_folder = Instance.new("Folder")
	chunk_folder.Name = cx .. "," .. cz
	chunk_folder.Parent = level_folder

	level.build_chunk(cx, cz, "client", chunk_folder)
end

local function unload_chunks(level_name, cx, cz)
	for key in pairs(loaded_chunks) do
		local klevel, kx, kz = key:match("([^:]+):(-?%d+),(-?%d+)")
		kx, kz = tonumber(kx), tonumber(kz)

		if klevel ~= level_name then continue end
		if math.abs(kx - cx) <= radius and math.abs(kz - cz) <= radius then continue end

		loaded_chunks[key] = nil

		local folder = levels_folder:FindFirstChild(level_name)
		if folder then
			local chunk = folder:FindFirstChild(kx .. "," .. kz)
			if chunk then
				chunk:Destroy()
			end
		end
	end
end

local function render(level_name)
	local level = get_level(level_name)
	local character = player.Character
	local root = character:WaitForChild("HumanoidRootPart")

	if render_connection then
		render_connection:Disconnect()
	end	
	
	render_connection = run_service.Heartbeat:Connect(function()
		if not root.Parent then return end

		local cx = math.floor(root.Position.X / level.chunk_size)
		local cz = math.floor(root.Position.Z / level.chunk_size)

		for x = -radius, radius do
			for z = -radius, radius do
				render_chunk(level_name, cx + x, cz + z)
			end
		end

		unload_chunks(level_name, cx, cz)
	end)
end

task.spawn(function()
	for _, level_module in ipairs(replicated_storage.modules.levels:GetChildren()) do
		local level = require(level_module)
		print("loading", level_module)
		level.generate_graph(replicated_storage:GetAttribute("seed"))
		print("loaded", level_module)
	end

	replicated_storage:SetAttribute("client_levels_generated", true)
	
	player.CharacterAdded:Connect(function()
		repeat
			task.wait()
		until player:GetAttribute("current_level") ~= nil
		
		render(player:GetAttribute("current_level"))
	end)
end)

return 0