## Univers VOXEL INFINI — chunks générés à la volée en se déplaçant.
##   • Le terrain vient d'un bruit de Perlin (défini partout) → monde illimité.
##   • On CUIT (beginChunk/endChunk) les chunks autour du joueur et on LIBÈRE
##     (freeChunk) les lointains → mémoire bornée, univers qui s'étend en marchant.
##   • On ne dessine que les chunks VISIBLES (inFrustum). BIOMES : désert/plaine/
##     forêt/montagne. COMMANDES : bas gauche/droite = tourner, haut = avancer.

global CS = 16             ## côté d'un chunk
global VIEW = 4            ## rayon de chunks chargés (9×9 autour du joueur)
global SEA = 3
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

## commande par zones
global touching = false
global tx = 0
global ty = 0

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

func biome_at(x, z)
    var b = math.noise(x * 0.026 + 50, z * 0.026 + 50)
    if b < 0.36 then return 0 end
    if b < 0.56 then return 1 end
    if b < 0.76 then return 2 end
    return 3
end

func height_at(x, z, b)
    var n = math.noise(x * 0.05, z * 0.05) * 0.6
          + math.noise(x * 0.12, z * 0.12) * 0.3
          + math.noise(x * 0.25, z * 0.25) * 0.1
    if b == 0 then return math.floor(n * 4 + 1) end
    if b == 1 then return math.floor(n * 6 + 1) end
    if b == 2 then return math.floor(n * 8 + 2) end
    return math.floor(n * n * 26 + 3)
end

func ground(x, z)
    var ix = math.floor(x)
    var iz = math.floor(z)
    var b = biome_at(ix, iz)
    return math.max(height_at(ix, iz, b), SEA)
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

func ckey(cx, cz)
    return cx + "," + cz
end

## Génère + cuit le chunk (cx,cz) depuis le bruit → handle persistant.
func bake_chunk(cx, cz)
    graphics.beginChunk()
    var x0 = cx * CS
    var z0 = cz * CS
    for z = z0, z0 + CS - 1 do
        for x = x0, x0 + CS - 1 do
            var b = biome_at(x, z)
            var h = height_at(x, z, b)
            for y = 0, h do
                graphics.fill(block_color(b, h, y))
                graphics.cube(x, y, z,  1, 1, 1)
            end
            if h < SEA then
                graphics.fill(C_WATER)
                graphics.cube(x, SEA, z,  1, 1, 1)
            end
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
    ## spawn dégagé près de l'origine (bas, sec, sans forêt/montagne autour)
    var bestd = 1000000
    for z = 0, 48 do
        for x = 0, 48 do
            var b = biome_at(x, z)
            if b <= 1 and height_at(x, z, b) > SEA and height_at(x, z, b) < 6 then
                var open = biome_at(x + 1, z) <= 1 and biome_at(x - 1, z) <= 1
                          and biome_at(x, z + 1) <= 1 and biome_at(x, z - 1) <= 1
                if open then
                    var cx = x - 24
                    var cz = z - 24
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
    return H * 0.66
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
    var bh = H - y0
    graphics.fill(Color(1, 1, 1, 0.08))
    graphics.rect(0, y0, W, bh)
    if touching then
        graphics.fill(Color(0.5, 0.6, 1.0, 0.25))
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
    graphics.rect(W / 2 - 1, y0, 2, bh)
    graphics.draw_text("GAUCHE", 22, y0 + bh / 2 - 9, 18, colors.WHITE)
    graphics.draw_text("DROITE", W - 92, y0 + bh / 2 - 9, 18, colors.WHITE)
    graphics.draw_text("haut : avancer   ·   chunks affichés " + shown, 12, 12, 15, colors.WHITE)
end

func draw()
    graphics.clear(C_SKY)
    if touching then
        var turn = 0.8 * deltaTime       ## rotation plus lente
        var sp = 5 * deltaTime           ## avance plus lente
        if ty >= turn_y() then
            if tx < W / 2 then
                yaw = yaw + turn       ## gauche = tourner à gauche
            else
                yaw = yaw - turn       ## droite = tourner à droite
            end
        else
            ## avance avec glissement : franchit les pentes douces, bute sur les murs
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

    camY = ground(camX, camZ) + EYE
    var dx = math.cos(PITCH) * math.sin(yaw)
    var dy = math.sin(PITCH)
    var dz = math.cos(PITCH) * math.cos(yaw)
    cam.set_pos(camX, camY, camZ)
    cam.look_at(camX + dx, camY + dy, camZ + dz)

    graphics.noStroke()
    var shown = 0
    graphics.begin3d(cam)
        for k, c in loaded do
            if graphics.inFrustum(c.wx, 10, c.wz, CS + 6) then
                shown = shown + 1
                graphics.drawChunk(c)
            end
        end
    graphics.end3d()

    draw_hud(shown)
end
