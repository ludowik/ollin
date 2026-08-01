var t0 = cpuTime()
var s = 0
for i = 1, 10_000_000 do
    s += i
end
var t1 = cpuTime()
printf("ollin  loop 10M = {}  time: {}s", s, t1 - t0)
