## Capture webcam en temps réel — niveau de gris

graphics.canvas(640, 480)

global frame = nil
global status = "En attente de l'autorisation..."

func setup()
    camera.open(320, 240)
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
        status = ""
        frame = camera.capture()
        if frame <> nil then
            toGrayscale(frame)
        end
    end
end

func draw()
    graphics.clear(0.08)
    if frame <> nil then
        graphics.sprite(frame, 0, 0, W, H)
    end
    if status <> "" then
        graphics.text(status, 12, 12, 18)
    end
end
