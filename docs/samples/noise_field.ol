## math.noise — champ de bruit de Perlin animé, redessiné à chaque frame.
## La 3e dimension du bruit sert de temps : les motifs ondulent en douceur.
## Le bruit fBm se resserre autour de 0.5 → on étire un peu le contraste, puis
## on applique un dégradé continu (bleu → cyan → blanc) qui révèle la structure
## lisse du bruit : de grandes taches molles qui se déforment dans le temps.

graphics.canvas(W, H, "math.noise")

math.noise_seed(7)

var CELL = 8          ## taille d'une cellule (px) — petit = plus de définition
var SCALE = 0.0102145 ## zoom du bruit (petit = taches plus larges)

## `draw` est appelée automatiquement à chaque frame par le moteur.
func draw()
    graphics.noStroke()   ## pas de contour → cellules jointives, sans bordure
    var t = elapsedTime * 0.3

    for y = 0, H - 1, CELL do
        for x = 0, W - 1, CELL do
            var n = math.noise(x * SCALE, y * SCALE, t)
            ## étirement de contraste autour de 0.5, borné dans [0, 1]
            var v = (n - 0.5) * 2.0 + 0.5
            v = math.clamp(v, 0, 1)
            ## dégradé continu : bleu profond → cyan → blanc
            graphics.fill(Color(0.1 + 0.9 * v * v, 0.2 + 0.8 * v, 0.4 + 0.6 * v))
            graphics.rect(x, y, CELL, CELL)
        end
    end

    graphics.draw_text("math.noise(x, y, temps)", 14, 14, 18, Color(1, 1, 1))
end
