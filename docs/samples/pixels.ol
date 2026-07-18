## Bruit de Perlin rendu pixel par pixel : un petit buffer (math.noise, 3e dimension
## = le temps) recalculé chaque frame puis agrandi à la fenêtre → champ lisse animé.
const LOW_W = 128
const LOW_H = 96
const SCALE = 0.044   ## petit = taches plus larges

graphics.canvas(W, H, "Perlin par pixel")
math.noiseSeed(7)
var canvas = image.create(LOW_W, LOW_H)

func draw()
    var t = elapsedTime * 0.3
    image.beginPixels(canvas)
    for y = 0, LOW_H-1 do
        var ny = y * SCALE
        for x = 0, LOW_W-1 do
            var n = math.noise(x * SCALE, ny, t)
            var v = math.clamp((n - 0.5) * 2.0 + 0.5, 0, 1)   ## étire le contraste (bruit resserré autour de 0.5)
            image.setPixel(canvas, x, y, 0.1 + 0.9 * v * v, 0.2 + 0.8 * v, 0.4 + 0.6 * v, 1)   ## dégradé bleu → cyan → blanc
        end
    end
    image.endPixels(canvas)

    graphics.clear(colors.BLACK)
    image.draw(canvas, 0, 0, W, H)
    graphics.text("Perlin par pixel", 12, 12, 18, Color(1, 1, 1))
end
