## External models (.obj and .glb), framed automatically: modelSize plus fitDistance keep them
## toujours visible quel que soit le ratio) et rotation interactive par quaternion.
## Drag with the mouse or a finger to turn it; otherwise it rotates gently on its own.
## The "Model" menu switches from one object to the other: an .obj carries its geometry alone
## (le fill le teinte), un .glb embarque aussi sa texture (fill blanc = couleurs
## its own colours). In the playground, add your file under "Resources" and extend the
## liste ci-dessous.)

## The mouse rotation lives in trackball.ol, a library shared by the 3D examples: the host
## relays the three mouse callbacks to it.
import "trackball.ol"
global ball = Trackball()
global cam = graphics.camera(0, 0, 10,  0, 0, 0)

## One entry per model: everything that differs from one object to the next lives here, and the
## rest of the program does not depend on it.
global models = [
    {name: "Nœud (.obj)", file: "knot.obj", tint: colors.ORANGE, ambient: 0.25, margin: 1.15, height: 0.15},
    {name: "Textured cube (.glb)", file: "cube_tex.glb", tint: colors.WHITE, ambient: 0.5, margin: 1.2, height: 0.12}
]
global current = nil   ## the entry on display
global sz = nil       ## the model's dimensions, for the framing

func choose(i)
    current = models[i]
    ## graphics.model caches the model, so calling it again in draw() reloads nothing.
    sz = graphics.modelSize(graphics.model(current.file))
    graphics.ambient(current.ambient)
end

func setup()
    graphics.canvas(W, H, "3D models")
    graphics.light("dir", -1, -1, -0.6)

    var menu = ui.menu("Model")
    menu.button(models[1].name, func() choose(1) end)
    menu.button(models[2].name, func() choose(2) end)
    ui.show(menu)

    choose(1)
end

## Mouse AND touch: on the web a finger drives the pointer, hence the same callbacks.
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
    var dist = graphics.fitDistance(sz.radius) * current.margin
    cam.setPos(sz.cx, sz.cy + dist * current.height, sz.cz + dist)   ## a FIXED camera, framed
    cam.lookAt(sz.cx, sz.cy, sz.cz)
    ball.idle(30)   ## rotation douce quand on ne glisse pas

    graphics.begin3d(cam)
        graphics.fill(current.tint)
        graphics.translate(sz.cx, sz.cy, sz.cz)            ## pivot around the model's centre
        graphics.rotateq(ball.orient())
        graphics.translate(-sz.cx, -sz.cy, -sz.cz)
        graphics.drawModel(graphics.model(current.file), 0, 0, 0, 1)
    graphics.end3d()

    graphics.stroke(colors.WHITE)
    graphics.text(current.name + " — glisse pour tourner", 12, 12)
end
