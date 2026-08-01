func id(x)
    return x
end
var t0 = cpuTime()
var s = 0
for i = 1, 1_000_000 do
    s += id(i)
end
var t1 = cpuTime()
printf("ollin  calls 1M = {}  time: {}s", s, t1 - t0)
