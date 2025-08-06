--[[
    Server Snake System
    This handles the game logic for snakes without any visual components
    Visual rendering is handled entirely by the client
]]

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local ServerSnakeSystem = {}
ServerSnakeSystem.__index = ServerSnakeSystem

-- Constants
local SEGMENT_SPACING = 3.2
local BASE_SPEED = 60
local BOOST_SPEED = 100
local TURN_SPEED = 3.5

function ServerSnakeSystem.new(character, config)
    local self = setmetatable({}, ServerSnakeSystem)
    
    self.character = character
    self.player = Players:GetPlayerFromCharacter(character)
    self.humanoid = character:WaitForChild("Humanoid")
    self.rootPart = character:WaitForChild("HumanoidRootPart")
    
    -- Game state
    self.config = config
    self.length = config.InitialLength or 85
    self.segments = {}
    self.isAlive = true
    self.isBoosting = false
    self.speed = BASE_SPEED
    
    -- Movement
    self.targetDirection = Vector3.new(1, 0, 0)
    self.currentDirection = Vector3.new(1, 0, 0)
    
    -- Initialize segments (just positions, no parts)
    for i = 0, self.length do
        self.segments[i] = {
            position = self.rootPart.Position - (self.currentDirection * i * SEGMENT_SPACING),
            index = i
        }
    end
    
    -- Create collision box for the head
    self:setupHeadCollision()
    
    -- Start update loop
    self:startUpdateLoop()
    
    return self
end

function ServerSnakeSystem:setupHeadCollision()
    -- Create an invisible part for collision detection
    local headPart = Instance.new("Part")
    headPart.Name = "SnakeHead"
    headPart.Size = Vector3.new(6, 6, 6)
    headPart.CanCollide = false
    headPart.Transparency = 1
    headPart.Parent = self.character
    
    -- Weld to root part
    local weld = Instance.new("WeldConstraint")
    weld.Part0 = headPart
    weld.Part1 = self.rootPart
    weld.Parent = headPart
    
    self.headPart = headPart
end

function ServerSnakeSystem:startUpdateLoop()
    self.updateConnection = RunService.Heartbeat:Connect(function(dt)
        if not self.isAlive then return end
        
        self:updateMovement(dt)
        self:updateSegments()
        self:syncWithClient()
    end)
end

function ServerSnakeSystem:updateMovement(dt)
    -- Get mouse direction from client
    local mouseDir = self.character:GetAttribute("MouseDirection")
    if mouseDir then
        self.targetDirection = Vector3.new(mouseDir.X, 0, mouseDir.Z).Unit
    end
    
    -- Smooth turn
    self.currentDirection = self.currentDirection:Lerp(self.targetDirection, TURN_SPEED * dt)
    self.currentDirection = self.currentDirection.Unit
    
    -- Move forward
    local moveSpeed = self.isBoosting and BOOST_SPEED or self.speed
    local newPosition = self.rootPart.Position + (self.currentDirection * moveSpeed * dt)
    
    -- Keep at ground level
    newPosition = Vector3.new(newPosition.X, 5, newPosition.Z)
    
    self.rootPart.CFrame = CFrame.lookAt(newPosition, newPosition + self.currentDirection)
end

function ServerSnakeSystem:updateSegments()
    -- Update head position
    self.segments[0].position = self.rootPart.Position
    
    -- Each segment follows the one in front
    for i = 1, self.length do
        local prevSegment = self.segments[i - 1]
        local currentSegment = self.segments[i]
        
        local direction = (prevSegment.position - currentSegment.position).Unit
        local targetPos = prevSegment.position - (direction * SEGMENT_SPACING)
        
        currentSegment.position = currentSegment.position:Lerp(targetPos, 0.8)
    end
end

function ServerSnakeSystem:syncWithClient()
    -- Send critical positions to client via attributes
    -- We'll send head + every 5th segment to reduce data
    local syncData = {
        head = {self.rootPart.Position.X, self.rootPart.Position.Y, self.rootPart.Position.Z},
        segments = {}
    }
    
    for i = 5, math.min(self.length, 50), 5 do
        local seg = self.segments[i]
        if seg then
            table.insert(syncData.segments, {
                i,
                seg.position.X,
                seg.position.Y,
                seg.position.Z
            })
        end
    end
    
    self.character:SetAttribute("SnakeSyncData", game:GetService("HttpService"):JSONEncode(syncData))
end

function ServerSnakeSystem:updateLength(newLength)
    if newLength > self.length then
        -- Add segments
        for i = self.length + 1, newLength do
            local lastSegment = self.segments[i - 1]
            self.segments[i] = {
                position = lastSegment.position,
                index = i
            }
        end
    end
    
    self.length = newLength
    self.character:SetAttribute("SnakeLength", newLength)
end

function ServerSnakeSystem:setBoosting(boosting)
    self.isBoosting = boosting
    self.character:SetAttribute("IsBoosting", boosting)
end

function ServerSnakeSystem:destroy()
    if self.updateConnection then
        self.updateConnection:Disconnect()
    end
    
    if self.headPart then
        self.headPart:Destroy()
    end
    
    self.isAlive = false
end

return ServerSnakeSystem