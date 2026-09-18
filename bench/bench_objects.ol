## Benchmark: creating and using N objects with several properties, kept in an array until
## the end so an escape-analysis JIT (LuaJIT) cannot prove them dead and skip the allocation.

var N = 100_000

var t0 = cpuTime()

var keep = []
for i = 1, N do
    var obj = {"x": i, "y": 2, "z": 3, "name": "point", "value": 42}
    obj["x"] += 1
    obj["value"] *= 2
    keep[i] = obj
end

var t1 = cpuTime()
var total = keep[N]["x"] + keep[N]["value"]
printf("ollin  objects {} = {}  time: {}s", N, total, t1 - t0)
