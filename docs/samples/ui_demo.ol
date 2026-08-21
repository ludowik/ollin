## Module ui — widgets dessinés par le MOTEUR, en haut à droite de la zone de tracé.
## Aucune dépendance au navigateur : le même code tourne en natif et dans le playground.
##
## Un widget se déclare UNE fois. Le moteur le dessine et le teste à chaque frame.
## Les widgets se rangent dans des menus et sous-menus ; ui.show change le menu affiché.
## Une case à cocher, un slider et une liste reçoivent une RÉFÉRENCE : `ref` accepte un chemin de
## champs, donc les réglages tiennent dans UN objet `config` plutôt que dans autant de
## variables globales. Le programme les lit normalement — voir `config.grille` et
## `config.vitesse` dans draw().

## Tous les réglages exposés par l'interface, en un seul endroit : ce que l'utilisateur
## peut changer se lit ici, sans chercher parmi les globales du programme.
global config = {
    grid: true,
    anim: true,
    thick: false,
    speed: nil,    ## le slider l'initialise à son défaut
    branches: 3,
    tint: 0.55,
    shape: nil,      ## la liste l'initialise à son premier élément
    direction: nil
}

## Sources d'une liste : un TABLEAU donne ses valeurs, un ENUM (ou une map) ses clés.
global shapes = ["cercle", "carré", "triangle"]
enum Direction
    clockwise,
    counterClockwise
end

## État de l'animation (pas des réglages) et couleur dérivée de la teinte.
global turns = 0
global t = 0
global armColor

func reset()
    t = 0
    turns = 0
end

func onDirection(value)
    ## Le rappel reçoit l'élément choisi — ici la clé de l'enum, une chaîne.
    print("sens : " + value)
end

func onTint(value)
    ## Le rappel reçoit la NOUVELLE valeur : la couleur est donc calculée quand elle
    ## change, et non à chaque frame comme le ferait une lecture dans draw().
    armColor = Color(value, 0.85, 1 - value * 0.6)
end

func onThick(on)
    ## Appelée à chaque changement, avec le nouvel état — pratique pour réagir tout
    ## de suite plutôt que de comparer la variable à chaque frame.
    if on then
        print("trait épais")
    else
        print("trait fin")
    end
end

## setup() est appelée UNE fois avant la première frame : c'est là que se fait toute
## l'initialisation — zone de tracé, menus, état de départ.
func setup()
    graphics.canvas(W, H, "ui")

    var main = ui.menu("Principal")
    main.button("Remettre à zéro", reset)
    main.checkbox("Animation", ref config.anim)
    ## `config.vitesse` valant nil, le slider l'initialise à son défaut (1.0).
    main.slider("Vitesse", ref config.speed, 0.25, 3, 1.0)
    ## Bornes ET départ entiers → slider entier, sans décimale affichée.
    main.slider("Branches", ref config.branches, 1, 8)

    ## Une liste est en mono-sélection : la ligne montre l'élément retenu, un clic déplie
    ## les choix. Le tableau renvoie la VALEUR choisie, l'enum sa CLÉ.
    main.list("Forme", shapes, ref config.shape)
    main.list("Sens", Direction, ref config.direction, onDirection)

    var appearance = main.menu("Apparence")
    appearance.checkbox("Grille", ref config.grid)
    appearance.checkbox("Trait épais", ref config.thick, onThick)
    appearance.slider("Teinte", ref config.tint, 0, 1, onTint)

    ## ui.show remplace le menu affiché : de quoi passer d'un écran à l'autre (réglages,
    ## pause, fin de partie) sans reconstruire l'interface. Les menus sont des locales de
    ## setup, capturées par les closures des boutons.
    var pause = ui.menu("Pause")
    pause.button("Reprendre", func() ui.show(main) end)
    main.button("Pause", func() ui.show(pause) end)
    ui.show(main)

    onTint(config.tint)   ## le rappel ne part qu'au premier changement : couleur initiale ici
end

## La forme du bout de bras vient de la liste : le programme lit config.forme comme une
## variable ordinaire.
func drawShape(x, y, radius)
    if config.shape == "carré" then
        graphics.rect(x - radius, y - radius, radius * 2, radius * 2)
    elseif config.shape == "triangle" then
        graphics.polygon([x, y - radius, x + radius, y + radius, x - radius, y + radius])
    else
        graphics.circle(x, y, radius)
    end
end

func drawGrid()
    graphics.stroke(Color(1, 1, 1, 0.10), 1)
    var step = H / 12
    for x = 0, W, step do
        graphics.line(x, 0, x, H)
    end
    for y = 0, H, step do
        graphics.line(0, y, W, y)
    end
end

func draw()
    graphics.clear(Color(0.09, 0.10, 0.14))
    if config.grid then
        drawGrid()
    end
    if config.anim then
        t += deltaTime * config.speed
    end

    ## Autant de bras que `config.branches` : chaque widget agit tout de suite sur le dessin.
    var side = math.min(W, H)
    var r = side * 0.28
    var radius = side * 0.06
    var gap = math.TAU / config.branches
    graphics.stroke(armColor, config.thick and 8 or 2)
    graphics.noFill()
    var direction = config.direction == "horaire" and 1 or -1
    for i = 1, config.branches do
        var angle = direction * t + gap * i
        var cx = CW + math.cos(angle) * r
        var cy = CH + math.sin(angle) * r
        drawShape(cx, cy, radius)
        graphics.line(CW, CH, cx, cy)
    end

    if t > math.TAU then
        t -= math.TAU
        turns += 1
    end

    graphics.stroke(Color(0.85, 0.88, 0.95))
    graphics.fontSize(H * 0.035)
    graphics.text("tours : " + turns, W * 0.05, H * 0.12)
end
