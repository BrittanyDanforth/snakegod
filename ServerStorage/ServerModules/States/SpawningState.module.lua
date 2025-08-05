--[[
    SpawningState.module - Handles snake spawning and initial setup
    Responsible for creating the snake model, setting up camera, and resetting stats
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local CollectionService = game:GetService("CollectionService")

local SpawningState = {}
SpawningState.__index = SpawningState

function SpawningState.new(controller)
    local self = setmetatable({}, SpawningState)
    self.controller = controller
    self.name = "Spawning"
    return self
end

function SpawningState:OnEnter()
    -- Reset player data for respawn
    self.controller.data.lastRespawnTime = os.clock()
    self.controller.collisionState.canCollide = false -- Disable collisions during spawn
    
    -- Clear any existing snake
    if self.controller.snakeObject then
        if self.controller.snakeObject.destroy then
            self.controller.snakeObject:destroy()
        end
        self.controller.snakeObject = nil
    end
    
    -- Respawn the player using Roblox's character loading
    -- This will trigger SnakeSystemIntegration to create the snake
    warn("[SpawningState] Respawning player:", self.controller.player.Name)
    
    -- Store revive position if player just revived
    if self.controller.player:GetAttribute("JustRevived") then
        local lastPosition = self.controller.player:GetAttribute("DeathPosition")
        if lastPosition then
            self.controller.player:SetAttribute("RevivePosition", lastPosition)
        end
    end
    
    -- Load character (this triggers SnakeSystemIntegration)
    self.controller.player:LoadCharacter()
    
    -- Wait a bit for character to load
    task.wait(0.5)
    
    -- Clear revive flags
    self.controller.player:SetAttribute("JustRevived", false)
    self.controller.player:SetAttribute("RevivingNow", false)
    
    -- Setup camera follow
    self:_setupCamera()
    
    -- Apply spawn invincibility
    self.controller:setInvincible(self.controller.config.spawnInvincibilityDuration or 3)
    
    -- Wait a brief moment for everything to initialize
    task.wait(0.5)
    
    -- Enable collisions and transition to alive
    self.controller.collisionState.canCollide = true
    self.controller.fsm:changeState("Alive")
end

function SpawningState:OnExecute(dt)
    -- Nothing to do during spawn
end

function SpawningState:OnExit()
    -- Notify that spawning is complete
    self.controller:notifyStateChange("Spawned")
end

function SpawningState:_getSpawnPosition()
    -- Find a safe spawn position
    -- This is simplified - a real implementation would check for obstacles
    local mapSize = self.controller.config.mapSize or 1000
    local x = math.random(-mapSize/2, mapSize/2)
    local z = math.random(-mapSize/2, mapSize/2)
    
    return Vector3.new(x, 5, z)
end

function SpawningState:_setupCamera()
    -- Send camera setup remote to client
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local cameraRemote = remotes:FindFirstChild("SetupSnakeCamera")
    
    if cameraRemote and self.controller.snakeObject then
        cameraRemote:FireClient(
            self.controller.player,
            self.controller.snakeObject.model
        )
    end
end

return SpawningState