## Rotation par quaternion : glisse à la souris/au doigt pour tourner le cube.
## Chaque glissement compose un quaternion → « trackball » fluide, sans blocage de cardan.

global cam = graphics.camera(0, 0, 14,  0, 0, 0)
global orient = graphics.quat()
global dragging = false
global lastx = 0
global lasty = 0

func setup()
    graphics.canvas(W, H, "Quaternions — glisser pour tourner")
    graphics.ambient(0.2)
    graphics.light("dir", -1, -1, -1)
end

## Souris ET tactile : sur le web, le doigt pilote le pointeur → mêmes callbacks.
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
    graphics.fill(colors.SKYBLUE)
    graphics.stroke(colors.BLACK)      ## arêtes → rotation plus lisible
    graphics.begin3d(cam)
        graphics.grid(12, 1)           ## sol dessiné avant la rotation → reste fixe
        graphics.rotateq(orient)
        graphics.cube(0, 0, 0,  3, 3, 3)
    graphics.end3d()
    graphics.drawText("Glisse pour tourner", 12, 12, 20, colors.WHITE)
end
