local N = 200000
local nm = "ollin"
local total = 0
local t0 = os.clock()
for i = 1, N do
    local a = "item" .. i .. ":" .. nm
    local b = string.format("item%d:%s", i, nm)
    total = total + #a + #b
end
local t1 = os.clock()
print(string.format("lua    strings %d = %d  time: %.4fs", N, total, t1 - t0))
