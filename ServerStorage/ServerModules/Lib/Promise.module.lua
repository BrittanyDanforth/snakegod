--[[
    Promise.module - A simplified Promise implementation for Roblox
    Provides cancellable asynchronous operations to eliminate race conditions
]]

local Promise = {}
Promise.__index = Promise

Promise.Status = {
    Started = "Started",
    Resolved = "Resolved", 
    Rejected = "Rejected",
    Cancelled = "Cancelled"
}

function Promise.new(executor)
    local self = setmetatable({}, Promise)
    
    self._status = Promise.Status.Started
    self._value = nil
    self._reason = nil
    self._resolveCallbacks = {}
    self._rejectCallbacks = {}
    self._finallyCallbacks = {}
    self._cancellationCallbacks = {}
    
    local function resolve(value)
        if self._status ~= Promise.Status.Started then
            return
        end
        
        self._status = Promise.Status.Resolved
        self._value = value
        
        for _, callback in ipairs(self._resolveCallbacks) do
            task.spawn(callback, value)
        end
        
        self:_runFinallyCallbacks()
    end
    
    local function reject(reason)
        if self._status ~= Promise.Status.Started then
            return
        end
        
        self._status = Promise.Status.Rejected
        self._reason = reason
        
        for _, callback in ipairs(self._rejectCallbacks) do
            task.spawn(callback, reason)
        end
        
        self:_runFinallyCallbacks()
    end
    
    local function onCancel(callback)
        table.insert(self._cancellationCallbacks, callback)
    end
    
    -- Execute the promise
    task.spawn(function()
        local ok, err = pcall(executor, resolve, reject, onCancel)
        if not ok then
            reject(err)
        end
    end)
    
    return self
end

function Promise:andThen(onResolve, onReject)
    return Promise.new(function(resolve, reject)
        local function handleResolve(value)
            if onResolve then
                local ok, result = pcall(onResolve, value)
                if ok then
                    resolve(result)
                else
                    reject(result)
                end
            else
                resolve(value)
            end
        end
        
        local function handleReject(reason)
            if onReject then
                local ok, result = pcall(onReject, reason)
                if ok then
                    resolve(result)
                else
                    reject(result)
                end
            else
                reject(reason)
            end
        end
        
        if self._status == Promise.Status.Resolved then
            handleResolve(self._value)
        elseif self._status == Promise.Status.Rejected then
            handleReject(self._reason)
        elseif self._status == Promise.Status.Started then
            table.insert(self._resolveCallbacks, handleResolve)
            table.insert(self._rejectCallbacks, handleReject)
        end
    end)
end

function Promise:catch(onReject)
    return self:andThen(nil, onReject)
end

function Promise:finally(onFinally)
    if self._status ~= Promise.Status.Started then
        task.spawn(onFinally, self._status)
    else
        table.insert(self._finallyCallbacks, onFinally)
    end
    return self
end

function Promise:cancel()
    if self._status ~= Promise.Status.Started then
        return
    end
    
    self._status = Promise.Status.Cancelled
    
    -- Run cancellation callbacks
    for _, callback in ipairs(self._cancellationCallbacks) do
        task.spawn(callback)
    end
    
    self:_runFinallyCallbacks()
end

function Promise:getStatus()
    return self._status
end

function Promise:await()
    if self._status ~= Promise.Status.Started then
        if self._status == Promise.Status.Resolved then
            return self._value
        else
            error(self._reason or "Promise rejected")
        end
    end
    
    local thread = coroutine.running()
    
    self:andThen(function(value)
        task.spawn(thread, true, value)
    end):catch(function(reason)
        task.spawn(thread, false, reason)
    end)
    
    local ok, value = coroutine.yield()
    
    if ok then
        return value
    else
        error(value)
    end
end

function Promise:awaitStatus()
    if self._status ~= Promise.Status.Started then
        return {
            ok = self._status == Promise.Status.Resolved,
            value = self._value,
            error = self._reason
        }
    end
    
    local thread = coroutine.running()
    
    self:andThen(function(value)
        task.spawn(thread, true, value)
    end):catch(function(reason)
        task.spawn(thread, false, reason)
    end)
    
    local ok, value = coroutine.yield()
    
    return {
        ok = ok,
        value = ok and value or nil,
        error = not ok and value or nil
    }
end

function Promise:_runFinallyCallbacks()
    for _, callback in ipairs(self._finallyCallbacks) do
        task.spawn(callback, self._status)
    end
end

-- Static methods
function Promise.resolve(value)
    return Promise.new(function(resolve)
        resolve(value)
    end)
end

function Promise.reject(reason)
    return Promise.new(function(_, reject)
        reject(reason)
    end)
end

function Promise.delay(seconds)
    return Promise.new(function(resolve, _, onCancel)
        local cancelled = false
        
        onCancel(function()
            cancelled = true
        end)
        
        task.wait(seconds)
        
        if not cancelled then
            resolve()
        end
    end)
end

function Promise.race(promises)
    return Promise.new(function(resolve, reject)
        for _, promise in ipairs(promises) do
            promise:andThen(resolve):catch(reject)
        end
    end)
end

function Promise.all(promises)
    return Promise.new(function(resolve, reject)
        local results = {}
        local completed = 0
        local total = #promises
        
        if total == 0 then
            resolve({})
            return
        end
        
        for i, promise in ipairs(promises) do
            promise:andThen(function(value)
                results[i] = value
                completed = completed + 1
                
                if completed == total then
                    resolve(results)
                end
            end):catch(reject)
        end
    end)
end

function Promise.is(value)
    return type(value) == "table" and getmetatable(value) == Promise
end

return Promise