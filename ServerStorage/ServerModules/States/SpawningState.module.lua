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

function SpawningState:OnEnter(previousState)
    warn("[SpawningState] Entered spawning state for", self.controller.player.Name, "from state:", previousState)
    
    -- Check if this is a revive spawn
    local isReviving = previousState == "Reviving" or self.controller.fsm.previousStateForSpawning == "Reviving"
    
    -- Clear the flag
    if self.controller.fsm.previousStateForSpawning then
        self.controller.fsm.previousStateForSpawning = nil
    end
    
    -- Reset player data for respawn
    self.controller.data.lastRespawnTime = os.clock()
    self.controller.collisionState.canCollide = false -- Disable collisions during spawn
    
    -- If reviving, set the revival attributes for SnakeSystemIntegration
    if isReviving then
        warn("[SpawningState] Handling revive spawn for", self.controller.player.Name)
        self.controller.player:SetAttribute("JustRevived", true)
        self.controller.player:SetAttribute("RevivingNow", true)
        
        -- The ReviveSnakeLength and RevivePosition should already be set by DyingState
        local reviveLength = self.controller.player:GetAttribute("ReviveSnakeLength")
        local revivePos = self.controller.player:GetAttribute("RevivePosition")
        warn("[SpawningState] Revive length:", reviveLength, "Position:", revivePos)
    else
        warn("[SpawningState] Normal spawn (not reviving)")
    end
    
    -- Clear any existing snake
    if self.controller.snakeObject then
        if self.controller.snakeObject.destroy then
            self.controller.snakeObject:destroy()
        end
        self.controller.snakeObject = nil
    end
    
    -- Create new snake using adapter
    local SnakeAdapter = require(script.Parent.Parent.SnakeAdapter)
    
    -- Get spawn position (this could be more sophisticated)
    local spawnPosition = self:_getSpawnPosition()
    
    -- For revival spawns, we need to trigger LoadCharacter instead
    if isReviving then
        warn("[SpawningState] Triggering LoadCharacter for revive")
        -- LoadCharacter will trigger CharacterAdded, which SnakeSystemIntegration listens to
        local success, err = pcall(function()
            self.controller.player:LoadCharacter()
        end)
        
        if not success then
            warn("[SpawningState] Failed to LoadCharacter:", err)
            return resolve("Spectating")
        end
        
        -- Wait for character and snake to be created
        local maxWaitTime = 5
        local startTime = os.clock()
        local snakeCreated = false
        
        while (os.clock() - startTime) < maxWaitTime do
            task.wait(0.1)
            
            -- Check if snake has been created by looking for the snake head in workspace
            local snakeModel = workspace:FindFirstChild("Snake_" .. self.controller.player.Name)
            if snakeModel and snakeModel:FindFirstChild("Segment0_Head") then
                warn("[SpawningState] Snake created successfully for revive")
                snakeCreated = true
                
                -- Give a bit more time for everything to initialize
                task.wait(0.5)
                break
            end
        end
        
        if not snakeCreated then
            warn("[SpawningState] WARNING: Snake creation timed out for revive!")
        end
        
        -- Clear revive attributes after successful spawn
        self.controller.player:SetAttribute("JustRevived", false)
        self.controller.player:SetAttribute("RevivingNow", false)
        self.controller.player:SetAttribute("RevivePromptActive", false)
        self.controller.player:SetAttribute("AwaitingReviveResponse", false)
        
        -- The snake should now be created by SnakeSystemIntegration
        -- Just transition to Alive state
        self.controller.fsm:changeState("Alive")
        return
    end
    
    -- Normal spawn - create snake with initial configuration
    local snakeConfig = {
        player = self.controller.player,
        position = spawnPosition,
        length = self.controller.data.length,
        speed = self.controller.data.speed,
        color = self.controller.player:GetAttribute("SnakeColor") or Color3.new(0, 1, 0)
    }
    
    local success, snakeObject = pcall(function()
        return SnakeAdapter.createSnake(self.controller.player, snakeConfig)
    end)
    
    if not success then
        warn("Failed to create snake:", snakeObject)
        self.controller.fsm:changeState("Spectating")
        return
    end
    
    -- Store snake reference
    self.controller:setSnakeObject(snakeObject)
    
    -- Setup camera follow
    self:_setupCamera()
    
    -- Apply spawn invincibility
    self.controller:setInvincible(self.controller.config.spawnInvincibilityDuration or 3)
    
    -- Wait a brief moment for everything to initialize
    task.wait(0.5)
    
    -- Enable collisions and transition to alive
    self.controller.collisionState.canCollide = true
    
    -- Safely transition to Alive state
    local success, err = pcall(function()
        self.controller.fsm:changeState("Alive")
    end)
    
    if not success then
        warn("[SpawningState] Failed to transition to Alive state:", err)
        -- Try spectating as fallback
        self.controller.fsm:changeState("Spectating")
    end
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