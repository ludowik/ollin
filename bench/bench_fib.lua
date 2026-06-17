local function fib(n)
    if n <= 1 then return n end
    return fib(n - 1) + fib(n - 2)
end

local t0 = os.clock()
local result = fib(35)
local t1 = os.clock()
print(string.format("lua    fib(35) = %d  time: %.4fs", result, t1 - t0))
