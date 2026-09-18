-- Benchmark: creating and using N objects with several properties, kept in an array until
-- the end so LuaJIT's allocation sinking cannot prove them dead and skip them.

local N = 100000

local t0 = os.clock()

local keep = {}
for i = 1, N do
    local obj = {
        x     = i,
        y     = 2,
        z     = 3,
        name  = "point",
        value = 42
    }
    obj.x     = obj.x + 1
    obj.value = obj.value * 2
    keep[i] = obj
end

local t1 = os.clock()
local total = keep[N].x + keep[N].value
print(string.format("lua    objects %d = %d  time: %.4fs", N, total, t1 - t0))
