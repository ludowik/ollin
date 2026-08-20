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
global hauteur = 0.0      ## 0..1, position du doigt dans la bande
## Contact qui pilote l'archet : identifiant de doigt, "souris", ou nil s'il ne sonne pas. Se
## compare TOUJOURS à nil, jamais par véracité : un identifiant de doigt peut valoir 0, que le
## langage tient pour faux — l'archet restait alors muet sous le premier doigt du navigateur. La
## bande n'obéit qu'à UN contact, sinon deux positions se disputeraient la même fréquence —
## et « l'archet sonne » se lit sur cette seule variable, sans drapeau à tenir d'accord.
global pilote = nil

global appui = false      ## le bouton de la souris est enfoncé

## Un oscillateur TENU par contact, créé à la pose et rendu au lever par `free()`. C'est le
## moteur qui gère la réserve : il ne reprend une voix rendue qu'une fois son extinction finie.
global voixDe = {}        ## contact (identifiant de doigt, ou "souris") → oscillateur

## Une entrée par contact POSÉ (doigt ou pointeur) : identifiant → touche qu'il presse. C'est
## ce qui permet plusieurs notes en même temps. Le pointeur y figure sous le nom "souris",
## comme un contact de plus — tout le reste du programme le traite alors sans cas particulier.
global sousDoigts = {}
## Les touches tenues, réutilisée d'une image à l'autre : une map neuve par image serait une
## allocation, et la vider coûte huit écritures.
global tenues = {}

## Chiffre du clavier → indice de note : comparer la touche à `"" + i` fabriquerait huit
## chaînes à chaque frappe, y compris pour les touches qui ne sont pas des chiffres.
global CHIFFRE = {}

## Bornée par la LARGEUR autant que par la hauteur : sur un écran de téléphone tenu debout,
## une taille tirée de la seule hauteur donne des lignes plus larges que l'écran.
func tailleTexte()
    return math.min(W * 0.055, H * 0.03)
end

func hautBande()
    return H * 0.12
end

func basBande()
    return H * 0.42
end

func hautClavier()
    return H * 0.55
end

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

    ## L'archet reste silencieux jusqu'au premier glissement : son volume est nul et c'est
    ## `start` qui le met en marche, pas `play`. Triangle et non dent de scie : sur un
    ## glissando, une forme riche en harmoniques devient criarde dans l'aigu.
    archet = sound.triangle(220).volume(0.0)
    archet.start()

    for i = 1, #notes do
        CHIFFRE["" + i] = i
    end
end

## L'oscillateur de ce contact, créé au besoin. L'enveloppe donne l'attaque et le
## relâchement ; sans durée passée à `trigger`, la note se tient jusqu'au lever du doigt.
## Le moteur peut refuser si toutes ses voix sonnent encore : mieux vaut alors une note
## manquante qu'une note volée à un doigt encore posé.
func voixPour(contact)
    var o = voixDe[contact]
    if o then
        return o
    end
    try
        o = sound.triangle(440).volume(0.3).envelope(0.01, 0.09, 0.5, 0.18)
    catch e
        return nil
    end
    voixDe[contact] = o
    return o
end

## Tenir la note d'une touche, ou relâcher si le contact ne presse plus rien. Rend la touche
## RÉELLEMENT tenue : zéro si aucune voix n'était libre, sinon la touche s'allumerait sans
## qu'aucun son ne sorte, et elle resterait muette même une fois une voix libérée.
func tenir(contact, i)
    ## Rendre la voix AVANT de la demander : un doigt qui ne fait que glisser dans la bande en
    ## immobilisait une sinon, et trois suffisaient à faire taire une touche.
    if i == 0 then
        relacher(contact)
        return 0
    end
    var o = voixPour(contact)
    if o == nil then
        return 0
    end
    o.freq(sound.note(notes[i])).trigger()
    derniere = i
    lueur = 1.0
    return i
end

func relacher(contact)
    var o = voixDe[contact]
    if not o then
        return
    end
    o.free()             ## lâche l'enveloppe et rend la voix — la note finit de s'éteindre
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
## l'on CHANGE de touche : sinon un déplacement de trois pixels la redéclencherait par image.
func suivre(contact, avant, x, y)
    var t = toucheSous(x, y)
    if t == avant then
        return avant
    end
    return tenir(contact, t)
end

func majArchet(x, y)
    hauteur = math.clamp(x / W, 0, 1)
end

func dansBande(y)
    return y >= hautBande() and y <= basBande()
end

## ── Multitouche : plusieurs doigts, chacun suivi par son identifiant ────────────
func touch.began(id, x, y)
    if dansBande(y) and pilote == nil then
        pilote = id
        majArchet(x, y)
    end
    sousDoigts[id] = suivre(id, 0, x, y)
end

func touch.moved(id, x, y)
    if id == pilote then
        if dansBande(y) then
            majArchet(x, y)
        else
            pilote = nil   ## sorti de la bande : il rend l'archet, et peut jouer des notes
        end
    end
    sousDoigts[id] = suivre(id, sousDoigts[id], x, y)
end

func touch.ended(id, x, y)
    if id == pilote then
        pilote = nil
    end
    relacher(id)          ## le lever du doigt relâche la note, qui s'éteint sur son enveloppe
    sousDoigts[id] = nil
end

## ── Souris : un seul pointeur, pour l'ordinateur ────────────────────────────────
## Sur un écran tactile, le système émule la souris sous un doigt unique : les deux familles
## de rappels partent alors, et le moteur ne filtre rien — c'est au script de choisir. Sans ce
## garde-fou, un doigt jouait la note DEUX fois, donc deux fois plus fort.
func sourisIgnoree()
    return touch.count() > 0
end

func mouse.pressed(x, y)
    if sourisIgnoree() then
        return
    end
    appui = true
    if dansBande(y) and pilote == nil then
        pilote = "souris"
        majArchet(x, y)
    end
    sousDoigts["souris"] = suivre("souris", 0, x, y)
end

func mouse.moved(x, y)
    if not appui or sourisIgnoree() then
        return
    end
    if pilote == "souris" then
        if dansBande(y) then
            majArchet(x, y)
        else
            pilote = nil
        end
    end
    sousDoigts["souris"] = suivre("souris", sousDoigts["souris"], x, y)
end

## Pas de garde-fou ici : une voix prise par le pointeur doit être rendue dans tous les cas,
## y compris si un doigt s'est posé entre-temps.
func mouse.released(x, y)
    appui = false
    relacher("souris")
    sousDoigts["souris"] = nil
    if pilote == "souris" then
        pilote = nil
    end
end

func keyboard.keypressed(key)
    ## Les chiffres 1 à 8 jouent les huit notes : de quoi essayer au clavier physique.
    var i = CHIFFRE[key]
    if i then
        jouer(i)
    end
end

func update()
    ## L'oscillateur suit le doigt : une fréquence qui bouge pendant que le son sort, ce
    ## qu'un tampon figé ne saurait pas faire. Le volume s'ouvre et se ferme en douceur.
    var cible = 0.0
    if pilote <> nil then
        cible = 0.25
        archet.freq(110 + hauteur * 660)
    end
    var v = archet.volume()
    archet.volume(v + (cible - v) * math.min(1, deltaTime * 8))

    lueur = math.max(lueur - deltaTime * 2.5, 0)
end

## Les touches TENUES restent allumées, puisque leur note dure aussi longtemps que l'appui.
## Relevé en UNE passe, à réutiliser pour les huit touches : interroger chaque touche
## reparcourait la liste des contacts autant de fois.
func releverTenues()
    for i = 1, #notes do
        tenues[i] = nil
    end
    for contact, sous in sousDoigts do
        tenues[sous] = true
    end
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.13))
    graphics.noStroke()
    graphics.fontSize(tailleTexte())
    ## Géométrie lue une fois : ces trois fonctions étaient rappelées une trentaine de fois.
    var hb = hautBande()
    var bb = basBande()
    var hc = hautClavier()

    ## La bande de l'archet : sa teinte dit s'il sonne.
    var chaud = (pilote <> nil) and 1 or 0
    graphics.fill(Color(0.13 + 0.2 * chaud, 0.15, 0.24))
    graphics.rect(0, hb, W, bb - hb)
    if pilote <> nil then
        graphics.fill(Color(0.55, 0.85, 1))
        graphics.rect(hauteur * W - 2, hb, 4, bb - hb)
    end
    graphics.stroke(Color(0.75, 0.82, 0.95))
    graphics.text("glisse ici : oscillateur vivant", W * 0.04, hb + H * 0.05)
    if pilote <> nil then
        graphics.text("{archet.freq():.0f} Hz", W * 0.04, hb + H * 0.11)
    end

    ## Le clavier : huit touches, la dernière jouée reste éclairée le temps de sa lueur. La
    ## touche SOUS LE DOIGT est cerclée, pour que le balayage se voie autant qu'il s'entende.
    graphics.stroke(Color(0.62, 0.7, 0.85))
    graphics.text("tiens plusieurs doigts posés", W * 0.04, hc - H * 0.07)
    graphics.text("chiffres 1 à 8 : notes brèves", W * 0.04, hc - H * 0.03)
    graphics.noStroke()
    var l = largeurTouche()
    releverTenues()
    for i = 1, #notes do
        var tenue = tenues[i]
        ## Tenue : pleine lumière tant que l'appui dure. Sinon, la lueur d'une note brève.
        var vive = tenue and 1 or ((i == derniere) and lueur or 0)
        ## noStroke AVANT le rectangle, stroke seulement pour le texte : posé dans l'autre
        ## ordre, le contour du texte cerne aussi les touches suivantes.
        graphics.noStroke()
        graphics.fill(Color(0.16 + 0.5 * vive, 0.18 + 0.35 * vive, 0.3 + 0.4 * vive))
        graphics.rect(l * (i - 1) + 2, hc, l - 4, H - hc)
        if tenue then
            graphics.noFill()
            graphics.stroke(Color(0.55, 0.85, 1), 3)
            graphics.rect(l * (i - 1) + 2, hc, l - 4, H - hc)
        end
        graphics.stroke(Color(0.8, 0.86, 0.96))
        graphics.text(notes[i], l * (i - 1) + l * 0.28, hc + H * 0.07)
    end

    ## Ce que valent les accesseurs d'un tampon : rien d'autre ne permet de les voir.
    graphics.stroke(Color(0.62, 0.7, 0.85))
    graphics.text("tampon : {sons[1].duration():.2f} s, crête {sons[1].peak():.2f}",
                  W * 0.04, bb - H * 0.04)
end
