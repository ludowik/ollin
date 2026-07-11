
## Canvas interne en basse résolution, recalculé pixel par pixel à CHAQUE frame
## puis agrandi à la taille de la fenêtre par image.draw → animation fluide
## malgré le coût d'un dessin complet par image.
## (LOW_W/LOW_H : dimensions du buffer — à ne pas confondre avec les globales
##  moteur CW/CH, qui valent le centre W/2 et H/2.)
const LOW_W = 128
const LOW_H = 96

graphics.canvas(W, H, "Pixels animés")
var canvas = image.create(LOW_W, LOW_H)

## `draw` est appelée automatiquement à chaque frame par le moteur.
func draw()
    var t = time()
    ## composante bleue commune à toute la frame (hors boucle → calculée 1 fois)
    var blue = 0.5 + 0.5 * math.sin(t)

    image.begin_pixels(canvas)
    for y = 0, LOW_H-1 do
        var sy = math.sin(y * 0.09 + t * 0.8)        ## terme en y, hors boucle x
        for x = 0, LOW_W-1 do
            ## plasma : somme de sinus décalés par le temps → le motif évolue
            var v = math.sin(x * 0.07 + t) + sy + math.sin((x + y) * 0.05 + t * 1.3)
            var n = (v + 3) / 6                       ## normalise [-3;3] → [0;1]
            image.set_pixel(canvas, x, y, n, 1 - n, blue, 1)
        end
    end
    image.end_pixels(canvas)

    graphics.clear(colors.BLACK)
    image.draw(canvas, 0, 0, W, H)                    ## agrandit le canvas à la fenêtre
end
