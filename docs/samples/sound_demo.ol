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
global buffers = []          ## un tampon par note, calculé une fois dans setup()
global lastKey = 0       ## touche allumée, pour le retour visuel
global glow = 0.0        ## décroît à chaque frame — le clavier « respire »

global bow = nil       ## l'oscillateur vivant
global bowPos = 0.0      ## 0..1, position du doigt dans la bande
## Contact qui bowHolder l'bow : identifiant de doigt, "souris", ou nil s'il ne sonne pas. Se
## compare TOUJOURS à nil, jamais par véracité : un identifiant de doigt peut valoir 0, que le
## langage tient pour faux — l'bow restait alors muet sous le premier doigt du navigateur. La
## bande n'obéit qu'à UN contact, sinon deux positions se disputeraient la même fréquence —
## et « l'bow sonne » se lit sur cette seule variable, sans drapeau à holdKey d'accord.
global bowHolder = nil

global mouseDown = false      ## le bouton de la souris est enfoncé

## Un oscillateur TENU par contact, créé à la pose et rendu au lever par `free()`. C'est le
## moteur qui gère la réserve : il ne reprend une voix rendue qu'une fois son extinction finie.
global voiceOf = {}        ## contact (identifiant de doigt, ou "souris") → oscillateur

## Une entrée par contact POSÉ (doigt ou pointeur) : identifiant → touche qu'il presse. C'est
## ce qui permet plusieurs notes en même temps. Le pointeur y figure sous le nom "souris",
## comme un contact de plus — tout le reste du programme le traite alors sans cas particulier.
global underFinger = {}
## Les touches heldKeys, réutilisée d'une image à l'autre : une map neuve par image serait une
## allocation, et la vider coûte huit écritures.
global heldKeys = {}

## Chiffre du clavier → indice de note : comparer la touche à `"" + i` fabriquerait huit
## chaînes à chaque frappe, y compris pour les touches qui ne sont pas des chiffres.
global DIGIT = {}

## Bornée par la LARGEUR autant que par la bowPos : sur un écran de téléphone tenu debout,
## une taille tirée de la seule bowPos donne des lignes plus larges que l'écran.
func textSize()
    return math.min(W * 0.055, H * 0.03)
end

func bandTop()
    return H * 0.12
end

func bandBottom()
    return H * 0.42
end

func keyboardTop()
    return H * 0.55
end

func keyWidth()
    return W / #notes
end

func setup()
    graphics.canvas(W, H, "son")

    ## Un tampon par note : la forme d'onde est échantillonnée UNE fois, puis l'enveloppe est
    ## appliquée aux échantillons. Rien n'est recalculé à la lecture.
    for i = 1, #notes do
        buffers[i] = sound.tone(sound.note(notes[i]), 0.5, "triangle")
        buffers[i].envelope(0.01, 0.12, 0.35, 0.25).volume(0.5)
    end

    ## L'bow reste silencieux jusqu'au premier glissement : son volume est nul et c'est
    ## `start` qui le met en marche, pas `play`. Triangle et non dent de scie : sur un
    ## glissando, une forme riche en harmoniques devient criarde dans l'aigu.
    bow = sound.triangle(220).volume(0.0)
    bow.start()

    for i = 1, #notes do
        DIGIT["" + i] = i
    end
end

## L'oscillateur de ce contact, créé au besoin. L'enveloppe donne l'attaque et le
## relâchement ; sans durée passée à `trigger`, la note se tient jusqu'au lever du doigt.
## Le moteur peut refuser si toutes ses voix sonnent encore : mieux vaut alors une note
## manquante qu'une note volée à un doigt encore posé.
func voiceFor(contact)
    var o = voiceOf[contact]
    if o then
        return o
    end
    try
        o = sound.triangle(440).volume(0.3).envelope(0.01, 0.09, 0.5, 0.18)
    catch e
        return nil
    end
    voiceOf[contact] = o
    return o
end

## Tenir la note d'une touche, ou relâcher si le contact ne presse plus rien. Rend la touche
## RÉELLEMENT tenue : zéro si aucune voix n'était libre, sinon la touche s'allumerait sans
## qu'aucun son ne sorte, et elle resterait muette même une fois une voix libérée.
func holdKey(contact, i)
    ## Rendre la voix AVANT de la demander : un doigt qui ne fait que glisser dans la bande en
    ## immobilisait une sinon, et trois suffisaient à faire taire une touche.
    if i == 0 then
        releaseVoice(contact)
        return 0
    end
    var o = voiceFor(contact)
    if o == nil then
        return 0
    end
    o.freq(sound.note(notes[i])).trigger()
    lastKey = i
    glow = 1.0
    return i
end

func releaseVoice(contact)
    var o = voiceOf[contact]
    if not o then
        return
    end
    o.free()             ## lâche l'enveloppe et rend la voix — la note finit de s'éteindre
    voiceOf[contact] = nil
end

## Note BRÈVE, pour le clavier physique : un tampon figé, rejoué tel quel. Rejouer repart du
## début, inutile de l'arrêter d'abord.
func playBuffer(i)
    buffers[i].play()
    lastKey = i
    glow = 1.0
end

## Touche sous le point (x, y), ou 0 si le point n'est pas sur le clavier.
func keyAt(x, y)
    if y < keyboardTop() then
        return 0
    end
    var i = math.floor(x / keyWidth()) + 1
    if i < 1 or i > #notes then
        return 0
    end
    return i
end

## Ce que le contact survole décide, à la pose comme au glissement. La note ne change que si
## l'on CHANGE de touche : sinon un déplacement de trois pixels la redéclencherait par image.
func follow(contact, avant, x, y)
    var t = keyAt(x, y)
    if t == avant then
        return avant
    end
    return holdKey(contact, t)
end

func moveBow(x, y)
    bowPos = math.clamp(x / W, 0, 1)
end

func inBand(y)
    return y >= bandTop() and y <= bandBottom()
end

## ── Multitouche : plusieurs doigts, chacun suivi par son identifiant ────────────
func touch.began(id, x, y)
    if inBand(y) and bowHolder == nil then
        bowHolder = id
        moveBow(x, y)
    end
    underFinger[id] = follow(id, 0, x, y)
end

func touch.moved(id, x, y)
    if id == bowHolder then
        if inBand(y) then
            moveBow(x, y)
        else
            bowHolder = nil   ## sorti de la bande : il rend l'bow, et peut playBuffer des notes
        end
    end
    underFinger[id] = follow(id, underFinger[id], x, y)
end

func touch.ended(id, x, y)
    if id == bowHolder then
        bowHolder = nil
    end
    releaseVoice(id)          ## le lever du doigt relâche la note, qui s'éteint sur son enveloppe
    underFinger[id] = nil
end

## ── Souris : un seul pointeur, pour l'ordinateur ────────────────────────────────
## Sur un écran tactile, le système émule la souris sous un doigt unique : les deux familles
## de rappels partent alors, et le moteur ne filtre rien — c'est au script de choisir. Sans ce
## garde-fou, un doigt jouait la note DEUX fois, donc deux fois plus fort.
func mouseIgnored()
    return touch.count() > 0
end

func mouse.pressed(x, y)
    if mouseIgnored() then
        return
    end
    mouseDown = true
    if inBand(y) and bowHolder == nil then
        bowHolder = "souris"
        moveBow(x, y)
    end
    underFinger["souris"] = follow("souris", 0, x, y)
end

func mouse.moved(x, y)
    if not mouseDown or mouseIgnored() then
        return
    end
    if bowHolder == "souris" then
        if inBand(y) then
            moveBow(x, y)
        else
            bowHolder = nil
        end
    end
    underFinger["souris"] = follow("souris", underFinger["souris"], x, y)
end

## Pas de garde-fou ici : une voix prise par le pointeur doit être rendue dans tous les cas,
## y compris si un doigt s'est posé entre-temps.
func mouse.released(x, y)
    mouseDown = false
    releaseVoice("souris")
    underFinger["souris"] = nil
    if bowHolder == "souris" then
        bowHolder = nil
    end
end

func keyboard.keypressed(key)
    ## Les chiffres 1 à 8 jouent les huit notes : de quoi essayer au clavier physique.
    var i = DIGIT[key]
    if i then
        playBuffer(i)
    end
end

func update()
    ## L'oscillateur suit le doigt : une fréquence qui bouge pendant que le son sort, ce
    ## qu'un tampon figé ne saurait pas faire. Le volume s'ouvre et se ferme en douceur.
    var cible = 0.0
    if bowHolder <> nil then
        cible = 0.25
        bow.freq(110 + bowPos * 660)
    end
    var v = bow.volume()
    bow.volume(v + (cible - v) * math.min(1, deltaTime * 8))

    glow = math.max(glow - deltaTime * 2.5, 0)
end

## Les touches TENUES restent allumées, puisque leur note dure aussi longtemps que l'appui.
## Relevé en UNE passe, à réutiliser pour les huit touches : interroger chaque touche
## reparcourait la liste des contacts autant de fois.
func collectHeldKeys()
    for i = 1, #notes do
        heldKeys[i] = nil
    end
    for contact, sous in underFinger do
        heldKeys[sous] = true
    end
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.13))
    graphics.noStroke()
    graphics.fontSize(textSize())
    ## Géométrie lue une fois : ces trois fonctions étaient rappelées une trentaine de fois.
    var hb = bandTop()
    var bb = bandBottom()
    var hc = keyboardTop()

    ## La bande de l'bow : sa teinte dit s'il sonne.
    var chaud = (bowHolder <> nil) and 1 or 0
    graphics.fill(Color(0.13 + 0.2 * chaud, 0.15, 0.24))
    graphics.rect(0, hb, W, bb - hb)
    if bowHolder <> nil then
        graphics.fill(Color(0.55, 0.85, 1))
        graphics.rect(bowPos * W - 2, hb, 4, bb - hb)
    end
    graphics.stroke(Color(0.75, 0.82, 0.95))
    graphics.text("glisse ici : oscillateur vivant", W * 0.04, hb + H * 0.05)
    if bowHolder <> nil then
        graphics.text("{bow.freq():.0f} Hz", W * 0.04, hb + H * 0.11)
    end

    ## Le clavier : huit touches, la dernière jouée reste éclairée le temps de sa glow. La
    ## touche SOUS LE DOIGT est cerclée, pour que le balayage se voie autant qu'il s'entende.
    graphics.stroke(Color(0.62, 0.7, 0.85))
    graphics.text("tiens plusieurs doigts posés", W * 0.04, hc - H * 0.07)
    graphics.text("chiffres 1 à 8 : notes brèves", W * 0.04, hc - H * 0.03)
    graphics.noStroke()
    var l = keyWidth()
    collectHeldKeys()
    for i = 1, #notes do
        var tenue = heldKeys[i]
        ## Tenue : pleine lumière tant que l'appui dure. Sinon, la glow d'une note brève.
        var vive = tenue and 1 or ((i == lastKey) and glow or 0)
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
    graphics.text("tampon : {buffers[1].duration():.2f} s, crête {buffers[1].peak():.2f}",
                  W * 0.04, bb - H * 0.04)
end
