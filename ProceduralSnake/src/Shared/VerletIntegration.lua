--!strict
-- Verlet Integration Module for Physics-Based Snake Movement
-- Optional advanced module for dynamic, physics-driven snake behavior

local VerletIntegration = {}
VerletIntegration.__index = VerletIntegration

type VerletPoint = {
	pos: Vector3,
	oldPos: Vector3,
	isLocked: boolean,
	mass: number
}

type VerletConstraint = {
	p1: VerletPoint,
	p2: VerletPoint,
	restLength: number,
	stiffness: number
}

type VerletSystem = {
	points: {VerletPoint},
	constraints: {VerletConstraint},
	gravity: Vector3,
	damping: number,
	iterations: number
}

-- Create a new Verlet integration system
function VerletIntegration.new(config: {
	gravity: Vector3?,
	damping: number?,
	iterations: number?
}?): VerletSystem
	local self = setmetatable({}, VerletIntegration)
	
	config = config or {}
	self.points = {}
	self.constraints = {}
	self.gravity = config.gravity or Vector3.new(0, -workspace.Gravity, 0)
	self.damping = config.damping or 0.99
	self.iterations = config.iterations or 3
	
	return self
end

-- Create a Verlet point
function VerletIntegration:CreatePoint(position: Vector3, isLocked: boolean?, mass: number?): VerletPoint
	local point: VerletPoint = {
		pos = position,
		oldPos = position,
		isLocked = isLocked or false,
		mass = mass or 1
	}
	
	table.insert(self.points, point)
	return point
end

-- Create a distance constraint between two points
function VerletIntegration:CreateConstraint(p1: VerletPoint, p2: VerletPoint, restLength: number?, stiffness: number?): VerletConstraint
	if not restLength then
		restLength = (p1.pos - p2.pos).Magnitude
	end
	
	local constraint: VerletConstraint = {
		p1 = p1,
		p2 = p2,
		restLength = restLength,
		stiffness = stiffness or 1
	}
	
	table.insert(self.constraints, constraint)
	return constraint
end

-- Create a chain of connected points (useful for snake body)
function VerletIntegration:CreateChain(startPos: Vector3, segmentCount: number, segmentLength: number): {VerletPoint}
	local chain = {}
	
	for i = 0, segmentCount - 1 do
		local pos = startPos + Vector3.new(0, 0, -i * segmentLength)
		local point = self:CreatePoint(pos, i == 0) -- Lock first point
		table.insert(chain, point)
		
		if i > 0 then
			self:CreateConstraint(chain[i], chain[i + 1], segmentLength)
		end
	end
	
	return chain
end

-- Apply external force to a point
function VerletIntegration:ApplyForce(point: VerletPoint, force: Vector3)
	if not point.isLocked then
		-- F = ma, so acceleration = F/m
		local acceleration = force / point.mass
		point.pos = point.pos + acceleration
	end
end

-- Update the physics simulation
function VerletIntegration:Update(deltaTime: number)
	-- 1. Integration step - update positions based on velocity
	for _, point in ipairs(self.points) do
		if not point.isLocked then
			local velocity = point.pos - point.oldPos
			velocity = velocity * self.damping -- Apply damping
			
			point.oldPos = point.pos
			point.pos = point.pos + velocity + self.gravity * (deltaTime * deltaTime)
		end
	end
	
	-- 2. Constraint satisfaction - iterate to solve constraints
	for iter = 1, self.iterations do
		self:SolveConstraints()
	end
end

-- Solve all constraints
function VerletIntegration:SolveConstraints()
	for _, constraint in ipairs(self.constraints) do
		local p1, p2 = constraint.p1, constraint.p2
		
		-- Calculate current distance
		local axis = p1.pos - p2.pos
		local distance = axis.Magnitude
		
		if distance > 0 then
			-- Calculate correction needed
			local difference = constraint.restLength - distance
			local correction = axis.Unit * (difference * 0.5 * constraint.stiffness)
			
			-- Apply correction based on mass ratio
			local totalMass = p1.mass + p2.mass
			if not p1.isLocked then
				local p1Ratio = p2.mass / totalMass
				p1.pos = p1.pos + correction * p1Ratio
			end
			if not p2.isLocked then
				local p2Ratio = p1.mass / totalMass
				p2.pos = p2.pos - correction * p2Ratio
			end
		end
	end
end

-- Set the position of a locked point (e.g., snake head)
function VerletIntegration:SetLockedPosition(point: VerletPoint, position: Vector3)
	if point.isLocked then
		local delta = position - point.pos
		point.oldPos = point.oldPos + delta
		point.pos = position
	end
end

-- Get positions of all points (useful for updating visual representation)
function VerletIntegration:GetPositions(): {Vector3}
	local positions = {}
	for _, point in ipairs(self.points) do
		table.insert(positions, point.pos)
	end
	return positions
end

-- Add collision with ground plane
function VerletIntegration:ApplyGroundCollision(groundY: number, bounce: number?)
	bounce = bounce or 0.5
	
	for _, point in ipairs(self.points) do
		if point.pos.Y < groundY then
			point.pos = Vector3.new(point.pos.X, groundY, point.pos.Z)
			
			-- Apply bounce
			local velocity = point.pos - point.oldPos
			velocity = Vector3.new(velocity.X, -velocity.Y * bounce, velocity.Z)
			point.oldPos = point.pos - velocity
		end
	end
end

-- Apply sphere collision (useful for obstacles)
function VerletIntegration:ApplySphereCollision(center: Vector3, radius: number)
	for _, point in ipairs(self.points) do
		local toPoint = point.pos - center
		local distance = toPoint.Magnitude
		
		if distance < radius and distance > 0 then
			-- Push point outside sphere
			point.pos = center + toPoint.Unit * radius
		end
	end
end

-- Blend between kinematic target and physics simulation
function VerletIntegration:BlendWithTarget(point: VerletPoint, targetPos: Vector3, blendFactor: number)
	if not point.isLocked then
		point.pos = point.pos:Lerp(targetPos, blendFactor)
	end
end

-- Reset the simulation
function VerletIntegration:Reset()
	for _, point in ipairs(self.points) do
		point.oldPos = point.pos
	end
end

return VerletIntegration