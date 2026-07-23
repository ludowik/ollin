## Capture webcam en temps réel
## Nécessite l'autorisation de la caméra dans le navigateur
## Espace = démarrer / Echap = arrêter

graphics.canvas(640, 480)

var opened = false
var frame = nil
var status = "Appuie sur Espace pour démarrer la caméra"

func keyboard.keypressed(key)
    if key == "space" and not opened then
        camera.open(640, 480)
        opened = true
        status = "En attente de l'autorisation..."
    end
    if key == "escape" and opened then
        camera.close()
        opened = false
        frame = nil
        status = "Caméra fermée — Espace pour redémarrer"
    end
end

graphics.run(func()
    graphics.clear(0.08)

    if frame <> nil then
        graphics.sprite(frame, 0, 0, W, H)
    end

    if status <> "" then
        graphics.fill(1, 1, 1, 0.85)
        graphics.textSize(18)
        graphics.text(status, 12, 12)
    end
end,
func()
    if opened and camera.isOpen() then
        status = ""
        frame = camera.capture()
    end
end)
