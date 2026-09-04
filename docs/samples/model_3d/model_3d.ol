## External models (.obj and .glb), framed automatically: modelSize plus fitDistance keep them
## visible whatever the aspect ratio, and the rotation is interactive, by quaternion.
## Drag with the mouse or a finger to turn it, or steer it with the ARROW KEYS; otherwise it rotates
## gently on its own. Wheel or pinch to zoom, double-click to recentre.
## The "Model" menu switches between them, covering the three ways a file can carry its appearance:
## a model may hold its geometry ALONE, and then the fill tints it; it may hold a TEXTURE, and then
## a white fill shows it as painted; or it may hold a COLOUR PER VERTEX, which paints one mesh in
## many colours with no image at all — that is the terrain, coloured by altitude. Four of them are
## classics, each bringing its own weight: Suzanne, the Blender mascot, four thousand triangles of
## sculpted geometry; the Stanford dragon, ninety thousand; the damaged helmet, a real painted
## texture over that geometry; and the Utah teapot, the emblem of the whole field, rebuilt from its
## 32 Bezier patches rather than borrowed as a mesh. Each file's own header carries its source and
## its credit. In the playground, add your file under "Resources" and extend the list below.

## The mouse rotation lives in trackball.ol, a library shared by the 3D examples: the host
## relays the three mouse callbacks to it.
import "../lib/trackball.ol"
global ball = Trackball()
global cam = graphics.camera(0, 0, 10,  0, 0, 0)

## One entry per model: everything that differs from one object to the next lives here, and the
## rest of the program does not depend on it.
global models = [
    {name: "Rubik cube (.glb)", file: "rubik.glb", tint: colors.WHITE, ambient: 0.5, margin: 1.2, height: 0.12},
    {name: "Suzanne (.obj)", file: "suzanne.obj", tint: colors.GRAY, ambient: 0.3, margin: 1.1, height: 0.1},
    {name: "Stanford dragon (.glb)", file: "dragon.glb", tint: colors.GRAY, ambient: 0.3, margin: 1.15, height: 0.15},
    {name: "Damaged helmet (.glb)", file: "helmet.glb", tint: colors.WHITE, ambient: 0.5, margin: 1.15, height: 0.1},
    {name: "Coloured terrain (.glb)", file: "terrain.glb", tint: colors.WHITE, ambient: 0.4, margin: 1.05, height: 0.45},
    {name: "Utah teapot (.glb)", file: "teapot.glb", tint: colors.SKYBLUE, ambient: 0.3, margin: 1.15, height: 0.2}
]
global current = nil   ## the entry on display
global sz = nil       ## the model's dimensions, for the framing

## The zoom multiplies the framing distance rather than replacing it, so every model keeps being
## framed by its own size and the gesture only says "closer" or "further".
global zoom = {
    factor:    1.0,
    min:       0.35,
    max:       4.0,
    wheelStep: 0.1     ## zoom fraction per wheel notch
}

func choose(i)
    current = models[i]
    zoom.factor = 1.0   ## each model has its own framing: the previous zoom means nothing here
    ## graphics.model caches the model, so calling it again in draw() reloads nothing.
    sz = graphics.modelSize(graphics.model(current.file))
    graphics.ambient(current.ambient)
end

func setup()
    graphics.canvas(W, H, "3D models")
    graphics.light("dir", -1, -1, -0.6)

    ## One button per entry: the list is the only place to edit to add a model. Each closure
    ## captures the index of ITS iteration, the loop variable being per-turn.
    var menu = ui.menu("Model")
    for i, model in models do
        menu.button(model.name, func() choose(i) end)
    end
    ui.show(menu)

    choose(1)
end

## Mouse AND touch: on the web a finger drives the pointer, hence the same callbacks.
func mouse.pressed(x, y)
    ball.press(x, y)
end

## A pinch is not a drag: while two fingers are down, the system still emulates the mouse with one
## of them, and the model would spin as one zooms.
func mouse.moved(x, y)
    if touch.count() > 1 then return end
    ball.move(x, y)
end

func mouse.released(x, y)
    ball.release()
end

## The zoom lives in ONE function; the two gestures only differ by the factor they hand it — a
## wheel notch is a step, a pinch is a ratio.
func zoomBy(factor)
    zoom.factor = math.max(zoom.min, math.min(zoom.max, zoom.factor * factor))
end

func mouse.scrolled(x, y, dx, dy)
    zoomBy(1.0 + dy * zoom.wheelStep)
end

## Spreading fingers (scale > 1) bring the model closer, which is a LARGER factor here: the
## distance is divided by it below.
func touch.pinch(scale, cx, cy)
    zoomBy(scale)
end

## Recentre: the orientation AND the zoom go back to their starting values, which is what makes
## the gesture a way out when the model has been turned or zoomed off.
func mouse.doubleClicked(x, y)
    ball.reset()
    zoom.factor = 1.0
end

## The ARROW KEYS turn the model: left and right around the vertical axis, up and down around the
## horizontal one, at KEY_SPIN degrees per second. A held state (keyboard.isDown) and not a key
## event, so the rotation is continuous and independent of the repeat rate — and multiplied by the
## time step, so it keeps its speed whatever the frame rate. Two arrows at once turn diagonally,
## the two amounts composing in the trackball's own frame.
const KEY_SPIN = 90

func arrowSpin(dt)
    var dx = 0
    var dy = 0
    if keyboard.isDown("left") then
        dx -= 1
    end
    if keyboard.isDown("right") then
        dx += 1
    end
    if keyboard.isDown("up") then
        dy -= 1
    end
    if keyboard.isDown("down") then
        dy += 1
    end
    if dx == 0 and dy == 0 then
        return false
    end
    ball.spin(dx * KEY_SPIN * dt, dy * KEY_SPIN * dt)
    return true
end

func update(dt)
    ## The gentle drift only resumes when nobody is steering: it would otherwise pull against the
    ## arrows, exactly as it stands aside during a drag.
    if not arrowSpin(dt) then
        ball.idle(dt, 30)
    end
end

func draw()
    graphics.clear(colors.BLACK)
    var dist = graphics.fitDistance(sz.radius) * current.margin / zoom.factor
    cam.setPos(sz.cx, sz.cy + dist * current.height, sz.cz + dist)   ## a FIXED camera, framed
    cam.lookAt(sz.cx, sz.cy, sz.cz)

    graphics.begin3d(cam)
        graphics.fill(current.tint)
        graphics.translate(sz.cx, sz.cy, sz.cz)            ## pivot around the model's centre
        graphics.rotateq(ball.orient())
        graphics.translate(-sz.cx, -sz.cy, -sz.cz)
        graphics.drawModel(graphics.model(current.file), 0, 0, 0, 1)
    graphics.end3d()

    graphics.stroke(colors.WHITE)
    graphics.text(current.name + " - drag or arrows: turn   wheel or pinch: zoom   double-click: reset", 12, 12)
end
