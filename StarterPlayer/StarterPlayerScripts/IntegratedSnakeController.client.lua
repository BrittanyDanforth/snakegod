-- 🚀 INTEGRATED SNAKE CONTROLLER - ZERO LAG MOVEMENT + VISUALS
-- Combines the advanced movement system with OptimizedSnakeSystemV9 visuals
-- Place in StarterPlayer/StarterPlayerScripts

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local HttpService = game:GetService("HttpService")

-- Get the visual module
local OptimizedSnakeSystemV9 = require(ReplicatedStorage:WaitForChild("OptimizedSnakeSystemV9"))

-- Initialize the visual system
if OptimizedSnakeSystemV9.init then
    OptimizedSnakeSystemV9.init()
end

-- 🔧 NETWORK-OPTIMIZED CONFIG SYSTEM
local Config = {}
local success, externalConfig = pcall(function()
    return require(game.ReplicatedStorage:WaitForChild("SnakeConfig"))
end)

if success and externalConfig then
    Config = externalConfig
    print("✅ External config loaded successfully")
else
    print("⚠️ External config not found using defaults")
    Config = {
        BaseSpeed = 50,
        BoostSpeed = 100,
        TurnSpeed = 5.1,
        CrawlSpeed = 8,
        SlowSpeed = 18,
        SuperSpeed = 55,
        LudicrousSpeed = 90,
        HeadSize = Vector3.new(2, 2, 2),
        HeadColor = Color3.fromRGB(0, 255, 0),
        SegmentSize = Vector3.new(1.5, 1.5, 1.5),
        SegmentColor = Color3.fromRGB(0, 200, 0),
        MaxSegments = 80,
        SegmentGap = 3.0,
        PathSmoothness = 0.85,
        UpdateRate = 30,
        LODDistance = 120
    }
end

-- Validate and optimize config
local function validateConfig()
    local defaults = {
        BaseSpeed = 35, BoostSpeed = 70, TurnSpeed = 4.5, SegmentGap = 3.0,
        HeadSize = Vector3.new(2, 2, 2), HeadColor = Color3.fromRGB(0, 255, 0),
        MaxSegments = 80, PathSmoothness = 0.85, UpdateRate = 30
    }
    for key, defaultValue in pairs(defaults) do
        if Config[key] == nil then
            Config[key] = defaultValue
            print("⚠️ Config missing " .. key .. ", using default")
        end
    end
end
validateConfig()

-- Player setup
local player = Players.LocalPlayer
local mouse = player:GetMouse()

-- Movement control state
local movementEnabled = true
local heartbeatConnection = nil
local snakeVisuals = nil -- Store visual snake instance

-- Get remotes
local remoteEvents = ReplicatedStorage:WaitForChild("RemoteEvents", 10)
local mouseDirectionRemote = remoteEvents and remoteEvents:FindFirstChild("UpdateMouseDirection")
local boostRemote = remoteEvents and remoteEvents:FindFirstChild("UpdateBoostState")

-- Setup remote event handlers for death/revive
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

-- 🎯 NETWORK-OPTIMIZED ZERO-GAP PATH SYSTEM
local PathSystem = {}
PathSystem.__index = PathSystem

function PathSystem.new()
    return setmetatable({
        pathPoints = {},
        totalDistance = 0,
        segmentSpacing = Config.SegmentGap,
        smoothingBuffer = {},
        smoothingRadius = 2.5,
        lastRecordedPos = nil,
        minRecordDistance = 0.5,
        networkUpdateCounter = 0,
        pointCount = 0,
        maxPoints = 250,
        interpolationCache = {},
        cacheSize = 150,
        cacheDirty = false,
        lastNetworkUpdate = 0,
        networkUpdateInterval = 1/30,
    }, PathSystem)
end

function PathSystem:recordPoint(position, speed, time)
    local dynamicInterval = speed > 50 and self.networkUpdateInterval * 0.5 or self.networkUpdateInterval
    
    if time - self.lastNetworkUpdate < dynamicInterval then
        return
    end
    
    local dynamicMinDistance = speed > 50 and self.minRecordDistance * 0.5 or self.minRecordDistance
    if self.lastRecordedPos and (position - self.lastRecordedPos).Magnitude < dynamicMinDistance then
        return
    end
    
    local distanceFromLast = 0
    if #self.pathPoints > 0 then
        distanceFromLast = (position - self.pathPoints[#self.pathPoints].position).Magnitude
    end
    
    local pathPoint = {
        position = position,
        speed = speed,
        time = time,
        distanceFromStart = self.totalDistance + distanceFromLast,
        index = #self.pathPoints + 1
    }
    
    table.insert(self.pathPoints, pathPoint)
    self.totalDistance = pathPoint.distanceFromStart
    self.pointCount = #self.pathPoints
    self.lastNetworkUpdate = time
    
    if self.pointCount > self.maxPoints then
        local removed = table.remove(self.pathPoints, 1)
        self.totalDistance = self.totalDistance - removed.distanceFromStart
        
        local startIdx = math.max(1, #self.pathPoints - 8)
        for i = startIdx, #self.pathPoints do
            self.pathPoints[i].index = i
        end
    end
    
    self.lastRecordedPos = position
    self.cacheDirty = true
end

function PathSystem:getPositionAtDistance(targetDistance)
    if #self.pathPoints == 0 then
        return nil
    end
    
    targetDistance = math.max(0, math.min(targetDistance, self.totalDistance))
    
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
    
    local left, right = 1, #self.pathPoints
    while left < right do
        local mid = math.floor((left + right) / 2)
        if self.pathPoints[mid].distanceFromStart < targetDistance then
            left = mid + 1
        else
            right = mid
        end
    end
    
    local index = math.max(1, left - 1)
    local p1 = self.pathPoints[index]
    local p2 = self.pathPoints[math.min(index + 1, #self.pathPoints)]
    
    local segmentDistance = p2.distanceFromStart - p1.distanceFromStart
    local t = (segmentDistance > 0) and ((targetDistance - p1.distanceFromStart) / segmentDistance) or 0
    
    local position = p1.position:Lerp(p2.position, t)
    
    local direction = (p2.position - p1.position).Unit
    if direction.Magnitude < 0.1 then
        direction = Vector3.new(0,0,-1)
    end
    
    local speed = p1.speed + (p2.speed - p1.speed) * t
    
    return {
        position = position,
        direction = direction,
        speed = speed,
        t = t,
        segmentIndex = index
    }
end

function PathSystem:getSmoothedPositionAtDistance(targetDistance)
    local baseResult = self:getPositionAtDistance(targetDistance)
    if not baseResult then return nil end
    
    if #self.pathPoints < 3 then
        return baseResult
    end
    
    local segmentIndex = baseResult.segmentIndex or 1
    local prevIndex = math.max(1, segmentIndex - 1)
    local nextIndex = math.min(segmentIndex + 1, #self.pathPoints)
    
    if prevIndex == segmentIndex or nextIndex == segmentIndex then
        return baseResult
    end
    
    local p0 = self.pathPoints[prevIndex].position
    local p1 = self.pathPoints[segmentIndex].position
    local p2 = self.pathPoints[nextIndex].position
    
    local t = baseResult.t or 0
    local smoothedPosition = p0:Lerp(p1, 0.3):Lerp(p1:Lerp(p2, t), 0.7)
    
    return {
        position = smoothedPosition,
        direction = baseResult.direction,
        speed = baseResult.speed
    }
end

-- 🧹 SNAKE STATE & CONNECTION MANAGEMENT
local heartbeatConnection
local inputBeganConnection
local inputEndedConnection
local diedConnection

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
    
    -- Destroy visual snake
    if snakeVisuals and typeof(snakeVisuals.destroy) == "function" then
        snakeVisuals:destroy()
        snakeVisuals = nil
    end
    
    -- Clear global functions
    _G.GetSnakePoint = nil
    _G.GetSnakePointRaw = nil
    _G.SnakePathSystem = nil
    _G.SnakeSpeed = nil
    _G.SnakeState = nil
end

-- ✨ INITIALIZATION FUNCTION FOR A NEW SNAKE/CHARACTER
local function initializeForCharacter(character)
    cleanupSnake()
    print("🐍 Initializing integrated snake for character: " .. character.Name)
    
    -- Reset movement enabled when spawning
    movementEnabled = true
    
    local humanoid = character:WaitForChild("Humanoid")
    local rootPart = character:WaitForChild("HumanoidRootPart")
    local camera = workspace.CurrentCamera
    
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
    
    -- CREATE VISUAL SNAKE
    snakeVisuals = OptimizedSnakeSystemV9.createSnake(character, snakeConfig)
    
    if not snakeVisuals then
        warn("[Client] FAILED to create snake visuals!")
        return
    end
    
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
    
    -- Create a fresh path system and state for the new snake
    local pathSystem = PathSystem.new()
    
    -- 🎮 NETWORK-OPTIMIZED MOVEMENT STATE
    local initialDirection = Vector3.new(0, 0, -1) -- Forward direction
    local State = {
        currentSpeed = Config.BaseSpeed,
        targetSpeed = Config.BaseSpeed,
        speedMode = "normal",
        boosting = false,
        smoothSpeed = Config.BaseSpeed,
        currentDirection = initialDirection,
        targetDirection = initialDirection,
        debugMode = false,
        lastDebugUpdate = 0,
        speedMultiplier = player:GetAttribute("SpeedMultiplier") or 1,
        tempSpeedMultiplier = 1,
        wallStuckTime = 0,
        lastPosition = rootPart.Position,
        stats = {
            fps = 0,
            distance = 0,
            pathPoints = 0,
            totalDistance = 0
        }
    }
    
    -- 🌟 NETWORK-OPTIMIZED EXPORT FUNCTIONS
    _G.GetSnakePoint = function(distance)
        return pathSystem:getSmoothedPositionAtDistance(distance)
    end
    
    _G.GetSnakePointRaw = function(distance)
        return pathSystem:getPositionAtDistance(distance)
    end
    
    _G.SnakePathSystem = pathSystem
    _G.SnakeSpeed = State.currentSpeed
    _G.SnakeState = State
    
    -- 🎨 NETWORK-OPTIMIZED HEAD SETUP
    local function setupHead()
        humanoid.WalkSpeed = 0
        humanoid.JumpPower = 0
        humanoid.JumpHeight = 0
        humanoid.AutoRotate = false
        
        -- Keep rootPart invisible but functional for orb collection
        rootPart.Transparency = 1
        rootPart.CanCollide = false
        rootPart.CanTouch = true
        rootPart.Size = Config.HeadSize
        rootPart.Shape = Enum.PartType.Ball
        
        -- Hide body parts efficiently
        for _, part in pairs(character:GetChildren()) do
            if part:IsA("BasePart") and part ~= rootPart then
                part.Transparency = 1
                part.CanCollide = false
            elseif part:IsA("Accessory") or part:IsA("Decal") then
                part:Destroy()
            end
        end
    end
    
    -- 🚀 NETWORK-OPTIMIZED SPEED MODES
    local speedModes = {
        crawl = Config.CrawlSpeed or 15,
        slow = Config.SlowSpeed or 30,
        normal = Config.BaseSpeed,
        super = Config.SuperSpeed or 75,
        ludicrous = Config.LudicrousSpeed or 120
    }
    
    local function setSpeedMode(mode)
        State.speedMode = mode
        State.targetSpeed = speedModes[mode] or Config.BaseSpeed
        
        local color = Config.HeadColor
        if mode == "super" then
            color = Color3.fromRGB(255, 255, 0)
        elseif mode == "ludicrous" then
            color = Color3.fromRGB(255, 0, 0)
        end
        
        local flash = Instance.new("Part")
        flash.Shape = Enum.PartType.Ball
        flash.Size = Config.HeadSize * 2
        flash.Material = Enum.Material.ForceField
        flash.Color = color
        flash.Transparency = 0.4
        flash.CanCollide = false
        flash.Anchored = true
        flash.Position = rootPart.Position
        flash.Parent = workspace
        
        local flashTween = TweenService:Create(flash,
            TweenInfo.new(0.3, Enum.EasingStyle.Quad),
            {Size = Config.HeadSize * 4, Transparency = 1}
        )
        flashTween:Play()
        Debris:AddItem(flash, 0.3)
    end
    
    -- 🎮 NETWORK-OPTIMIZED INPUT HANDLING
    local keybinds = {
        [Enum.KeyCode.F1] = function() setSpeedMode("normal") end,
        [Enum.KeyCode.F2] = function() setSpeedMode("super") end,
        [Enum.KeyCode.F3] = function() setSpeedMode("slow") end,
        [Enum.KeyCode.F4] = function() setSpeedMode("ludicrous") end,
        [Enum.KeyCode.F5] = function() setSpeedMode("crawl") end,
        [Enum.KeyCode.F7] = function() 
            State.debugMode = not State.debugMode 
            print("🔍 Debug Mode:", State.debugMode and "ON" or "OFF")
        end,
    }
    
    inputBeganConnection = UserInputService.InputBegan:Connect(function(input, processed)
        if processed then return end
        
        if keybinds[input.KeyCode] then
            keybinds[input.KeyCode]()
            return
        end
        
        if input.KeyCode == Enum.KeyCode.LeftShift or input.UserInputType == Enum.UserInputType.MouseButton1 then
            State.boosting = true
            State.targetSpeed = Config.BoostSpeed
            
            -- Send boost state to server
            if boostRemote then
                boostRemote:FireServer(true)
            end
            
            local boostEffect = Instance.new("ParticleEmitter")
            boostEffect.Name = "BoostEffect"
            boostEffect.Texture = "rbxasset://textures/particles/sparkles_main.dds"
            boostEffect.Color = ColorSequence.new(Config.HeadColor)
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
    
    -- 🎯 NETWORK-OPTIMIZED MOUSE TRACKING
    local function getMouseWorldPosition()
        local unitRay = camera:ScreenPointToRay(mouse.X, mouse.Y)
        local planeY = rootPart.Position.Y
        local planeNormal = Vector3.new(0, 1, 0)
        local planePoint = Vector3.new(0, planeY, 0)
        
        local rayDirection = unitRay.Direction
        local rayOrigin = unitRay.Origin
        
        local denom = planeNormal:Dot(rayDirection)
        if math.abs(denom) > 1e-6 then
            local t = (planePoint - rayOrigin):Dot(planeNormal) / denom
            if t >= 0 then
                local intersection = rayOrigin + t * rayDirection
                return intersection
            end
        end
        
        local distance = 40
        local worldPoint = rayOrigin + rayDirection * distance
        return Vector3.new(worldPoint.X, planeY, worldPoint.Z)
    end
    
    -- 📊 NETWORK-OPTIMIZED FPS COUNTER
    local fpsCounter = {frames = 0, lastUpdate = tick()}
    local lastDebugTime = 0
    
    -- 🚀 NETWORK-OPTIMIZED MAIN MOVEMENT LOOP
    local lastPosition = rootPart.Position
    local updateCounter = 0
    local networkUpdateInterval = 1
    local lastNetworkUpdate = 0
    
    heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
        if not rootPart or not rootPart.Parent then
            cleanupSnake()
            return
        end
        
        if not movementEnabled then
            return
        end
        
        updateCounter = updateCounter + 1
        
        -- FPS tracking
        fpsCounter.frames = fpsCounter.frames + 1
        if tick() - fpsCounter.lastUpdate >= 1 then
            State.stats.fps = fpsCounter.frames
            fpsCounter.frames = 0
            fpsCounter.lastUpdate = tick()
        end
        
        -- Input handling
        if updateCounter % networkUpdateInterval == 0 then
            local mousePos = getMouseWorldPosition()
            local delta = mousePos - rootPart.Position
            delta = Vector3.new(delta.X, 0, delta.Z)
            
            if delta.Magnitude > 1.0 then
                local newTargetDir = delta.Unit
                if newTargetDir.Magnitude < 0.9 or newTargetDir.Magnitude > 1.1 then
                    newTargetDir = State.currentDirection
                end
                State.targetDirection = newTargetDir
            end
        end
        
        -- Smooth direction changes
        local turnRate = Config.TurnSpeed * dt * 0.9
        
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
        local speedRate = 15 * dt
        State.smoothSpeed = State.smoothSpeed + (State.targetSpeed - State.smoothSpeed) * speedRate
        
        -- Apply movement
        local tempMultiplier = player:GetAttribute("TempSpeedMultiplier") or 1
        local actualSpeed = State.smoothSpeed * State.speedMultiplier * tempMultiplier
        local moveDistance = actualSpeed * dt
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
                    
                    rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
                    rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
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
            State.wallStuckTime = State.wallStuckTime + dt
            
            if State.wallStuckTime > 0.5 then
                local escapeAngle = math.random() * math.pi * 2
                State.currentDirection = Vector3.new(math.sin(escapeAngle), 0, math.cos(escapeAngle)).Unit
                State.targetDirection = State.currentDirection
                newPosition = rootPart.Position + State.currentDirection * 5
                State.wallStuckTime = 0
                
                if State.debugMode then
                    warn("🔄 Stuck detected! Auto-escaping...")
                end
            end
        else
            State.wallStuckTime = 0
        end
        State.lastPosition = newPosition
        
        -- Apply movement
        rootPart.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        rootPart.AssemblyAngularVelocity = Vector3.new(0, 0, 0)
        rootPart.CFrame = CFrame.lookAt(newPosition, newPosition + State.currentDirection)
        
        -- Record path
        if updateCounter % networkUpdateInterval == 0 then
            pathSystem:recordPoint(rootPart.Position, State.smoothSpeed, tick())
        end
        
        -- Update globals
        _G.SnakeSpeed = State.smoothSpeed
        State.stats.distance = State.stats.distance + (rootPart.Position - lastPosition).Magnitude
        State.stats.pathPoints = pathSystem.pointCount
        State.stats.totalDistance = pathSystem.totalDistance
        lastPosition = rootPart.Position
        
        -- Send to server periodically
        local currentTime = tick()
        if currentTime - lastNetworkUpdate > 0.033 then -- 30Hz
            lastNetworkUpdate = currentTime
            
            -- Store locally
            character:SetAttribute("MouseDirection", State.targetDirection)
            
            -- Send to server
            if mouseDirectionRemote then
                mouseDirectionRemote:FireServer(State.targetDirection)
            end
        end
        
        -- Debug output
        if State.debugMode and tick() - lastDebugTime > 1 then
            lastDebugTime = tick()
            print(string.format(
                "📊 FPS: %d | Speed: %.1f | Distance: %.1fm | Path Points: %d | Total Distance: %.1fm",
                State.stats.fps,
                State.smoothSpeed,
                State.stats.distance,
                State.stats.pathPoints,
                State.stats.totalDistance
            ))
        end
    end)
    
    -- Connect cleanup to humanoid death
    diedConnection = humanoid.Died:Connect(cleanupSnake)
    
    -- Initialize
    setupHead()
    setSpeedMode("normal")
end

-- Main execution logic
player.CharacterAdded:Connect(initializeForCharacter)

if player.Character then
    initializeForCharacter(player.Character)
end

print("🚀 Integrated Snake Controller loaded - Zero lag movement + visuals!")