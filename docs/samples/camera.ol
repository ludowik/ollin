## Live webcam capture, in greyscale

graphics.canvas(640, 480)

global scale = 2
global frame = nil

func setup()
    camera.open(W / scale, H / scale)
end

func update()
    if camera.isOpen() then
        frame = camera.capture()
        if frame then
            image.mapPixel(frame, func(x, y, r, g, b, a)
                var lum = 0.299 * r + 0.587 * g + 0.114 * b
                return lum, lum, lum, a
            end)
        end
    end
end

func draw()
    if frame then
        graphics.sprite(frame, 0, 0, W, H)
    end
end
