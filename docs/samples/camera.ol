## Live webcam capture, in greyscale.
##
## The webcam belongs to the BROWSER: `camera.open` is refused anywhere else, so the call is
## guarded and the reason is drawn on the canvas. An example that dies on its first line teaches
## nothing, and this one still shows what the code looks like.

global scale = 2
global frame = nil
global why = nil               ## nil while all is well, otherwise what stopped us

func setup()
    graphics.canvas(640, 480)
    try
        camera.open(W / scale, H / scale)
    catch e
        why = e
    end
end

func update(dt)
    if why <> nil or not camera.isOpen() then
        return
    end
    frame = camera.capture()
    if frame then
        image.mapPixel(frame, func(x, y, r, g, b, a)
            var lum = 0.299 * r + 0.587 * g + 0.114 * b
            return lum, lum, lum, a
        end)
    end
end

func draw()
    graphics.clear(Color(0.04, 0.04, 0.06))
    if frame then
        graphics.sprite(frame, 0, 0, W, H)
        return
    end
    graphics.fontSize(16)
    graphics.textMode("center", "center")
    graphics.stroke(Color(0.9, 0.92, 1))
    if why <> nil then
        graphics.text(why, CX, CY)
    else
        graphics.text("waiting for the camera...", CX, CY)
    end
end
