## Benchmark: creating and using N objects with several properties

var N = 100_000

var t0 = cpuTime()

var i = 0
while i < N do
    var obj = {"x": 1, "y": 2, "z": 3, "name": "point", "value": 42}
    var s = obj["x"] + obj["y"] + obj["z"] + obj["value"]
    obj["x"] += 1
    obj["value"] *= 2
    i += 1
end

var t1 = cpuTime()
printf("ollin  objects N={}  time: {}s", N, t1 - t0)
