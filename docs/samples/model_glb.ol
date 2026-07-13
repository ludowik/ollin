## Modèle GLB TEXTURÉ (.glb) — matériaux et textures EMBARQUÉS.
##   Le .glb est auto-suffisant : géométrie + texture dans UN seul fichier.
##   graphics.drawModel affiche le modèle avec sa propre texture.
##   fill BLANC → couleurs d'origine du modèle ; un fill coloré le teinte.
## Pour charger le tien : ajoute un .glb dans « Ressources » (＋) et change le nom.

global cam = graphics.camera(3, 2.5, 5,  0, 0, 0)

func setup()
    graphics.canvas(W, H, "Modèle GLB")
    graphics.ambient(0.5)                    ## base ambiante
    graphics.light("dir", -1, -1, -0.5)      ## lumière directionnelle
end

func draw()
    graphics.clear(colors.BLACK)             ## efface couleur + profondeur
    cam.orbit(elapsedTime * 0.5, 5, 2.5)     ## caméra en orbite

    graphics.begin3d(cam)
        graphics.fill(colors.WHITE)          ## blanc → garde la texture d'origine
        graphics.drawModel(graphics.model("cube_tex.glb"), 0, 0, 0, 1.4)
    graphics.end3d()

    graphics.draw_text("Modèle GLB — texture embarquée", 12, 12, 18, colors.WHITE)
end
