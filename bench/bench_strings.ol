## Chaînes : concaténation, coercition nombre→chaîne et interpolation.
## Mesure l'internement, le hachage et le décodage UTF-8 des chaînes.

var N = 200_000
var nm = "ollin"
var total = 0

var t0 = cpuTime()
for i = 1, N do
    var a = "item" + i + ":" + nm      ## concaténation + coercition
    var b = "item{i}:{nm}"             ## interpolation
    total += len(a) + len(b)
end
var t1 = cpuTime()
printf("ollin  strings {} = {}  time: {}s", N, total, t1 - t0)
