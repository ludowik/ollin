## Mandelbrot : arithmétique FLOTTANTE pure (multiplications, additions,
## comparaisons), seul benchmark à solliciter la promotion entier/flottant.
## Le total d'itérations sert de somme de contrôle : il doit être identique
## dans les trois langages.

var W = 200
var H = 200
var MAXI = 50
var total = 0

var t0 = cpuTime()
for py = 0, H - 1 do
    var y0 = py * 2.0 / H - 1.0
    for px = 0, W - 1 do
        var x0 = px * 3.0 / W - 2.0
        var zx = 0.0
        var zy = 0.0
        var n = 0
        while n < MAXI and zx * zx + zy * zy <= 4.0 do
            var tmp = zx * zx - zy * zy + x0
            zy = 2.0 * zx * zy + y0
            zx = tmp
            n += 1
        end
        total += n
    end
end
var t1 = cpuTime()
printf("ollin  mandelbrot {}x{} = {}  time: {}s", W, H, total, t1 - t0)
