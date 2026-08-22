## Iteration with `for ... in` over an array then over a map — the MAKE_ITER /
## FOR_ITER_NEXT path, distinct from the numeric `for`, which has its own fast path.
## The collections are built OUTSIDE the measurement.

var NA = 100_000    ## taille du tableau, parcouru PA fois
var PA = 20
var NM = 10_000     ## the number of keys in the map, walked PM times
var PM = 40

var arr = []
for i = 1, NA do
    arr[i] = i
end

var m = {}
for i = 1, NM do
    m["k{i}"] = i
end

var acc = 0
var t0 = cpuTime()
for p = 1, PA do
    for v in arr do
        acc += v
    end
end
for p = 1, PM do
    for k, v in m do
        acc += v
    end
end
var t1 = cpuTime()
printf("ollin  iter {} = {}  time: {}s", NA * PA + NM * PM, acc, t1 - t0)
