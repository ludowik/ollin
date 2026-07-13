## Chargement d'un MODÈLE EXTERNE (.obj) en 3D.
##   graphics.model(nom)                       → handle vers un modèle
##   graphics.drawModel(handle, x,y,z [, éch]) → le dessine (teinte = fill, éclairé)
## Ici le modèle "knot.obj" est fourni avec les exemples. Pour charger TON modèle :
## ajoute un fichier .obj dans « Ressources » (＋), puis remplace "knot.obj" par son
## nom. (v1 : format OBJ, la couleur vient du fill ; GLB/matériaux à venir.)

global cam = graphics.camera(0, 3, 9,  0, 0, 0)

func setup()
    graphics.canvas(W, H, "Modèle 3D")
    graphics.ambient(0.25)                   ## base ambiante
    graphics.light("dir", -1, -1, -0.6)      ## lumière directionnelle
end

func draw()
    graphics.clear(colors.BLACK)             ## efface couleur + profondeur
    cam.orbit(elapsedTime * 0.5, 9, 3)       ## caméra en orbite (angle en radians)

    graphics.begin3d(cam)
        graphics.fill(colors.ORANGE)         ## teinte appliquée au modèle
        graphics.drawModel(graphics.model("knot.obj"), 0, 0, 0, 1)
    graphics.end3d()

    graphics.draw_text("Modèle externe (.obj) — ajoute le tien dans Ressources", 12, 12, 18, colors.WHITE)
end
