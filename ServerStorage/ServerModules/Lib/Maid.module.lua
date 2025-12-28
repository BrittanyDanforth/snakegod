--[[
    Maid.module - Automated cleanup pattern for preventing memory leaks
    Manages connections, instances, and cleanup tasks
]]

local Maid = {}
Maid.__index = Maid

function Maid.new()
    local self = setmetatable({}, Maid)
    self._tasks = {}
    return self
end

function Maid:GiveTask(task)
    local taskType = typeof(task)
    
    if taskType == "RBXScriptConnection" then
        table.insert(self._tasks, {Type = "Connection", Task = task})
    elseif taskType == "Instance" then
        table.insert(self._tasks, {Type = "Instance", Task = task})
    elseif taskType == "function" then
        table.insert(self._tasks, {Type = "Function", Task = task})
    elseif taskType == "table" then
        -- Assume it's an object with a Destroy or destroy method
        if task.Destroy or task.destroy then
            table.insert(self._tasks, {Type = "Object", Task = task})
        else
            warn("Maid: Given table has no Destroy/destroy method")
        end
    else
        warn("Maid: Unknown task type:", taskType)
    end
    
    return task -- Return the task for inline usage
end

function Maid:DoCleaning()
    -- Clean in reverse order (LIFO)
    for i = #self._tasks, 1, -1 do
        local entry = self._tasks[i]
        
        if entry.Type == "Connection" then
            entry.Task:Disconnect()
        elseif entry.Type == "Instance" then
            entry.Task:Destroy()
        elseif entry.Type == "Function" then
            local ok, err = pcall(entry.Task)
            if not ok then
                warn("Maid cleanup function error:", err)
            end
        elseif entry.Type == "Object" then
            local method = entry.Task.Destroy or entry.Task.destroy
            local ok, err = pcall(method, entry.Task)
            if not ok then
                warn("Maid cleanup object error:", err)
            end
        end
        
        self._tasks[i] = nil
    end
end

-- Alias for consistency with some implementations
function Maid:Destroy()
    self:DoCleaning()
end

-- Remove a specific task without cleaning it
function Maid:RemoveTask(task)
    for i = #self._tasks, 1, -1 do
        if self._tasks[i].Task == task then
            table.remove(self._tasks, i)
            return true
        end
    end
    return false
end

-- Get the number of tasks
function Maid:GetTaskCount()
    return #self._tasks
end

return Maid