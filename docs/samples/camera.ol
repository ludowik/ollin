## Capture webcam en temps réel
## Nécessite l'autorisation de la caméra dans le navigateur
## Espace = démarrer / Echap = arrêter

graphics.canvas(640, 480)

global opened = false
global frame = nil
global status = "Appuie sur Espace pour démarrer la caméra"

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

func update()
    if opened and camera.isOpen() then
        status = ""
        frame = camera.capture()
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
