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
            var r, g, b, a = image.getPixel(img, x, y)
            var lum = 0.299 * r + 0.587 * g + 0.114 * b
            image.setPixel(img, x, y, lum, lum, lum, a)
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
        graphics.sprite(frame, 0, 0, W, H)
    end
end
