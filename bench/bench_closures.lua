local function make_adder(x)
    return function(y) return x + y end
end
local t0 = os.clock()
local s = 0
for i = 1, 1000000 do
    local f = make_adder(i)
    s = s + f(1)
end
local t1 = os.clock()
print(string.format("lua    closures 1M = %d  time: %.4fs", s, t1-t0))
