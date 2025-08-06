--[[
    Death & Revive Test Script
    Tests the new death fade effect, death orb spawning, and revival system
]]

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

print("🧪 Death & Revive Test Script loaded")

-- Test commands
Players.PlayerAdded:Connect(function(player)
    player.Chatted:Connect(function(message)
        local character = player.Character
        if not character then return end
        
        local humanoid = character:FindFirstChildOfClass("Humanoid")
        if not humanoid then return end
        
        if message:lower() == "/testdeath" then
            print("💀 Testing death effect for", player.Name)
            
            -- Trigger death
            humanoid.Health = 0
            
        elseif message:lower() == "/testrevive" then
            print("💚 Testing revive for", player.Name)
            
            -- Set revive token
            player:SetAttribute("RevivesAvailable", 1)
            
            -- Trigger death
            humanoid.Health = 0
            
        elseif message:lower() == "/givelength" then
            print("📏 Giving length to", player.Name)
            
            local leaderstats = player:FindFirstChild("leaderstats")
            if leaderstats then
                local length = leaderstats:FindFirstChild("Length")
                if length then
                    length.Value = length.Value + 100
                    print("✅ Added 100 length, new total:", length.Value)
                end
            end
            
        elseif message:lower() == "/checkstate" then
            print("🔍 Checking snake state for", player.Name)
            
            local snakeSystem = _G.PlayerSnakes and _G.PlayerSnakes[player]
            if snakeSystem then
                print("  - Snake exists: YES")
                print("  - Visible segments:", snakeSystem.visibleSegmentCount or "unknown")
                print("  - Target length:", snakeSystem.targetLength or "unknown")
                print("  - Model parent:", snakeSystem.model and snakeSystem.model.Parent or "nil")
            else
                print("  - Snake exists: NO")
            end
            
            local controller = _G.PlayerControllers and _G.PlayerControllers[player]
            if controller then
                print("  - Controller exists: YES")
                print("  - Current state:", controller.fsm and controller.fsm.currentState and controller.fsm.currentState.name or "unknown")
                print("  - Has saved state:", controller.savedSnakeState and "YES" or "NO")
            else
                print("  - Controller exists: NO")
            end
        end
    end)
end)

print("🎮 Test commands:")
print("  /testdeath - Test death fade and orb spawning")
print("  /testrevive - Test revival system")
print("  /givelength - Add 100 length to your snake")
print("  /checkstate - Check snake and controller state")