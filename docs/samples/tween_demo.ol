## Module tween — fait évoluer un champ d'objet de sa valeur COURANTE vers une valeur
## cible, sur une durée, selon une courbe. Le moteur avance les tweens à chaque frame :
## rien à appeler dans draw(), on déclare et on oublie.
##
## Clique n'importe où pour relancer les animations. Le menu choisit la courbe.

global config = {courbe: "easeInOutQuad"}

## Un mobile par courbe comparée : chacun porte sa position et sa couleur, que le tween
## écrit directement. Le dessin ne fait que LIRE ces champs, sans se soucier du temps.
global pastilles = []
global libelles = ["linear", "easeOutQuad", "easeInOutCubic", "easeOutBack", "easeOutElastic", "easeOutBounce"]

## Objet unique piloté par le menu, pour comparer une courbe choisie à la volée.
global vedette = {x: 0, taille: 0, teinte: Color(0.3, 0.7, 1)}
global duree = 1.2

func xDepart()
    return W * 0.12
end

## Arrivée à l'écart du menu (coin haut droit) : les courbes à dépassement — back,
## elastic — vont AU-DELÀ de la cible avant de revenir, et la pastille passerait dessous.
func xArrivee()
    return W * 0.72
end

func lancer()
    ## Chaque pastille repart de la gauche vers la droite avec SA courbe. Déclarer un
    ## nouveau tween sur un champ déjà animé annule le précédent : cliquer en pleine
    ## course ne crée donc pas deux animations concurrentes.
    for i = 1, #pastilles do
        var p = pastilles[i]
        p.x = xDepart()
        tween.to(p, {x: xArrivee()}, duree, libelles[i])
    end

    ## Plusieurs champs dans le même appel, dont une COULEUR : une instance de classe est
    ## interpolée champ par champ (r, g, b, a), sans traitement particulier ici.
    vedette.x = xDepart()
    vedette.taille = H * 0.02
    vedette.teinte = Color(0.3, 0.7, 1)
    tween.to(vedette, {x: xArrivee(), taille: H * 0.055, teinte: Color(1, 0.45, 0.2)},
             duree, config.courbe)

    ## Le retour part 0,3 s plus tard, depuis la valeur qu'aura la vedette à ce moment :
    ## un délai retarde la LECTURE de la valeur de départ, pas seulement le mouvement.
    tween.to(vedette, {taille: H * 0.02}, duree * 0.6, "easeInQuad").delay(duree + 0.3)
end

func setup()
    graphics.canvas(W, H, "tween")

    for i = 1, #libelles do
        pastilles[i] = {x: 0}
    end

    ## Un bouton par courbe : le menu écrit config.courbe puis relance. La liste vient de
    ## tween.curves(), donc elle suit le catalogue du moteur sans être recopiée ici.
    var menu = ui.menu("Courbe")
    for nom in tween.curves() do
        menu.button(nom, func()
            config.courbe = nom
            lancer()
        end)
    end
    ui.show(menu)

    lancer()
end

func mouse.pressed(x, y)
    lancer()
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.13))
    graphics.fontSize(H * 0.028)

    ## Une ligne par courbe comparée : la pastille est à la position que le tween écrit.
    var y = H * 0.18
    var pas = H * 0.1
    for i = 1, #pastilles do
        graphics.stroke(Color(1, 1, 1, 0.12), 1)
        graphics.line(xDepart(), y, xArrivee(), y)
        graphics.noStroke()
        graphics.fill(Color(0.45, 0.8, 1))
        graphics.circle(pastilles[i].x, y, H * 0.014)
        graphics.stroke(Color(0.65, 0.72, 0.85))
        graphics.text(libelles[i], W * 0.02, y - H * 0.014)
        y += pas
    end

    ## La vedette : position, taille et couleur animées ensemble.
    graphics.noStroke()
    graphics.fill(vedette.teinte)
    graphics.circle(vedette.x, H * 0.86, vedette.taille)
    graphics.stroke(Color(0.85, 0.88, 0.95))
    graphics.text(config.courbe + " — clique pour relancer", W * 0.02, H * 0.93)
end
