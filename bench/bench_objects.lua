-- Benchmark : création et usage de N objets avec plusieurs propriétés

local N = 100000

local t0 = os.clock()

for i = 1, N do
    local obj = {
        x     = 1,
        y     = 2,
        z     = 3,
        name  = "point",
        value = 42
    }
    -- lecture
    local s = obj.x + obj.y + obj.z + obj.value
    -- écriture
    obj.x     = obj.x + 1
    obj.value = obj.value * 2
end

local t1 = os.clock()
print(string.format("lua    objects N=%d  time: %.4fs", N, t1 - t0))
