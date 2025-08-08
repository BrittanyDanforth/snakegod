-- CatmullRomSpline V2.1 (Hermite tension 0.1) - Stable Turning
-- CHANGELOG:
-- - V2.1: safer tangent at endpoints, header/version note for CI visibility

--[[
	Catmull-Rom Spline Module (V2 - Stable Turning)
	This script creates a smooth, mathematical curve from a series of points.
	It is essential for the snake's body to look fluid and natural.
	Place this script inside a ModuleScript named "CatmullRomSpline" in ReplicatedStorage.

	--[ V2 Change ]--
	* REPLACED the core `interpolate` function with a more robust version based on Hermite splines.
	* THE PROBLEM: The old formula was unstable on sharp turns, causing the curve to overshoot,
	  create loops, and make the snake model "shit the bed".
	* THE FIX: The new function uses a 'tension' parameter. A low tension forces the curve to be
	  "tighter" and stick closer to the control points, which completely prevents loops and instability
	  during sharp turns. This is the definitive fix for turning-related visual bugs.
]]

local CatmullRomSpline = {}
CatmullRomSpline.__index = CatmullRomSpline

-- t is the interpolation factor between 0 and 1
-- p0, p1, p2, p3 are the four control points (Vector3)
local function interpolate(t, p0, p1, p2, p3)
	-- Low tension keeps curve tight and stable on sharp turns
	local tension = 0.1

	local t2 = t * t
	local t3 = t2 * t

	-- Tangents (Hermite form)
	local m1 = (p2 - p0) * tension
	local m2 = (p3 - p1) * tension

	-- Hermite basis
	local h1 =  2*t3 - 3*t2 + 1
	local h2 = -2*t3 + 3*t2
	local h3 =    t3 - 2*t2 + t
	local h4 =    t3 - t2

	return h1*p1 + h2*p2 + h3*m1 + h4*m2
end

function CatmullRomSpline.new(points)
	local self = setmetatable({}, CatmullRomSpline)

	if #points < 4 then
		warn("CatmullRomSpline requires at least 4 points. Returning nil.")
		return nil
	end

	self.points = points
	self.segments = #points - 3
	self.length = nil
	self.arcLengths = nil
	self.isUniform = false

	return self
end

function CatmullRomSpline:SetUniform(isUniform)
	if isUniform and not self.arcLengths then
		self:_calculateArcLengths()
	end
	self.isUniform = isUniform
end

function CatmullRomSpline:GetPoint(t)
	t = math.clamp(t, 0, 1)

	if self.isUniform then
		t = self:_mapToNonUniform(t)
	end

	local totalSegments = self.segments
	local scaledT = t * totalSegments
	local segmentIndex = math.floor(scaledT)

	if segmentIndex >= totalSegments then
		segmentIndex = totalSegments - 1
	end

	local localT = scaledT - segmentIndex

	local p0 = self.points[segmentIndex + 1]
	local p1 = self.points[segmentIndex + 2]
	local p2 = self.points[segmentIndex + 3]
	local p3 = self.points[segmentIndex + 4]

	return interpolate(localT, p0, p1, p2, p3)
end

function CatmullRomSpline:GetTangent(t)
	local h = 0.001
	-- clamp endpoints to avoid NaNs
	if t <= 0 then t = 0.0005 elseif t >= 1 then t = 0.9995 end
	local p1 = self:GetPoint(t - h)
	local p2 = self:GetPoint(t + h)
	local v = p2 - p1
	local mag = v.Magnitude
	if mag < 1e-6 or mag ~= mag then
		return Vector3.new(0,0,-1)
	end
	return v / mag
end

function CatmullRomSpline:GetLength(stepsPerSegment)
	stepsPerSegment = stepsPerSegment or 20
	if self.length then
		return self.length
	end

	local totalLength = 0
	local lastPoint = self:GetPoint(0)

	for i = 1, self.segments * stepsPerSegment do
		local t = i / (self.segments * stepsPerSegment)
		local currentPoint = self:GetPoint(t)
		totalLength = totalLength + (currentPoint - lastPoint).Magnitude
		lastPoint = currentPoint
	end

	self.length = totalLength
	return totalLength
end

function CatmullRomSpline:_calculateArcLengths()
	local steps = self.segments * 20
	self.arcLengths = {0}
	local totalLength = 0
	local lastPoint = self:GetPoint(0)

	for i = 1, steps do
		local t = i / steps
		local currentPoint = self:GetPoint(t)
		totalLength = totalLength + (currentPoint - lastPoint).Magnitude
		self.arcLengths[i + 1] = totalLength
		lastPoint = currentPoint
	end

	-- Normalize
	for i = 1, #self.arcLengths do
		self.arcLengths[i] = self.arcLengths[i] / totalLength
	end
end

function CatmullRomSpline:_mapToNonUniform(t)
	if not self.arcLengths then return t end

	local targetArcLength = t
	local low = 1
	local high = #self.arcLengths
	local index = 1

	while low < high do
		index = low + math.floor((high - low) / 2)
		if self.arcLengths[index] < targetArcLength then
			low = index + 1
		else
			high = index
		end
	end

	if self.arcLengths[index] > targetArcLength and index > 1 then
		index = index - 1
	end

	local lengthBefore = self.arcLengths[index]
	local lengthAfter = self.arcLengths[index + 1]
	local segmentLength = lengthAfter - lengthBefore

	if segmentLength < 1e-6 then
		return (index - 1) / (self.segments * 20)
	end

	local segmentT = (targetArcLength - lengthBefore) / segmentLength
	local resultT = (index - 1 + segmentT) / (self.segments * 20)

	return resultT
end

return CatmullRomSpline