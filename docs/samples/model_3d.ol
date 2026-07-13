## Chargement d'un MODÈLE EXTERNE (.obj) — CADRAGE AUTOMATIQUE.
##   La caméra s'éloigne selon la TAILLE du modèle ET le RATIO de l'écran
##   (portrait / paysage) → le modèle reste toujours visible en entier.
##   graphics.modelSize(handle) → { w, h, d, cx, cy, cz, radius }
##   graphics.fitDistance(rayon [, fovy]) → distance pour tout voir (ratio courant)
## Pour charger le tien : ajoute un .obj dans « Ressources » (＋) et change le nom.

global cam = graphics.camera(0, 0, 10,  0, 0, 0)
global sz = nil

func setup()
    graphics.canvas(W, H, "Modèle 3D")
    graphics.ambient(0.25)
    graphics.light("dir", -1, -1, -0.6)
    sz = graphics.modelSize(graphics.model("knot.obj"))   ## dimensions (une seule fois)
    cam.look_at(sz.cx, sz.cy, sz.cz)                       ## viser le centre du modèle
end

func draw()
    graphics.clear(colors.BLACK)
    var dist = graphics.fitDistance(sz.radius) * 1.15      ## +15% de marge ; suit le ratio
    cam.orbit(elapsedTime * 0.5, dist, dist * 0.3)         ## orbite auto-cadrée

    graphics.begin3d(cam)
        graphics.fill(colors.ORANGE)
        graphics.drawModel(graphics.model("knot.obj"), 0, 0, 0, 1)
    graphics.end3d()

    graphics.draw_text("Modèle externe (.obj) — cadrage auto", 12, 12, 18, colors.WHITE)
end
