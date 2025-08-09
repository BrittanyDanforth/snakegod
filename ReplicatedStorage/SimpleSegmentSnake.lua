-- SimpleSegmentSnake.lua
-- Minimal, stable, non-stretching visual renderer using fixed segments
-- Follows the client PathSystem via _G.GetSnakePoint(distance)

local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")
local Players = game:GetService("Players")

local SimpleSegmentSnake = {}
SimpleSegmentSnake.__index = SimpleSegmentSnake

local DEFAULT_SEGMENT_SPACING = 3.2
local MAX_VISUAL_SEGMENTS = 600 -- hard cap to protect performance

local function createPart(name, size, color, material)
    local p = Instance.new("Part")
    p.Name = name
    p.Shape = Enum.PartType.Ball
    p.Size = size
    p.Color = color
    p.Material = material or Enum.Material.Neon
    p.Anchored = true
    p.CanCollide = false
    p.CanTouch = false
    p.CanQuery = false
    p.TopSurface = Enum.SurfaceType.Smooth
    p.BottomSurface = Enum.SurfaceType.Smooth
    return p
end

function SimpleSegmentSnake.new(character, config)
    local self = setmetatable({}, SimpleSegmentSnake)

    self.character = character
    self.player = Players:GetPlayerFromCharacter(character)
    self.config = config or {}
    self.segmentSpacing = self.config.SegmentSpacing or DEFAULT_SEGMENT_SPACING
    self.segmentSize = self.config.SegmentSize or Vector3.new(2.5, 2.5, 2.5)
    self.headSize = self.config.HeadSize or Vector3.new(3, 3, 3)
    self.headColor = self.config.HeadColor or Color3.fromRGB(76, 217, 100)
    self.bodyColors = self.config.BodyColors or {self.headColor}
    self.maxSegments = math.min(self.config.MaxSegments or 500, MAX_VISUAL_SEGMENTS)
    self.length = math.clamp(self.config.InitialLength or 85, 1, self.maxSegments)

    -- Create model
    self.model = Instance.new("Model")
    self.model.Name = "Snake_" .. (self.player and self.player.Name or "Player")
    self.model.Parent = Workspace

    -- Head
    self.head = createPart("Segment0_Head", self.headSize, self.headColor, self.config.HeadMaterial or Enum.Material.Neon)
    self.head.Parent = self.model

    -- Body container
    self.segments = {}

    -- Pre-create segments up to initial length
    self:_ensureSegmentCount(self.length)

    -- Start update loop
    self.updateConn = RunService.Heartbeat:Connect(function()
        self:_updateVisuals()
    end)

    return self
end

function SimpleSegmentSnake:_ensureSegmentCount(target)
    target = math.clamp(target, 1, self.maxSegments)
    -- Add segments if needed
    for i = #self.segments + 1, target do
        local color = self.bodyColors[((i - 1) % #self.bodyColors) + 1]
        local seg = createPart("Segment" .. i, self.segmentSize, color, self.config.BodyMaterial or Enum.Material.Neon)
        seg.Parent = self.model
        self.segments[i] = seg
    end
    -- Remove extra segments
    for i = #self.segments, target + 1, -1 do
        local seg = self.segments[i]
        if seg then seg:Destroy() end
        self.segments[i] = nil
    end
    self.length = target
end

function SimpleSegmentSnake:_getPoint(distance)
    local getter = _G.GetSnakePoint or _G.GetSnakePointRaw
    if not getter then return nil end
    return getter(distance)
end

function SimpleSegmentSnake:_updateVisuals()
    -- Head at distance 0
    local headData = self:_getPoint(0)
    if headData and headData.position and headData.direction then
        self.head.CFrame = CFrame.lookAt(headData.position, headData.position + headData.direction)
    end

    -- Body segments along the path
    local spacing = self.segmentSpacing
    for i = 1, self.length do
        local d = i * spacing
        local data = self:_getPoint(d)
        local seg = self.segments[i]
        if data and seg then
            seg.CFrame = CFrame.lookAt(data.position, data.position + data.direction)
        end
    end
end

function SimpleSegmentSnake:updateLength(newLength)
    if typeof(newLength) == "number" then
        self:_ensureSegmentCount(newLength)
    end
end

function SimpleSegmentSnake:updateConfig(newConfig)
    if typeof(newConfig) ~= "table" then return end
    if newConfig.HeadColor then
        self.headColor = newConfig.HeadColor
        if self.head then self.head.Color = newConfig.HeadColor end
    end
    if newConfig.BodyColors and #newConfig.BodyColors > 0 then
        self.bodyColors = newConfig.BodyColors
        -- Recolor existing segments
        for i, seg in ipairs(self.segments) do
            if seg then
                seg.Color = self.bodyColors[((i - 1) % #self.bodyColors) + 1]
            end
        end
    end
end

function SimpleSegmentSnake:destroy()
    if self.updateConn then self.updateConn:Disconnect() end
    if self.model then self.model:Destroy() end
    self.segments = nil
end

local M = {}
function M.createSnake(character, config)
    return SimpleSegmentSnake.new(character, config)
end
return M