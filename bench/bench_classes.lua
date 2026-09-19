local Point = {}
Point.__index = Point
function Point.new(x, y)
    return setmetatable({ x = x, y = y }, Point)
end
function Point:sum()
    return self.x + self.y
end

local Point3 = setmetatable({}, { __index = Point })
Point3.__index = Point3
function Point3.new(x, y, z)
    local o = Point.new(x, y)
    o.z = z
    return setmetatable(o, Point3)
end
function Point3:total()
    return self:sum() + self.z
end

local N = 200000
local acc = 0
local t0 = os.clock()
for i = 1, N do
    local p = Point3.new(i, i + 1, i + 2)
    acc = acc + p:total()
end
local t1 = os.clock()
print(string.format("lua    classes %d = %d  time: %.4fs", N, acc, t1 - t0))
