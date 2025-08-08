local CatmullRomSpline = {}
CatmullRomSpline.__index = CatmullRomSpline

-- Defaults tuned for sharp turns stability
local DEFAULT_TENSION = 0.1           -- Lower = tighter curve, less overshoot
local DEFAULT_TANGENT_CLAMP = 0.9     -- Fraction of adjacent chord length
local MAX_SUBDIVISIONS = 64
local MIN_SAMPLES_PER_SEGMENT = 8
local MAX_SAMPLES_PER_SEGMENT = 64

-- Utility
local function clampFloat(x, lo, hi)
	if x < lo then return lo end
	if x > hi then return hi end
	return x
end

local function clampVectorMagnitude(vec, maxMag)
	local mag = vec.Magnitude
	if mag == 0 then
		return vec
	end
	if mag > maxMag then
		return vec.Unit * maxMag
	end
	return vec
end

-- Compute Hermite basis and derivative at t in [0,1]
local function hermiteBasis(t)
	local t2 = t * t
	local t3 = t2 * t
	-- Position basis
	local h1 =  2 * t3 - 3 * t2 + 1   -- p1
	local h2 = -2 * t3 + 3 * t2       -- p2
	local h3 =      t3 - 2 * t2 + t   -- m1
	local h4 =      t3 - t2           -- m2
	-- Derivative basis
	local dh1 =  6 * t2 - 6 * t       -- p1
	local dh2 = -6 * t2 + 6 * t       -- p2
	local dh3 =  3 * t2 - 4 * t + 1   -- m1
	local dh4 =  3 * t2 - 2 * t       -- m2
	return h1, h2, h3, h4, dh1, dh2, dh3, dh4
end

-- Interpolate position and derivative using Hermite form with clamped tangents
local function interpolateHermite(t, p0, p1, p2, p3, tension, tangentClamp)
	local tangentScale = tension or DEFAULT_TENSION
	local clampFrac = tangentClamp or DEFAULT_TANGENT_CLAMP

	-- Raw tangents
	local m1 = (p2 - p0) * tangentScale
	local m2 = (p3 - p1) * tangentScale

	-- Clamp tangents to mitigate overshoot on sharp turns
	local len10 = (p1 - p0).Magnitude
	local len21 = (p2 - p1).Magnitude
	local len32 = (p3 - p2).Magnitude
	local maxM1 = clampFrac * math.min(len10, len21)
	local maxM2 = clampFrac * math.min(len21, len32)
	m1 = clampVectorMagnitude(m1, maxM1)
	m2 = clampVectorMagnitude(m2, maxM2)

	local h1, h2, h3, h4, dh1, dh2, dh3, dh4 = hermiteBasis(t)
	local position = p1 * h1 + p2 * h2 + m1 * h3 + m2 * h4
	local derivative = p1 * dh1 + p2 * dh2 + m1 * dh3 + m2 * dh4
	return position, derivative
end

-- Heuristic to select per-segment samples based on local curvature
local function estimateSamplesForSegment(p0, p1, p2, p3)
	local v01 = (p1 - p0)
	local v12 = (p2 - p1)
	local v23 = (p3 - p2)
	if v01.Magnitude == 0 or v12.Magnitude == 0 or v23.Magnitude == 0 then
		return MIN_SAMPLES_PER_SEGMENT
	end
	local u01 = v01.Unit
	local u12 = v12.Unit
	local u23 = v23.Unit
	local dot1 = clampFloat(u01:Dot(u12), -1, 1)
	local dot2 = clampFloat(u12:Dot(u23), -1, 1)
	local angle1 = math.acos(dot1)
	local angle2 = math.acos(dot2)
	local curvature = math.max(angle1, angle2) / math.pi -- 0..1
	local base = MIN_SAMPLES_PER_SEGMENT
	local extra = math.floor(curvature * (MAX_SAMPLES_PER_SEGMENT - MIN_SAMPLES_PER_SEGMENT))
	local samples = base + extra
	if samples < MIN_SAMPLES_PER_SEGMENT then samples = MIN_SAMPLES_PER_SEGMENT end
	if samples > MAX_SAMPLES_PER_SEGMENT then samples = MAX_SAMPLES_PER_SEGMENT end
	return samples
end

-- Instance constructor
function CatmullRomSpline.new(points, options)
	options = options or {}
	if type(points) ~= "table" or #points < 4 then
		warn("CatmullRomSpline requires at least 4 points. Returning nil.")
		return nil
	end

	local self = setmetatable({}, CatmullRomSpline)
	self.points = points
	self.segments = #points - 3
	self.tension = options.tension or DEFAULT_TENSION
	self.tangentClamp = options.tangentClamp or DEFAULT_TANGENT_CLAMP
	self.uniform = options.uniform or false

	self._arcSamples = nil       -- array of cumulative normalized t (0..1 across whole curve)
	self._arcCumulative = nil    -- cumulative lengths (normalized 0..1)
	self._totalLength = nil      -- absolute studs length

	return self
end

function CatmullRomSpline:SetUniform(isUniform)
	if isUniform and not self._arcSamples then
		self:_rebuildArcLengthTable()
	end
	self.uniform = isUniform and true or false
end

function CatmullRomSpline:SetTension(newTension)
	self.tension = tonumber(newTension) or self.tension
	self:_invalidateArcLength()
end

function CatmullRomSpline:SetPoints(points)
	if type(points) ~= "table" or #points < 4 then return end
	self.points = points
	self.segments = #points - 3
	self:_invalidateArcLength()
end

function CatmullRomSpline:_invalidateArcLength()
	self._arcSamples = nil
	self._arcCumulative = nil
	self._totalLength = nil
	if self.uniform then
		self:_rebuildArcLengthTable()
	end
end

-- Build adaptive arc-length lookup table across all segments
function CatmullRomSpline:_rebuildArcLengthTable()
	local cumulative = {0}
	local samples = {0}
	local total = 0

	for i = 1, self.segments do
		local p0 = self.points[i]
		local p1 = self.points[i + 1]
		local p2 = self.points[i + 2]
		local p3 = self.points[i + 3]

		local steps = estimateSamplesForSegment(p0, p1, p2, p3)
		local prevPos = p1
		for j = 1, steps do
			local t = j / steps
			local pos = interpolateHermite(t, p0, p1, p2, p3, self.tension, self.tangentClamp)
			local segLen = (pos - prevPos).Magnitude
			total = total + segLen
			table.insert(cumulative, total)
			-- Store global t across entire curve [0,1] for each sample
			local globalT = ((i - 1) + t) / self.segments
			table.insert(samples, globalT)
			prevPos = pos
		end
	end

	-- Normalize cumulative to [0,1]
	if total <= 1e-6 then
		self._arcSamples = samples
		self._arcCumulative = cumulative
		self._totalLength = 0
		return
	end
	for k = 1, #cumulative do
		cumulative[k] = cumulative[k] / total
	end
	self._arcSamples = samples
	self._arcCumulative = cumulative
	self._totalLength = total
end

-- Map uniform t in [0,1] to the curve's parameter space based on arc-length table
function CatmullRomSpline:_mapUniformToNonUniform(t)
	if not self._arcSamples or not self._arcCumulative or #self._arcCumulative < 2 then
		return t
	end

	local target = clampFloat(t, 0, 1)
	local low, high = 1, #self._arcCumulative
	while high - low > 1 do
		local mid = math.floor((low + high) / 2)
		if self._arcCumulative[mid] < target then
			low = mid
		else
			high = mid
		end
	end

	local l0 = self._arcCumulative[low]
	local l1 = self._arcCumulative[high]
	local s0 = self._arcSamples[low]
	local s1 = self._arcSamples[high]
	local denom = (l1 - l0)
	if denom <= 1e-6 then
		return s0
	end
	local alpha = (target - l0) / denom
	return s0 + (s1 - s0) * alpha
end

-- Convert absolute distance (studs) along the curve to parameter t in [0,1]
function CatmullRomSpline:DistanceToT(distance)
	if not self._totalLength then
		self:_rebuildArcLengthTable()
	end
	local total = self._totalLength or 0
	if total <= 1e-6 then return 0 end
	local norm = clampFloat((distance or 0) / total, 0, 1)
	-- Use the arc-length map to get correct parameterization even if uniform=false
	return self:_mapUniformToNonUniform(norm)
end

-- Get a position on the curve at t in [0,1]
function CatmullRomSpline:GetPoint(t)
	t = clampFloat(t, 0, 1)
	if self.uniform then
		-- remap to param space that approximates uniform arc-length
		t = self:_mapUniformToNonUniform(t)
	end

	local scaled = t * self.segments
	local segIndex = math.floor(scaled) + 1
	local localT = scaled - (segIndex - 1)
	if segIndex > self.segments then
		segIndex = self.segments
		localT = 1
	end

	local p0 = self.points[segIndex]
	local p1 = self.points[segIndex + 1]
	local p2 = self.points[segIndex + 2]
	local p3 = self.points[segIndex + 3]
	local pos = interpolateHermite(localT, p0, p1, p2, p3, self.tension, self.tangentClamp)
	return pos
end

-- Get the unit tangent at t in [0,1]
function CatmullRomSpline:GetTangent(t)
	t = clampFloat(t, 0, 1)
	local mappedT = self.uniform and self:_mapUniformToNonUniform(t) or t
	local scaled = mappedT * self.segments
	local segIndex = math.floor(scaled) + 1
	local localT = scaled - (segIndex - 1)
	if segIndex > self.segments then
		segIndex = self.segments
		localT = 1
	end
	local p0 = self.points[segIndex]
	local p1 = self.points[segIndex + 1]
	local p2 = self.points[segIndex + 2]
	local p3 = self.points[segIndex + 3]
	local _, deriv = interpolateHermite(localT, p0, p1, p2, p3, self.tension, self.tangentClamp)
	local mag = deriv.Magnitude
	if mag < 1e-6 then
		-- fallback to finite difference around t
		local h = 1e-3
		local pA = self:GetPoint(clampFloat(t - h, 0, 1))
		local pB = self:GetPoint(clampFloat(t + h, 0, 1))
		local d = pB - pA
		if d.Magnitude < 1e-6 then
			return Vector3.new(1, 0, 0)
		end
		return d.Unit
	end
	return deriv.Unit
end

-- Total arc length of the curve
function CatmullRomSpline:GetLength()
	if not self._totalLength then
		self:_rebuildArcLengthTable()
	end
	return self._totalLength or 0
end

-- Sample N positions along the curve
function CatmullRomSpline:SamplePoints(count)
	local n = math.max(2, math.floor(count or 50))
	local pts = {}
	for i = 0, n - 1 do
		local t = i / (n - 1)
		pts[i + 1] = self:GetPoint(t)
	end
	return pts
end

return CatmullRomSpline