## 3D éclairée + instancing. Glisse à la souris/au doigt pour tourner la scène :
## chaque glissement compose un quaternion → « trackball » fluide, sans blocage de cardan.

global cam = graphics.camera(0, 14, 34,  0, 0, 0)   ## FIXE : c'est la scène qui tourne
global orient = graphics.quat()
global dragging = false
global lastx = 0
global lasty = 0

func setup()
    graphics.canvas(W, H, "3D — glisser pour tourner")
    graphics.ambient(0.2)
    graphics.light("dir", -1, -2, -0.5)
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

    graphics.noStroke()
    graphics.begin3d(cam)
        graphics.grid(16, 2)         ## sol dessiné AVANT la rotation → reste fixe
        graphics.rotateq(orient)
        ## grille de cubes colorés = 1 seul draw call (instancing) malgré N couleurs
        for x = -4, 4 do
            for z = -4, 4 do
                var t = elapsedTime * 2 + x + z
                var h = 1 + (math.sin(t) + 1) * 1.5
                graphics.fill(Color((x + 4) / 8, (z + 4) / 8, 0.8))
                graphics.cube(x * 2, h / 2, z * 2,  1.4, h, 1.4)
            end
        end

        graphics.push()
            graphics.translate(0, 6, 0)
            graphics.rotateY(elapsedTime * 60)
            graphics.rotate(elapsedTime * 40, 1, 0, 1)
            graphics.fill(colors.WHITE)
            graphics.cube(0, 0, 0,  2, 2, 2)
        graphics.pop()
    graphics.end3d()

    graphics.drawText("Glisse pour tourner la scène", 12, 12, 20, colors.WHITE)
end
