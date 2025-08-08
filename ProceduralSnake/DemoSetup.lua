--!strict
-- Demo Setup Script for Procedural Snake System
-- This script demonstrates how to set up the snake system in your Roblox game

--[[
	INSTALLATION INSTRUCTIONS:
	
	1. Place this entire ProceduralSnake folder in ServerStorage
	2. Run this script in the Command Bar to set up the system
	3. Ensure your character has a SnakeMeshPart with properly named bones
]]

local ServerStorage = game:GetService("ServerStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StarterPlayer = game:GetService("StarterPlayer")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Find the ProceduralSnake folder
local sourceFolder = script.Parent
if not sourceFolder:FindFirstChild("src") then
	error("ProceduralSnake folder structure is incorrect. Ensure src folder exists.")
end

local srcFolder = sourceFolder.src

-- Set up server scripts
local serverFolder = srcFolder:FindFirstChild("Server")
if serverFolder then
	local serverContainer = Instance.new("Folder")
	serverContainer.Name = "ProceduralSnake"
	
	for _, script in ipairs(serverFolder:GetChildren()) do
		local clone = script:Clone()
		clone.Parent = serverContainer
	end
	
	serverContainer.Parent = ServerScriptService
	print("✓ Server scripts installed")
else
	warn("Server folder not found")
end

-- Set up client scripts
local clientFolder = srcFolder:FindFirstChild("Client")
if clientFolder then
	local clientContainer = Instance.new("Folder")
	clientContainer.Name = "ProceduralSnake"
	
	for _, script in ipairs(clientFolder:GetChildren()) do
		local clone = script:Clone()
		clone.Parent = clientContainer
	end
	
	clientContainer.Parent = StarterPlayer.StarterPlayerScripts
	print("✓ Client scripts installed")
else
	warn("Client folder not found")
end

-- Set up shared modules
local sharedFolder = srcFolder:FindFirstChild("Shared")
if sharedFolder then
	local sharedContainer = ReplicatedStorage:FindFirstChild("Shared") or Instance.new("Folder")
	sharedContainer.Name = "Shared"
	
	for _, module in ipairs(sharedFolder:GetChildren()) do
		local clone = module:Clone()
		clone.Parent = sharedContainer
	end
	
	sharedContainer.Parent = ReplicatedStorage
	print("✓ Shared modules installed")
else
	warn("Shared folder not found")
end

-- Create a sample snake character setup
local function createSampleSnakeCharacter()
	local character = Instance.new("Model")
	character.Name = "SnakeCharacter"
	
	-- Create humanoid
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	
	-- Create HumanoidRootPart
	local rootPart = Instance.new("Part")
	rootPart.Name = "HumanoidRootPart"
	rootPart.Size = Vector3.new(2, 2, 2)
	rootPart.Transparency = 1
	rootPart.CanCollide = false
	rootPart.Parent = character
	
	-- Create Head
	local head = Instance.new("Part")
	head.Name = "Head"
	head.Size = Vector3.new(1, 1, 1)
	head.Shape = Enum.PartType.Ball
	head.TopSurface = Enum.SurfaceType.Smooth
	head.BottomSurface = Enum.SurfaceType.Smooth
	head.BrickColor = BrickColor.new("Bright green")
	head.Parent = character
	
	-- Weld head to root
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = rootPart
	weld.Part1 = head
	weld.Parent = rootPart
	
	-- Create placeholder snake mesh (in real use, this would be your imported skinned mesh)
	local snakeMesh = Instance.new("MeshPart")
	snakeMesh.Name = "SnakeMeshPart"
	snakeMesh.Size = Vector3.new(1, 1, 10)
	snakeMesh.Material = Enum.Material.Neon
	snakeMesh.BrickColor = BrickColor.new("Lime green")
	snakeMesh.Parent = character
	
	-- Create sample bones (in real use, these would come from your imported model)
	for i = 1, 20 do
		local bone = Instance.new("Bone")
		bone.Name = "Bone_" .. i
		bone.Parent = snakeMesh
		
		-- Position bones along the length
		local offset = (i - 1) * 0.5
		bone.Position = Vector3.new(0, 0, -offset)
		
		-- Set up bone hierarchy
		if i > 1 then
			local prevBone = snakeMesh:FindFirstChild("Bone_" .. (i - 1))
			if prevBone then
				bone.Parent = prevBone
			end
		end
	end
	
	-- Weld mesh to root
	local meshWeld = Instance.new("WeldConstraint")
	meshWeld.Part0 = rootPart
	meshWeld.Part1 = snakeMesh
	meshWeld.Parent = rootPart
	
	character.PrimaryPart = rootPart
	
	return character
end

-- Option to create a sample character
print("\n=== Procedural Snake System Installed ===")
print("To create a sample snake character, run:")
print("  workspace.SnakeCharacter = createSampleSnakeCharacter()")
print("\nEnsure your character model has:")
print("  - A MeshPart named 'SnakeMeshPart'")
print("  - Bones named 'Bone_1', 'Bone_2', etc.")
print("  - Proper skinning/weighting from your 3D software")

-- Store the function for manual use
_G.createSampleSnakeCharacter = createSampleSnakeCharacter

print("\n✓ Setup complete!")