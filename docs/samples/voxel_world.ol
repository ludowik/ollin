## Univers voxel infini — chunks générés à la volée par bruit de Perlin, cuits
## autour du joueur (beginChunk/endChunk) et libérés au loin (freeChunk). Distance
## de vue auto-adaptative (classe ViewDistance, view_distance.ol). Joystick tactile.
## Déplacement à inertie : vitesse, virage et hauteur d'œil rejoignent leur consigne
## au lieu de l'adopter d'un coup (voir approach).

import "joystick.ol"
import "view_distance.ol"

global CS = 16
global vd = ViewDistance(4, 1, 24)   ## rayon de chunks : auto-adaptatif + boutons − / +

global SEA = 9
global WATER = SEA + 0.45    ## niveau de la surface d'eau — SEUL seuil de « sous l'eau »
global loaded = {}          ## "cx,cz" → handle endChunk
global cam = graphics.camera(0, 0, 10,  0, 0, 0)
## Caméra de CONTRÔLE (debug) : vue de haut regardant vers le bas, orientée comme la
## caméra du joueur, pour VÉRIFIER de l'extérieur que seuls les chunks visibles (frustum
## de la caméra du joueur) sont dessinés. Bascule avec la touche « C ».
global ctrlCam = graphics.camera(0, 0, 10,  0, 0, 0)
global debugCam = false
global CAMBTN = 46          ## bouton « C » (bascule caméra de contrôle), coin haut-gauche

global EYE = 2.2
global STEP = 1.2           ## marche franchissable ; au-delà = mur
global camX = 8.5
global camY = 10
global camZ = 8.5
global yaw = 0.0
global saveAcc = 0.0        ## accumulateur pour throttler la sauvegarde de position
global PITCH = -0.12
global lastcx = 999999
global lastcz = 999999
global streaming = false

global pad = Joystick()
global TURN_MAX = 1.8
global SPEED_MAX = 8.0
## Inertie : la vitesse et le virage ne suivent pas la consigne du joystick d'un
## coup, ils la rejoignent. L'œil perçoit alors un démarrage et un freinage au lieu
## d'un mouvement uniforme qui s'allume et s'éteint.
global vel = 0.0            ## vitesse d'avance courante
global turnVel = 0.0        ## vitesse de rotation courante
global ACCEL = 5.0          ## nervosité de l'avance (plus grand = plus sec)
global TURN_ACCEL = 7.0
global EYE_RISE = 6.0       ## lissage de la hauteur d'œil (terrain en marches de 1)

## Rapproche `cur` de `target` d'une fraction du chemin restant. La fraction dépend
## de deltaTime via une exponentielle : le résultat ne change donc pas avec le
## nombre d'images par seconde, contrairement à un simple `cur + (target-cur) * 0.1`.
func approach(cur, target, rate)
    return cur + (target - cur) * (1 - math.exp(-rate * deltaTime))
end

global C_SKY = Color(0.55, 0.80, 0.95)
global AMB = 0.5              ## ambiant du terrain

## Nuages : couche de cubes blancs semi-transparents, dérivant en +x. Dessinés en
## IMMÉDIAT chaque frame (ils bougent → pas de chunk/cuisson). 1 seul draw call
## (instancing). Cull par SECTEUR : bbox du secteur testée en frustum → on saute le
## bruit et les cubes d'un pavé de ciel hors-champ.
global CLOUD_Y = SEA + 40     ## altitude (au-dessus des sommets)
global CLOUD_SIZE = 4         ## côté d'un bloc-nuage
global CLOUD_TH = 2           ## épaisseur
global CLOUD_STEP = 4         ## pas de la grille (= CLOUD_SIZE → blocs jointifs)
global CLOUD_SEC = 32         ## côté d'un secteur (8 cellules) pour le cull frustum
global CLOUD_MARGIN = 96      ## marge au-delà du terrain chargé (nuages jusqu'à l'horizon)
global CLOUD_SCALE = 0.05     ## fréquence du bruit de placement
global CLOUD_THRESH = 0.67    ## seuil de couverture (plus haut = moins de nuages)
global CLOUD_SPEED = 1.2      ## dérive (blocs/s)
global CLOUD_ALPHA = 0.9
global CLOUD_TEX = 16         ## côté de la texture mouchetée des nuages
global cloudTex = nil

global TILE = 16
global ACOLS = 4
global AROWS = 4
global atlas = nil
global T_GRASS = 0
global T_DIRT  = 1
global T_SAND  = 2
global T_ROCK  = 3
global T_SNOW  = 4
global T_WATER = 5
global T_TRUNK = 6
global T_LEAF  = 7
global T_STONE = 8
global T_SANDD = 9

## Couleur de base + bruit INDÉPENDANT par canal → variation de teinte, pas seulement
## de luminosité (les tuiles paraissent moins plates).
##
## `trous` (0 = tuile pleine) perce la tuile : le moteur écarte les pixels dont l'alpha est
## sous 0,5, si bien que le cube laisse voir le ciel à travers. C'est ainsi qu'un feuillage
## s'aère sans qu'on retire un seul cube — la forme du houppier reste entière, seule la
## matière devient claire. Les trous suivent un bruit fin : des amas irréguliers, alors
## qu'un pixel sur deux aurait donné un grillage.
func putTile(idx, br, bg, bb, jit, trous = 0)
    var cx = (idx % ACOLS) * TILE
    var cy = math.floor(idx / ACOLS) * TILE
    for py = 0, TILE - 1 do
        for px = 0, TILE - 1 do
            var wx = (cx + px) * 1.7
            var wy = (cy + py) * 1.7
            var nr = (math.noise(wx + 9,  wy + 9)   - 0.5) * 2 * jit
            var ng = (math.noise(wx + 41, wy + 67)  - 0.5) * 2 * jit
            var nb = (math.noise(wx + 113, wy + 151) - 0.5) * 2 * jit
            var a = 1
            if trous > 0 then
                ## Les BORDS de la tuile restent pleins : un trou au bord ouvrirait une fente
                ## continue entre deux cubes voisins, bien plus voyante qu'un trou isolé.
                var bord = math.min(math.min(px, py), math.min(TILE - 1 - px, TILE - 1 - py))
                var n = math.noise((cx + px) * 0.55 + 200, (cy + py) * 0.55 + 200)
                if bord >= 2 and n > 1 - trous then
                    a = 0
                end
            end
            image.setPixel(atlas, cx + px, cy + py,
                math.clamp(br + nr, 0, 1), math.clamp(bg + ng, 0, 1), math.clamp(bb + nb, 0, 1), a)
        end
    end
end

func buildAtlas()
    atlas = image.create(ACOLS * TILE, AROWS * TILE)
    image.beginPixels(atlas)
    putTile(T_GRASS, 0.42, 0.68, 0.30, 0.16)
    putTile(T_DIRT,  0.46, 0.33, 0.20, 0.15)
    putTile(T_SAND,  0.86, 0.79, 0.53, 0.11)
    putTile(T_ROCK,  0.47, 0.46, 0.45, 0.18)
    putTile(T_SNOW,  0.95, 0.97, 1.00, 0.07)
    putTile(T_WATER, 0.20, 0.45, 0.80, 0.14)
    putTile(T_TRUNK, 0.40, 0.26, 0.13, 0.16)
    putTile(T_LEAF,  0.18, 0.42, 0.16, 0.22, 0.42)   ## seule tuile ajourée : le feuillage
    putTile(T_STONE, 0.36, 0.36, 0.40, 0.16)
    putTile(T_SANDD, 0.72, 0.63, 0.40, 0.12)
    image.endPixels(atlas)
    graphics.tileset(atlas, ACOLS, AROWS)
    graphics.tileAnim(T_WATER)
end

## Texture de nuage : blanc légèrement moucheté (bruit de luminosité), alpha plein.
## Casse le blanc plat des cubes sans créer de trou.
func buildCloudTex()
    cloudTex = image.create(CLOUD_TEX, CLOUD_TEX)
    image.beginPixels(cloudTex)
    for py = 0, CLOUD_TEX - 1 do
        for px = 0, CLOUD_TEX - 1 do
            var v = 0.78 + math.noise(px * 0.22 + 3, py * 0.22 + 7) * 0.22   ## ~0.78 → 1.0, basse fréquence → dégradé doux
            image.setPixel(cloudTex, px, py, v, v, v, 1)
        end
    end
    image.endPixels(cloudTex)
end

## Biome de surface : 0 = désert, 1 = plaine, 2 = forêt. Le relief (roche/neige) vient
## de l'altitude, pas du biome.
func biomeAt(x, z)
    var b = math.noise(x * 0.026 + 50, z * 0.026 + 50)
    if b < 0.38 then return 0 end
    if b < 0.62 then return 1 end
    return 2
end

## Élévation lisse : une grande échelle (collines larges) + un léger détail. Source
## unique → pentes douces, aucune falaise aléatoire.
func elevation(x, z)
    return math.noise(x * 0.013, z * 0.013) * 0.82
         + math.noise(x * 0.075, z * 0.075) * 0.18
end

## Amplitude 44 (et non 60) : depuis la normalisation de math.noise sur [0,1], le bruit
## s'étale ~1,35× plus → 60 rendait le relief trop escarpé. 44 restaure des pentes douces.
func rawHeight(x, z)
    return math.floor((elevation(x, z) - 0.42) * 44 + SEA)
end

## Élimine les extrema d'1 colonne : un pic isolé (plus haut que ses 4 voisins) est
## rabaissé au plus haut voisin, un puits isolé (plus bas que ses 4 voisins) est
## remonté au plus bas voisin → ni cube ni trou solitaire. Fonction pure de (x, z)
## → même hauteur pour le culling, la collision et le spawn (pas de jointure incohérente).
func heightAt(x, z)
    var h = rawHeight(x, z)
    var e = rawHeight(x + 1, z)
    var w = rawHeight(x - 1, z)
    var n = rawHeight(x, z + 1)
    var s = rawHeight(x, z - 1)
    var hi = math.max(math.max(e, w), math.max(n, s))
    var lo = math.min(math.min(e, w), math.min(n, s))
    if h > hi then return hi end   ## cube solitaire → éliminé
    if h < lo then return lo end   ## trou solitaire → rempli
    return h
end

## Sommet cuit de la colonne : le dessus du cube le plus haut est à colTop + 0.5.
func colTop(x, z)
    return math.max(heightAt(x, z), 0)
end

## Hauteur du SOL sous (x, z) : le dessus du cube de sommet, ou la surface de l'eau si la
## colonne est immergée (on flotte). Le terrain monte donc par marches d'un bloc — c'est
## l'esprit voxel : tous les cubes ont la même taille.
func ground(x, z)
    return math.max(colTop(math.floor(x), math.floor(z)) + 0.5, WATER)
end

## Tuiles (dessus/côté/dessous) selon l'altitude : plage → herbe → roche → neige ;
## le biome ne distingue que le désert.
func setBlockTiles(b, h, y)
    if y >= h then
        if h < SEA + 1 then
            graphics.tile(T_SAND)
        elseif h >= SEA + 13 then
            graphics.tiles(T_SNOW, T_SNOW, T_ROCK)
        elseif h >= SEA + 8 then
            graphics.tile(T_ROCK)
        elseif b == 0 then
            graphics.tile(T_SAND)
        else
            graphics.tiles(T_GRASS, T_DIRT, T_DIRT)
        end
        return
    end
    if y >= h - 2 then
        if b == 0 then
            graphics.tile(T_SANDD)
        else
            graphics.tile(T_DIRT)
        end
        return
    end
    graphics.tile(T_STONE)
end

func ckey(cx, cz)
    return cx + "," + cz
end

## Hash 2D bien mélangé (≠ x*a + z*b linéaire, qui alignait les arbres en diagonales).
## `salt` donne des flux indépendants (position / hauteur / forme) pour la même colonne.
func treeHash(x, z, salt)
    var h = (x * 374761393) ~ (z * 668265263) ~ (salt * 2246822519)
    h = (h ~ (h >> 15)) * 2654435761
    h = h ~ (h >> 13)
    return h & 2147483647
end

## Un niveau de houppier : carré de rayon r ; round=true retire les coins (arrondi).
func canopy(x, y, z, r, round)
    for tx = -r, r do
        for tz = -r, r do
            if not (round and math.abs(tx) == r and math.abs(tz) == r) then
                graphics.cube(x + tx, y, z + tz,  1, 1, 1)
            end
        end
    end
end

## Arbre à la colonne (x,z), sol en h. Hauteur de tronc et forme du houppier variées,
## dérivées du hash (déterministe par colonne) → chaque arbre diffère.
func putTree(x, z, h)
    var th = 3 + treeHash(x, z, 1) % 4      ## tronc : 3..6 cubes
    var shape = treeHash(x, z, 2) % 3       ## 0 rond · 1 touffu · 2 conique
    graphics.tile(T_TRUNK)
    for k = 1, th do
        graphics.cube(x, h + k, z,  1, 1, 1)
    end
    graphics.tile(T_LEAF)
    var top = h + th
    if shape == 2 then
        canopy(x, top - 1, z, 1, true)       ## conique : base arrondie + flèche
        graphics.cube(x, top, z,  1, 1, 1)
        graphics.cube(x, top + 1, z,  1, 1, 1)
    else
        var round = shape == 0               ## rond (coins retirés) ou touffu (plein)
        canopy(x, top - 1, z, 1, round)
        canopy(x, top, z, 1, round)
        graphics.cube(x, top + 1, z,  1, 1, 1)
    end
end

func bakeChunk(cx, cz)
    graphics.beginChunk()
    graphics.fill(colors.WHITE)   ## teinte neutre : l'atlas fournit la couleur
    var x0 = cx * CS
    var z0 = cz * CS
    ## Hauteurs BRUTES sur la zone + une bordure de 1 (indices -1..CS), pour le culling
    ## des faces cachées : on ne cuit un cube que si une face touche le vide (sommet de
    ## colonne, ou voisin plus bas) → seule la surface est instanciée, pas le volume.
    var W2 = CS + 2
    var hg = []
    for lz = -1, CS do
        for lx = -1, CS do
            hg[(lz + 1) * W2 + (lx + 1) + 1] = heightAt(x0 + lx, z0 + lz)
        end
    end
    for lz = 0, CS - 1 do
        for lx = 0, CS - 1 do
            var x = x0 + lx
            var z = z0 + lz
            var b = biomeAt(x, z)
            var h = hg[(lz + 1) * W2 + (lx + 1) + 1]
            var top = math.max(h, 0)
            ## hauteurs des 4 voisins, clampées comme les colonnes cuites (>= 0)
            var he = math.max(hg[(lz + 1) * W2 + (lx + 2) + 1], 0)
            var hw = math.max(hg[(lz + 1) * W2 + lx + 1], 0)
            var hs = math.max(hg[(lz + 2) * W2 + (lx + 1) + 1], 0)
            var hn = math.max(hg[lz * W2 + (lx + 1) + 1], 0)
            var mn = math.min(math.min(he, hw), math.min(hs, hn))
            for y = 0, top do
                if y == top or y > mn then   ## face visible : sommet OU un voisin plus bas
                    setBlockTiles(b, h, y)
                    ## Cube IMMERGÉ : assombri selon sa profondeur (moins de lumière au fond).
                    ## C'est le FOND qui s'assombrit avec la profondeur, pas l'eau (uniforme).
                    if y < SEA then
                        var dk = math.clamp((SEA - y) / 5.0, 0, 0.85)   ## assombrit plus tôt et plus fort
                        graphics.fill(Color(1 - dk, 1 - dk, 1 - dk))
                    else
                        graphics.fill(colors.WHITE)
                    end
                    graphics.cube(x, y, z,  1, 1, 1)
                end
            end
            ## Nappe posée dès que le dessus de la colonne passe sous la surface : même
            ## comparaison que ground, donc le contact eau/terrain ne peut pas se désaccorder.
            if top + 0.5 < WATER then
                ## eau = UN plan semi-transparent UNIFORME au niveau de la mer (surface
                ## continue) ; l'atténuation avec la profondeur est portée par les cubes du fond.
                graphics.tile(T_WATER)
                graphics.fill(Color(1, 1, 1, 0.72))
                graphics.plane(x, WATER, z,  1, 1)
                graphics.fill(colors.WHITE)
            end
            var hp = treeHash(x, z, 0) % 100    ## placement dispersé (hash mélangé)
            var grassy = h > SEA and h < SEA + 8 and b <> 0
            var tree = grassy and ((b == 2 and hp < 6) or hp == 0)
            if tree then
                putTree(x, z, h)
            end
        end
    end
    var g = graphics.endChunk()
    g.wx = x0 + CS / 2
    g.wz = z0 + CS / 2
    g.cx = cx
    g.cz = cz
    return g
end

## Cuit les chunks manquants du rayon, `budget` par frame, en priorisant ce qui est
## devant la caméra puis le plus proche (buffer trié borné). Renvoie le nombre cuit.
func streamLoad(pcx, pcz, budget)
    if budget < 1 then
        return 0
    end
    var bcx = []
    var bcz = []
    var bsc = []
    var cnt = 0
    var fdx = math.sin(yaw)
    var fdz = math.cos(yaw)
    ## Balayage en anneaux (Chebyshev) croissants, du plus proche au plus loin. On ne
    ## parcourt que le PÉRIMÈTRE de chaque anneau (O(r²) total, comme un carré plein) ;
    ## dès que le tampon est plein et que l'anneau courant ne peut plus battre le pire
    ## score retenu (d² > bsc[cnt]), on arrête — plus de rebalayage de toute la grille.
    for d = 0, vd.radius do
        if cnt >= budget and d * d > bsc[cnt] then
            break
        end
        for dz = -d, d do
            var stepx = 1
            if d > 0 and dz > -d and dz < d then
                stepx = 2 * d       ## lignes du milieu : seulement les colonnes ±d
            end
            for dx = -d, d, stepx do
                var cx = pcx + dx
                var cz = pcz + dz
                if loaded[ckey(cx, cz)] == nil then
                    var score = dx * dx + dz * dz
                    if dx * fdx + dz * fdz < 0 then
                        score = score + 100000         ## derrière la caméra → après
                    end
                    if cnt < budget or score < bsc[cnt] then
                        var p = budget
                        if cnt < budget then
                            cnt = cnt + 1
                            p = cnt
                        end
                        while p > 1 and bsc[p - 1] > score do
                            bcx[p] = bcx[p - 1]
                            bcz[p] = bcz[p - 1]
                            bsc[p] = bsc[p - 1]
                            p = p - 1
                        end
                        bcx[p] = cx
                        bcz[p] = cz
                        bsc[p] = score
                    end
                end
            end
        end
    end
    for i = 1, cnt do
        loaded[ckey(bcx[i], bcz[i])] = bakeChunk(bcx[i], bcz[i])
    end
    return cnt
end

## Libère les chunks hors rayon. margin = hystérésis : 1 en déplacement (anneau tampon,
## pas de churn en reculant d'un pas), 0 en réduction (libère aussitôt).
func streamUnload(pcx, pcz, margin)
    var keep = {}
    for k, c in loaded do
        if math.abs(c.cx - pcx) <= vd.radius + margin and math.abs(c.cz - pcz) <= vd.radius + margin then
            keep[k] = c
        else
            graphics.freeChunk(c)
        end
    end
    loaded = keep
end

func setup()
    graphics.canvas(W, H, "Voxel infini")
    graphics.ambient(AMB)
    graphics.light("dir", -0.5, -1, -0.35)
    math.noiseSeed(7)
    buildAtlas()
    buildCloudTex()
    ## spawn : terre ferme, basse et proche de l'origine (pénalité forte sur l'altitude
    ## → jamais sous l'eau).
    var best = 1000000000.0
    for z = 0, 60 do
        for x = 0, 60 do
            var h = heightAt(x, z)
            if h > SEA then
                var cx = x - 30
                var cz = z - 30
                var score = cx * cx + cz * cz + (h - SEA) * (h - SEA) * 40
                if score < best then
                    best = score
                    camX = x + 0.5
                    camZ = z + 0.5
                end
            end
        end
    end
    ## regard vers la direction la plus dégagée (somme d'altitude minimale)
    var bestSum = 1000000.0
    for a = 0, 15 do
        var ang = a / 16.0 * 6.28319
        var sum = 0.0
        for k = 3, 18, 3 do
            sum = sum + ground(camX + math.sin(ang) * k, camZ + math.cos(ang) * k)
        end
        if sum < bestSum then
            bestSum = sum
            yaw = ang
        end
    end
    ## restaure la position mémorisée (module data) si présente → écrase le spawn par défaut
    if data.has("camX") then
        camX = data.get("camX", camX)
        camZ = data.get("camZ", camZ)
        yaw = data.get("yaw", yaw)
    end
    camY = ground(camX, camZ) + EYE   ## sans ça, l'œil descendrait depuis le ciel au 1er frame
    lastcx = math.floor(camX / CS)
    lastcz = math.floor(camZ / CS)
    loaded[ckey(lastcx, lastcz)] = bakeChunk(lastcx, lastcz)   ## sol présent dès le spawn
    streaming = true
end

## Bouton caméra (bascule debug) : carré en haut-gauche, sous le HUD.
func camBtnHit(x, y)
    return x >= 12 and x <= 12 + CAMBTN and y >= 36 and y <= 36 + CAMBTN
end

func drawCamButton()
    graphics.noStroke()
    graphics.fill(Color(0, 0, 0, 0.38))
    graphics.rect(12, 36, CAMBTN, CAMBTN)
    if debugCam then                   ## allumé = caméra de contrôle active
        graphics.fill(Color(0.30, 0.70, 1.00, 0.55))
        graphics.rect(12, 36, CAMBTN, CAMBTN)
    end
    graphics.stroke(colors.WHITE)
    graphics.fontSize(28)
    graphics.text("C", 12 + CAMBTN / 2 - 8, 36 + CAMBTN / 2 - 15)
end

func mouse.pressed(x, y)
    if camBtnHit(x, y) then          ## bouton caméra → bascule (accessible tactile)
        debugCam = not debugCam
        return
    end
    var ev = vd.hit(x, y)              ## boutons − / + gérés par ViewDistance
    if ev == 1 then
        streaming = true               ## rayon agrandi → charger le nouvel anneau
    elseif ev == -1 then
        streamUnload(lastcx, lastcz, 0)   ## rayon réduit → libérer aussitôt
    elseif ev == 0 then
        pad.press(x, y)                ## hors boutons → joystick (ev == 2 : borne atteinte, rien)
    end
end
func mouse.released(x, y)
    pad.release()
end
## Touche C : bascule la caméra de contrôle (le déplacement, lui, lit keyboard.isDown).
func keyboard.keypressed(key)
    if string.upper(key) == "C" then
        debugCam = not debugCam
    end
end
func mouse.moved(x, y)
    pad.move(x, y)
end

## Avance le joueur (virage + vitesse), joystick tactile ET flèches clavier combinés,
## avec glissement sur les pentes franchissables et blocage sur les murs.
func movePlayer()
    var turn = pad.steer()
    if keyboard.isDown("left") then turn = turn - 1 end
    if keyboard.isDown("right") then turn = turn + 1 end
    turnVel = approach(turnVel, math.clamp(turn, -1, 1) * TURN_MAX, TURN_ACCEL)
    yaw = yaw - turnVel * deltaTime

    var thr = pad.throttle()      ## joystick : [-1;1] (avant / arrière)
    if keyboard.isDown("up") then thr = thr + 1 end
    if keyboard.isDown("down") then thr = thr - 1 end   ## flèche bas = marche arrière
    vel = approach(vel, math.clamp(thr, -1, 1) * SPEED_MAX, ACCEL)
    ## Sous le millimètre par seconde, on est à l'arrêt : couper évite de faire
    ## tourner le test de collision pour un déplacement invisible.
    if math.abs(vel) < 0.001 then
        vel = 0.0
        return
    end
    var sp = vel * deltaTime
    ## Déplacement découpé en sous-pas d'un DEMI-BLOC au plus. La garde ci-dessous ne
    ## compare que le sol de départ et celui d'arrivée : un pas plus large qu'un bloc peut
    ## enjamber un mur étroit sans jamais l'échantillonner. Cela n'arrive qu'en dessous de
    ## huit images par seconde — une frame très longue, par exemple pendant une cuisson de
    ## chunks — mais le joueur se retrouve alors DANS le terrain.
    var pas = math.max(math.ceil(math.abs(sp) / 0.5), 1)
    var dx = math.sin(yaw) * sp / pas
    var dz = math.cos(yaw) * sp / pas
    var moved = false
    for i = 1, pas do
        var g0 = ground(camX, camZ)
        var nx = camX + dx
        var nz = camZ + dz
        var bloque = true
        if ground(nx, camZ) - g0 <= STEP then
            camX = nx
            moved = true
            bloque = false
        end
        if ground(camX, nz) - g0 <= STEP then
            camZ = nz
            moved = true
            bloque = false
        end
        ## Mur atteint : les sous-pas restants n'iraient pas plus loin.
        if bloque then
            break
        end
    end
    ## Face à un mur, on retombe à zéro : sinon la vitesse continuerait de monter
    ## dans le vide et le joueur bondirait en se dégageant.
    if not moved then
        vel = 0.0
    end
end

## Mémorise la position (module data) au plus une fois par seconde (throttle) : éviter
## une écriture localStorage/fichier à chaque frame.
func savePlayer()
    saveAcc = saveAcc + deltaTime
    if saveAcc < 1.0 then
        return
    end
    saveAcc = 0.0
    data.set("camX", camX)
    data.set("camZ", camZ)
    data.set("yaw", yaw)
end

## Nuages : pattern de bruit FIGÉ échantillonné aux positions « maison » (cx,cz),
## rendu décalé de `drift` en x → translation continue et lisse.
##
## Cull par SECTEUR fait ICI, comme les chunks : AVANT begin3d(rcam), donc contre le
## frustum FIGÉ du JOUEUR. Sinon, en caméra de contrôle (rendu depuis ctrlCam),
## inFrustum lirait le frustum de la caméra de contrôle → aucun secteur rejeté.
##
## On ne scanne pas le carré 2·reach plein (dont ~la moitié est DERRIÈRE le joueur et
## échoue toujours inFrustum) : chaque rangée est clippée au demi-plan avant (produit
## scalaire avec la direction de regard f). On ne retire que des secteurs derrière la
## caméra — que inFrustum rejetait déjà — donc couverture visible inchangée.
## Renvoie un tableau plat [sx0, sz0, sx1, sz1, …] des secteurs visibles.
global cloudStats = {"tested": 0, "kept": 0, "full": 0}

func cullCloudSectors()
    var drift = elapsedTime * CLOUD_SPEED
    var reach = vd.radius * CS + CLOUD_MARGIN   ## suit la distance d'affichage du terrain
    var fx = math.sin(yaw)                       ## direction de regard (XZ)
    var fz = math.cos(yaw)
    var secs = []
    var tested = 0
    var s0z = math.floor((camZ - reach) / CLOUD_SEC) * CLOUD_SEC
    ## carré plein sans demi-plan : toutes les rangées de s0z à camZ+reach
    var fullW = math.floor(2 * reach / CLOUD_SEC) + 1
    var fullRows = math.floor(2 * reach / CLOUD_SEC) + 1
    var fullTotal = fullW * fullRows
    for sz = s0z, camZ + reach, CLOUD_SEC do
        var wz = sz + CLOUD_SEC / 2
        ## span x du demi-plan avant : (wx-camX)*fx + (wz-camZ)*fz >= -CLOUD_SEC
        var rhs = 0 - CLOUD_SEC - (wz - camZ) * fz
        var wlo = camX - reach
        var whi = camX + reach
        if fx > 0.001 then
            wlo = math.max(wlo, camX + rhs / fx)
        elseif fx < -0.001 then
            whi = math.min(whi, camX + rhs / fx)
        elseif rhs > 0 then
            wlo = whi + 1                         ## rangée entièrement derrière → vide
        end
        var s0x = math.floor((wlo - drift) / CLOUD_SEC) * CLOUD_SEC
        for sx = s0x, whi - drift, CLOUD_SEC do
            tested = tested + 1
            if graphics.inFrustum(sx + CLOUD_SEC / 2 + drift, CLOUD_Y, wz, CLOUD_SEC * 0.72 + 4) then
                secs[#secs + 1] = sx
                secs[#secs + 1] = sz
            end
        end
    end
    cloudStats.tested = tested
    cloudStats.full = fullTotal
    cloudStats.kept = #secs // 2
    return secs
end

func drawClouds(secs)
    var drift = elapsedTime * CLOUD_SPEED
    graphics.ambient(0.8)                        ## < 1 → la lumière directionnelle donne du volume aux nuages
    graphics.fill(Color(1, 1, 1, CLOUD_ALPHA))
    graphics.texture(cloudTex)                    ## moucheté doux (casse le blanc plat)
    for i = 1, #secs, 2 do
        var sx = secs[i]
        var sz = secs[i + 1]
        for cx = sx, sx + CLOUD_SEC - CLOUD_STEP, CLOUD_STEP do
            for cz = sz, sz + CLOUD_SEC - CLOUD_STEP, CLOUD_STEP do
                if math.noise(cx * CLOUD_SCALE, cz * CLOUD_SCALE) > CLOUD_THRESH then
                    graphics.cube(cx + drift, CLOUD_Y, cz,  CLOUD_SIZE, CLOUD_TH, CLOUD_SIZE)
                end
            end
        end
    end
    graphics.noTexture()
    graphics.fill(colors.WHITE)
end

func draw()
    graphics.clear(C_SKY)
    movePlayer()
    savePlayer()

    var pcx = math.floor(camX / CS)
    var pcz = math.floor(camZ / CS)
    if pcx <> lastcx or pcz <> lastcz then
        lastcx = pcx
        lastcz = pcz
        streamUnload(pcx, pcz, 1)
        streaming = true
    end
    var budget = 6
    if vd.manual then budget = 10 end
    if streaming and streamLoad(pcx, pcz, budget) == 0 then
        streaming = false
    end
    var ev = vd.update(deltaTime, streaming)
    if ev == 1 then
        streaming = true
    elseif ev == -1 then
        streamUnload(pcx, pcz, 0)
    end

    ## Le terrain monte par marches d'un bloc : poser l'œil dessus le ferait sauter
    ## d'un cran d'un seul coup. On le laisse rejoindre la marche progressivement.
    camY = approach(camY, ground(camX, camZ) + EYE, EYE_RISE)
    cam.setPos(camX, camY, camZ)
    cam.lookAt(camX + math.cos(PITCH) * math.sin(yaw),
               camY + math.sin(PITCH),
               camZ + math.cos(PITCH) * math.cos(yaw))

    graphics.noStroke()
    ## Caméra de rendu : joueur, ou caméra de contrôle en hauteur (regard vers le bas,
    ## up = direction d'avancée du joueur → même orientation à l'écran). Le culling reste
    ## TOUJOURS celui du joueur : en mode contrôle on rend d'une AUTRE caméra, alors on
    ## fige d'abord le frustum du joueur (bloc 3D vide → gèle vue+projection lues par
    ## inFrustum). En mode joueur, inutile : inFrustum réutilise le frustum figé par le
    ## rendu de la frame précédente (donc pas de passe 3D vide sur le chemin normal).
    var rcam = cam
    if debugCam then
        graphics.begin3d(cam)
        graphics.end3d()
        var high = vd.radius * CS * 2.0 + 40
        ctrlCam.setPos(camX, camY + high, camZ)
        ctrlCam.lookAt(camX, camY, camZ)
        ctrlCam.ux = math.sin(yaw)
        ctrlCam.uy = 0
        ctrlCam.uz = math.cos(yaw)
        rcam = ctrlCam
    end

    var vis = []
    for k, c in loaded do
        if graphics.inFrustum(c.wx, SEA, c.wz, CS + 24) then
            vis[#vis + 1] = c
        end
    end
    var cloudSecs = cullCloudSectors()   ## cull avant begin3d(rcam) → frustum joueur figé
    graphics.begin3d(rcam)
    do
        for i = 1, #vis do
            graphics.drawChunk(vis[i])
        end
        for i = 1, #vis do
            graphics.drawChunkAlpha(vis[i])
        end
        drawClouds(cloudSecs)
    end
    graphics.end3d()
    graphics.ambient(AMB)           ## drawClouds a baissé l'ambiant → rétablir pour le terrain

    pad.draw()
    vd.draw()                          ## boutons − / + (ViewDistance)
    drawCamButton()                  ## bouton « C » (bascule caméra de contrôle)
    var camlbl = "joueur"
    if debugCam then camlbl = "contrôle" end
    graphics.stroke(colors.WHITE)
    graphics.fontSize(15)
    graphics.text("vue " + vd.radius + " " + vd.mode() + " " + vd.hz() + "Hz  chunks " + #vis +
                  "  cam " + camlbl, 12, 12)
    graphics.stroke(colors.WHITE)
    graphics.fontSize(13)
    graphics.text("nuages : " + cloudStats.tested + "/" + cloudStats.full + " testés  " + cloudStats.kept + " rendus", 12, 30)
end
