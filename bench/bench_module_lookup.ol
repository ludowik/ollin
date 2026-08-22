## Measures the cost of resolving `module.function` (a GET_INDEX on every call) against a
## hoisted version (var f = module.function; f(i)) — what an inline cache on GET_INDEX would
## get. The difference is roughly the cache's greatest possible gain.

var N = 5_000_000

## ---- a cheap builtin: the lookup weighs proportionally more ----
var s = 0.0
var t0 = cpuTime()
for i = 1, N do
    s += math.abs(i)
end
var t1 = cpuTime()
var abs_direct = t1 - t0

var fa = math.abs
s = 0.0
var t2 = cpuTime()
for i = 1, N do
    s += fa(i)
end
var t3 = cpuTime()
var abs_hoisted = t3 - t2

## ---- an expensive builtin (noise): the lookup weighs little, which is realistic ----
s = 0.0
var t4 = cpuTime()
for i = 1, N do
    s += math.noise(i * 0.01)
end
var t5 = cpuTime()
var noise_direct = t5 - t4

var fn = math.noise
s = 0.0
var t6 = cpuTime()
for i = 1, N do
    s += fn(i * 0.01)
end
var t7 = cpuTime()
var noise_hoisted = t7 - t6

printf("N = {} appels", N)
printf("abs   direct  = {}s   hoisted = {}s   delta = {}s  ({} ns/call)",
       abs_direct, abs_hoisted, abs_direct - abs_hoisted, (abs_direct - abs_hoisted) * 1e9 / N)
printf("noise direct  = {}s   hoisted = {}s   delta = {}s  ({} ns/call)",
       noise_direct, noise_hoisted, noise_direct - noise_hoisted, (noise_direct - noise_hoisted) * 1e9 / N)
