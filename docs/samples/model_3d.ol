## Modèle externe (.obj) avec cadrage automatique : modelSize + fitDistance
## éloignent la caméra selon la taille du modèle ET le ratio de l'écran → toujours
## visible en entier. (Playground : ajoute un .obj dans « Ressources » et change le nom.)

global cam = graphics.camera(0, 0, 10,  0, 0, 0)
global sz = nil

func setup()
    graphics.canvas(W, H, "Modèle 3D")
    graphics.ambient(0.25)
    graphics.light("dir", -1, -1, -0.6)
    sz = graphics.modelSize(graphics.model("knot.obj"))
    cam.lookAt(sz.cx, sz.cy, sz.cz)
end

func draw()
    graphics.clear(colors.BLACK)
    var dist = graphics.fitDistance(sz.radius) * 1.15      ## +15% de marge
    cam.orbit(elapsedTime * 0.5, dist, dist * 0.3)

    graphics.begin3d(cam)
        graphics.fill(colors.ORANGE)
        graphics.drawModel(graphics.model("knot.obj"), 0, 0, 0, 1)
    graphics.end3d()

    graphics.drawText("Modèle externe (.obj) — cadrage auto", 12, 12, 18, colors.WHITE)
end
