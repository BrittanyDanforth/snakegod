-- THIS IS THE ENTIRE SCRIPT FOR: StarterPlayer > StarterPlayerScripts > ClientSnakeController
-- Enhanced with zero-lag client-side prediction movement system

print("[Client] ClientSnakeController started - Enhanced Movement System")

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local RunService = game:GetService("RunService")
local HttpService = game:GetService("HttpService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

-- Get the module
local OptimizedSnakeSystemV9 = require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV9"))

-- Initialize the system on the client
if OptimizedSnakeSystemV9.init then
    OptimizedSnakeSystemV9.init()
end

local player = Players.LocalPlayer
local Camera = workspace.CurrentCamera
local mouse = player:GetMouse()
local snakeVisuals = nil -- Variable to hold our snake instance

-- Create/get remote for sending input to server
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
local mouseDirectionRemote = nil
local boostRemote = nil
if remoteEvents then
    mouseDirectionRemote = remoteEvents:FindFirstChild("UpdateMouseDirection") or remoteEvents:WaitForChild("UpdateMouseDirection", 5)
    boostRemote = remoteEvents:FindFirstChild("UpdateBoostState")
else
    warn("[Client] RemoteEvents folder not found!")
end

-- ===================================================================
--  ADVANCED MOVEMENT CONFIGURATION
-- ===================================================================
local Config = {
    BaseSpeed = 35,
    BoostSpeed = 55,
    TurnSpeed = 4.5,
    CrawlSpeed = 15,
    SlowSpeed = 25,
    SuperSpeed = 65,
    LudicrousSpeed = 90,
    PathSmoothness = 0.85,
    UpdateRate = 60, -- 60 FPS for buttery smooth movement
    NetworkUpdateRate = 30 -- Send to server at 30Hz
}

-- Movement control state
local movementEnabled = true
local heartbeatConnection = nil
local inputBeganConnection = nil
local inputEndedConnection = nil
local diedConnection = nil

-- ===================================================================
--  PATH SYSTEM FOR SMOOTH SNAKE BODY MOVEMENT
-- ===================================================================
local PathSystem = {}
PathSystem.__index = PathSystem

function PathSystem.new()
    return setmetatable({
        pathPoints = {},
        totalDistance = 0,
        segmentSpacing = 3.2, -- Will be updated from config
        lastRecordedPos = nil,
        minRecordDistance = 0.5,
        pointCount = 0,
        maxPoints = 350,
        lastUpdate = 0,
        updateInterval = 1/60, -- 60 FPS recording
    }, PathSystem)
end

function PathSystem:recordPoint(position, speed, time)
    -- Only record if we've moved enough
    if self.lastRecordedPos and (position - self.lastRecordedPos).Magnitude < self.minRecordDistance then
        return
    end
    
    -- Calculate distance from last point
    local distanceFromLast = 0
    if #self.pathPoints > 0 then
        distanceFromLast = (position - self.pathPoints[#self.pathPoints].position).Magnitude
    end
    
    -- Create path point
    local pathPoint = {
        position = position,
        speed = speed,
        time = time,
        distanceFromStart = self.totalDistance + distanceFromLast,
        index = #self.pathPoints + 1
    }
    
    -- Add to path
    table.insert(self.pathPoints, pathPoint)
    self.totalDistance = pathPoint.distanceFromStart
    self.pointCount = #self.pathPoints
    
    -- Maintain max points
    if self.pointCount > self.maxPoints then
        table.remove(self.pathPoints, 1)
        -- Update indices
        for i = 1, #self.pathPoints do
            self.pathPoints[i].index = i
        end
    end
    
    self.lastRecordedPos = position
end

function PathSystem:getPositionAtDistance(targetDistance)
    if #self.pathPoints == 0 then return nil end
    
    -- Clamp distance
    targetDistance = math.max(0, math.min(targetDistance, self.totalDistance))
    
    -- Handle edge cases
    if targetDistance <= 0 then
        local first = self.pathPoints[1]
        return {
            position = first.position,
            direction = (#self.pathPoints > 1) and (self.pathPoints[2].position - first.position).Unit or Vector3.new(0,0,-1),
            speed = first.speed
        }
    end
    
    if targetDistance >= self.totalDistance then
        local last = self.pathPoints[#self.pathPoints]
        return {
            position = last.position,
            direction = (#self.pathPoints > 1) and (last.position - self.pathPoints[#self.pathPoints - 1].position).Unit or Vector3.new(0,0,-1),
            speed = last.speed
        }
    end
    
    -- Binary search for the right segment
    local left, right = 1, #self.pathPoints
    while left < right do
        local mid = math.floor((left + right) / 2)
        if self.pathPoints[mid].distanceFromStart < targetDistance then
            left = mid + 1
        else
            right = mid
        end
    end
    
    -- Get interpolation points
    local index = math.max(1, left - 1)
    local p1 = self.pathPoints[index]
    local p2 = self.pathPoints[math.min(index + 1, #self.pathPoints)]
    
    -- Calculate interpolation factor
    local segmentDistance = p2.distanceFromStart - p1.distanceFromStart
    local t = (segmentDistance > 0) and ((targetDistance - p1.distanceFromStart) / segmentDistance) or 0
    
    -- Interpolate position
    local position = p1.position:Lerp(p2.position, t)
    
    -- Calculate direction
    local direction = (p2.position - p1.position).Unit
    if direction.Magnitude < 0.1 then
        direction = Vector3.new(0,0,-1)
    end
    
    return {
        position = position,
        direction = direction,
        speed = p1.speed + (p2.speed - p1.speed) * t
    }
end

-- ===================================================================
--  CLEANUP FUNCTION
-- ===================================================================
local function cleanupSnake()
    print("🧹 Cleaning up old snake instance...")
    if heartbeatConnection then
        heartbeatConnection:Disconnect()
        heartbeatConnection = nil
    end
    if inputBeganConnection then
        inputBeganConnection:Disconnect()
        inputBeganConnection = nil
    end
    if inputEndedConnection then
        inputEndedConnection:Disconnect()
        inputEndedConnection = nil
    end
    if diedConnection then
        diedConnection:Disconnect()
        diedConnection = nil
    end
    
    -- Clear globals
    _G.GetSnakePoint = nil
    _G.GetSnakePointRaw = nil
    _G.SnakePathSystem = nil
    _G.SnakeSpeed = nil
    _G.SnakeState = nil
end

-- ===================================================================
--  MAIN SETUP FUNCTION
-- ===================================================================
local function setupSnake(character)
    cleanupSnake()
    print("[Client] Character detected:", character.Name, ". Setting up enhanced snake...")
    
    -- Reset movement when spawning
    movementEnabled = true
    
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")
    
    -- If there's an old snake, destroy it first
    if snakeVisuals and typeof(snakeVisuals.destroy) == "function" then
        print("[Client] Destroying old snake visuals.")
        snakeVisuals:destroy()
        snakeVisuals = nil
    end
    
    -- Wait for server config
    print("[Client] Waiting for SnakeConfig attribute from server...")
    local configJson = character:GetAttribute("SnakeConfig")
    if not configJson then
        local connection
        connection = character:GetAttributeChangedSignal("SnakeConfig"):Connect(function()
            configJson = character:GetAttribute("SnakeConfig")
            if configJson then
                connection:Disconnect()
            end
        end)
        
        local startTime = tick()
        while not configJson and tick() - startTime < 5 do
            wait(0.1)
            configJson = character:GetAttribute("SnakeConfig")
        end
        
        if connection then
            connection:Disconnect()
        end
    end
    
    if not configJson then
        warn("[Client] Timeout waiting for SnakeConfig from server!")
        return
    end
    
    print("[Client] Received SnakeConfig from server.")
    
    -- Decode and fix config
    local decodedConfig = HttpService:JSONDecode(configJson)
    if not decodedConfig then
        warn("[Client] FAILED to decode snake config!")
        return
    end
    
    -- Fix Color3 values
    local snakeConfig = {
        InitialLength = decodedConfig.InitialLength,
        MaxSegments = decodedConfig.MaxSegments,
        SegmentSpacing = decodedConfig.SegmentSpacing,
        SegmentSize = decodedConfig.SegmentSize and Vector3.new(decodedConfig.SegmentSize.X, decodedConfig.SegmentSize.Y, decodedConfig.SegmentSize.Z),
        HeadSize = decodedConfig.HeadSize and Vector3.new(decodedConfig.HeadSize.X, decodedConfig.HeadSize.Y, decodedConfig.HeadSize.Z),
        HeadMaterial = decodedConfig.HeadMaterial,
        BodyMaterial = decodedConfig.BodyMaterial,
        GlowIntensity = decodedConfig.GlowIntensity,
        GlowRange = decodedConfig.GlowRange,
        HeadColor = decodedConfig.HeadColor and Color3.new(decodedConfig.HeadColor.R, decodedConfig.HeadColor.G, decodedConfig.HeadColor.B),
        BodyColors = {}
    }
    
    -- Convert body colors
    if decodedConfig.BodyColors then
        for i, colorData in ipairs(decodedConfig.BodyColors) do
            snakeConfig.BodyColors[i] = Color3.new(colorData.R, colorData.G, colorData.B)
        end
    end
    
    -- Create snake visuals
    snakeVisuals = OptimizedSnakeSystemV9.createSnake(character, snakeConfig)
    
    if snakeVisuals then
        print("[Client] Snake visuals created successfully with length:", snakeConfig.InitialLength)
        
        -- Listen for config updates
        character:GetAttributeChangedSignal("SnakeConfig"):Connect(function()
            local newConfigJson = character:GetAttribute("SnakeConfig")
            if newConfigJson and snakeVisuals then
                local newDecodedConfig = HttpService:JSONDecode(newConfigJson)
                local newConfig = {
                    HeadColor = newDecodedConfig.HeadColor and Color3.new(newDecodedConfig.HeadColor.R, newDecodedConfig.HeadColor.G, newDecodedConfig.HeadColor.B),
                    BodyColors = {}
                }
                if newDecodedConfig.BodyColors then
                    for i, colorData in ipairs(newDecodedConfig.BodyColors) do
                        newConfig.BodyColors[i] = Color3.new(colorData.R, colorData.G, colorData.B)
                    end
                end
                if snakeVisuals.updateConfig then
                    snakeVisuals:updateConfig(newConfig)
                end
            end
        end)
        
        -- Listen for length updates
        character:GetAttributeChangedSignal("SnakeLength"):Connect(function()
            local newLength = character:GetAttribute("SnakeLength")
            if newLength and snakeVisuals and snakeVisuals.updateLength then
                snakeVisuals:updateLength(newLength)
            end
        end)
    else
        warn("[Client] FAILED to create snake visuals!")
        return
    end
    
    -- ===================================================================
    --  ENHANCED MOVEMENT SYSTEM
    -- ===================================================================
    
    -- Create path system
    local pathSystem = PathSystem.new()
    pathSystem.segmentSpacing = snakeConfig.SegmentSpacing or 3.2
    
    -- Movement state
    local State = {
        currentSpeed = Config.BaseSpeed,
        targetSpeed = Config.BaseSpeed,
        speedMode = "normal",
        boosting = false,
        smoothSpeed = Config.BaseSpeed,
        currentDirection = Vector3.new(0, 0, -1), -- Forward
        targetDirection = Vector3.new(0, 0, -1),
        wallStuckTime = 0,
        lastPosition = rootPart.Position,
        speedMultiplier = player:GetAttribute("SpeedMultiplier") or 1,
        tempSpeedMultiplier = 1
    }
    
    -- Export globals for other systems
    _G.GetSnakePoint = function(distance)
        return pathSystem:getPositionAtDistance(distance)
    end
    _G.GetSnakePointRaw = _G.GetSnakePoint
    _G.SnakePathSystem = pathSystem
    _G.SnakeSpeed = State.currentSpeed
    _G.SnakeState = State
    
    -- Setup character for movement
    humanoid.WalkSpeed = 0
    humanoid.JumpPower = 0
    humanoid.JumpHeight = 0
    humanoid.AutoRotate = false
    
    -- Speed modes
    local speedModes = {
        crawl = Config.CrawlSpeed,
        slow = Config.SlowSpeed,
        normal = Config.BaseSpeed,
        super = Config.SuperSpeed,
        ludicrous = Config.LudicrousSpeed
    }
    
    local function setSpeedMode(mode)
        State.speedMode = mode
        State.targetSpeed = speedModes[mode] or Config.BaseSpeed
        
        -- Visual feedback
        local color = snakeConfig.HeadColor
        if mode == "super" then
            color = Color3.fromRGB(255, 255, 0)
        elseif mode == "ludicrous" then
            color = Color3.fromRGB(255, 0, 0)
        end
        
        -- Flash effect
        local flash = Instance.new("Part")
        flash.Shape = Enum.PartType.Ball
        flash.Size = (snakeConfig.HeadSize or Vector3.new(4.5, 4.5, 4.5)) * 2
        flash.Material = Enum.Material.ForceField
        flash.Color = color
        flash.Transparency = 0.4
        flash.CanCollide = false
        flash.Anchored = true
        flash.Position = rootPart.Position
        flash.Parent = workspace
        
        local flashTween = TweenService:Create(flash,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad),
            {Size = flash.Size * 2, Transparency = 1}
        )
        flashTween:Play()
        Debris:AddItem(flash, 0.3)
    end
    
    -- Input handling
    local keybinds = {
        [Enum.KeyCode.F1] = function() setSpeedMode("normal") end,
        [Enum.KeyCode.F2] = function() setSpeedMode("super") end,
        [Enum.KeyCode.F3] = function() setSpeedMode("slow") end,
        [Enum.KeyCode.F4] = function() setSpeedMode("ludicrous") end,
        [Enum.KeyCode.F5] = function() setSpeedMode("crawl") end,
    }
    
    inputBeganConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        
        if keybinds[input.KeyCode] then
            keybinds[input.KeyCode]()
            return
        end
        
        -- Boost handling
        if input.KeyCode == Enum.KeyCode.LeftShift or input.UserInputType == Enum.UserInputType.MouseButton1 then
            State.boosting = true
            State.targetSpeed = Config.BoostSpeed
            
            -- Send boost state to server
            if boostRemote then
                boostRemote:FireServer(true)
            end
            
            -- Boost effect
            local boostEffect = Instance.new("ParticleEmitter")
            boostEffect.Name = "BoostEffect"
            boostEffect.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            boostEffect.Color = ColorSequence.new(snakeConfig.HeadColor or Color3.fromRGB(0, 255, 0))
            boostEffect.Rate = 60
            boostEffect.Lifetime = NumberRange.new(0.5)
            boostEffect.Speed = NumberRange.new(6)
            boostEffect.SpreadAngle = Vector2.new(35, 35)
            boostEffect.Parent = rootPart
        end
    end)
    
    inputEndedConnection = UserInputService.InputEnded:Connect(function(input)
        if input.KeyCode == Enum.KeyCode.LeftShift or input.UserInputType == Enum.UserInputType.MouseButton1 then
            State.boosting = false
            State.targetSpeed = speedModes[State.speedMode]
            
            -- Send boost state to server
            if boostRemote then
                boostRemote:FireServer(false)
            end
            
            local boostEffect = rootPart:FindFirstChild("BoostEffect")
            if boostEffect then
                boostEffect.Enabled = false
                Debris:AddItem(boostEffect, 0.8)
            end
        end
    end)
    
    -- Get mouse world position
    local function getMouseWorldPosition()
        local unitRay = Camera:ScreenPointToRay(mouse.X, mouse.Y)
        local planeY = rootPart.Position.Y
        local planeNormal = Vector3.new(0, 1, 0)
        local planePoint = Vector3.new(0, planeY, 0)
        
        local rayDirection = unitRay.Direction
        local rayOrigin = unitRay.Origin
        
        local denom = planeNormal:Dot(rayDirection)
        if math.abs(denom) > 1e-6 then
            local t = (planePoint - rayOrigin):Dot(planeNormal) / denom
            if t >= 0 then
                return rayOrigin + t * rayDirection
            end
        end
        
        -- Fallback
        local distance = 40
        local worldPoint = rayOrigin + rayDirection * distance
        return Vector3.new(worldPoint.X, planeY, worldPoint.Z)
    end
    
    -- ===================================================================
    --  MAIN MOVEMENT LOOP - ZERO LAG CLIENT PREDICTION
    -- ===================================================================
    local lastNetworkUpdate = 0
    local networkUpdateInterval = 1/Config.NetworkUpdateRate
    
    heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
        if not rootPart or not rootPart.Parent then
            cleanupSnake()
            return
        end
        
        if not movementEnabled then
            return
        end
        
        -- Get mouse target
        local mousePos = getMouseWorldPosition()
        local delta = mousePos - rootPart.Position
        delta = Vector3.new(delta.X, 0, delta.Z)
        
        if delta.Magnitude > 1.0 then
            State.targetDirection = delta.Unit
        end
        
        -- Smooth direction changes
        local turnRate = Config.TurnSpeed * deltaTime
        if State.wallStuckTime > 0 then
            turnRate = turnRate * 0.3
        end
        
        if State.targetDirection.Magnitude > 0.001 and State.currentDirection.Magnitude > 0.001 then
            local newDirection = State.currentDirection:Lerp(State.targetDirection, turnRate)
            if newDirection.Magnitude > 0.001 then
                State.currentDirection = newDirection.Unit
            end
        end
        
        -- Smooth speed changes
        local speedRate = 15 * deltaTime
        State.smoothSpeed = State.smoothSpeed + (State.targetSpeed - State.smoothSpeed) * speedRate
        
        -- Apply movement with multipliers
        local tempMultiplier = player:GetAttribute("TempSpeedMultiplier") or 1
        local actualSpeed = State.smoothSpeed * State.speedMultiplier * tempMultiplier
        local moveDistance = actualSpeed * deltaTime
        local newPosition = rootPart.Position + State.currentDirection * moveDistance
        
        -- Wall collision detection
        local raycastParams = RaycastParams.new()
        raycastParams.FilterType = Enum.RaycastFilterType.Blacklist
        raycastParams.FilterDescendantsInstances = {character}
        
        local checkDistance = moveDistance + 8
        local raycast = workspace:Raycast(rootPart.Position, State.currentDirection * checkDistance, raycastParams)
        
        if raycast and raycast.Instance then
            local hitPart = raycast.Instance
            if hitPart.Name:match("Wall") or hitPart.Name:match("Boundary") or (hitPart.CanCollide and hitPart.Parent ~= character) then
                local distanceToWall = raycast.Distance
                local safeDistance = 5
                
                if distanceToWall < safeDistance then
                    newPosition = rootPart.Position
                    local wallNormal = raycast.Normal
                    local awayFromWall = wallNormal * 10
                    local escapeDirection = (State.currentDirection + awayFromWall).Unit
                    State.targetDirection = escapeDirection
                    
                    if State.currentDirection:Dot(wallNormal) < -0.5 then
                        local rightVector = State.currentDirection:Cross(Vector3.new(0, 1, 0))
                        State.targetDirection = rightVector.Unit
                        State.currentDirection = State.targetDirection
                    end
                    
                    rootPart.AssemblyLinearVelocity = Vector3.zero
                    rootPart.AssemblyAngularVelocity = Vector3.zero
                elseif distanceToWall < safeDistance * 2 then
                    local wallNormal = raycast.Normal
                    local slideDirection = State.currentDirection - (State.currentDirection:Dot(wallNormal) * wallNormal)
                    if slideDirection.Magnitude > 0.1 then
                        slideDirection = slideDirection.Unit
                        State.targetDirection = slideDirection
                        newPosition = rootPart.Position + slideDirection * moveDistance * 0.7
                    end
                end
            end
        end
        
        -- Stuck detection
        local movementDelta = (newPosition - State.lastPosition).Magnitude
        if movementDelta < 0.1 and State.smoothSpeed > 5 then
            State.wallStuckTime = State.wallStuckTime + deltaTime
            if State.wallStuckTime > 0.5 then
                local escapeAngle = math.random() * math.pi * 2
                State.currentDirection = Vector3.new(math.sin(escapeAngle), 0, math.cos(escapeAngle)).Unit
                State.targetDirection = State.currentDirection
                newPosition = rootPart.Position + State.currentDirection * 5
                State.wallStuckTime = 0
            end
        else
            State.wallStuckTime = 0
        end
        State.lastPosition = newPosition
        
        -- Apply movement
        rootPart.AssemblyLinearVelocity = Vector3.zero
        rootPart.AssemblyAngularVelocity = Vector3.zero
        rootPart.CFrame = CFrame.lookAt(newPosition, newPosition + State.currentDirection)
        
        -- Record path for body
        pathSystem:recordPoint(rootPart.Position, State.smoothSpeed, tick())
        
        -- Update globals
        _G.SnakeSpeed = State.smoothSpeed
        
        -- Send to server periodically
        local currentTime = tick()
        if currentTime - lastNetworkUpdate > networkUpdateInterval then
            lastNetworkUpdate = currentTime
            
            -- Store locally
            character:SetAttribute("MouseDirection", State.targetDirection)
            
            -- Send to server with position for validation
            if mouseDirectionRemote then
                mouseDirectionRemote:FireServer(State.targetDirection)
            end
        end
    end)
    
    -- Connect death cleanup
    diedConnection = humanoid.Died:Connect(function()
        movementEnabled = false
        cleanupSnake()
    end)
    
    -- Initialize
    setSpeedMode("normal")
end

-- Connect character spawning
player.CharacterAdded:Connect(setupSnake)

-- Setup existing character
if player.Character then
    setupSnake(player.Character)
end

-- Setup death/revive remote handlers
local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
if remotes then
    local stopMovementRemote = remotes:FindFirstChild("StopSnakeMovement")
    local resumeMovementRemote = remotes:FindFirstChild("ResumeSnakeMovement")
    
    if stopMovementRemote then
        stopMovementRemote.OnClientEvent:Connect(function()
            print("🛑 Stopping snake movement - player died")
            movementEnabled = false
        end)
    end
    
    if resumeMovementRemote then
        resumeMovementRemote.OnClientEvent:Connect(function()
            print("▶️ Resuming snake movement - player revived")
            movementEnabled = true
        end)
    end
end

print("[Client] Enhanced ClientSnakeController loaded successfully!")