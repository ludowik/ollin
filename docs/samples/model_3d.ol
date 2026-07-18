## Modèle externe (.obj), cadrage automatique (modelSize + fitDistance → toujours
## visible quel que soit le ratio) et rotation interactive par quaternion : glisse à
## la souris/au doigt pour tourner, sinon rotation douce automatique.
## (Playground : ajoute un .obj dans « Ressources » et change le nom.)

global cam = graphics.camera(0, 0, 10,  0, 0, 0)
global sz = nil
global orient = graphics.quat()
global dragging = false
global lastx = 0
global lasty = 0

func setup()
    graphics.canvas(W, H, "Modèle 3D")
    graphics.ambient(0.25)
    graphics.light("dir", -1, -1, -0.6)
    sz = graphics.modelSize(graphics.model("knot.obj"))
end

func mouse.pressed(x, y)
    dragging = true
    lastx = x
    lasty = y
end

func mouse.released(x, y)
    dragging = false
end

func mouse.moved(x, y)
    if not dragging then
        return
    end
    var dx = x - lastx
    var dy = y - lasty
    lastx = x
    lasty = y
    ## dx → rotation autour de Y, dy → autour de X ; composée À GAUCHE = repère écran (trackball)
    var spin = graphics.quatAxis(0, 1, 0, dx * 0.5).mul(graphics.quatAxis(1, 0, 0, dy * 0.5))
    orient = spin.mul(orient)
end

func draw()
    graphics.clear(colors.BLACK)
    var dist = graphics.fitDistance(sz.radius) * 1.15      ## +15% de marge
    cam.setPos(sz.cx, sz.cy + dist * 0.15, sz.cz + dist)   ## caméra FIXE, cadrée (c'est le modèle qui tourne)
    cam.lookAt(sz.cx, sz.cy, sz.cz)
    if not dragging then
        orient = graphics.quatAxis(0, 1, 0, deltaTime * 30).mul(orient)   ## rotation douce au repos
    end

    graphics.begin3d(cam)
        graphics.fill(colors.ORANGE)
        graphics.translate(sz.cx, sz.cy, sz.cz)            ## pivoter autour du centre du modèle
        graphics.rotateq(orient)
        graphics.translate(-sz.cx, -sz.cy, -sz.cz)
        graphics.drawModel(graphics.model("knot.obj"), 0, 0, 0, 1)
    graphics.end3d()

    graphics.text("Glisse pour tourner — .obj cadrage auto", 12, 12, 18, colors.WHITE)
end
