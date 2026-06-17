local t0 = os.clock()
local s = 0
for i = 1, 10000000 do s = s + i end
local t1 = os.clock()
print(string.format("lua    loop 10M = %d  time: %.4fs", s, t1-t0))
