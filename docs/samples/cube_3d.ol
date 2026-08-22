## Lit 3D plus instancing. Drag with the mouse or a finger to turn the scene:
## every drag composes a quaternion, giving a smooth trackball with no gimbal lock.

## The mouse rotation lives in trackball.ol, a library shared by the 3D examples: the host
## relays the three mouse callbacks to it.
import "trackball.ol"
global ball = Trackball()
global cam = graphics.camera(0, 14, 34,  0, 0, 0)   ## FIXED: it is the scene that turns

func setup()
    graphics.canvas(W, H, "3D - drag to turn")
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
        graphics.grid(16, 2)         ## the ground is drawn BEFORE the rotation, so it stays put
        graphics.rotateq(ball.orient())
        ## a grid of coloured cubes is one draw call, through instancing, whatever the number of colours
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
