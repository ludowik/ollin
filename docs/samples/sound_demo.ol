## Modules audio et sound — TOUT ce qu'on entend ici est calculé : pas un fichier chargé.
##
## Clique une touche du clavier pour jouer sa note (un tampon calculé au démarrage, avec son
## enveloppe), et glisse dans la bande du haut pour piloter un oscillateur vivant, dont la
## fréquence suit le doigt PENDANT qu'il sonne. C'est là toute la différence entre les deux
## natures d'objet du module.

global notes = ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
global sons = []          ## un tampon par note, calculé une fois dans setup()
global derniere = 0       ## touche allumée, pour le retour visuel
global lueur = 0.0        ## décroît à chaque frame — le clavier « respire »

global archet = nil       ## l'oscillateur vivant
global glisse = false
global hauteur = 0.0      ## 0..1, position du doigt dans la bande

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

func mouse.pressed(x, y)
    if y >= hautBande() and y <= basBande() then
        glisse = true
        hauteur = (x / W)
        return
    end
    if y >= hautClavier() then
        var i = math.floor(x / largeurTouche()) + 1
        if i >= 1 and i <= #notes then
            jouer(i)
        end
    end
end

## `moved` est appelé à chaque déplacement du pointeur ; on ne suit que si le glissement est
## en cours, l'appui ayant eu lieu dans la bande.
func mouse.moved(x, y)
    if not glisse then
        return
    end
    hauteur = x / W
    if hauteur < 0 then
        hauteur = 0
    elseif hauteur > 1 then
        hauteur = 1
    end
end

func mouse.released(x, y)
    glisse = false
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

    ## Le clavier : huit touches, la dernière jouée reste éclairée le temps de sa lueur.
    graphics.noStroke()
    var l = largeurTouche()
    for i = 1, #notes do
        var vive = (i == derniere) and lueur or 0
        ## noStroke AVANT le rectangle, stroke seulement pour le texte : posé dans l'autre
        ## ordre, le contour du texte cerne aussi les touches suivantes.
        graphics.noStroke()
        graphics.fill(Color(0.16 + 0.5 * vive, 0.18 + 0.35 * vive, 0.3 + 0.4 * vive))
        graphics.rect(l * (i - 1) + 2, hautClavier(), l - 4, H - hautClavier())
        graphics.stroke(Color(0.8, 0.86, 0.96))
        graphics.text(notes[i], l * (i - 1) + l * 0.28, hautClavier() + H * 0.07)
    end

    ## Ce que valent les accesseurs d'un tampon : rien d'autre ne permet de les voir.
    graphics.stroke(Color(0.62, 0.7, 0.85))
    graphics.text("tampon : {sons[1].duration():.2f} s, crête {sons[1].peak():.2f}",
                  W * 0.04, basBande() - H * 0.04)
end
