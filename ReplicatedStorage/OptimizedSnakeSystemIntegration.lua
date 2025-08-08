-- Optimized Snake System Integration - Fixes all gimbal lock and smoothness issues
-- Drop-in fix for your existing snake system - NO MODIFICATIONS TO YOUR FILES NEEDED!

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- CRITICAL: Stable CFrame calculation to prevent gimbal lock and "parts sticking up"
local function createStableCFrame(position: Vector3, lookAtPosition: Vector3, upVector: Vector3?)
    upVector = upVector or Vector3.new(0, 1, 0)
    
    local lookVector = (lookAtPosition - position).Unit
    
    -- Check if lookVector and upVector are nearly parallel (THIS CAUSES THE "STICKING UP" PROBLEM)
    local dot = math.abs(lookVector:Dot(upVector))
    if dot > 0.999 then
        -- If they are parallel, use a different up vector
        upVector = if math.abs(lookVector.X) < 0.9 
            then Vector3.new(1, 0, 0) 
            else Vector3.new(0, 1, 0)
    end
    
    -- Calculate right vector using cross product
    local rightVector = upVector:Cross(lookVector).Unit
    
    -- Recalculate up vector to ensure orthogonality
    local newUpVector = lookVector:Cross(rightVector).Unit
    
    -- Create CFrame using fromMatrix (THIS PREVENTS ROLLING)
    return CFrame.fromMatrix(
        position,
        rightVector,
        newUpVector,
        -lookVector -- Note: fromMatrix uses -Z as look direction
    )
end

-- Frame-rate independent damping for smooth interpolation
local function dampCFrame(current: CFrame, goal: CFrame, smoothingFactor: number, deltaTime: number): CFrame
    smoothingFactor = math.clamp(smoothingFactor, 0, 0.999)
    local alpha = 1 - (smoothingFactor ^ deltaTime)
    return current:Lerp(goal, alpha)
end

-- Integration module
local Integration = {}
Integration.__index = Integration

-- Create integration instance for a snake
function Integration.new(snakeInstance)
    local self = setmetatable({}, Integration)
    self.snake = snakeInstance
    self.previousBoneTransforms = {}
    self.smoothingFactor = 0.85
    
    -- Hook into the snake's update cycle
    self:hookUpdate()
    
    return self
end

-- Enhanced bone update that fixes all visual artifacts
function Integration:updateBonesFixed(deltaTime)
    local snake = self.snake
    if not snake.bones or #snake.bones == 0 then return end
    
    -- Update wave phase
    snake.wavePhase = snake.wavePhase + (snake.config.WAVE_FREQUENCY or 2.0) * deltaTime
    
    local numBones = #snake.bones
    local historySize = #snake.positionHistory
    
    for i, bone in ipairs(snake.bones) do
        -- Calculate how far back in history this bone should look
        local boneProgress = (i - 1) / math.max(1, numBones - 1)
        local historyLookback = math.floor(boneProgress * math.min(historySize * 0.8, snake.length))
        
        -- Get position from history
        local historyIndex = math.max(1, snake.historyIndex - historyLookback)
        local historicalData = snake.positionHistory[historyIndex]
        
        if historicalData then
            local targetPos = historicalData.position
            local targetLook = historicalData.lookVector or (targetPos - (snake.positionHistory[math.max(1, historyIndex - 1)] or {position = targetPos}).position).Unit
            
            -- Add wave motion
            local waveOffset = math.sin(snake.wavePhase - (i * 0.5)) * (snake.config.WAVE_AMPLITUDE or 1.2)
            local perpendicular = targetLook:Cross(Vector3.new(0, 1, 0))
            
            if perpendicular.Magnitude > 0.001 then
                perpendicular = perpendicular.Unit
                targetPos = targetPos + perpendicular * waveOffset * (1 - boneProgress * 0.5)
            end
            
            -- Calculate next position for look direction
            local nextHistoryIndex = math.min(historySize, historyIndex + 1)
            local nextData = snake.positionHistory[nextHistoryIndex]
            local lookAtPos = nextData and nextData.position or (targetPos + targetLook * 2)
            
            -- CREATE STABLE WORLD CFRAME (THIS IS THE FIX!)
            local worldCFrame = createStableCFrame(targetPos, lookAtPos)
            
            -- Convert to bone-local transform
            local meshCFrame = snake.meshPart.CFrame
            local localTransform = meshCFrame:Inverse() * worldCFrame
            
            -- Apply smoothing (FIXES JITTER)
            if self.previousBoneTransforms[i] then
                localTransform = dampCFrame(
                    self.previousBoneTransforms[i], 
                    localTransform, 
                    self.smoothingFactor, 
                    deltaTime
                )
            end
            
            -- Store for next frame
            self.previousBoneTransforms[i] = localTransform
            
            -- Apply tapering
            local scaleFactor = 1 - (boneProgress * 0.3)
            
            -- Apply transform to bone
            if snake.originalBoneTransforms and snake.originalBoneTransforms[i] then
                bone.Transform = snake.originalBoneTransforms[i] * 
                               CFrame.new(localTransform.Position * scaleFactor * 0.1) * 
                               (localTransform - localTransform.Position)
            else
                bone.Transform = localTransform
            end
        end
    end
end

-- Hook into the snake's update method
function Integration:hookUpdate()
    local snake = self.snake
    
    -- Replace the updateBones method with our fixed version
    snake.updateBonesOriginal = snake.updateBones
    snake.updateBones = function(...)
        self:updateBonesFixed(...)
    end
    
    -- If on client and local player, use PreRender for smoothness
    if RunService:IsClient() and snake.isLocalPlayer then
        self.renderConnection = RunService.PreRender:Connect(function(dt)
            self:updateBonesFixed(dt)
        end)
    end
end

-- Cleanup
function Integration:destroy()
    if self.renderConnection then
        self.renderConnection:Disconnect()
    end
    
    -- Restore original method
    if self.snake and self.snake.updateBonesOriginal then
        self.snake.updateBones = self.snake.updateBonesOriginal
    end
end

-- EASY USAGE: Just require this after creating your snake!
Integration.ApplyToSnake = function(snakeInstance)
    return Integration.new(snakeInstance)
end

-- Manual utilities if needed
Integration.CreateStableCFrame = createStableCFrame
Integration.DampCFrame = dampCFrame

return Integration