## Univers VOXEL INFINI — chunks générés à la volée en se déplaçant.
##   • Le terrain vient d'un bruit de Perlin (défini partout) → monde illimité.
##   • On CUIT (beginChunk/endChunk) les chunks autour du joueur et on LIBÈRE
##     (freeChunk) les lointains → mémoire bornée, univers qui s'étend en marchant.
##   • On ne dessine que les chunks VISIBLES (inFrustum). BIOMES : désert/plaine/
##     forêt/montagne. COMMANDES : bas gauche/droite = tourner, haut = avancer.

global CS = 16             ## côté d'un chunk
global VIEW = 4            ## rayon de chunks chargés (9×9 autour du joueur)
global SEA = 9             ## niveau de la mer (marge sous la mer pour les océans)
global loaded = {}         ## "cx,cz" → { id, wx, wz, cx, cz }
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

## commande analogique (joystick ancré en bas-centre de la zone)
global touching = false
global tx = 0
global ty = 0
global TURN_MAX = 1.8      ## rad/s à l'inclinaison horizontale maximale
global SPEED_MAX = 8.0     ## blocs/s à la poussée verticale maximale
global DEAD = 0.06         ## zone morte du virage (près du centre = tout droit)

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

func biome_at(x, z)
    var b = math.noise(x * 0.026 + 50, z * 0.026 + 50)
    if b < 0.36 then return 0 end
    if b < 0.56 then return 1 end
    if b < 0.76 then return 2 end
    return 3
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
            for y = 0, h do
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
            var hash = (x * 131 + z * 197) % 100
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
func stream_load(pcx, pcz, budget)
    for dz = -VIEW, VIEW do
        for dx = -VIEW, VIEW do
            if budget > 0 then
                var cx = pcx + dx
                var cz = pcz + dz
                var k = ckey(cx, cz)
                if loaded[k] == nil then
                    loaded[k] = bake_chunk(cx, cz)
                    budget = budget - 1
                end
            end
        end
    end
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
    ## spawn sur la terre ferme basse la plus proche de l'origine (au-dessus de la mer)
    var bestd = 1000000
    for z = 0, 60 do
        for x = 0, 60 do
            var h = height_at(x, z)
            if h > SEA and h < SEA + 4 then
                var cx = x - 30
                var cz = z - 30
                var d = cx * cx + cz * cz
                if d < bestd then
                    bestd = d
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
    ## cuisson initiale COMPLÈTE du rayon (le monde est là dès le départ)
    lastcx = math.floor(camX / CS)
    lastcz = math.floor(camZ / CS)
    stream_load(lastcx, lastcz, 9999)
end

func turn_y()
    return H * 0.66           ## haut de la zone de commande
end
## virage ∈ [-1;1] : distance horizontale du doigt au MILIEU (zone morte au centre)
func steer()
    var s = (tx - W / 2) / (W / 2)
    if s > 0 - DEAD and s < DEAD then
        return 0.0
    end
    return math.clamp(s, -1.0, 1.0)
end
## poussée ∈ [0;1] : distance verticale du doigt AU-DESSUS du bas de la zone
func throttle()
    return math.clamp((H - ty) / (H - turn_y()), 0.0, 1.0)
end
func mouse.pressed(x, y)
    touching = true
    tx = x
    ty = y
end
func mouse.released(x, y)
    touching = false
end
func mouse.moved(x, y)
    tx = x
    ty = y
end

func draw_hud(shown)
    var y0 = turn_y()
    var ax = W / 2            ## ancre horizontale = centre (tout droit)
    ## fond de la zone de commande
    graphics.fill(Color(1, 1, 1, 0.06))
    graphics.rect(0, y0, W, H - y0)
    ## axe central (tout droit) + repère du niveau bas (vitesse nulle)
    graphics.fill(Color(1, 1, 1, 0.14))
    graphics.rect(ax - 1, y0, 2, H - y0)
    ## poignée du joystick : suit le doigt, dosage visible (distance = intensité)
    if touching and ty >= y0 then
        graphics.stroke(Color(1, 1, 1, 0.45))
        graphics.line(ax, H - 4, tx, ty)     ## ancre bas-centre → doigt
        graphics.noStroke()
        graphics.fill(Color(0.45, 0.65, 1.0, 0.85))
        graphics.circle(tx, ty, 20)
    end
    graphics.draw_text("<  tourner  >", ax - 52, H - 24, 16, colors.WHITE)
    graphics.draw_text("avancer (haut)", 16, y0 + 8, 16, colors.WHITE)
    graphics.draw_text("chunks affichés " + shown, 12, 12, 15, colors.WHITE)
end

func draw()
    graphics.clear(C_SKY)
    if touching and ty >= turn_y() then
        ## analogique : virage dosé par la distance au centre, vitesse par la
        ## distance au bas de la zone (steer < 0 = gauche → yaw augmente).
        yaw = yaw - steer() * TURN_MAX * deltaTime
        var sp = throttle() * SPEED_MAX * deltaTime
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
    end
    ## streaming : charge autour du joueur (budget/frame), décharge au changement de chunk
    var pcx = math.floor(camX / CS)
    var pcz = math.floor(camZ / CS)
    stream_load(pcx, pcz, 2)
    if pcx <> lastcx or pcz <> lastcz then
        lastcx = pcx
        lastcz = pcz
        stream_unload(pcx, pcz)
    end

    ## rester au-dessus du sol : toujours EYE au-dessus de la colonne courante
    camY = ground(camX, camZ) + EYE
    var dx = math.cos(PITCH) * math.sin(yaw)
    var dy = math.sin(PITCH)
    var dz = math.cos(PITCH) * math.cos(yaw)
    cam.set_pos(camX, camY, camZ)
    cam.look_at(camX + dx, camY + dy, camZ + dz)

    graphics.noStroke()
    var shown = 0
    graphics.begin3d(cam)
        ## passe 1 : opaque (terrain, arbres)
        for k, c in loaded do
            if graphics.inFrustum(c.wx, SEA, c.wz, CS + 24) then
                shown = shown + 1
                graphics.drawChunk(c)
            end
        end
        ## passe 2 : eau transparente, APRÈS tout l'opaque
        for k, c in loaded do
            if graphics.inFrustum(c.wx, SEA, c.wz, CS + 24) then
                graphics.drawChunkAlpha(c)
            end
        end
    graphics.end3d()

    draw_hud(shown)
end
