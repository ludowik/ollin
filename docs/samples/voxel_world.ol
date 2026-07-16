## Univers voxel infini — chunks générés à la volée par bruit de Perlin, cuits
## autour du joueur (beginChunk/endChunk) et libérés au loin (freeChunk). Distance
## de vue auto-adaptative (voir adapt_view). Déplacement : joystick tactile.

import "joystick.ol"

global CS = 16
global VIEW = 4
global VIEW_MIN = 1
global VIEW_MAX = 24        ## filet de sécurité ; la vraie limite vient du FPS ou de la mémoire

## Auto-adaptation : en vsync verrouillé, deltaTime ne révèle la marge que quand des
## frames débordent. On mesure la PART de frames lentes sur une fenêtre. Les frames
## irréelles (> STALL_DT, arrière-plan/reprise) sont ignorées.
global SLOW_DT  = 0.021
global STALL_DT = 0.30
global ADAPT_WIN = 0.5
global adapt_t  = 0.0
global adapt_n  = 0
global adapt_slow = 0
global grow_step = 1        ## montée qui double à chaque fenêtre fluide (1,2,4,8…)
global view_cap = 999       ## plafond appris au décrochage ; relâché après RELAX_T stable
global view_good = 4        ## dernier rayon confirmé fluide (repli d'un dépassement)
global stable_t = 0.0
global GROW_SLOW = 0.10
global DROP_SLOW = 0.25
global RELAX_T  = 8.0
global MEM_MAX  = 110000000

global manual = false       ## true dès qu'on touche un bouton − / + (auto-adapt en retrait)
global BTN = 54
global BTN_Y = 40
global SEA = 9
global loaded = {}          ## "cx,cz" → handle endChunk
global cam = graphics.camera(0, 0, 10,  0, 0, 0)

global EYE = 2.2
global STEP = 1.2           ## marche franchissable ; au-delà = mur
global camX = 8.5
global camY = 10
global camZ = 8.5
global yaw = 0.0
global PITCH = -0.12
global lastcx = 999999
global lastcz = 999999
global streaming = false

global pad = Joystick()
global TURN_MAX = 1.8
global SPEED_MAX = 8.0

global C_SKY = Color(0.55, 0.80, 0.95)
global WHITE = Color(1, 1, 1)

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
func put_tile(idx, br, bg, bb, jit)
    var cx = (idx % ACOLS) * TILE
    var cy = math.floor(idx / ACOLS) * TILE
    for py = 0, TILE - 1 do
        for px = 0, TILE - 1 do
            var wx = (cx + px) * 1.7
            var wy = (cy + py) * 1.7
            var nr = (math.noise(wx + 9,  wy + 9)   - 0.5) * 2 * jit
            var ng = (math.noise(wx + 41, wy + 67)  - 0.5) * 2 * jit
            var nb = (math.noise(wx + 113, wy + 151) - 0.5) * 2 * jit
            image.setPixel(atlas, cx + px, cy + py,
                math.clamp(br + nr, 0, 1), math.clamp(bg + ng, 0, 1), math.clamp(bb + nb, 0, 1), 1)
        end
    end
end

func build_atlas()
    atlas = image.create(ACOLS * TILE, AROWS * TILE)
    image.beginPixels(atlas)
    put_tile(T_GRASS, 0.42, 0.68, 0.30, 0.16)
    put_tile(T_DIRT,  0.46, 0.33, 0.20, 0.15)
    put_tile(T_SAND,  0.86, 0.79, 0.53, 0.11)
    put_tile(T_ROCK,  0.47, 0.46, 0.45, 0.18)
    put_tile(T_SNOW,  0.95, 0.97, 1.00, 0.07)
    put_tile(T_WATER, 0.20, 0.45, 0.80, 0.14)
    put_tile(T_TRUNK, 0.40, 0.26, 0.13, 0.16)
    put_tile(T_LEAF,  0.18, 0.42, 0.16, 0.22)
    put_tile(T_STONE, 0.36, 0.36, 0.40, 0.16)
    put_tile(T_SANDD, 0.72, 0.63, 0.40, 0.12)
    image.endPixels(atlas)
    graphics.tileset(atlas, ACOLS, AROWS)
    graphics.tileAnim(T_WATER)
end

## Biome de surface : 0 = désert, 1 = plaine, 2 = forêt. Le relief (roche/neige) vient
## de l'altitude, pas du biome.
func biome_at(x, z)
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

func height_at(x, z)
    return math.floor((elevation(x, z) - 0.42) * 60 + SEA)
end

func ground(x, z)
    return math.max(height_at(math.floor(x), math.floor(z)), SEA)
end

## Tuiles (dessus/côté/dessous) selon l'altitude : plage → herbe → roche → neige ;
## le biome ne distingue que le désert.
func set_block_tiles(b, h, y)
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

func bake_chunk(cx, cz)
    graphics.beginChunk()
    graphics.fill(WHITE)          ## teinte neutre : l'atlas fournit la couleur
    var x0 = cx * CS
    var z0 = cz * CS
    for z = z0, z0 + CS - 1 do
        for x = x0, x0 + CS - 1 do
            var b = biome_at(x, z)
            var h = height_at(x, z)
            for y = 0, math.max(h, 0) do   ## au moins un fond (y=0) même si h<0
                set_block_tiles(b, h, y)
                graphics.cube(x, y, z,  1, 1, 1)
            end
            if h < SEA then
                ## eau = UN plan semi-transparent au niveau de la mer (surface continue,
                ## pas une pile de cubes → on voit le fond, sans faces internes).
                graphics.tile(T_WATER)
                graphics.fill(Color(1, 1, 1, 0.72))
                graphics.plane(x, SEA + 0.45, z,  1, 1)
                graphics.fill(WHITE)
            end
            var hash = math.abs(x * 131 + z * 197) % 100    ## abs : % signé sinon ~53%
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

## Cuit les chunks manquants du rayon, `budget` par frame, en priorisant ce qui est
## devant la caméra puis le plus proche (buffer trié borné). Renvoie le nombre cuit.
func stream_load(pcx, pcz, budget)
    if budget < 1 then
        return 0
    end
    var bcx = []
    var bcz = []
    var bsc = []
    var cnt = 0
    var fdx = math.sin(yaw)
    var fdz = math.cos(yaw)
    for dz = -VIEW, VIEW do
        for dx = -VIEW, VIEW do
            var cx = pcx + dx
            var cz = pcz + dz
            if loaded[ckey(cx, cz)] == nil then
                var score = dx * dx + dz * dz
                if dx * fdx + dz * fdz < 0 then
                    score = score + 100000             ## derrière la caméra → après
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
    var baked = 0
    for i = 1, cnt do
        loaded[ckey(bcx[i], bcz[i])] = bake_chunk(bcx[i], bcz[i])
        baked = baked + 1
    end
    return baked
end

## Libère les chunks hors rayon. margin = hystérésis : 1 en déplacement (anneau tampon,
## pas de churn en reculant d'un pas), 0 en réduction (libère aussitôt).
func stream_unload(pcx, pcz, margin)
    var keep = {}
    for k, c in loaded do
        if math.abs(c.cx - pcx) <= VIEW + margin and math.abs(c.cz - pcz) <= VIEW + margin then
            keep[k] = c
        else
            graphics.freeChunk(c)
        end
    end
    loaded = keep
end

## Ajuste VIEW selon la part de frames lentes sur la fenêtre écoulée. Décrochage
## (mémoire pleine ou > DROP_SLOW) → repli dichotomique vers view_good + plafond appris.
## Fluide (< GROW_SLOW) → montée qui double ; au plafond, relâche view_cap après RELAX_T.
## Entre les deux → on tient. Ne mesure ni pendant la cuisson ni en manuel.
func adapt_view(pcx, pcz)
    if deltaTime <= 0 or deltaTime >= STALL_DT then
        return
    end
    if streaming or manual then
        return
    end
    adapt_t = adapt_t + deltaTime
    adapt_n = adapt_n + 1
    if deltaTime > SLOW_DT then
        adapt_slow = adapt_slow + 1
    end
    if adapt_t < ADAPT_WIN then
        return
    end
    var mem_full = mem() > MEM_MAX
    if (mem_full or adapt_slow > adapt_n * DROP_SLOW) and VIEW > VIEW_MIN then
        view_cap = VIEW - 1
        var back = (view_good + VIEW) // 2
        if back > VIEW - 1 then back = VIEW - 1 end
        if back < VIEW_MIN then back = VIEW_MIN end
        VIEW = back
        stream_unload(pcx, pcz, 0)
        grow_step = 1
        stable_t = 0.0
    elseif adapt_slow < adapt_n * GROW_SLOW then
        view_good = VIEW
        if VIEW < VIEW_MAX and VIEW < view_cap and not mem_full then
            VIEW = math.min(VIEW + grow_step, math.min(VIEW_MAX, view_cap))
            grow_step = grow_step * 2
            streaming = true
            stable_t = 0.0
        else
            grow_step = 1
            stable_t = stable_t + adapt_t
            if VIEW == view_cap and stable_t >= RELAX_T and not mem_full then
                view_cap = view_cap + 1
                stable_t = 0.0
            end
        end
    else
        grow_step = 1
        stable_t = 0.0
    end
    adapt_t = 0.0
    adapt_n = 0
    adapt_slow = 0
end

func setup()
    graphics.canvas(W, H, "Voxel infini")
    graphics.ambient(0.5)
    graphics.light("dir", -0.5, -1, -0.35)
    math.noiseSeed(7)
    build_atlas()
    ## spawn : terre ferme, basse et proche de l'origine (pénalité forte sur l'altitude
    ## → jamais sous l'eau).
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
    lastcx = math.floor(camX / CS)
    lastcz = math.floor(camZ / CS)
    loaded[ckey(lastcx, lastcz)] = bake_chunk(lastcx, lastcz)   ## sol présent dès le spawn
    streaming = true
end

## Boutons de distance (haut-droite) : +1 (bouton +), -1 (bouton −), 0 sinon.
func dist_btn_hit(x, y)
    if y < BTN_Y or y > BTN_Y + BTN then
        return 0
    end
    var xp = W - BTN - 12
    var xm = xp - BTN - 10
    if x >= xp and x <= xp + BTN then return 1 end
    if x >= xm and x <= xm + BTN then return -1 end
    return 0
end

func draw_dist_buttons()
    var xp = W - BTN - 12
    var xm = xp - BTN - 10
    graphics.noStroke()
    graphics.fill(Color(0, 0, 0, 0.38))
    graphics.rect(xm, BTN_Y, BTN, BTN)
    graphics.rect(xp, BTN_Y, BTN, BTN)
    graphics.drawText("-", xm + BTN / 2 - 6, BTN_Y + BTN / 2 - 16, 30, colors.WHITE)
    graphics.drawText("+", xp + BTN / 2 - 9, BTN_Y + BTN / 2 - 16, 30, colors.WHITE)
end

func mouse.pressed(x, y)
    var hit = dist_btn_hit(x, y)
    if hit <> 0 then
        manual = true
        if hit > 0 and VIEW < VIEW_MAX then
            VIEW = VIEW + 1
            streaming = true
        elseif hit < 0 and VIEW > VIEW_MIN then
            VIEW = VIEW - 1
            stream_unload(lastcx, lastcz, 0)
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

## Avance le joueur (virage + vitesse du joystick), avec glissement sur les pentes
## franchissables et blocage sur les murs.
func move_player()
    yaw = yaw - pad.steer() * TURN_MAX * deltaTime
    var sp = pad.throttle() * SPEED_MAX * deltaTime
    if sp <= 0 then
        return
    end
    var nx = camX + math.sin(yaw) * sp
    var nz = camZ + math.cos(yaw) * sp
    var g0 = ground(camX, camZ)
    if ground(nx, camZ) - g0 <= STEP then camX = nx end
    if ground(camX, nz) - g0 <= STEP then camZ = nz end
end

func draw()
    graphics.clear(C_SKY)
    move_player()

    var pcx = math.floor(camX / CS)
    var pcz = math.floor(camZ / CS)
    if pcx <> lastcx or pcz <> lastcz then
        lastcx = pcx
        lastcz = pcz
        stream_unload(pcx, pcz, 1)
        streaming = true
    end
    var budget = 6
    if manual then budget = 10 end
    if streaming and stream_load(pcx, pcz, budget) == 0 then
        streaming = false
    end
    adapt_view(pcx, pcz)

    camY = ground(camX, camZ) + EYE
    cam.setPos(camX, camY, camZ)
    cam.lookAt(camX + math.cos(PITCH) * math.sin(yaw),
               camY + math.sin(PITCH),
               camZ + math.cos(PITCH) * math.cos(yaw))

    graphics.noStroke()
    var vis = []
    for k, c in loaded do
        if graphics.inFrustum(c.wx, SEA, c.wz, CS + 24) then
            vis[#vis + 1] = c
        end
    end
    graphics.begin3d(cam)
        for i = 1, #vis do
            graphics.drawChunk(vis[i])
        end
        for i = 1, #vis do          ## eau transparente après tout l'opaque
            graphics.drawChunkAlpha(vis[i])
        end
    graphics.end3d()

    pad.draw()
    draw_dist_buttons()
    var mode = "auto"
    if manual then mode = "manuel" end
    graphics.drawText("vue " + VIEW + " (" + mode + ")   chunks " + #vis, 12, 12, 15, colors.WHITE)
end
