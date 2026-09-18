## Closures: a fresh closure created (one upvalue captured) and called on every iteration —
## distinct from calls 1M, which calls the SAME function with nothing to capture.

func make_adder(x)
    return func(y)
        return x + y
    end
end

var t0 = cpuTime()
var s = 0
for i = 1, 1_000_000 do
    var f = make_adder(i)
    s += f(1)
end
var t1 = cpuTime()
printf("ollin  closures 1M = {}  time: {}s", s, t1 - t0)
