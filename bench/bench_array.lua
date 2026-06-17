local N = 1000000
local arr = {}
local t0 = os.clock()
for i = 1, N do arr[i] = i end
local s = 0
for i = 1, N do s = s + arr[i] end
local t1 = os.clock()
print(string.format("lua    array 1M = %d  time: %.4fs", s, t1-t0))
