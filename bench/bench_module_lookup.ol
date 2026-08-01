## Mesure du coût de résolution `module.fonction` (GET_INDEX à chaque appel)
## vs version hoistée (var f = module.fonction ; f(i)) — ce qu'un inline cache
## sur GET_INDEX obtiendrait. Le delta ≈ gain maximal du cache.

var N = 5_000_000

## ---- builtin bon marché : le lookup pèse proportionnellement plus ----
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

## ---- builtin coûteux (noise) : le lookup pèse peu, réalisme ----
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
printf("abs   direct  = {}s   hoisté = {}s   delta = {}s  ({} ns/appel)",
       abs_direct, abs_hoisted, abs_direct - abs_hoisted, (abs_direct - abs_hoisted) * 1e9 / N)
printf("noise direct  = {}s   hoisté = {}s   delta = {}s  ({} ns/appel)",
       noise_direct, noise_hoisted, noise_direct - noise_hoisted, (noise_direct - noise_hoisted) * 1e9 / N)
