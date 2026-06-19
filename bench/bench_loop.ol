var t0 = time()
var s = 0
for i = 1, 10_000_000 do
    s += i
end
var t1 = time()
printf("ollin  loop 10M = {}  time: {}s", s, t1 - t0)
