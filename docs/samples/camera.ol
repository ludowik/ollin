## Capture webcam en temps réel — niveau de gris

graphics.canvas(640, 480)

global scale = 2
global frame = nil

func setup()
    camera.open(W / scale, H / scale)
end

func toGrayscale(img)
    image.beginPixels(img)
    for y = 0, img.height - 1 do
        for x = 0, img.width - 1 do
            var c = image.getPixel(img, x, y)
            var g = 0.299 * c.r + 0.587 * c.g + 0.114 * c.b
            image.setPixel(img, x, y, g, g, g, c.a)
        end
    end
    image.endPixels(img)
end

func update()
    if camera.isOpen() then
        frame = camera.capture()
        if frame then
            toGrayscale(frame)
        end
    end
end

func draw()
    if frame then
        graphics.sprite(frame, 0, 0, frame.width * scale, frame.height * scale)
    end
end
