-- Trove - A simple resource cleanup utility
-- Place in ReplicatedStorage/Packages/Trove

local Trove = {}
Trove.__index = Trove

function Trove.new()
	return setmetatable({
		_objects = {},
		_cleaning = false
	}, Trove)
end

function Trove:Add(object)
	if self._cleaning then
		error("Cannot add to Trove while cleaning", 2)
	end
	
	table.insert(self._objects, object)
	return object
end

function Trove:Clean()
	if self._cleaning then
		return
	end
	
	self._cleaning = true
	
	-- Clean in reverse order
	for i = #self._objects, 1, -1 do
		local object = self._objects[i]
		
		if type(object) == "function" then
			-- Call cleanup function
			object()
		elseif typeof(object) == "RBXScriptConnection" then
			-- Disconnect connection
			object:Disconnect()
		elseif typeof(object) == "Instance" then
			-- Destroy instance
			object:Destroy()
		elseif type(object) == "table" then
			-- Check for cleanup methods
			if type(object.Destroy) == "function" then
				object:Destroy()
			elseif type(object.Disconnect) == "function" then
				object:Disconnect()
			elseif type(object.destroy) == "function" then
				object:destroy()
			end
		end
	end
	
	table.clear(self._objects)
end

-- Alias for Clean
function Trove:Destroy()
	self:Clean()
end

return Trove