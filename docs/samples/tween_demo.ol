## Module tween — fait évoluer un champ d'objet de sa valeur COURANTE vers une valeur
## cible, sur une durée, selon une courbe. Le moteur avance les tweens à chaque frame :
## rien à appeler dans draw(), on déclare et on oublie.
##
## Clique n'importe où pour relancer les animations. La liste « Courbe » du menu choisit la
## courbe appliquée à la vedette, le slider règle la durée.

global config = {curve: "easeInOutQuad"}

## Un mobile par courbe comparée : chacun porte sa position et sa couleur, que le tween
## écrit directement. Le dessin ne fait que LIRE ces champs, sans se soucier du temps.
global dots = []
global labels = ["linear", "easeOutQuad", "easeInOutCubic", "easeOutBack", "easeOutElastic", "easeOutBounce"]

## Objet unique piloté par le menu, pour comparer une courbe choisie à la volée.
global star = {x: 0, size: 0, tint: Color(0.3, 0.7, 1)}
global duration = 1.2

func xStart()
    return W * 0.12
end

## Arrivée à l'écart du menu (coin haut droit), liste DÉPLIÉE comprise : les courbes à
## dépassement — back, elastic — vont au-delà de la cible avant de revenir, et la pastille
## finirait sous les choix affichés.
func xEnd()
    return W * 0.72
end

func start()
    ## Chaque pastille repart de la gauche vers la droite avec SA courbe. Déclarer un
    ## nouveau tween sur un champ déjà animé annule le précédent : cliquer en pleine
    ## course ne crée donc pas deux animations concurrentes.
    for i = 1, #dots do
        var p = dots[i]
        p.x = xStart()
        tween.to(p, {x: xEnd()}, duration, labels[i])
    end

    ## Plusieurs champs dans le même appel, dont une COULEUR : une instance de classe est
    ## interpolée champ par champ (r, g, b, a), sans traitement particulier ici.
    star.x = xStart()
    star.size = H * 0.02
    star.tint = Color(0.3, 0.7, 1)
    tween.to(star, {x: xEnd(), size: H * 0.055, tint: Color(1, 0.45, 0.2)},
             duration, config.curve)

    ## Le retour part 0,3 s plus tard, depuis la valeur qu'aura la vedette à ce moment :
    ## un délai retarde la LECTURE de la valeur de départ, pas seulement le mouvement.
    tween.to(star, {size: H * 0.02}, duration * 0.6, "easeInQuad").delay(duration + 0.3)
end

## Le rappel reçoit l'élément choisi ; config.courbe est déjà écrite quand il part, donc
## il suffit de relancer.
func onCurve(name)
    start()
end

func setup()
    graphics.canvas(W, H, "tween")

    for i = 1, #labels do
        dots[i] = {x: 0}
    end

    ## UNE liste au lieu de dix-huit boutons : elle écrit config.courbe (le nom choisi,
    ## puisqu'un tableau renvoie ses valeurs) puis appelle le rappel. Sa source est
    ## tween.curves(), donc elle suit le catalogue du moteur sans le recopier ici.
    var menu = ui.menu("Animation")
    menu.list("Courbe", tween.curves(), ref config.curve, onCurve)
    menu.slider("Durée", ref duration, 0.3, 3)
    ui.show(menu)

    start()
end

func mouse.pressed(x, y)
    start()
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.13))
    graphics.fontSize(H * 0.028)

    ## Une ligne par courbe comparée : la pastille est à la position que le tween écrit.
    var y = H * 0.18
    var step = H * 0.1
    for i = 1, #dots do
        graphics.stroke(Color(1, 1, 1, 0.12), 1)
        graphics.line(xStart(), y, xEnd(), y)
        graphics.noStroke()
        graphics.fill(Color(0.45, 0.8, 1))
        graphics.circle(dots[i].x, y, H * 0.014)
        graphics.stroke(Color(0.65, 0.72, 0.85))
        graphics.text(labels[i], W * 0.02, y - H * 0.014)
        y += step
    end

    ## La vedette : position, taille et couleur animées ensemble.
    graphics.noStroke()
    graphics.fill(star.tint)
    graphics.circle(star.x, H * 0.86, star.size)
    graphics.stroke(Color(0.85, 0.88, 0.95))
    graphics.text(config.curve + " — clique pour relancer", W * 0.02, H * 0.93)
end
