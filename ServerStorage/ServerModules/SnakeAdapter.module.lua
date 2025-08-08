--[[
    SnakeAdapter.module - Integration layer between existing snake system and new architecture
    Provides compatibility with OptimizedSnakeSystemV9
]]

local CollectionService = game:GetService("CollectionService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

-- Bootstrap: ensure a mesh template exists in ReplicatedStorage for clients
local function ensureSnakeTemplate()
    if not RunService:IsServer() then return end
    if ReplicatedStorage:FindFirstChild("SkinnedSnakeTemplate") then return end

    local ok, err = pcall(function()
        local container = Instance.new("Model")
        container.Name = "SkinnedSnakeTemplate"
        container.Parent = ReplicatedStorage

        local mesh = Instance.new("MeshPart")
        mesh.Name = "SnakeBody"
        mesh.CanCollide = false
        mesh.CanQuery = false
        mesh.Anchored = true
        mesh.Parent = container
        mesh.MeshId = "rbxassetid://84274514316556"
    end)
    if not ok then
        warn("[SnakeAdapter] Failed to create SkinnedSnakeTemplate:", err)
    end
end

ensureSnakeTemplate()

local SnakeAdapter = {}
SnakeAdapter.__index = SnakeAdapter

-- Create a snake instance compatible with the existing system
function SnakeAdapter.createSnake(player, config)
    -- Try to use the existing snake system
    local snakeSystemModule = ReplicatedStorage:FindFirstChild("OptimizedSnakeSystemV9")
    if not snakeSystemModule then
        warn("OptimizedSnakeSystemV9 not found, using fallback")
        return SnakeAdapter.createFallbackSnake(player, config)
    end
    
    local SnakeSystem = require(snakeSystemModule)
    
    -- Create snake with existing system
    local snakeData = {
        player = player,
        position = config.position or Vector3.new(0, 5, 0),
        length = config.length or 3,
        speed = config.speed or 16,
        color = config.color or Color3.new(0, 1, 0)
    }
    
    -- Create snake instance
    local snake = SnakeSystem.new(player)
    
    -- Ensure snake has required properties
    if not snake.model then
        snake.model = Instance.new("Model")
        snake.model.Name = player.Name .. "_Snake"
        snake.model.Parent = workspace
    end
    
    -- Tag snake parts for collision system
    SnakeAdapter.tagSnakeParts(snake, player)
    
    -- Add destroy method if not present
    if not snake.destroy then
        snake.destroy = function(self)
            if self.model then
                self.model:Destroy()
            end
            -- Clean up any connections
            if self.connections then
                for _, conn in pairs(self.connections) do
                    conn:Disconnect()
                end
            end
        end
    end
    
    return snake
end

-- Fallback snake creation if OptimizedSnakeSystemV9 is not available
function SnakeAdapter.createFallbackSnake(player, config)
    local snake = {
        player = player,
        segments = {},
        model = Instance.new("Model"),
        length = config.length or 3,
        speed = config.speed or 16
    }
    
    snake.model.Name = player.Name .. "_Snake"
    snake.model.Parent = workspace
    
    -- Create head
    local head = Instance.new("Part")
    head.Name = "Head"
    head.Size = Vector3.new(4, 4, 4)
    head.Shape = Enum.PartType.Ball
    head.TopSurface = Enum.SurfaceType.Smooth
    head.BottomSurface = Enum.SurfaceType.Smooth
    head.Color = config.color or Color3.new(0, 1, 0)
    head.Material = Enum.Material.Neon
    head.Position = config.position or Vector3.new(0, 5, 0)
    head.Parent = snake.model
    
    -- Tag the head
    CollectionService:AddTag(head, "SnakeHead")
    CollectionService:AddTag(head, "SnakeBody")
    CollectionService:AddTag(head, "PlayerID_" .. player.UserId)
    
    -- Create initial segments
    for i = 1, snake.length - 1 do
        local segment = Instance.new("Part")
        segment.Name = "Segment" .. i
        segment.Size = Vector3.new(3.5, 3.5, 3.5)
        segment.Shape = Enum.PartType.Ball
        segment.TopSurface = Enum.SurfaceType.Smooth
        segment.BottomSurface = Enum.SurfaceType.Smooth
        segment.Color = config.color or Color3.new(0, 1, 0)
        segment.Material = Enum.Material.Neon
        segment.Position = config.position - Vector3.new(0, 0, i * 3.5)
        segment.Parent = snake.model
        segment:SetAttribute("SegmentIndex", i)
        
        -- Tag the segment
        CollectionService:AddTag(segment, "SnakeBody")
        CollectionService:AddTag(segment, "PlayerID_" .. player.UserId)
        
        table.insert(snake.segments, segment)
    end
    
    -- Add required methods
    function snake:destroy()
        if self.model then
            self.model:Destroy()
        end
    end
    
    function snake:addSegment()
        local lastSegment = self.segments[#self.segments] or self.model.Head
        local newSegment = Instance.new("Part")
        newSegment.Name = "Segment" .. (#self.segments + 1)
        newSegment.Size = Vector3.new(3.5, 3.5, 3.5)
        newSegment.Shape = Enum.PartType.Ball
        newSegment.TopSurface = Enum.SurfaceType.Smooth
        newSegment.BottomSurface = Enum.SurfaceType.Smooth
        newSegment.Color = lastSegment.Color
        newSegment.Material = Enum.Material.Neon
        newSegment.Position = lastSegment.Position
        newSegment.Parent = self.model
        newSegment:SetAttribute("SegmentIndex", #self.segments + 1)
        
        -- Tag the segment
        CollectionService:AddTag(newSegment, "SnakeBody")
        CollectionService:AddTag(newSegment, "PlayerID_" .. self.player.UserId)
        
        table.insert(self.segments, newSegment)
        self.length = self.length + 1
    end
    
    return snake
end

-- Tag all parts of an existing snake for the collision system
function SnakeAdapter.tagSnakeParts(snake, player)
    if not snake.model then return end
    
    local playerTag = "PlayerID_" .. player.UserId
    
    -- Tag the head
    local head = snake.model:FindFirstChild("Head")
    if head then
        CollectionService:AddTag(head, "SnakeHead")
        CollectionService:AddTag(head, "SnakeBody")
        CollectionService:AddTag(head, playerTag)
    end
    
    -- Tag all segments
    local segmentIndex = 1
    for _, part in ipairs(snake.model:GetDescendants()) do
        if part:IsA("BasePart") and part.Name ~= "Head" then
            CollectionService:AddTag(part, "SnakeBody")
            CollectionService:AddTag(part, playerTag)
            
            -- Set segment index for self-collision detection
            if part.Name:match("Segment") then
                part:SetAttribute("SegmentIndex", segmentIndex)
                segmentIndex = segmentIndex + 1
            end
        end
    end
end

-- Remove all tags from a snake
function SnakeAdapter.cleanupSnakeTags(snake, player)
    if not snake.model then return end
    
    local playerTag = "PlayerID_" .. player.UserId
    
    for _, part in ipairs(snake.model:GetDescendants()) do
        if part:IsA("BasePart") then
            CollectionService:RemoveTag(part, "SnakeHead")
            CollectionService:RemoveTag(part, "SnakeBody")
            CollectionService:RemoveTag(part, playerTag)
        end
    end
end

-- Update snake movement (to be called from AliveState if needed)
function SnakeAdapter.updateMovement(snake, direction, deltaTime)
    if not snake.model then return end
    
    local head = snake.model:FindFirstChild("Head")
    if not head then return end
    
    -- Simple movement logic if the existing system doesn't handle it
    local speed = snake.speed or 16
    local moveVector = direction * speed * deltaTime
    
    -- Move head
    head.CFrame = head.CFrame + moveVector
    
    -- Update segments to follow
    -- This is simplified - the actual snake system should handle this
end

return SnakeAdapter