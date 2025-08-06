--[[
    SpectatingState.module - Handles spectator mode after death
    Manages camera switching and waiting for next round
]]

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Players = game:GetService("Players")

local SpectatingState = {}
SpectatingState.__index = SpectatingState

function SpectatingState.new(controller)
    local self = setmetatable({}, SpectatingState)
    self.controller = controller
    self.name = "Spectating"
    self.spectateIndex = 1
    self.deathScreenSent = false
    return self
end

function SpectatingState:OnEnter()
    warn("[SpectatingState] Player", self.controller.player.Name, "entered spectating state")
    
    -- Check if player is somehow in revive process (shouldn't happen but safety check)
    if self.controller.player:GetAttribute("IsReviving") or 
       self.controller.player:GetAttribute("RevivingNow") or
       self.controller.player:GetAttribute("JustRevived") then
        warn("[SpectatingState] WARNING: Player has revive attributes in spectating state, clearing them")
        self.controller.player:SetAttribute("IsReviving", false)
        self.controller.player:SetAttribute("RevivingNow", false)
        self.controller.player:SetAttribute("JustRevived", false)
        self.controller.player:SetAttribute("RevivePromptActive", false)
        self.controller.player:SetAttribute("AwaitingReviveResponse", false)
        
        -- If player is in revive process, don't show death screen
        warn("[SpectatingState] Not showing death screen - player was in revive process")
        return
    end
    
    -- Also check if player character is somehow alive
    if self.controller.player.Character then
        local humanoid = self.controller.player.Character:FindFirstChildOfClass("Humanoid")
        if humanoid and humanoid.Health > 0 then
            warn("[SpectatingState] WARNING: Player is alive in spectating state! Not showing death screen")
            -- Force transition back to Alive state
            task.wait(0.1)
            self.controller.fsm:changeState("Alive")
            return
        end
    end
    
    -- This state is entered when player is truly dead (no revives or declined)
    -- Wait a moment to ensure all states are properly set
    task.wait(0.1)
    
    -- Now we tell the client to show the death screen
    self:_sendDeathScreenCommand()
    
    -- Disable controls
    self.controller.collisionState.canCollide = false
    
    -- Make player spectate (implementation depends on your spectating system)
    self:_enterSpectatorMode()
    
    -- Notify state change
    self.controller:notifyStateChange("Spectating")
end

function SpectatingState:OnExecute(dt)
    -- Could implement camera cycling through alive players here
    -- For now, just ensure we stay in spectator mode
end

function SpectatingState:OnExit()
    -- Clear spectating attributes
    self.controller.player:SetAttribute("IsSpectating", false)
    
    -- Reset flags
    self.deathScreenSent = false
    
    -- Reset camera to player
    self:_resetCamera()
end

function SpectatingState:_setupSpectatorCamera()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local spectateRemote = remotes:FindFirstChild("SetSpectatorCamera")
    
    if not spectateRemote then
        spectateRemote = Instance.new("RemoteEvent")
        spectateRemote.Name = "SetSpectatorCamera"
        spectateRemote.Parent = remotes
    end
    
    -- Find an alive player to spectate
    local alivePlayer = self:_findAlivePlayer()
    
    if alivePlayer then
        spectateRemote:FireClient(self.controller.player, {
            mode = "spectate",
            target = alivePlayer
        })
    else
        -- No one to spectate, use free camera
        spectateRemote:FireClient(self.controller.player, {
            mode = "free"
        })
    end
end

function SpectatingState:_findAlivePlayer()
    -- Find a living player to spectate
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= self.controller.player then
            -- Check if player is alive (would check their controller state)
            if not player:GetAttribute("IsDead") then
                return player
            end
        end
    end
    return nil
end

function SpectatingState:_resetCamera()
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local spectateRemote = remotes:FindFirstChild("SetSpectatorCamera")
    
    if spectateRemote then
        spectateRemote:FireClient(self.controller.player, {
            mode = "reset"
        })
    end
end

-- Method to handle cycling through spectate targets
function SpectatingState:cycleSpectateTarget(direction)
    local alivePlayers = {}
    
    for _, player in ipairs(Players:GetPlayers()) do
        if player ~= self.controller.player and not player:GetAttribute("IsDead") then
            table.insert(alivePlayers, player)
        end
    end
    
    if #alivePlayers == 0 then
        return
    end
    
    self.spectateIndex = self.spectateIndex + direction
    if self.spectateIndex > #alivePlayers then
        self.spectateIndex = 1
    elseif self.spectateIndex < 1 then
        self.spectateIndex = #alivePlayers
    end
    
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local spectateRemote = remotes:FindFirstChild("SetSpectatorCamera")
    
    if spectateRemote then
        spectateRemote:FireClient(self.controller.player, {
            mode = "spectate",
            target = alivePlayers[self.spectateIndex]
        })
    end
end

-- Send death screen command to client
function SpectatingState:_sendDeathScreenCommand()
    -- Only send death screen once per spectating session
    if self.deathScreenSent then
        warn("[SpectatingState] Death screen already sent, skipping")
        return
    end
    
    local remotes = ReplicatedStorage:WaitForChild("Remotes")
    local showDeathScreenRemote = remotes:FindFirstChild("ShowDeathScreen")
    
    if showDeathScreenRemote then
        -- Gather stats for the death screen
        local stats = {}
        local leaderstats = self.controller.player:FindFirstChild("leaderstats")
        
        if leaderstats then
            local length = leaderstats:FindFirstChild("Length")
            if length then
                stats.score = length.Value
            end
        end
        
        -- Get kills from attribute
        stats.kills = self.controller.player:GetAttribute("LastKills") or 0
        
        -- Send the command with stats
        showDeathScreenRemote:FireClient(self.controller.player, {
            stats = stats,
            timestamp = os.time()
        })
        self.deathScreenSent = true
        warn("[SpectatingState] Death screen command sent")
    else
        warn("[SpectatingState] ShowDeathScreen remote not found")
    end
end

return SpectatingState