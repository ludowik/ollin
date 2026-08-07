## Modèles externes (.obj et .glb) : cadrage automatique (modelSize + fitDistance →
## toujours visible quel que soit le ratio) et rotation interactive par quaternion.
## Glisse à la souris/au doigt pour tourner, sinon rotation douce automatique.
## Le menu « Modèle » passe d'un objet à l'autre : un .obj porte sa seule géométrie
## (le fill le teinte), un .glb embarque aussi sa texture (fill blanc = couleurs
## d'origine). (Playground : ajoute ton fichier dans « Ressources » et complète la
## liste ci-dessous.)

## La rotation à la souris vit dans trackball.ol (bibliothèque partagée par les
## exemples 3D) : l'hôte lui relaie les trois callbacks souris.
import "trackball.ol"
global ball = Trackball()
global cam = graphics.camera(0, 0, 10,  0, 0, 0)

## Une entrée par modèle : tout ce qui change d'un objet à l'autre est ici, le reste
## du programme n'en dépend pas.
global modeles = [
    {nom: "Nœud (.obj)", fichier: "knot.obj", teinte: colors.ORANGE, ambient: 0.25, marge: 1.15, hauteur: 0.15},
    {nom: "Cube texturé (.glb)", fichier: "cube_tex.glb", teinte: colors.WHITE, ambient: 0.5, marge: 1.2, hauteur: 0.12}
]
global modele = nil   ## entrée affichée
global sz = nil       ## dimensions du modèle, pour le cadrage

func choisir(i)
    modele = modeles[i]
    ## graphics.model met le modèle en cache : le rappeler dans draw() ne recharge rien.
    sz = graphics.modelSize(graphics.model(modele.fichier))
    graphics.ambient(modele.ambient)
end

func setup()
    graphics.canvas(W, H, "Modèles 3D")
    graphics.light("dir", -1, -1, -0.6)

    var menu = ui.menu("Modèle")
    menu.button(modeles[1].nom, func() choisir(1) end)
    menu.button(modeles[2].nom, func() choisir(2) end)
    ui.show(menu)

    choisir(1)
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
    var dist = graphics.fitDistance(sz.radius) * modele.marge
    cam.setPos(sz.cx, sz.cy + dist * modele.hauteur, sz.cz + dist)   ## caméra FIXE, cadrée
    cam.lookAt(sz.cx, sz.cy, sz.cz)
    ball.idle(30)   ## rotation douce quand on ne glisse pas

    graphics.begin3d(cam)
        graphics.fill(modele.teinte)
        graphics.translate(sz.cx, sz.cy, sz.cz)            ## pivoter autour du centre du modèle
        graphics.rotateq(ball.orient())
        graphics.translate(-sz.cx, -sz.cy, -sz.cz)
        graphics.drawModel(graphics.model(modele.fichier), 0, 0, 0, 1)
    graphics.end3d()

    graphics.stroke(colors.WHITE)
    graphics.text(modele.nom + " — glisse pour tourner", 12, 12)
end
