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
    assert(self.states[newStateName], "State '" .. tostring(newStateName) .. "' not found")
    
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
                if typeof(nextState) == "string" and self.states[nextState] then
                    self:changeState(nextState)
                end
            end):catch(function(err)
                warn("State promise error:", err)
                -- Optionally transition to a default state on error
                if self.states["Spectating"] then
                    self:changeState("Spectating")
                end
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