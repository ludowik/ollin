## Modules audio et sound — TOUT ce qu'on entend ici est calculé : pas un fichier chargé.
##
## Pose les doigts sur les touches : chaque note SONNE TANT QUE le doigt reste appuyé, et
## plusieurs doigts jouent plusieurs notes à la fois — c'est le module `touch` qui les suit,
## chacun par son identifiant. Fais glisser sans lever : la note suit la touche survolée.
##
## L'exemple montre les DEUX natures d'objet du module `sound`, chacune pour ce qu'elle sait
## faire :
##   un OSCILLATEUR tenu pour une touche pressée — sa durée n'est pas connue d'avance, et son
##     enveloppe la relâche au lever du doigt ;
##   un TAMPON calculé pour les chiffres 1 à 8 du clavier physique — une note brève, figée,
##     rejouée telle quelle ;
##   et un oscillateur de plus dans la bande du haut, dont la fréquence suit le doigt.
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

## Les voix TENUES : une par contact possible, créées une fois pour toutes dans setup(). Les
## créer à la demande serait un piège — une voix relâchée devient libre, donc recyclable par
## la création suivante, et l'ancien objet ne désignerait plus rien.
global voix = []          ## oscillateurs disponibles
global voixDe = {}        ## contact (identifiant de doigt, ou "souris") → index dans `voix`
## Instant où chaque voix a été rendue. Une voix rendue continue de s'éteindre sur son
## relâchement : reprendre la plus RÉCEMMENT rendue couperait net cette queue de note.
global rendueA = []

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

    ## Une voix tenue par contact : huit doigts au plus, plus le pointeur. L'enveloppe donne
    ## l'attaque et le relâchement ; sans durée passée à `trigger`, la note se tient.
    for i = 1, 9 do
        voix[i] = sound.triangle(440).volume(0.3).envelope(0.01, 0.09, 0.5, 0.18)
        rendueA[i] = 0
    end

    ## L'archet reste silencieux jusqu'au premier glissement : son volume est nul et c'est
    ## `start` qui le met en marche, pas `play`.
    archet = sound.saw(220).volume(0.0)
    archet.start()
end

## Voix libre pour ce contact, ou celle qu'il tient déjà. On prend la plus ANCIENNEMENT
## rendue : la dernière rendue s'éteint encore sur son relâchement, et la redéclencher
## couperait sa queue de note. Toutes prises : on ne joue pas — mieux vaut une note manquante
## qu'une note volée à un doigt encore posé.
func voixPour(contact)
    if voixDe[contact] <> nil then
        return voix[voixDe[contact]]
    end
    var choisie = 0
    for i = 1, #voix do
        var pris = false
        for c, j in voixDe do
            if j == i then
                pris = true
            end
        end
        if not pris and (choisie == 0 or rendueA[i] < rendueA[choisie]) then
            choisie = i
        end
    end
    if choisie == 0 then
        return nil
    end
    voixDe[contact] = choisie
    return voix[choisie]
end

## Tenir la note d'une touche, ou relâcher si le contact ne presse plus rien. Rend la touche
## RÉELLEMENT tenue : zéro si aucune voix n'était libre, sinon la touche s'allumerait sans
## qu'aucun son ne sorte, et elle resterait muette même une fois une voix libérée.
func tenir(contact, i)
    ## Ne presse plus rien : on rend la voix au lieu de la garder. La demander d'abord, puis
    ## découvrir qu'on n'en a pas besoin, immobilisait une voix par doigt qui ne fait que
    ## glisser dans la bande — trois d'entre eux suffisaient à faire taire une touche.
    if i == 0 then
        relacher(contact)
        return 0
    end
    var o = voixPour(contact)
    if o == nil then
        return 0
    end
    o.freq(sound.note(notes[i])).trigger()   ## sans durée : la note se tient
    derniere = i
    lueur = 1.0
    return i
end

func relacher(contact)
    if voixDe[contact] == nil then
        return
    end
    voix[voixDe[contact]].release()
    rendueA[voixDe[contact]] = elapsedTime   ## pour ne pas la reprendre pendant son extinction
    voixDe[contact] = nil
end

## Note BRÈVE, pour le clavier physique : un tampon figé, rejoué tel quel. Rejouer repart du
## début, inutile de l'arrêter d'abord.
func jouer(i)
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

## Ce que le contact survole décide, à la pose comme au glissement. La note ne change que si
## l'on CHANGE de touche : sinon un déplacement de trois pixels la redéclencherait à chaque
## image. `avant` est la touche que ce contact pressait, `rend` la nouvelle.
func suivre(contact, avant, x, y)
    var t = toucheSous(x, y)
    if t == avant then
        return avant
    end
    return tenir(contact, t)
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
    sousDoigts[id] = suivre(id, 0, x, y)
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
    sousDoigts[id] = suivre(id, sousDoigts[id], x, y)
end

func touch.ended(id, x, y)
    if id == doigtArchet then
        doigtArchet = nil
        glisse = false
    end
    relacher(id)          ## le lever du doigt relâche la note, qui s'éteint sur son enveloppe
    sousDoigts[id] = nil
end

## ── Souris : un seul pointeur, pour l'ordinateur ────────────────────────────────
## Sur un écran tactile, le système émule la souris quand un seul doigt touche : les deux
## familles de rappels partent alors, et le moteur ne filtre rien (c'est au script de
## choisir). Sans ce garde-fou, un doigt déclenchait la note DEUX fois — deux voix à la même
## hauteur, donc deux fois plus fort, et deux voix consommées au lieu d'une.
func sourisIgnoree()
    return touch.count() > 0
end

func mouse.pressed(x, y)
    if sourisIgnoree() then
        return
    end
    appui = true
    if dansBande(y) then
        glisse = true
        majArchet(x, y)
    end
    sousSouris = suivre("souris", 0, x, y)
end

func mouse.moved(x, y)
    if not appui or sourisIgnoree() then
        return
    end
    if glisse and dansBande(y) then
        majArchet(x, y)
    elseif glisse then
        glisse = false
    end
    sousSouris = suivre("souris", sousSouris, x, y)
end

## Pas de garde-fou ici : une voix prise par le pointeur doit être rendue dans tous les cas,
## y compris si un doigt s'est posé entre-temps.
func mouse.released(x, y)
    appui = false
    relacher("souris")
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

## Une touche est-elle TENUE, par un doigt ou par le pointeur ? Elle reste alors allumée,
## puisque sa note dure aussi longtemps que l'appui.
func tenue(i)
    if i == sousSouris then
        return true
    end
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
    graphics.text("tiens plusieurs doigts posés — chiffres 1 à 8 : notes brèves",
                  W * 0.04, hautClavier() - H * 0.03)
    graphics.noStroke()
    var l = largeurTouche()
    for i = 1, #notes do
        ## Tenue : pleine lumière tant que l'appui dure. Sinon, la lueur d'une note brève.
        var vive = tenue(i) and 1 or ((i == derniere) and lueur or 0)
        ## noStroke AVANT le rectangle, stroke seulement pour le texte : posé dans l'autre
        ## ordre, le contour du texte cerne aussi les touches suivantes.
        graphics.noStroke()
        graphics.fill(Color(0.16 + 0.5 * vive, 0.18 + 0.35 * vive, 0.3 + 0.4 * vive))
        graphics.rect(l * (i - 1) + 2, hautClavier(), l - 4, H - hautClavier())
        if tenue(i) then
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
