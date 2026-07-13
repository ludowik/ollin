## Univers VOXEL — grand monde en CHUNKS (géométrie retenue) + BIOMES + exploration.
##   • Chaque chunk est CUIT une fois (beginChunk/endChunk) → on ne ré-émet pas les
##     cubes chaque frame ; on ne dessine que les chunks visibles (inFrustum).
##   • BIOMES : un bruit basse fréquence choisit désert / plaine / forêt / montagne,
##     chacun avec ses couleurs, son relief et ses arbres.
##   • COMMANDES (3) : boutons à l'écran — ◄ tourner à gauche, ▲ avancer, ► tourner à droite.

global CS = 16              ## côté d'un chunk (colonnes) — chunks plus gros
global NC = 6               ## chunks par côté → monde de 96×96 colonnes
global WORLD = CS * NC
global SEA = 3
global heights = []
global biomes = []
global chunks = []
global cam = graphics.camera(0, 0, 10,  0, 0, 0)

## caméra (à hauteur d'homme : les yeux suivent le sol, regard quasi horizontal)
global EYE = 2.2           ## hauteur des yeux au-dessus du sol
global camX = WORLD / 2
global camY = 10
global camZ = WORLD / 2
global yaw = 0.0
global PITCH = -0.12       ## regard presque horizontal, un peu au loin
global held = -1            ## bouton maintenu : 0 gauche, 1 avancer, 2 droite, -1 aucun

## palette
global C_SKY   = Color(0.55, 0.80, 0.95)
global C_SAND  = Color(0.86, 0.79, 0.53)
global C_SANDD = Color(0.72, 0.63, 0.40)
global C_GRASS = Color(0.45, 0.70, 0.30)
global C_FOREST= Color(0.24, 0.52, 0.22)
global C_ROCK  = Color(0.47, 0.46, 0.45)
global C_SNOW  = Color(0.97, 0.98, 1.0)
global C_DIRT  = Color(0.46, 0.33, 0.20)
global C_STONE = Color(0.36, 0.36, 0.40)
global C_WATER = Color(0.20, 0.45, 0.80)
global C_TRUNK = Color(0.40, 0.26, 0.13)
global C_LEAF  = Color(0.18, 0.42, 0.16)

## Biome (0 désert, 1 plaine, 2 forêt, 3 montagne) via un bruit BASSE fréquence.
func biome_at(x, z)
    var b = math.noise(x * 0.026 + 50, z * 0.026 + 50)
    if b < 0.36 then return 0 end
    if b < 0.56 then return 1 end
    if b < 0.76 then return 2 end
    return 3
end

## Hauteur selon le biome (montagne accentuée par base²).
func height_at(x, z, b)
    var n = math.noise(x * 0.05, z * 0.05) * 0.6
          + math.noise(x * 0.12, z * 0.12) * 0.3
          + math.noise(x * 0.25, z * 0.25) * 0.1
    if b == 0 then return math.floor(n * 4 + 1) end
    if b == 1 then return math.floor(n * 6 + 1) end
    if b == 2 then return math.floor(n * 8 + 2) end
    return math.floor(n * n * 26 + 3)
end

## Hauteur du sol à (x, z) (au moins le niveau de la mer) — pour poser les yeux.
func ground(x, z)
    var ix = math.clamp(math.floor(x), 0, WORLD - 1)
    var iz = math.clamp(math.floor(z), 0, WORLD - 1)
    return math.max(heights[iz * WORLD + ix + 1], SEA)
end

func block_color(b, h, y)
    if y >= h then
        if b == 0 then return C_SAND end
        if b == 3 then
            if h >= 13 then return C_SNOW end
            if h >= 8 then return C_ROCK end
            return C_GRASS
        end
        if b == 2 then return C_FOREST end
        return C_GRASS
    end
    if y >= h - 2 then
        if b == 0 then return C_SANDD end
        return C_DIRT
    end
    return C_STONE
end

func bake_chunk(cx, cz)
    graphics.beginChunk()
    var x0 = cx * CS
    var z0 = cz * CS
    for z = z0, z0 + CS - 1 do
        for x = x0, x0 + CS - 1 do
            var i = z * WORLD + x + 1
            var h = heights[i]
            var b = biomes[i]
            for y = 0, h do
                graphics.fill(block_color(b, h, y))
                graphics.cube(x, y, z,  1, 1, 1)
            end
            if h < SEA then
                graphics.fill(C_WATER)
                graphics.cube(x, SEA, z,  1, 1, 1)
            end
            ## arbres : denses en forêt, rares en plaine, aucun ailleurs
            var hash = (x * 131 + z * 197) % 100
            var tree = (b == 2 and hash < 5) or (b == 1 and hash == 0)
            if tree and h > SEA then
                graphics.fill(C_TRUNK)
                for k = 1, 4 do
                    graphics.cube(x, h + k, z,  1, 1, 1)
                end
                graphics.fill(C_LEAF)
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
    chunks[#chunks + 1] = g
end

func setup()
    graphics.canvas(W, H, "Voxel — explorer")
    graphics.ambient(0.5)
    graphics.light("dir", -0.5, -1, -0.35)
    math.noise_seed(7)
    for z = 0, WORLD - 1 do
        for x = 0, WORLD - 1 do
            var b = biome_at(x, z)
            biomes[#biomes + 1] = b
            heights[#heights + 1] = height_at(x, z, b)
        end
    end
    for cz = 0, NC - 1 do
        for cx = 0, NC - 1 do
            bake_chunk(cx, cz)
        end
    end
    ## spawn DÉGAGÉ, le plus proche du centre : un endroit BAS et sec, sans forêt ni
    ## montagne ni arbre dans le voisinage 3×3 → vue à hauteur d'homme, horizon libre.
    var bestd = 1000000
    for z = 1, WORLD - 2 do
        for x = 1, WORLD - 2 do
            var i = z * WORLD + x + 1
            if biomes[i] <= 1 and heights[i] > SEA and heights[i] < 6 then
                var open = true
                for dz = -1, 1 do
                    for dx = -1, 1 do
                        var nx = x + dx
                        var nz = z + dz
                        var nb = biomes[nz * WORLD + nx + 1]
                        if nb == 2 or nb == 3 then open = false end       ## pas de forêt/montagne
                        if nb == 1 and (nx * 131 + nz * 197) % 100 == 0 then open = false end  ## pas d'arbre
                    end
                end
                if open then
                    var cx = x - WORLD / 2
                    var cz = z - WORLD / 2
                    var d = cx * cx + cz * cz
                    if d < bestd then
                        bestd = d
                        camX = x + 0.5
                        camZ = z + 0.5
                    end
                end
            end
        end
    end
    ## orienter le regard vers la direction la plus DÉGAGÉE (terrain le plus bas)
    ## → on regarde au loin sur le paysage plutôt que dans un mur d'arbres.
    var bestSum = 1000000.0
    for a = 0, 15 do
        var ang = a / 16.0 * 6.28319
        var sx = math.sin(ang)
        var sz = math.cos(ang)
        var sum = 0.0
        for k = 3, 18, 3 do
            sum = sum + ground(camX + sx * k, camZ + sz * k)
        end
        if sum < bestSum then
            bestSum = sum
            yaw = ang
        end
    end
end

## ── Contrôle par ZONES (pas de bouton) ──────────────────────────────────────
## Bande du BAS : toucher à gauche → tourner à gauche, à droite → tourner à droite.
## AU-DESSUS de cette bande : avancer. Appui maintenu = action continue.
global touching = false
global tx = 0
global ty = 0

func turn_y()
    return H * 0.66        ## sous cette hauteur = « tourner » ; au-dessus = « avancer »
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

## Repères discrets des zones (sans bouton) + surbrillance de la zone active.
func draw_hud(shown)
    var y0 = turn_y()
    var bh = H - y0
    graphics.fill(Color(1, 1, 1, 0.08))
    graphics.rect(0, y0, W, bh)                          ## bande « tourner »
    if touching then
        graphics.fill(Color(0.5, 0.6, 1.0, 0.25))       ## zone active en surbrillance
        if ty >= y0 then
            if tx < W / 2 then
                graphics.rect(0, y0, W / 2, bh)
            else
                graphics.rect(W / 2, y0, W / 2, bh)
            end
        else
            graphics.rect(0, 0, W, y0)
        end
    end
    graphics.fill(Color(1, 1, 1, 0.22))
    graphics.rect(W / 2 - 1, y0, 2, bh)                  ## séparateur gauche/droite
    graphics.draw_text("GAUCHE", 22, y0 + bh / 2 - 9, 18, colors.WHITE)
    graphics.draw_text("DROITE", W - 92, y0 + bh / 2 - 9, 18, colors.WHITE)
    graphics.draw_text("toucher le haut : avancer   ·   chunks " + shown + "/" + (NC * NC), 12, 12, 15, colors.WHITE)
end

func draw()
    graphics.clear(C_SKY)
    if touching then
        var turn = 1.6 * deltaTime
        var sp = 15 * deltaTime
        if ty >= turn_y() then                 ## bande du bas → tourner
            if tx < W / 2 then
                yaw = yaw - turn
            else
                yaw = yaw + turn
            end
        else                                    ## au-dessus → avancer
            camX = camX + math.sin(yaw) * sp
            camZ = camZ + math.cos(yaw) * sp
        end
    end
    camY = ground(camX, camZ) + EYE            ## les yeux suivent le relief
    var dx = math.cos(PITCH) * math.sin(yaw)
    var dy = math.sin(PITCH)
    var dz = math.cos(PITCH) * math.cos(yaw)
    cam.set_pos(camX, camY, camZ)
    cam.look_at(camX + dx, camY + dy, camZ + dz)

    graphics.noStroke()
    var shown = 0
    graphics.begin3d(cam)
        for c in chunks do
            if graphics.inFrustum(c.wx, 10, c.wz, CS + 6) then
                shown = shown + 1
                graphics.drawChunk(c)
            end
        end
    graphics.end3d()

    draw_hud(shown)
end
