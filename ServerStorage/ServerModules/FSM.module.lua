--[[
    FSM.module - A generic Finite State Machine implementation
    Provides predictable state management and eliminates invalid state combinations
]]

local FSM = {}
FSM.__index = FSM

function FSM.new()
    local self = setmetatable({}, FSM)
    
    self.states = {}
    self.currentState = nil
    self.currentStateName = nil
    self.context = nil
    self.activePromise = nil -- Track active promise for cancellation
    
    return self
end

function FSM:setContext(context)
    self.context = context
end

function FSM:addState(stateName, stateObject)
    assert(type(stateName) == "string", "State name must be a string")
    assert(type(stateObject) == "table", "State object must be a table")
    assert(type(stateObject.OnEnter) == "function", "State must have OnEnter method")
    
    self.states[stateName] = stateObject
end

function FSM:changeState(newStateName, ...)
    -- Safety check for destroyed FSM
    if not self.states or not next(self.states) then
        warn("[FSM] Attempted to change state on destroyed FSM")
        return
    end
    
    -- Check if state exists
    if not self.states[newStateName] then
        warn("[FSM] State '" .. tostring(newStateName) .. "' not found")
        warn("[FSM] Available states:", table.concat(self:getStateNames(), ", "))
        return
    end
    
    -- Prevent redundant state changes
    if self.currentStateName == newStateName then
        warn("[FSM] Already in state:", newStateName)
        return
    end
    
    warn("[FSM] Changing state from", self.currentStateName, "to", newStateName, "with args:", ...)
    
    -- Cancel any active promise from the current state
    if self.activePromise then
        local Promise = require(script.Parent.Lib.Promise)
        if Promise.is(self.activePromise) and self.activePromise:getStatus() == Promise.Status.Started then
            self.activePromise:cancel()
        end
        self.activePromise = nil
    end
    
    -- Exit current state
    if self.currentState and self.currentState.OnExit then
        self.currentState:OnExit()
    end
    
    -- Update state references
    self.currentStateName = newStateName
    self.currentState = self.states[newStateName]
    
    -- Enter new state
    if self.currentState.OnEnter then
        local result = self.currentState:OnEnter(...)
        
        -- If OnEnter returns a Promise, track it
        local Promise = require(script.Parent.Lib.Promise)
        if Promise.is(result) then
            self.activePromise = result
            
            -- Handle promise resolution
            result:andThen(function(nextState)
                warn("[FSM] Promise resolved, transitioning to:", nextState)
                if typeof(nextState) == "string" and self.states and self.states[nextState] then
                    self:changeState(nextState)
                else
                    warn("[FSM] Invalid next state:", nextState)
                end
            end):catch(function(err)
                warn("[FSM] State promise error:", err)
                -- Don't automatically transition to spectating to avoid loops
                -- Let the game logic handle error recovery
            end)
        end
    end
end

function FSM:update(dt)
    if self.currentState and self.currentState.OnExecute then
        self.currentState:OnExecute(dt)
    end
end

function FSM:getCurrentState()
    return self.currentStateName
end

function FSM:getStateNames()
    local names = {}
    if self.states then
        for name, _ in pairs(self.states) do
            table.insert(names, name)
        end
    end
    return names
end

function FSM:destroy()
    -- Cancel any active promise
    if self.activePromise then
        local Promise = require(script.Parent.Lib.Promise)
        if Promise.is(self.activePromise) and self.activePromise:getStatus() == Promise.Status.Started then
            self.activePromise:cancel()
        end
    end
    
    -- Exit current state
    if self.currentState and self.currentState.OnExit then
        self.currentState:OnExit()
    end
    
    -- Clear references
    self.states = {}
    self.currentState = nil
    self.currentStateName = nil
    self.context = nil
    self.activePromise = nil
end

return FSM