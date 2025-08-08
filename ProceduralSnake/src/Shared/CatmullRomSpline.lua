--!strict
-- Catmull-Rom Spline Module with Unit-Speed Parametrization
-- Provides smooth interpolation through control points for snake path generation

local CatmullRomSpline = {}
CatmullRomSpline.__index = CatmullRomSpline

type ControlPoint = Vector3 | CFrame
type SplineData = {
	points: {ControlPoint},
	alpha: number,
	tension: number,
	arcLengthTable: {{t: number, length: number}}?,
	totalLength: number?
}

-- Create a new Catmull-Rom spline
function CatmullRomSpline.new(points: {ControlPoint}, alpha: number?, tension: number?): SplineData
	local self = setmetatable({}, CatmullRomSpline)
	self.points = points
	self.alpha = alpha or 0.5 -- Centripetal spline by default
	self.tension = tension or 0
	self.arcLengthTable = nil
	self.totalLength = nil
	return self
end

-- Get position from control point (handles both Vector3 and CFrame)
local function getPosition(point: ControlPoint): Vector3
	if typeof(point) == "CFrame" then
		return point.Position
	else
		return point
	end
end

-- Catmull-Rom interpolation between 4 points
local function catmullRomInterpolate(p0: Vector3, p1: Vector3, p2: Vector3, p3: Vector3, t: number, alpha: number, tension: number): Vector3
	local t2 = t * t
	local t3 = t2 * t
	
	-- Calculate tangents
	local v0 = (p2 - p0) * (1 - tension)
	local v1 = (p3 - p1) * (1 - tension)
	
	-- Hermite basis functions
	local h00 = 2 * t3 - 3 * t2 + 1
	local h10 = t3 - 2 * t2 + t
	local h01 = -2 * t3 + 3 * t2
	local h11 = t3 - t2
	
	return h00 * p1 + h10 * v0 * 0.5 + h01 * p2 + h11 * v1 * 0.5
end

-- Get point on spline at parameter t (0-1)
function CatmullRomSpline:SolvePosition(t: number, useUnitSpeed: boolean?): Vector3
	local points = self.points
	local numPoints = #points
	
	if numPoints < 2 then
		error("Spline requires at least 2 control points")
	end
	
	-- Handle unit-speed parametrization
	if useUnitSpeed and self.arcLengthTable then
		t = self:GetUnitSpeedParameter(t)
	end
	
	-- Clamp t to valid range
	t = math.clamp(t, 0, 1)
	
	-- Handle edge cases
	if t == 0 then
		return getPosition(points[1])
	elseif t == 1 then
		return getPosition(points[numPoints])
	end
	
	-- Find segment
	local scaledT = t * (numPoints - 1)
	local segment = math.floor(scaledT)
	local localT = scaledT - segment
	
	-- Get control points for this segment
	local p0, p1, p2, p3
	
	-- Adjust segment index (1-based)
	segment = segment + 1
	
	-- Handle boundaries
	p1 = getPosition(points[segment])
	p2 = getPosition(points[segment + 1])
	
	if segment == 1 then
		p0 = p1 + (p1 - p2) -- Extrapolate
	else
		p0 = getPosition(points[segment - 1])
	end
	
	if segment >= numPoints - 1 then
		p3 = p2 + (p2 - p1) -- Extrapolate
	else
		p3 = getPosition(points[segment + 2])
	end
	
	return catmullRomInterpolate(p0, p1, p2, p3, localT, self.alpha, self.tension)
end

-- Get tangent (direction) at parameter t
function CatmullRomSpline:SolveTangent(t: number, useUnitSpeed: boolean?): Vector3
	local epsilon = 0.0001
	local t1 = math.max(0, t - epsilon)
	local t2 = math.min(1, t + epsilon)
	
	local p1 = self:SolvePosition(t1, useUnitSpeed)
	local p2 = self:SolvePosition(t2, useUnitSpeed)
	
	return (p2 - p1).Unit
end

-- Precompute arc length table for unit-speed parametrization
function CatmullRomSpline:PrecomputeUnitSpeedData(samples: number?)
	samples = samples or 100
	
	self.arcLengthTable = {}
	self.totalLength = 0
	
	local prevPoint = self:SolvePosition(0, false)
	
	for i = 0, samples do
		local t = i / samples
		local point = self:SolvePosition(t, false)
		local segmentLength = (point - prevPoint).Magnitude
		
		self.totalLength = self.totalLength + segmentLength
		
		table.insert(self.arcLengthTable, {
			t = t,
			length = self.totalLength
		})
		
		prevPoint = point
	end
end

-- Convert from arc-length parameter to spline parameter
function CatmullRomSpline:GetUnitSpeedParameter(arcLengthParam: number): number
	if not self.arcLengthTable or not self.totalLength then
		warn("Arc length table not computed. Call PrecomputeUnitSpeedData() first.")
		return arcLengthParam
	end
	
	local targetLength = arcLengthParam * self.totalLength
	
	-- Binary search for closest arc length
	local low, high = 1, #self.arcLengthTable
	
	while low < high do
		local mid = math.floor((low + high) / 2)
		
		if self.arcLengthTable[mid].length < targetLength then
			low = mid + 1
		else
			high = mid
		end
	end
	
	-- Linear interpolation between two closest samples
	if low == 1 then
		return 0
	elseif low >= #self.arcLengthTable then
		return 1
	else
		local entry1 = self.arcLengthTable[low - 1]
		local entry2 = self.arcLengthTable[low]
		
		local lengthRange = entry2.length - entry1.length
		if lengthRange > 0 then
			local localT = (targetLength - entry1.length) / lengthRange
			return entry1.t + (entry2.t - entry1.t) * localT
		else
			return entry1.t
		end
	end
end

-- Update control points
function CatmullRomSpline:UpdatePoints(points: {ControlPoint})
	self.points = points
	-- Invalidate arc length table when points change
	self.arcLengthTable = nil
	self.totalLength = nil
end

return CatmullRomSpline