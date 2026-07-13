## Modèle GLB TEXTURÉ (.glb) — matériaux/textures embarqués + CADRAGE AUTOMATIQUE.
##   Le .glb est auto-suffisant (géométrie + texture dans UN fichier).
##   La caméra s'éloigne selon la taille du modèle et le ratio de l'écran → il
##   reste entièrement visible en portrait comme en paysage.
##   fill BLANC → couleurs d'origine du modèle ; un fill coloré le teinte.
## Pour charger le tien : ajoute un .glb dans « Ressources » (＋) et change le nom.

global cam = graphics.camera(0, 0, 10,  0, 0, 0)
global sz = nil

func setup()
    graphics.canvas(W, H, "Modèle GLB")
    graphics.ambient(0.5)
    graphics.light("dir", -1, -1, -0.5)
    sz = graphics.modelSize(graphics.model("cube_tex.glb"))   ## dimensions (une fois)
    cam.look_at(sz.cx, sz.cy, sz.cz)                          ## viser le centre
end

func draw()
    graphics.clear(colors.BLACK)
    var dist = graphics.fitDistance(sz.radius) * 1.2          ## marge ; suit le ratio écran
    cam.orbit(elapsedTime * 0.5, dist, dist * 0.25)

    graphics.begin3d(cam)
        graphics.fill(colors.WHITE)                          ## blanc → texture d'origine
        graphics.drawModel(graphics.model("cube_tex.glb"), 0, 0, 0, 1)
    graphics.end3d()

    graphics.draw_text("Modèle GLB — cadrage auto", 12, 12, 18, colors.WHITE)
end
