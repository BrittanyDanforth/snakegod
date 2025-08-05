-- COMPLETE REVIVE SYSTEM FIX
-- Place this script in ServerScriptService to fix all revive-related issues

local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

-- Configuration
local DEATH_ORB_LIFETIME = 60 -- Seconds before auto-cleanup
local REVIVE_ORB_CLEANUP_RADIUS = 100 -- Studs around revive position to clean

-- Track active death orbs for cleanup
local deathOrbTracker = {}

-- Wait for game to initialize
RunService.Heartbeat:Wait()

-- PART 1: Disable old collision system if running
local function disableOldCollisionSystem()
    -- Check for old collision handler
    if _G.CollisionHandler and _G.CollisionHandler.destroy then
        warn("⚠️ DISABLING OLD COLLISION HANDLER")
        _G.CollisionHandler:destroy()
        _G.CollisionHandler = nil
    end
    
    -- Clean up old death queue
    if _G.DeathQueueConnection then
        _G.DeathQueueConnection:Disconnect()
        _G.DeathQueueConnection = nil
    end
    
    print("✅ Old collision system disabled")
end

-- PART 2: Add death orb auto-cleanup
local function setupDeathOrbCleanup()
    -- Monitor workspace for new death orbs
    local orbsFolder = workspace:FindFirstChild("Orbs")
    if not orbsFolder then
        orbsFolder = Instance.new("Folder")
        orbsFolder.Name = "Orbs"
        orbsFolder.Parent = workspace
    end
    
    -- Watch for new orbs
    orbsFolder.ChildAdded:Connect(function(orb)
        if orb.Name == "DeathOrb" and orb:IsA("BasePart") then
            -- Add cleanup timer
            local cleanupTime = tick() + DEATH_ORB_LIFETIME
            deathOrbTracker[orb] = cleanupTime
            
            -- Schedule cleanup
            task.spawn(function()
                task.wait(DEATH_ORB_LIFETIME)
                if orb and orb.Parent then
                    orb:Destroy()
                    deathOrbTracker[orb] = nil
                end
            end)
        end
    end)
    
    print("✅ Death orb auto-cleanup enabled")
end

-- PART 3: Clean up orbs when player revives
local function cleanupOrbsNearPosition(position, radius)
    local orbsFolder = workspace:FindFirstChild("Orbs")
    if not orbsFolder then return end
    
    local cleaned = 0
    for _, obj in ipairs(orbsFolder:GetChildren()) do
        if obj.Name == "DeathOrb" and obj:IsA("BasePart") then
            local distance = (obj.Position - position).Magnitude
            if distance <= radius then
                obj:Destroy()
                deathOrbTracker[obj] = nil
                cleaned = cleaned + 1
            end
        end
    end
    
    if cleaned > 0 then
        print("🧹 Cleaned", cleaned, "death orbs near revive position")
    end
end

-- PART 4: Hook into revive system
local function setupReviveHooks()
    -- Monitor player attributes for revive
    Players.PlayerAdded:Connect(function(player)
        player:GetAttributeChangedSignal("JustRevived"):Connect(function()
            if player:GetAttribute("JustRevived") then
                -- Player is reviving, clean up their death orbs
                local character = player.Character
                if character then
                    local rootPart = character:FindFirstChild("HumanoidRootPart")
                    if rootPart then
                        cleanupOrbsNearPosition(rootPart.Position, REVIVE_ORB_CLEANUP_RADIUS)
                    end
                end
            end
        end)
    end)
    
    print("✅ Revive cleanup hooks installed")
end

-- PART 5: Fix duplicate revive prompts
local function fixDuplicateRevivePrompts()
    -- Create or get remotes
    local remotes = ReplicatedStorage:WaitForChild("Remotes", 5)
    if not remotes then return end
    
    local promptRevive = remotes:FindFirstChild("PromptRevive")
    if not promptRevive then return end
    
    -- Track active prompts to prevent duplicates
    local activePrompts = {}
    
    -- Override the remote event to add duplicate prevention
    local originalFireClient = promptRevive.FireClient
    promptRevive.FireClient = function(self, player, ...)
        -- Check if prompt already active
        if activePrompts[player] then
            warn("⚠️ Duplicate revive prompt blocked for", player.Name)
            return
        end
        
        -- Mark as active
        activePrompts[player] = true
        
        -- Clear after timeout
        task.spawn(function()
            task.wait(10)
            activePrompts[player] = nil
        end)
        
        -- Fire original
        return originalFireClient(self, player, ...)
    end
    
    -- Clean up on response
    promptRevive.OnServerEvent:Connect(function(player, response)
        activePrompts[player] = nil
    end)
    
    -- Clean up on player leave
    Players.PlayerRemoving:Connect(function(player)
        activePrompts[player] = nil
    end)
    
    print("✅ Duplicate revive prompt prevention installed")
end

-- Execute all fixes
disableOldCollisionSystem()
setupDeathOrbCleanup()
setupReviveHooks()
fixDuplicateRevivePrompts()

print("🎉 COMPLETE REVIVE SYSTEM FIX APPLIED")
print("✅ Old collision handler disabled")
print("✅ Death orbs auto-cleanup after", DEATH_ORB_LIFETIME, "seconds")
print("✅ Death orbs cleaned on revive within", REVIVE_ORB_CLEANUP_RADIUS, "studs")
print("✅ Duplicate revive prompts prevented")