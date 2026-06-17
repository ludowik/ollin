local function id(x) return x end
local t0 = os.clock()
local s = 0
for i = 1, 1000000 do s = s + id(i) end
local t1 = os.clock()
print(string.format("lua    calls 1M = %d  time: %.4fs", s, t1-t0))
