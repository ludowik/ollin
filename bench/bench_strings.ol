## Strings: concatenation, number-to-string coercion and interpolation.
## Measures interning, hashing and the UTF-8 decoding of strings.

var N = 200_000
var nm = "ollin"
var total = 0

var t0 = cpuTime()
for i = 1, N do
    var a = "item" + i + ":" + nm      ## concatenation plus coercion
    var b = "item{i}:{nm}"             ## interpolation
    total += len(a) + len(b)
end
var t1 = cpuTime()
printf("ollin  strings {} = {}  time: {}s", N, total, t1 - t0)
