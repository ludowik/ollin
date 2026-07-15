## Univers VOXEL INFINI — chunks générés à la volée en se déplaçant.
##   • Le terrain vient d'un bruit de Perlin (défini partout) → monde illimité.
##   • On CUIT (beginChunk/endChunk) les chunks autour du joueur et on LIBÈRE
##     (freeChunk) les lointains → mémoire bornée, univers qui s'étend en marchant.
##   • On ne dessine que les chunks VISIBLES (inFrustum). Biomes de surface :
##     désert/plaine/forêt ; relief (roche/neige) selon l'altitude. DÉPLACEMENT :
##     joystick analogique tactile (classe réutilisable, joystick.ol).

import "joystick.ol"       ## classe Joystick (contrôle analogique)

global CS = 16             ## côté d'un chunk
global VIEW = 4            ## rayon de chunks chargés — ADAPTATIF (voir bloc auto-adapt)
global VIEW_MIN = 1        ## borne basse du rayon adaptatif
global VIEW_MAX = 24       ## garde-fou MÉMOIRE seulement (évite l'emballement) — PAS un plafond
                          ## de perf : en pratique le FPS décroche et limite bien avant.

## ── Auto-adaptation de la distance de vue ────────────────────────────────────
## En vsync verrouillé, deltaTime ne révèle PAS la marge (il reste à ~1/cadence
## tant qu'on tient) : il ne monte QUE quand des frames débordent. On compte donc,
## sur une fenêtre, la PART de frames LENTES : trop de lentes → on réduit la
## distance ; aucune lente → on sonde plus loin.
## CRUCIAL : les frames « irréelles » (> STALL_DT, ≈ moins de 3 fps) sont IGNORÉES.
## Elles ne viennent jamais d'une vraie surcharge de rendu mais du navigateur qui
## bride le requestAnimationFrame quand la page passe en arrière-plan / au retour
## d'une autre appli — les compter ferait rétrécir la vue À TORT (le bug précédent).
global SLOW_DT  = 0.021    ## frame « lente » : au-dessus de ~48 fps de période
global STALL_DT = 0.30     ## au-delà = arrière-plan/reprise, PAS une frame réelle → ignorée
global ADAPT_WIN = 0.5     ## durée d'une fenêtre d'évaluation (courte → réactif)
global fps_ema  = 60.0     ## FPS lissé — AFFICHAGE seulement (aucune décision dessus)
global adapt_t  = 0.0      ## secondes mesurées dans la fenêtre courante
global adapt_n  = 0        ## frames réelles comptées dans la fenêtre
global adapt_slow = 0      ## dont frames lentes
global grow_step = 1       ## amplitude de la prochaine montée : DOUBLE à chaque fenêtre fluide
                          ## (1,2,4,8…) → on atteint la limite du device en quelques fenêtres
global view_cap = 999      ## plafond APPRIS au décrochage → on n'y remonte plus (anti-oscillation)

## Réglage MANUEL de la distance : deux boutons tactiles − / + en haut à droite.
## Toucher un bouton passe en mode manuel → l'auto-adaptation se met en retrait
## (elle ne contre plus ton réglage). Pratique pour tester l'impact de la distance.
global manual = false      ## true dès qu'on a touché un bouton
global BTN = 54            ## côté d'un bouton (cible tactile)
global BTN_Y = 12          ## ordonnée des boutons
global SEA = 9             ## niveau de la mer (marge sous la mer pour les océans)
global loaded = {}         ## "cx,cz" → handle endChunk { id, idw, count, wcount, wx, wz, cx, cz }
global cam = graphics.camera(0, 0, 10,  0, 0, 0)

global EYE = 2.2
global STEP = 1.2          ## marche franchissable ; au-delà = mur (falaise/montagne)
global camX = 8.5
global camY = 10
global camZ = 8.5
global yaw = 0.0
global PITCH = -0.12
global lastcx = 999999
global lastcz = 999999
global streaming = false   ## vrai tant qu'il reste des chunks à charger (évite le balayage à vide)

## déplacement : joystick analogique réutilisable (joystick.ol)
global pad = Joystick()
global TURN_MAX = 1.8      ## rad/s à l'inclinaison horizontale maximale
global SPEED_MAX = 8.0     ## blocs/s à la poussée verticale maximale

global C_SKY   = Color(0.55, 0.80, 0.95)
global WHITE   = Color(1, 1, 1)

## Atlas de tuiles (grille 4×4 de tuiles 16×16 px). Chaque cube porte un triplet
## de tuiles (dessus/côté/dessous) ; le shader échantillonne l'atlas par face.
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

## Remplit une tuile de l'atlas : couleur de base + mouchetis (bruit) → matière.
func put_tile(idx, br, bg, bb, jit)
    var cx = (idx % ACOLS) * TILE
    var cy = math.floor(idx / ACOLS) * TILE
    for py = 0, TILE - 1 do
        for px = 0, TILE - 1 do
            var n = (math.noise((cx + px) * 1.7 + 9, (cy + py) * 1.7 + 9) - 0.5) * 2 * jit
            image.set_pixel(atlas, cx + px, cy + py,
                math.clamp(br + n, 0, 1), math.clamp(bg + n, 0, 1), math.clamp(bb + n, 0, 1), 1)
        end
    end
end

func build_atlas()
    atlas = image.create(ACOLS * TILE, AROWS * TILE)
    image.begin_pixels(atlas)
    put_tile(T_GRASS, 0.42, 0.68, 0.30, 0.10)
    put_tile(T_DIRT,  0.46, 0.33, 0.20, 0.10)
    put_tile(T_SAND,  0.86, 0.79, 0.53, 0.07)
    put_tile(T_ROCK,  0.47, 0.46, 0.45, 0.13)
    put_tile(T_SNOW,  0.95, 0.97, 1.00, 0.05)
    put_tile(T_WATER, 0.20, 0.45, 0.80, 0.10)
    put_tile(T_TRUNK, 0.40, 0.26, 0.13, 0.12)
    put_tile(T_LEAF,  0.18, 0.42, 0.16, 0.16)
    put_tile(T_STONE, 0.36, 0.36, 0.40, 0.11)
    put_tile(T_SANDD, 0.72, 0.63, 0.40, 0.08)
    image.end_pixels(atlas)
    graphics.tileset(atlas, ACOLS, AROWS)
    graphics.tileAnim(T_WATER)    ## l'eau ondule (UV qui défile)
end

## Biome de SURFACE uniquement (la hauteur vient de l'altitude, cf. height_at) :
## 0 = désert (sable, sec), 1 = plaine (herbe), 2 = forêt (herbe + arbres denses).
## Le relief « montagne » (roche/neige) est purement fonction de l'altitude.
func biome_at(x, z)
    var b = math.noise(x * 0.026 + 50, z * 0.026 + 50)
    if b < 0.38 then return 0 end
    if b < 0.62 then return 1 end
    return 2
end

## Élévation continue et LISSE (0..1). math.noise fait déjà du fBm multi-octave ;
## on garde UNE grande échelle (collines larges) + un léger détail. Une seule
## source → aucune discontinuité, pentes douces (pas de terrain haché ni de
## falaises aléatoires). Le biome n'intervient PAS ici (sinon cliffs aux frontières).
func elevation(x, z)
    return math.noise(x * 0.013, z * 0.013) * 0.82
         + math.noise(x * 0.075, z * 0.075) * 0.18
end

## Hauteur du terrain : fonction CONTINUE de la position. Centrée (≈13% sous la
## mer), amplitude étalée sur de larges reliefs → collines/vallées douces.
func height_at(x, z)
    return math.floor((elevation(x, z) - 0.42) * 60 + SEA)
end

func ground(x, z)
    return math.max(height_at(math.floor(x), math.floor(z)), SEA)
end

## Fixe les tuiles (dessus/côté/dessous) selon l'ALTITUDE (logique : plage → herbe
## → roche → neige) ; le biome ne sert qu'à distinguer le désert (bas et sec).
func set_block_tiles(b, h, y)
    if y >= h then
        if h < SEA + 1 then
            graphics.tile(T_SAND)                     ## fond marin + plage
        elseif h >= SEA + 13 then
            graphics.tiles(T_SNOW, T_SNOW, T_ROCK)    ## sommets enneigés
        elseif h >= SEA + 8 then
            graphics.tile(T_ROCK)                     ## roche en altitude
        elseif b == 0 then
            graphics.tile(T_SAND)                     ## désert (bas, sec)
        else
            graphics.tiles(T_GRASS, T_DIRT, T_DIRT)   ## herbe dessus, terre sur les côtés
        end
        return
    end
    if y >= h - 2 then
        if b == 0 then
            graphics.tile(T_SANDD)                    ## sous-sol désert
        else
            graphics.tile(T_DIRT)
        end
        return
    end
    graphics.tile(T_STONE)                            ## roche profonde
end

func ckey(cx, cz)
    return cx + "," + cz
end

## Génère + cuit le chunk (cx,cz) depuis le bruit → handle persistant.
func bake_chunk(cx, cz)
    graphics.beginChunk()
    graphics.fill(WHITE)          ## teinte neutre : l'atlas fournit la couleur
    var x0 = cx * CS
    var z0 = cz * CS
    for z = z0, z0 + CS - 1 do
        for x = x0, x0 + CS - 1 do
            var b = biome_at(x, z)
            var h = height_at(x, z)
            for y = 0, math.max(h, 0) do   ## au moins un fond (y=0) même si h<0 → pas de trou sous l'eau
                set_block_tiles(b, h, y)
                graphics.cube(x, y, z,  1, 1, 1)
            end
            if h < SEA then
                ## surface d'eau = UN plan au niveau de la mer (pas une pile de cubes) :
                ## surface continue, semi-transparente → on voit le fond, sans faces internes.
                graphics.tile(T_WATER)
                graphics.fill(Color(1, 1, 1, 0.72))
                graphics.plane(x, SEA + 0.45, z,  1, 1)
                graphics.fill(WHITE)                  ## retour opaque (arbres, colonnes suivantes)
            end
            var hash = math.abs(x * 131 + z * 197) % 100    ## abs : % signé sinon ~53% (au lieu de 6%)
            ## arbres uniquement sur l'herbe (au-dessus de la mer, sous la roche, hors désert)
            var grassy = h > SEA and h < SEA + 8 and b <> 0
            var tree = grassy and ((b == 2 and hash < 6) or hash == 0)
            if tree then
                graphics.tile(T_TRUNK)
                for k = 1, 4 do
                    graphics.cube(x, h + k, z,  1, 1, 1)
                end
                graphics.tile(T_LEAF)
                for ly = 4, 5 do
                    for lx = -1, 1 do
                        for lz = -1, 1 do
                            graphics.cube(x + lx, h + ly, z + lz,  1, 1, 1)
                        end
                    end
                end
                graphics.cube(x, h + 6, z,  1, 1, 1)
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

## Charge les chunks manquants dans le rayon (budget limité par frame → pas de à-coups).
## Renvoie le nombre de chunks cuits ce tour (0 = rayon complet → plus rien à charger).
func stream_load(pcx, pcz, budget)
    var baked = 0
    for dz = -VIEW, VIEW do
        for dx = -VIEW, VIEW do
            if budget > 0 then
                var cx = pcx + dx
                var cz = pcz + dz
                var k = ckey(cx, cz)
                if loaded[k] == nil then
                    loaded[k] = bake_chunk(cx, cz)
                    budget = budget - 1
                    baked = baked + 1
                end
            end
        end
    end
    return baked
end

## Décharge (libère les VBO) les chunks hors du rayon → mémoire bornée.
func stream_unload(pcx, pcz)
    var keep = {}
    for k, c in loaded do
        if math.abs(c.cx - pcx) <= VIEW + 1 and math.abs(c.cz - pcz) <= VIEW + 1 then
            keep[k] = c
        else
            graphics.freeChunk(c)
        end
    end
    loaded = keep
end

func setup()
    graphics.canvas(W, H, "Voxel infini")
    graphics.ambient(0.5)
    graphics.light("dir", -0.5, -1, -0.35)
    math.noise_seed(7)
    build_atlas()                 ## génère l'atlas de textures (herbe/terre/roche/…)
    ## spawn : meilleure terre ferme (au-dessus de la mer), score = proximité de
    ## l'origine + forte pénalité d'altitude → on choisit TOUJOURS un point sec, bas
    ## et proche (pas de repli sous l'eau si aucune bande de hauteur précise n'existe).
    var best = 1000000000.0
    for z = 0, 60 do
        for x = 0, 60 do
            var h = height_at(x, z)
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
    ## regard vers la direction la plus dégagée
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
    ## cuisson initiale : chunk du joueur tout de suite (sol présent au spawn),
    ## le reste du rayon streamé sur les frames suivantes (budget/frame → pas de gel
    ## du thread au démarrage, d'autant que VIEW démarre à 4).
    lastcx = math.floor(camX / CS)
    lastcz = math.floor(camZ / CS)
    loaded[ckey(lastcx, lastcz)] = bake_chunk(lastcx, lastcz)
    streaming = true
end

## Boutons de distance (haut-droite) : renvoie +1 (bouton +), -1 (bouton −), 0 sinon.
func dist_btn_hit(x, y)
    if y < BTN_Y or y > BTN_Y + BTN then
        return 0
    end
    var xp = W - BTN - 12          ## bouton +
    var xm = xp - BTN - 10         ## bouton −
    if x >= xp and x <= xp + BTN then
        return 1
    end
    if x >= xm and x <= xm + BTN then
        return -1
    end
    return 0
end

## Dessine les deux boutons − / + et le mode courant.
func draw_dist_buttons()
    var xp = W - BTN - 12
    var xm = xp - BTN - 10
    graphics.noStroke()
    graphics.fill(Color(0, 0, 0, 0.38))
    graphics.rect(xm, BTN_Y, BTN, BTN)
    graphics.rect(xp, BTN_Y, BTN, BTN)
    graphics.draw_text("-", xm + BTN / 2 - 6, BTN_Y + BTN / 2 - 16, 30, colors.WHITE)
    graphics.draw_text("+", xp + BTN / 2 - 9, BTN_Y + BTN / 2 - 16, 30, colors.WHITE)
end

## relais d'entrée vers le joystick (les callbacks mouse.* sont globaux au moteur)
func mouse.pressed(x, y)
    ## un appui sur un bouton de distance = réglage manuel (l'auto-adapt se retire)
    var hit = dist_btn_hit(x, y)
    if hit <> 0 then
        manual = true
        if hit > 0 and VIEW < VIEW_MAX then
            VIEW = VIEW + 1
            streaming = true                   ## charge le nouvel anneau
        elseif hit < 0 and VIEW > VIEW_MIN then
            VIEW = VIEW - 1
            stream_unload(lastcx, lastcz)       ## libère l'anneau lointain aussitôt
        end
        return
    end
    pad.press(x, y)
end
func mouse.released(x, y)
    pad.release()
end
func mouse.moved(x, y)
    pad.move(x, y)
end

func draw()
    graphics.clear(C_SKY)
    ## déplacement analogique : virage dosé par steer(), vitesse par throttle()
    ## (nuls si le joystick n'est pas actif → aucun mouvement).
    yaw = yaw - pad.steer() * TURN_MAX * deltaTime
    var sp = pad.throttle() * SPEED_MAX * deltaTime
    if sp > 0 then
        ## avance avec glissement (franchit les pentes, bute sur les murs)
        var nx = camX + math.sin(yaw) * sp
        var nz = camZ + math.cos(yaw) * sp
        var g0 = ground(camX, camZ)
        if ground(nx, camZ) - g0 <= STEP then
            camX = nx
        end
        if ground(camX, nz) - g0 <= STEP then
            camZ = nz
        end
    end
    ## streaming : au changement de chunk on décharge le lointain et on (ré)active le
    ## chargement ; on ne balaie le voisinage QUE tant qu'il reste des chunks à cuire
    ## (budget/frame → pas d'à-coups). En régime stable : aucun balayage (pas de churn).
    var pcx = math.floor(camX / CS)
    var pcz = math.floor(camZ / CS)
    if pcx <> lastcx or pcz <> lastcz then
        lastcx = pcx
        lastcz = pcz
        stream_unload(pcx, pcz)
        streaming = true
    end
    ## budget de cuisson/frame : 6 en auto (charge vite les gros anneaux d'une montée
    ## exponentielle), plus large en manuel pour un retour immédiat au toucher.
    var budget = 6
    if manual then
        budget = 10
    end
    if streaming and stream_load(pcx, pcz, budget) == 0 then
        streaming = false
    end

    ## auto-adaptation de la distance (voir en-tête). On IGNORE les frames irréelles
    ## (> STALL_DT : arrière-plan/reprise) et on ne mesure pas pendant la cuisson,
    ## dont les à-coups fausseraient le compte.
    if deltaTime > 0 and deltaTime < STALL_DT then
        fps_ema = fps_ema * 0.9 + (1.0 / deltaTime) * 0.1     ## affichage uniquement
        if not streaming and not manual then
            adapt_t = adapt_t + deltaTime
            adapt_n = adapt_n + 1
            if deltaTime > SLOW_DT then
                adapt_slow = adapt_slow + 1
            end
            if adapt_t >= ADAPT_WIN then
                ## > 25% de frames lentes → DÉCROCHAGE : on recule d'un cran et on
                ## RETIENT ce rayon comme plafond (view_cap) → on n'y remonte plus.
                ## Fenêtre entièrement fluide → on sonde plus loin par paliers qui
                ## DOUBLENT (1,2,4,8…) → on atteint la vraie limite du device en
                ## quelques fenêtres au lieu de grimper 1 par 1. Aucun plafond de
                ## perf codé en dur : seule VIEW_MAX (garde-fou mémoire) borne.
                if adapt_slow * 4 > adapt_n and VIEW > VIEW_MIN then
                    view_cap = VIEW - 1                ## on décroche à VIEW → plafond appris
                    VIEW = VIEW - 1
                    stream_unload(pcx, pcz)            ## libère l'anneau lointain aussitôt
                    grow_step = 1                      ## on repart d'un petit pas
                elseif adapt_slow == 0 and VIEW < VIEW_MAX and VIEW < view_cap then
                    VIEW = VIEW + grow_step
                    if VIEW > VIEW_MAX then
                        VIEW = VIEW_MAX
                    end
                    if VIEW > view_cap then
                        VIEW = view_cap
                    end
                    grow_step = grow_step * 2          ## prochaine montée deux fois plus grande
                    streaming = true                   ## charge les nouveaux anneaux
                else
                    grow_step = 1                      ## fenêtre mitigée (bruit) → on coupe la lancée
                end
                adapt_t = 0.0
                adapt_n = 0
                adapt_slow = 0
            end
        end
    end

    ## rester au-dessus du sol : toujours EYE au-dessus de la colonne courante
    camY = ground(camX, camZ) + EYE
    var dx = math.cos(PITCH) * math.sin(yaw)
    var dy = math.sin(PITCH)
    var dz = math.cos(PITCH) * math.cos(yaw)
    cam.set_pos(camX, camY, camZ)
    cam.look_at(camX + dx, camY + dy, camZ + dz)

    graphics.noStroke()
    ## culling une seule fois : liste des chunks visibles (inFrustum est coûteux)
    var vis = []
    for k, c in loaded do
        if graphics.inFrustum(c.wx, SEA, c.wz, CS + 24) then
            vis[#vis + 1] = c
        end
    end
    graphics.begin3d(cam)
        ## passe 1 : opaque (terrain, arbres)
        for i = 1, #vis do
            graphics.drawChunk(vis[i])
        end
        ## passe 2 : eau transparente, APRÈS tout l'opaque
        for i = 1, #vis do
            graphics.drawChunkAlpha(vis[i])
        end
    graphics.end3d()

    pad.draw()                        ## HUD du joystick (classe réutilisable)
    draw_dist_buttons()               ## boutons − / + de distance (réglage manuel)
    var mode = "auto"
    if manual then
        mode = "manuel"
    end
    graphics.draw_text("fps " + math.floor(fps_ema + 0.5) + "   vue " + VIEW + " (" + mode + ")   chunks " + #vis, 12, 12, 15, colors.WHITE)
end
