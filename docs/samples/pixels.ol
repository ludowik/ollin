var W = window.width
var H = window.height

graphics.canvas(W, H, "Pixels")
var canvas = image.create(W, H)

for y = 0, H-1 do
    for x = 0, W-1 do
        image.set_pixel(canvas, x, y, {r: x/W, g: y/H, b: 1-x/W, a: 1})
    end
end

var c = image.get_pixel(canvas, 0, 0)
print("(0,0) r=" + math.round(c.r * 100) / 100)

func frame()
    graphics.clear(colors.BLACK)
    image.draw(canvas, 0, 0)
    graphics.draw_text("FPS: " + graphics.fps(), 4, H-18, 13)
end

graphics.run(frame)
