func id(x)
    return x
end
var t0 = time()
var s = 0
for i = 1, 1_000_000
    s += id(i)
end
var t1 = time()
printf("ollin  calls 1M = {}  time: {}s", s, t1 - t0)
