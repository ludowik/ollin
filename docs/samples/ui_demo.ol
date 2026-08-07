## Module ui — widgets dessinés par le MOTEUR, en haut à droite de la zone de tracé.
## Aucune dépendance au navigateur : le même code tourne en natif et dans le playground.
##
## Un widget se déclare UNE fois. Le moteur le dessine et le teste à chaque frame.
## Les widgets se rangent dans des menus et sous-menus ; ui.show change le menu affiché.
## Une case à cocher et un slider reçoivent une RÉFÉRENCE (`ref maVariable`) : ils
## écrivent dedans, et le programme lit la variable normalement — voir `if grille then`
## et `t += deltaTime * vitesse` dans draw().
graphics.canvas(W, H, "ui")

global grille = true
global anim = true
global epais = false
global tours = 0
global t = 0
global vitesse = nil
global branches = 3
global teinte = 0.55
global couleurBras

func remettreAZero()
    t = 0
    tours = 0
end

func surTeinte(valeur)
    ## Le rappel reçoit la NOUVELLE valeur : la couleur est donc calculée quand elle
    ## change, et non à chaque frame comme le ferait une lecture dans draw().
    couleurBras = Color(valeur, 0.85, 1 - valeur * 0.6)
end

func surEpais(actif)
    ## Appelée à chaque changement, avec le nouvel état — pratique pour réagir tout
    ## de suite plutôt que de comparer la variable à chaque frame.
    if actif then
        print("trait épais")
    else
        print("trait fin")
    end
end

var principal = ui.menu("Principal")
principal.button("Remettre à zéro", remettreAZero)
principal.checkbox("Animation", ref anim)
## `vitesse` valant nil, le slider l'initialise à son défaut (1.0) dès la déclaration.
principal.slider("Vitesse", ref vitesse, 0.25, 3, 1.0)
## Bornes ET départ entiers → slider entier, sans décimale affichée.
principal.slider("Branches", ref branches, 1, 8)

var apparence = principal.menu("Apparence")
apparence.checkbox("Grille", ref grille)
apparence.checkbox("Trait épais", ref epais, surEpais)
apparence.slider("Teinte", ref teinte, 0, 1, surTeinte)
surTeinte(teinte)   ## le rappel ne part qu'au premier changement : couleur initiale ici

## ui.show remplace le menu affiché : de quoi passer d'un écran à l'autre (réglages,
## pause, fin de partie) sans reconstruire l'interface.
var pause = ui.menu("Pause")
pause.button("Reprendre", func() ui.show(principal) end)
principal.button("Pause", func() ui.show(pause) end)

ui.show(principal)

func dessineGrille()
    graphics.stroke(Color(1, 1, 1, 0.10), 1)
    var pas = H / 12
    for x = 0, W, pas do
        graphics.line(x, 0, x, H)
    end
    for y = 0, H, pas do
        graphics.line(0, y, W, y)
    end
end

func draw()
    graphics.clear(Color(0.09, 0.10, 0.14))
    if grille then
        dessineGrille()
    end
    if anim then
        t += deltaTime * vitesse
    end

    ## Autant de bras que `branches` : chaque widget agit tout de suite sur le dessin.
    var cote = math.min(W, H)
    var r = cote * 0.28
    var rayon = cote * 0.06
    var ecart = math.TAU / branches
    graphics.stroke(couleurBras, epais and 8 or 2)
    graphics.noFill()
    for i = 1, branches do
        var angle = t + ecart * i
        var cx = CW + math.cos(angle) * r
        var cy = CH + math.sin(angle) * r
        graphics.circle(cx, cy, rayon)
        graphics.line(CW, CH, cx, cy)
    end

    if t > math.TAU then
        t -= math.TAU
        tours += 1
    end

    graphics.stroke(Color(0.85, 0.88, 0.95))
    graphics.fontSize(H * 0.035)
    graphics.text("tours : " + tours, W * 0.05, H * 0.12)
end
