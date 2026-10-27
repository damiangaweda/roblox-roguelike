--!strict
-- Plane geometry shared by the core modules. Angles are radians from +x
-- toward +z.

local Geometry = {}

function Geometry.distance(ax: number, az: number, bx: number, bz: number): number
	local dx, dz = ax - bx, az - bz
	return math.sqrt(dx * dx + dz * dz)
end

-- The angle of the vector (dx, dz); 0 for the zero vector.
function Geometry.angle(dx: number, dz: number): number
	if dx == 0 and dz == 0 then
		return 0
	end
	return math.atan2(dz, dx)
end

-- The smallest difference between two angles, in [0, pi].
function Geometry.angleBetween(a: number, b: number): number
	local d = (a - b) % (2 * math.pi)
	if d > math.pi then
		d = 2 * math.pi - d
	end
	return d
end

-- The unit vector of (dx, dz), or (1, 0) for the zero vector.
function Geometry.normalize(dx: number, dz: number): (number, number)
	local length = math.sqrt(dx * dx + dz * dz)
	if length < 1e-9 then
		return 1, 0
	end
	return dx / length, dz / length
end

-- Whether the angle from (fromX, fromZ) toward (toX, toZ) lies within an arc
-- of `arcDegrees` centred on `facing`.
function Geometry.inArc(
	fromX: number,
	fromZ: number,
	facing: number,
	arcDegrees: number,
	toX: number,
	toZ: number
): boolean
	if arcDegrees >= 360 then
		return true
	end
	local toward = Geometry.angle(toX - fromX, toZ - fromZ)
	return Geometry.angleBetween(facing, toward) <= math.rad(arcDegrees) / 2
end

-- Moves (x, z) toward (toX, toZ) by at most `step` studs. Returns the new
-- point and whether it arrived.
function Geometry.stepToward(
	x: number,
	z: number,
	toX: number,
	toZ: number,
	step: number
): (number, number, boolean)
	local dx, dz = toX - x, toZ - z
	local distance = math.sqrt(dx * dx + dz * dz)
	if distance <= step then
		return toX, toZ, true
	end
	return x + dx / distance * step, z + dz / distance * step, false
end

return Geometry
