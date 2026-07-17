## Modèle GLB texturé (géométrie + texture dans UN fichier), cadrage automatique
## selon taille et ratio d'écran. (Playground : ajoute un .glb dans « Ressources ».)

global cam = graphics.camera(0, 0, 10,  0, 0, 0)
global sz = nil

func setup()
    graphics.canvas(W, H, "Modèle GLB")
    graphics.ambient(0.5)
    graphics.light("dir", -1, -1, -0.5)
    sz = graphics.modelSize(graphics.model("cube_tex.glb"))
    cam.lookAt(sz.cx, sz.cy, sz.cz)
end

func draw()
    graphics.clear(colors.BLACK)
    var dist = graphics.fitDistance(sz.radius) * 1.2
    cam.orbit(elapsedTime * 0.5, dist, dist * 0.25)

    graphics.begin3d(cam)
        graphics.fill(colors.WHITE)      ## blanc = couleurs d'origine du modèle ; un fill coloré le teinte
        graphics.drawModel(graphics.model("cube_tex.glb"), 0, 0, 0, 1)
    graphics.end3d()

    graphics.drawText("Modèle GLB — cadrage auto", 12, 12, 18, colors.WHITE)
end
