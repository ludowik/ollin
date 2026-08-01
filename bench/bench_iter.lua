local NA, PA = 100000, 20
local NM, PM = 10000, 40

local arr = {}
for i = 1, NA do arr[i] = i end
local m = {}
for i = 1, NM do m["k" .. i] = i end

local acc = 0
local t0 = os.clock()
for _ = 1, PA do
    for _, v in ipairs(arr) do acc = acc + v end
end
for _ = 1, PM do
    for _, v in pairs(m) do acc = acc + v end
end
local t1 = os.clock()
print(string.format("lua    iter %d = %d  time: %.4fs", NA * PA + NM * PM, acc, t1 - t0))
