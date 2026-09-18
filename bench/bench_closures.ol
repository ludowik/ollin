## Closures: a fresh closure created (one upvalue captured) and called on every iteration —
## distinct from calls 1M, which calls the SAME function with nothing to capture. Kept in an
## array until the end so an escape-analysis JIT cannot prove a closure dead and eliminate it.

func make_adder(x)
    return func(y)
        return x + y
    end
end

var t0 = cpuTime()
var s = 0
var keep = []
for i = 1, 1_000_000 do
    var f = make_adder(i)
    s += f(1)
    keep[i] = f
end
var t1 = cpuTime()
s += keep[1_000_000](2)
printf("ollin  closures 1M = {}  time: {}s", s, t1 - t0)
