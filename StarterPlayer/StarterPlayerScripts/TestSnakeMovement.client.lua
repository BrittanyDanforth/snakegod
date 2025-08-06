-- Test script to verify enhanced snake movement system
-- This can be deleted after testing

local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local player = Players.LocalPlayer

-- Wait a bit for everything to initialize
wait(3)

print("=== SNAKE MOVEMENT SYSTEM TEST ===")

-- Check if globals are set
local function checkGlobals()
    print("\n📊 Checking Global Functions:")
    print("_G.GetSnakePoint:", _G.GetSnakePoint and "✅ Available" or "❌ Missing")
    print("_G.GetSnakePointRaw:", _G.GetSnakePointRaw and "✅ Available" or "❌ Missing")
    print("_G.SnakePathSystem:", _G.SnakePathSystem and "✅ Available" or "❌ Missing")
    print("_G.SnakeSpeed:", _G.SnakeSpeed and ("✅ " .. tostring(_G.SnakeSpeed)) or "❌ Missing")
    print("_G.SnakeState:", _G.SnakeState and "✅ Available" or "❌ Missing")
end

-- Monitor speed and movement
local function monitorMovement()
    print("\n🚀 Movement Monitoring Started")
    local startTime = tick()
    local lastPos = nil
    
    for i = 1, 10 do
        wait(0.5)
        
        if player.Character and player.Character:FindFirstChild("HumanoidRootPart") then
            local rootPart = player.Character.HumanoidRootPart
            local currentPos = rootPart.Position
            
            if lastPos then
                local distance = (currentPos - lastPos).Magnitude
                local speed = distance / 0.5
                print(string.format("Frame %d: Speed = %.1f studs/sec | Current Speed: %.1f", 
                    i, speed, _G.SnakeSpeed or 0))
            end
            
            lastPos = currentPos
        end
    end
end

-- Test path system
local function testPathSystem()
    print("\n🛤️ Testing Path System:")
    if _G.SnakePathSystem then
        print("Path points:", _G.SnakePathSystem.pointCount)
        print("Total distance:", _G.SnakePathSystem.totalDistance)
        
        -- Test getting positions
        for i = 1, 5 do
            local distance = i * 10
            local point = _G.GetSnakePoint(distance)
            if point then
                print(string.format("Point at distance %d: Position = %s", 
                    distance, tostring(point.position)))
            end
        end
    else
        print("❌ Path system not available")
    end
end

-- Run tests
checkGlobals()
wait(2)
monitorMovement()
wait(1)
testPathSystem()

print("\n=== TEST COMPLETE ===")
print("Press F1-F5 to test speed modes")
print("Hold Shift or Mouse Button to boost")
print("Move mouse to control direction")