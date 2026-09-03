## PLACING objects in 3D, and the cost of drawing them. Two subjects, and the cubes are only the
## pretext: for the shapes themselves, see "Primitives 3D".
##
## TRANSFORMS. translate, rotate and scale do not move an object, they move the FRAME one draws
## in, and they compose: the white cube up top is placed by a translate then turned about two
## different axes, all of it inside the rotation of the whole scene. push and pop bracket that,
## so what is between them changes nothing outside. The ground, drawn BEFORE the scene's
## rotation, stays put — which is the whole point of an order that composes.
##
## INSTANCING. The 81 coloured cubes are drawn in ONE call. The engine groups by shape and by
## texture, the colour travelling with each instance, so 81 hues cost no more than one; a second
## shape, on the other hand, would cost a second call.
##
## The camera here is FIXED and it is the SCENE that turns. The opposite approach — a still scene
## and a camera one moves — is in "Isometric camera": orbit, zoom, pinch.
##
## The rotation itself lives in trackball.ol, a library shared by the 3D examples: dragging
## composes quaternions, hence a smooth trackball with no gimbal lock. The mouse.* callbacks are
## global to the engine, so the host relays the three of them.
import "../lib/trackball.ol"
global ball = Trackball()
global cam = graphics.camera(0, 14, 34,  0, 0, 0)   ## FIXED: it is the scene that turns

func setup()
    graphics.canvas(W, H, "3D transforms")
    graphics.ambient(0.2)
    graphics.light("dir", -1, -2, -0.5)
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

    graphics.noStroke()
    graphics.begin3d(cam)
        graphics.grid(16, 2)         ## before rotateq, hence unaffected by it
        graphics.rotateq(ball.orient())
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

    graphics.stroke(colors.WHITE)
    graphics.fontSize(20)
    graphics.text("Drag to turn the scene", 12, 12)
end
