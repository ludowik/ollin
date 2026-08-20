## Modules audio et sound — TOUT ce qu'on entend ici est calculé : pas un fichier chargé.
##
## Pose les doigts sur les touches et fais-les GLISSER : chaque touche traversée joue sa note,
## et PLUSIEURS DOIGTS jouent plusieurs notes à la fois — c'est le module `touch` qui les suit,
## chacun par son identifiant. Les notes sont des tampons calculés au démarrage, avec leur
## enveloppe. Dans la bande du haut, le glissement pilote un oscillateur vivant dont la
## fréquence suit le doigt PENDANT qu'il sonne — c'est là toute la différence entre les deux
## natures d'objet du module `sound`.
##
## À la souris, un seul pointeur : le module `mouse` prend alors le relais.

global notes = ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
global sons = []          ## un tampon par note, calculé une fois dans setup()
global derniere = 0       ## touche allumée, pour le retour visuel
global lueur = 0.0        ## décroît à chaque frame — le clavier « respire »

global archet = nil       ## l'oscillateur vivant
global glisse = false     ## le doigt est dans la bande de l'archet
global hauteur = 0.0      ## 0..1, position du doigt dans la bande

global appui = false      ## le bouton de la souris est enfoncé
global sousSouris = 0     ## touche sous le pointeur, 0 = aucune

## Une entrée par doigt POSÉ : identifiant → touche qu'il presse. C'est ce qui permet
## plusieurs notes en même temps, là où un seul pointeur ne peut en désigner qu'une.
global sousDoigts = {}
## Doigt qui pilote l'archet, s'il y en a un : la bande n'obéit qu'à UN doigt, sinon deux
## positions se disputeraient la même fréquence.
global doigtArchet = nil

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

## Noyau commun aux deux entrées : ce que le contact SURVOLE décide, à la pose comme au
## glissement. Une note ne repart que si l'on CHANGE de touche — sinon un déplacement de trois
## pixels la redéclencherait à chaque image. `avant` est la touche que ce contact pressait,
## `rend` la nouvelle.
func suivre(avant, x, y)
    var t = toucheSous(x, y)
    if t <> avant and t > 0 then
        jouer(t)
    end
    return t
end

## La bande de l'archet, pilotée par UN contact à la fois.
func majArchet(x, y)
    hauteur = x / W
    if hauteur < 0 then
        hauteur = 0
    elseif hauteur > 1 then
        hauteur = 1
    end
end

func dansBande(y)
    return y >= hautBande() and y <= basBande()
end

## ── Multitouche : plusieurs doigts, chacun suivi par son identifiant ────────────
func touch.began(id, x, y)
    if dansBande(y) and doigtArchet == nil then
        doigtArchet = id
        glisse = true
        majArchet(x, y)
    end
    sousDoigts[id] = suivre(0, x, y)
end

func touch.moved(id, x, y)
    if id == doigtArchet then
        if dansBande(y) then
            majArchet(x, y)
        else
            ## Le doigt a quitté la bande : il rend l'archet, et peut jouer des notes.
            doigtArchet = nil
            glisse = false
        end
    end
    sousDoigts[id] = suivre(sousDoigts[id], x, y)
end

func touch.ended(id, x, y)
    if id == doigtArchet then
        doigtArchet = nil
        glisse = false
    end
    sousDoigts[id] = nil
end

## ── Souris : un seul pointeur, et les rappels partent AUSSI sur un doigt unique (le
## système émule la souris). Les deux chemins sont donc écrits pour être idempotents :
## rejouer la même touche est sans effet, puisque `suivre` exige un changement.
func mouse.pressed(x, y)
    appui = true
    if dansBande(y) then
        glisse = true
        majArchet(x, y)
    end
    sousSouris = suivre(0, x, y)
end

func mouse.moved(x, y)
    if not appui then
        return
    end
    if glisse and dansBande(y) then
        majArchet(x, y)
    elseif glisse then
        glisse = false
    end
    sousSouris = suivre(sousSouris, x, y)
end

func mouse.released(x, y)
    appui = false
    sousSouris = 0
    if doigtArchet == nil then
        glisse = false
    end
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

## Une touche est-elle pressée par l'un des doigts posés ?
func presseeParUnDoigt(i)
    for id, t in sousDoigts do
        if t == i then
            return true
        end
    end
    return false
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
    graphics.text("pose plusieurs doigts, et balaie", W * 0.04, hautClavier() - H * 0.03)
    graphics.noStroke()
    var l = largeurTouche()
    for i = 1, #notes do
        var vive = (i == derniere) and lueur or 0
        ## noStroke AVANT le rectangle, stroke seulement pour le texte : posé dans l'autre
        ## ordre, le contour du texte cerne aussi les touches suivantes.
        graphics.noStroke()
        graphics.fill(Color(0.16 + 0.5 * vive, 0.18 + 0.35 * vive, 0.3 + 0.4 * vive))
        graphics.rect(l * (i - 1) + 2, hautClavier(), l - 4, H - hautClavier())
        if i == sousSouris or presseeParUnDoigt(i) then
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
