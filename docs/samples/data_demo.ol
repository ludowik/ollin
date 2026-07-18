## Persistance : le module `data` mémorise des valeurs d'un lancement à l'autre.
## Ici un compteur de lancements (portée PROJET) + un score incrémenté au clic.
## Relance le script (ou recharge la page) : le compteur et le score reviennent.

global runs = 0
global score = 0

func setup()
    graphics.canvas(W, H, "data — persistance")
    runs = data.get("runs", 0) + 1     ## lu puis incrémenté à chaque lancement
    data.set("runs", runs)
    score = data.get("score", 0)       ## repris là où on l'avait laissé
end

func mouse.pressed(x, y)
    score = score + 1
    data.set("score", score)           ## persisté immédiatement
end

func draw()
    graphics.clear(Color(0.10, 0.12, 0.18))
    graphics.text("Lancement n° " + runs, 24, 40, 30, colors.WHITE)
    graphics.text("Score (clique) : " + score, 24, 92, 26, colors.SKYBLUE)
    graphics.text("Relance ou recharge : tout est conservé.", 24, 150, 16, colors.GRAY)
    graphics.text("data.shared.* pour une portée partagée entre projets.", 24, 176, 16, colors.GRAY)
end
