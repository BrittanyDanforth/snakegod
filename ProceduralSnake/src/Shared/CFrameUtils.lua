--!strict
-- CFrame Utilities for Stable Orientation
-- Prevents gimbal lock and rolling artifacts in procedural snake animation

local CFrameUtils = {}

-- Create a stable CFrame that avoids gimbal lock when looking at a target
function CFrameUtils.createStableCFrame(position: Vector3, lookAtPosition: Vector3, upVector: Vector3?): CFrame
	upVector = upVector or Vector3.new(0, 1, 0)
	
	local lookVector = (lookAtPosition - position).Unit
	
	-- Check if lookVector and upVector are nearly parallel
	local dot = math.abs(lookVector:Dot(upVector))
	if dot > 0.999 then
		-- If they are parallel, use a different up vector
		upVector = if math.abs(lookVector.X) < 0.9 
			then Vector3.new(1, 0, 0) 
			else Vector3.new(0, 1, 0)
	end
	
	-- Calculate right vector using cross product
	local rightVector = upVector:Cross(lookVector).Unit
	
	-- Recalculate up vector to ensure orthogonality
	local newUpVector = lookVector:Cross(rightVector).Unit
	
	-- Create CFrame using fromMatrix
	-- Note: fromMatrix uses -Z as the look direction
	return CFrame.fromMatrix(
		position,
		rightVector,
		newUpVector,
		-lookVector
	)
end

-- Frame-rate independent damping for smooth interpolation
function CFrameUtils.damp(current: CFrame, goal: CFrame, smoothingFactor: number, deltaTime: number): CFrame
	-- Ensure smoothingFactor is in valid range
	smoothingFactor = math.clamp(smoothingFactor, 0, 0.999)
	
	-- Calculate frame-rate independent alpha
	local alpha = 1 - (smoothingFactor ^ deltaTime)
	
	return current:Lerp(goal, alpha)
end

-- Frame-rate independent damping for Vector3
function CFrameUtils.dampVector3(current: Vector3, goal: Vector3, smoothingFactor: number, deltaTime: number): Vector3
	smoothingFactor = math.clamp(smoothingFactor, 0, 0.999)
	local alpha = 1 - (smoothingFactor ^ deltaTime)
	return current:Lerp(goal, alpha)
end

-- Calculate CFrame from position and direction with twist control
function CFrameUtils.lookAtWithTwist(position: Vector3, direction: Vector3, twist: number, upVector: Vector3?): CFrame
	upVector = upVector or Vector3.new(0, 1, 0)
	
	-- Create initial stable CFrame
	local cf = CFrameUtils.createStableCFrame(position, position + direction, upVector)
	
	-- Apply twist around the look direction
	if twist ~= 0 then
		cf = cf * CFrame.Angles(0, 0, twist)
	end
	
	return cf
end

-- Align a CFrame's forward direction to a new direction while minimizing rotation
function CFrameUtils.alignToDirection(currentCFrame: CFrame, newDirection: Vector3): CFrame
	local currentForward = -currentCFrame.LookVector
	local axis = currentForward:Cross(newDirection)
	
	if axis.Magnitude < 0.001 then
		-- Directions are already aligned or opposite
		if currentForward:Dot(newDirection) < 0 then
			-- They're opposite, rotate 180 degrees around any perpendicular axis
			local perpAxis = if math.abs(newDirection.Y) < 0.9 
				then Vector3.new(0, 1, 0) 
				else Vector3.new(1, 0, 0)
			return currentCFrame * CFrame.fromAxisAngle(perpAxis, math.pi)
		else
			-- Already aligned
			return currentCFrame
		end
	end
	
	axis = axis.Unit
	local angle = math.acos(math.clamp(currentForward:Dot(newDirection), -1, 1))
	
	return currentCFrame * CFrame.fromAxisAngle(axis, angle)
end

-- Smoothly interpolate between two orientations using quaternion slerp
function CFrameUtils.slerpCFrame(cf1: CFrame, cf2: CFrame, t: number): CFrame
	-- Extract positions
	local p1 = cf1.Position
	local p2 = cf2.Position
	
	-- Interpolate position linearly
	local position = p1:Lerp(p2, t)
	
	-- Get rotation components
	local _, _, _, x1, y1, z1, w1 = cf1:GetComponents()
	local _, _, _, x2, y2, z2, w2 = cf2:GetComponents()
	
	-- Quaternion dot product
	local dot = x1*x2 + y1*y2 + z1*z2 + w1*w2
	
	-- Choose shorter path
	if dot < 0 then
		x2, y2, z2, w2 = -x2, -y2, -z2, -w2
		dot = -dot
	end
	
	-- If quaternions are very close, use linear interpolation
	if dot > 0.9995 then
		return CFrame.new(
			position.X, position.Y, position.Z,
			x1 + t*(x2-x1), y1 + t*(y2-y1), z1 + t*(z2-z1), w1 + t*(w2-w1)
		)
	end
	
	-- Spherical interpolation
	local theta = math.acos(dot)
	local sinTheta = math.sin(theta)
	local scale1 = math.sin((1-t)*theta) / sinTheta
	local scale2 = math.sin(t*theta) / sinTheta
	
	return CFrame.new(
		position.X, position.Y, position.Z,
		scale1*x1 + scale2*x2,
		scale1*y1 + scale2*y2,
		scale1*z1 + scale2*z2,
		scale1*w1 + scale2*w2
	)
end

return CFrameUtils