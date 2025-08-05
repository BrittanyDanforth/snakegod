--[[
    SpawningState.module - Handles respawning after revival or initial spawn
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Promise = require(script.Parent.Parent.Lib.Promise)

local SpawningState = {}
SpawningState.__index = SpawningState

function SpawningState.new(controller)
    local self = setmetatable({}, SpawningState)
    self.controller = controller
    self.name = "Spawning"
    return self
end

function SpawningState:OnEnter(previousState)
    local player = self.controller.player
    
    -- Log the spawn
    warn("[SpawningState] Player", player.Name, "entering spawn state from", previousState or "unknown")
    
    -- Return a promise that transitions to Alive when ready
    return Promise.new(function(resolve, reject, onCancel)
        -- Check if this is a revive spawn
        local isReviving = previousState == "Reviving"
        
        if isReviving then
            -- Get current snake length before respawn
            local currentLength = self.controller:getLength()
            if currentLength <= 0 then
                -- Fallback to leaderstats
                local leaderstats = player:FindFirstChild("leaderstats")
                if leaderstats then
                    local lengthValue = leaderstats:FindFirstChild("Length")
                    if lengthValue then
                        currentLength = lengthValue.Value or 55
                    end
                end
            end
            
            -- Store revive data for SnakeSystemIntegration
            player:SetAttribute("JustRevived", true)
            player:SetAttribute("RevivingNow", true)
            player:SetAttribute("ReviveSnakeLength", math.floor(currentLength * 0.8)) -- 80% of length
            
            -- Store current position for revival
            local character = player.Character
            if character then
                local rootPart = character:FindFirstChild("HumanoidRootPart")
                if rootPart then
                    local pos = rootPart.Position
                    player:SetAttribute("RevivePosition", string.format("%f,%f,%f", pos.X, pos.Y, pos.Z))
                end
            end
        end
        
        -- Respawn the player
        player:LoadCharacter()
        
        -- Wait a short time for character to load
        Promise.delay(0.5):andThen(function()
            -- Clear revive flags after spawn
            if isReviving then
                task.spawn(function()
                    task.wait(2)
                    player:SetAttribute("JustRevived", false)
                    player:SetAttribute("RevivingNow", false)
                end)
            end
            
            -- Transition to Alive state
            resolve("Alive")
        end)
    end)
end

function SpawningState:OnExecute(dt)
    -- Nothing to update during spawning
end

function SpawningState:OnExit()
    -- Notify spawn complete
    self.controller:notifyStateChange("SpawnComplete")
end

return SpawningState