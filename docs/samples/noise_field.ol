## math.noise — champ de bruit de Perlin animé.
## La 3e dimension du bruit sert de temps : le motif évolue en douceur,
## de façon continue et déterministe.

var W = window.width
var H = window.height
graphics.canvas(W, H, "math.noise")

var cell = 14        ## taille d'une cellule (px)
var scale = 0.06     ## zoom du bruit : plus petit = motifs plus larges

math.noise_seed(7)   ## bruit reproductible d'un lancement à l'autre

func frame()
    var t = time() * 0.25

    var y = 0
    while y < H do
        var x = 0
        while x < W do
            ## bruit dans [0, 1] piloté par la position ET le temps
            var n = math.noise(x * scale, y * scale, t)
            graphics.fill(Color(n, n * 0.6 + 0.2, 1 - n))
            graphics.rect(x, y, cell, cell)
            x = x + cell
        end
        y = y + cell
    end

    graphics.draw_text("math.noise(x, y, temps)", 12, 12, 18, Color(1, 1, 1))
end

graphics.run(frame)
