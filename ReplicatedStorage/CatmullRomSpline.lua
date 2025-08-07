-- CatmullRom Spline Module for Seamless Snake Movement
-- Provides smooth curve interpolation through control points with arc-length parameterization

local CatmullRomSpline = {}
CatmullRomSpline.__index = CatmullRomSpline

-- Constants
local ALPHA = 0.5 -- Centripetal Catmull-Rom (0.5) provides best results
local ARC_LENGTH_SAMPLES = 100 -- Number of samples for arc length calculation

-- Helper function to calculate Catmull-Rom interpolation
local function catmullRomInterpolate(p0, p1, p2, p3, t, alpha)
	alpha = alpha or ALPHA
	
	local t01 = (p0 - p1).Magnitude ^ alpha
	local t12 = (p1 - p2).Magnitude ^ alpha
	local t23 = (p2 - p3).Magnitude ^ alpha
	
	local m1 = (1 - alpha) * (p2 - p1 + t12 * ((p1 - p0) / t01 - (p2 - p0) / (t01 + t12)))
	local m2 = (1 - alpha) * (p2 - p1 + t12 * ((p3 - p2) / t23 - (p3 - p1) / (t12 + t23)))
	
	local a = 2 * (p1 - p2) + m1 + m2
	local b = -3 * (p1 - p2) - 2 * m1 - m2
	local c = m1
	local d = p1
	
	return a * t^3 + b * t^2 + c * t + d
end

-- Create a new spline from control points
function CatmullRomSpline.new(controlPoints)
	local self = setmetatable({}, CatmullRomSpline)
	
	self.controlPoints = controlPoints
	self.arcLengthTable = {}
	self.totalLength = 0
	self.uniform = false
	
	-- Validate we have enough points
	if #controlPoints < 4 then
		warn("CatmullRomSpline requires at least 4 control points")
		return nil
	end
	
	return self
end

-- Enable uniform (arc-length) parameterization
function CatmullRomSpline:SetUniform(enabled)
	self.uniform = enabled
	if enabled and #self.arcLengthTable == 0 then
		self:_computeArcLengthTable()
	end
end

-- Compute arc length parameterization table
function CatmullRomSpline:_computeArcLengthTable()
	self.arcLengthTable = {0}
	self.totalLength = 0
	
	local segments = #self.controlPoints - 3
	local samplesPerSegment = math.ceil(ARC_LENGTH_SAMPLES / segments)
	
	for i = 1, segments do
		local p0 = self.controlPoints[i]
		local p1 = self.controlPoints[i + 1]
		local p2 = self.controlPoints[i + 2]
		local p3 = self.controlPoints[i + 3]
		
		local prevPoint = p1
		
		for j = 1, samplesPerSegment do
			local t = j / samplesPerSegment
			local point = catmullRomInterpolate(p0, p1, p2, p3, t, ALPHA)
			local segmentLength = (point - prevPoint).Magnitude
			
			self.totalLength = self.totalLength + segmentLength
			table.insert(self.arcLengthTable, self.totalLength)
			
			prevPoint = point
		end
	end
end

-- Get position at parameter t (0 to 1)
function CatmullRomSpline:GetPoint(t)
	-- Clamp t to valid range
	t = math.clamp(t, 0, 1)
	
	-- If uniform parameterization is enabled, convert t to arc-length parameter
	if self.uniform then
		t = self:_uniformToNonUniform(t)
	end
	
	-- Determine which segment we're in
	local segments = #self.controlPoints - 3
	local scaledT = t * segments
	local segmentIndex = math.floor(scaledT) + 1
	local localT = scaledT - (segmentIndex - 1)
	
	-- Clamp segment index
	if segmentIndex > segments then
		segmentIndex = segments
		localT = 1
	end
	
	-- Get the four control points for this segment
	local p0 = self.controlPoints[segmentIndex]
	local p1 = self.controlPoints[segmentIndex + 1]
	local p2 = self.controlPoints[segmentIndex + 2]
	local p3 = self.controlPoints[segmentIndex + 3]
	
	-- Interpolate
	return catmullRomInterpolate(p0, p1, p2, p3, localT, ALPHA)
end

-- Convert uniform parameter to non-uniform parameter
function CatmullRomSpline:_uniformToNonUniform(uniformT)
	local targetLength = uniformT * self.totalLength
	
	-- Binary search through arc length table
	local low = 1
	local high = #self.arcLengthTable
	
	while high - low > 1 do
		local mid = math.floor((low + high) / 2)
		if self.arcLengthTable[mid] < targetLength then
			low = mid
		else
			high = mid
		end
	end
	
	-- Interpolate between the two closest samples
	local lengthBefore = self.arcLengthTable[low]
	local lengthAfter = self.arcLengthTable[high]
	local segmentLength = lengthAfter - lengthBefore
	
	if segmentLength > 0 then
		local segmentT = (targetLength - lengthBefore) / segmentLength
		return (low - 1 + segmentT) / (#self.arcLengthTable - 1)
	else
		return (low - 1) / (#self.arcLengthTable - 1)
	end
end

-- Get the tangent (direction) at parameter t
function CatmullRomSpline:GetTangent(t)
	local epsilon = 0.0001
	local p1 = self:GetPoint(t - epsilon)
	local p2 = self:GetPoint(t + epsilon)
	return (p2 - p1).Unit
end

-- Get total arc length of the spline
function CatmullRomSpline:GetLength()
	if #self.arcLengthTable == 0 then
		self:_computeArcLengthTable()
	end
	return self.totalLength
end

-- Sample the spline at regular intervals
function CatmullRomSpline:SamplePoints(count)
	local points = {}
	for i = 0, count - 1 do
		local t = i / (count - 1)
		table.insert(points, self:GetPoint(t))
	end
	return points
end

return CatmullRomSpline