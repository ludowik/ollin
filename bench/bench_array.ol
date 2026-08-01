var N = 1_000_000
var t0 = cpuTime()
var arr = []
for i = 1, N do
    arr[i] = i
end
var s = 0
for i = 1, N do
    s += arr[i]
end
var t1 = cpuTime()
printf("ollin  array 1M = {}  time: {}s", s, t1 - t0)
