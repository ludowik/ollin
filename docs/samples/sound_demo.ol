## Modules audio et sound — TOUT ce qu'on entend ici est calculé : pas un fichier chargé.
##
## Pose le doigt sur les touches et FAIS-LE GLISSER : chaque touche traversée joue sa note,
## sans qu'il faille cliquer l'une après l'autre. Les notes sont des tampons calculés au
## démarrage, avec leur enveloppe. Dans la bande du haut, le glissement pilote un oscillateur
## vivant dont la fréquence suit le doigt PENDANT qu'il sonne — c'est là toute la différence
## entre les deux natures d'objet du module.

global notes = ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
global sons = []          ## un tampon par note, calculé une fois dans setup()
global derniere = 0       ## touche allumée, pour le retour visuel
global lueur = 0.0        ## décroît à chaque frame — le clavier « respire »

global archet = nil       ## l'oscillateur vivant
global glisse = false     ## le doigt est dans la bande de l'archet
global hauteur = 0.0      ## 0..1, position du doigt dans la bande

global appui = false      ## le doigt (ou le bouton) est posé
global sousDoigt = 0      ## touche actuellement sous le doigt, 0 = aucune

func hautBande()
    return H * 0.12
end

func basBande()
    return H * 0.42
end

func hautClavier()
    return H * 0.55
end

## Une touche par note, en bas de l'écran.
func largeurTouche()
    return W / #notes
end

func setup()
    graphics.canvas(W, H, "son")

    ## Un tampon par note : la forme d'onde est échantillonnée UNE fois, puis l'enveloppe est
    ## appliquée aux échantillons. Rien n'est recalculé à la lecture.
    for i = 1, #notes do
        sons[i] = sound.tone(sound.note(notes[i]), 0.5, "triangle")
        sons[i].envelope(0.01, 0.12, 0.35, 0.25).volume(0.5)
    end

    ## L'oscillateur, lui, reste silencieux jusqu'au premier glissement : son volume est nul
    ## et c'est `start` qui le met en marche, pas `play`.
    archet = sound.saw(220).volume(0.0)
    archet.start()
end

func jouer(i)
    ## Rejouer un tampon repart de son début : inutile de l'arrêter d'abord.
    sons[i].play()
    derniere = i
    lueur = 1.0
end

## Touche sous le point (x, y), ou 0 si le point n'est pas sur le clavier.
func toucheSous(x, y)
    if y < hautClavier() then
        return 0
    end
    var i = math.floor(x / largeurTouche()) + 1
    if i < 1 or i > #notes then
        return 0
    end
    return i
end

## Ce que le doigt survole décide, à l'appui comme au glissement : c'est ce qui permet de
## balayer le clavier sans lever le doigt. Une note ne repart que si l'on CHANGE de touche —
## sinon un déplacement de trois pixels la redéclencherait à chaque frame.
func suivreDoigt(x, y)
    glisse = y >= hautBande() and y <= basBande()
    if glisse then
        hauteur = x / W
        if hauteur < 0 then
            hauteur = 0
        elseif hauteur > 1 then
            hauteur = 1
        end
    end

    var t = toucheSous(x, y)
    if t <> sousDoigt then
        sousDoigt = t
        if t > 0 then
            jouer(t)
        end
    end
end

func mouse.pressed(x, y)
    appui = true
    sousDoigt = 0     ## remis à zéro pour que la touche sous le doigt soit jouée
    suivreDoigt(x, y)
end

## `moved` est appelé à chaque déplacement du pointeur, bouton enfoncé ou non : sans le
## drapeau d'appui, une souris qui traverse l'écran jouerait toute la gamme.
func mouse.moved(x, y)
    if not appui then
        return
    end
    suivreDoigt(x, y)
end

func mouse.released(x, y)
    appui = false
    glisse = false
    sousDoigt = 0
end

func keyboard.keypressed(key)
    ## Les chiffres 1 à 8 jouent les huit notes : de quoi essayer au clavier physique.
    for i = 1, #notes do
        if key == "" + i then
            jouer(i)
        end
    end
end

func update()
    ## L'oscillateur suit le doigt : une fréquence qui bouge pendant que le son sort, ce
    ## qu'un tampon figé ne saurait pas faire. Le volume s'ouvre et se ferme en douceur.
    var cible = 0.0
    if glisse then
        cible = 0.25
        archet.freq(110 + hauteur * 660)
    end
    var v = archet.volume()
    archet.volume(v + (cible - v) * math.min(1, deltaTime * 8))

    lueur -= deltaTime * 2.5
    if lueur < 0 then
        lueur = 0
    end
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.13))
    graphics.noStroke()
    graphics.fontSize(H * 0.03)

    ## La bande de l'archet : sa teinte dit s'il sonne.
    var chaud = glisse and 1 or 0
    graphics.fill(Color(0.13 + 0.2 * chaud, 0.15, 0.24))
    graphics.rect(0, hautBande(), W, basBande() - hautBande())
    if glisse then
        graphics.fill(Color(0.55, 0.85, 1))
        graphics.rect(hauteur * W - 2, hautBande(), 4, basBande() - hautBande())
    end
    graphics.stroke(Color(0.75, 0.82, 0.95))
    graphics.text("glisse ici : oscillateur vivant", W * 0.04, hautBande() + H * 0.05)
    if glisse then
        graphics.text("{archet.freq():.0f} Hz", W * 0.04, hautBande() + H * 0.11)
    end

    ## Le clavier : huit touches, la dernière jouée reste éclairée le temps de sa lueur. La
    ## touche SOUS LE DOIGT est cerclée, pour que le balayage se voie autant qu'il s'entende.
    graphics.stroke(Color(0.62, 0.7, 0.85))
    graphics.text("pose le doigt et balaie les touches", W * 0.04, hautClavier() - H * 0.03)
    graphics.noStroke()
    var l = largeurTouche()
    for i = 1, #notes do
        var vive = (i == derniere) and lueur or 0
        ## noStroke AVANT le rectangle, stroke seulement pour le texte : posé dans l'autre
        ## ordre, le contour du texte cerne aussi les touches suivantes.
        graphics.noStroke()
        graphics.fill(Color(0.16 + 0.5 * vive, 0.18 + 0.35 * vive, 0.3 + 0.4 * vive))
        graphics.rect(l * (i - 1) + 2, hautClavier(), l - 4, H - hautClavier())
        if i == sousDoigt then
            graphics.noFill()
            graphics.stroke(Color(0.55, 0.85, 1), 3)
            graphics.rect(l * (i - 1) + 2, hautClavier(), l - 4, H - hautClavier())
        end
        graphics.stroke(Color(0.8, 0.86, 0.96))
        graphics.text(notes[i], l * (i - 1) + l * 0.28, hautClavier() + H * 0.07)
    end

    ## Ce que valent les accesseurs d'un tampon : rien d'autre ne permet de les voir.
    graphics.stroke(Color(0.62, 0.7, 0.85))
    graphics.text("tampon : {sons[1].duration():.2f} s, crête {sons[1].peak():.2f}",
                  W * 0.04, basBande() - H * 0.04)
end
