## Modèle GLB texturé (géométrie + texture dans UN fichier), cadrage automatique
## selon taille et ratio, et rotation interactive par quaternion : glisse à la
## souris/au doigt pour tourner, sinon rotation douce automatique.
## (Playground : ajoute un .glb dans « Ressources » et change le nom.)

## La rotation à la souris vit dans trackball.ol (bibliothèque partagée par les
## exemples 3D) : l'hôte lui relaie les trois callbacks souris.
import "trackball.ol"
global ball = Trackball()
global cam = graphics.camera(0, 0, 10,  0, 0, 0)
global sz = nil

func setup()
    graphics.canvas(W, H, "Modèle GLB")
    graphics.ambient(0.5)
    graphics.light("dir", -1, -1, -0.5)
    sz = graphics.modelSize(graphics.model("cube_tex.glb"))
end

## Souris ET tactile : sur le web, le doigt pilote le pointeur → mêmes callbacks.
func mouse.pressed(x, y)
    ball.press(x, y)
end

func mouse.moved(x, y)
    ball.move(x, y)
end

func mouse.released(x, y)
    ball.release()
end

func draw()
    graphics.clear(colors.BLACK)
    var dist = graphics.fitDistance(sz.radius) * 1.2
    cam.setPos(sz.cx, sz.cy + dist * 0.12, sz.cz + dist)   ## caméra FIXE, cadrée (c'est le modèle qui tourne)
    cam.lookAt(sz.cx, sz.cy, sz.cz)
    ball.idle(30)   ## rotation douce quand on ne glisse pas

    graphics.begin3d(cam)
        graphics.fill(colors.WHITE)      ## blanc = couleurs d'origine du modèle ; un fill coloré le teinte
        graphics.translate(sz.cx, sz.cy, sz.cz)            ## pivoter autour du centre du modèle
        graphics.rotateq(ball.orient())
        graphics.translate(-sz.cx, -sz.cy, -sz.cz)
        graphics.drawModel(graphics.model("cube_tex.glb"), 0, 0, 0, 1)
    graphics.end3d()

    graphics.stroke(colors.WHITE)
    graphics.text("Glisse pour tourner — GLB cadrage auto", 12, 12)
end
