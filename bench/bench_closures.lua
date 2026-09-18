local function make_adder(x)
    return function(y) return x + y end
end
local t0 = os.clock()
local s = 0
local keep = {}
for i = 1, 1000000 do
    local f = make_adder(i)
    s = s + f(1)
    keep[i] = f -- kept until the end so an escape-analysis JIT cannot eliminate the closure
end
local t1 = os.clock()
s = s + keep[1000000](2)
print(string.format("lua    closures 1M = %d  time: %.4fs", s, t1-t0))
