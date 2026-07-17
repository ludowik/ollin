## Champ de bruit de Perlin rendu PIXEL PAR PIXEL. Un petit canvas interne est
## recalculé à chaque frame (math.noise, la 3e dimension = le temps) puis agrandi
## à la fenêtre par image.draw → un champ lisse qui ondule, plus fin qu'un rendu
## par cellules. (LOW_W/LOW_H : dimensions du buffer, pas les globales CW/CH.)
const LOW_W = 128
const LOW_H = 96
const SCALE = 0.044   ## zoom du bruit (petit = taches plus larges)

graphics.canvas(W, H, "Perlin par pixel")
math.noiseSeed(7)
var canvas = image.create(LOW_W, LOW_H)

## `draw` est appelée automatiquement à chaque frame par le moteur.
func draw()
    var t = elapsedTime * 0.3               ## temps → 3e dimension du bruit
    image.beginPixels(canvas)
    for y = 0, LOW_H-1 do
        var ny = y * SCALE                  ## terme en y, hors boucle x
        for x = 0, LOW_W-1 do
            var n = math.noise(x * SCALE, ny, t)
            ## le bruit se resserre autour de 0.5 → on étire le contraste, borné
            var v = math.clamp((n - 0.5) * 2.0 + 0.5, 0, 1)
            ## dégradé continu : bleu profond → cyan → blanc (révèle la structure)
            image.setPixel(canvas, x, y, 0.1 + 0.9 * v * v, 0.2 + 0.8 * v, 0.4 + 0.6 * v, 1)
        end
    end
    image.endPixels(canvas)

    graphics.clear(colors.BLACK)
    image.draw(canvas, 0, 0, W, H)          ## agrandit le canvas à la fenêtre
    graphics.drawText("Perlin par pixel", 12, 12, 18, Color(1, 1, 1))
end
