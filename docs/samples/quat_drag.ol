## Rotation interactive par quaternion — glisse à la SOURIS (ou au DOIGT) pour
## faire tourner le cube. Chaque glissement compose une petite rotation dans
## l'orientation courante : l'accumulation de quaternions donne un « trackball »
## fluide, sans blocage de cardan.

global cam = graphics.camera(0, 0, 8,  0, 0, 0)
global orient = graphics.quat()   ## orientation courante (identité au départ)
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
    ## glissement horizontal → rotation autour de Y ; vertical → autour de X.
    ## On compose la nouvelle rotation À GAUCHE (repère écran) → effet trackball.
    var spin = graphics.quat_axis(0, 1, 0, dx * 0.5).mul(graphics.quat_axis(1, 0, 0, dy * 0.5))
    orient = spin.mul(orient)
end

func draw()
    graphics.clear(colors.BLACK)
    graphics.fill(colors.SKYBLUE)
    graphics.stroke(colors.BLACK)      ## arêtes → la rotation reste bien lisible
    graphics.begin3d(cam)
        graphics.rotateq(orient)       ## applique l'orientation accumulée
        graphics.cube(0, 0, 0,  3, 3, 3)
    graphics.end3d()
    graphics.draw_text("Glisse pour tourner", 12, 12, 20, colors.WHITE)
end
