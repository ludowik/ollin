## Univers VOXEL — grand monde en CHUNKS, géométrie RETENUE + exploration.
##   • Chaque chunk est CUIT une seule fois (graphics.beginChunk/endChunk) dans des
##     buffers GPU persistants → on ne ré-émet PAS les cubes à chaque frame.
##   • Chaque frame : pour chaque chunk visible (graphics.inFrustum) → graphics.drawChunk
##     = UN appel de dessin. La boucle Ollin ne parcourt que les ~chunks, pas les cubes.
##   • Déplacement : GLISSE à gauche = regarder, à droite = avancer (souris ou doigt).

global CS = 8               ## côté d'un chunk (colonnes)
global NC = 12              ## chunks par côté → monde de 96×96 colonnes
global WORLD = CS * NC
global SEA = 3
global heights = []         ## hauteur de chaque colonne
global chunks = []          ## groupes cuits { id, count, wx, wz }
global cam = graphics.camera(0, 0, 10,  0, 0, 0)

## caméra libre (position + cap/inclinaison)
global camX = WORLD / 2
global camY = 17
global camZ = -8
global yaw = 0.0
global pitch = -0.35
global pressing = false
global moveMode = false
global lastx = 0
global lasty = 0

## palette (créée une fois)
global C_SKY   = Color(0.55, 0.80, 0.95)
global C_SAND  = Color(0.85, 0.78, 0.52)
global C_GRASS = Color(0.42, 0.68, 0.28)
global C_FOREST= Color(0.24, 0.50, 0.22)
global C_ROCK  = Color(0.48, 0.47, 0.46)
global C_SNOW  = Color(0.96, 0.97, 0.99)
global C_DIRT  = Color(0.46, 0.33, 0.20)
global C_STONE = Color(0.38, 0.38, 0.42)
global C_WATER = Color(0.20, 0.45, 0.80)
global C_TRUNK = Color(0.40, 0.26, 0.13)
global C_LEAF  = Color(0.18, 0.42, 0.16)

func height_at(x, z)
    var n = math.noise(x * 0.06, z * 0.06) * 0.6
          + math.noise(x * 0.13, z * 0.13) * 0.3
          + math.noise(x * 0.28, z * 0.28) * 0.1
    return math.floor(n * 11)
end

func block_color(h, y)
    if y >= h then
        if h <= SEA then return C_SAND end
        if h <= SEA + 3 then return C_GRASS end
        if h <= 7 then return C_FOREST end
        if h <= 9 then return C_ROCK end
        return C_SNOW
    end
    if y >= h - 2 then return C_DIRT end
    return C_STONE
end

## Cuit un chunk (toutes ses colonnes) → un groupe d'instances persistant.
func bake_chunk(cx, cz)
    graphics.beginChunk()
    var x0 = cx * CS
    var z0 = cz * CS
    for z = z0, z0 + CS - 1 do
        for x = x0, x0 + CS - 1 do
            var h = heights[z * WORLD + x + 1]
            for y = 0, h do                       ## colonne pleine (pas de trous)
                graphics.fill(block_color(h, y))
                graphics.cube(x, y, z,  1, 1, 1)
            end
            if h < SEA then                        ## eau dans les creux
                graphics.fill(C_WATER)
                graphics.cube(x, SEA, z,  1, 1, 1)
            end
            if h > SEA and h <= SEA + 3 and (x * 131 + z * 197) % 223 == 0 then
                graphics.fill(C_TRUNK)             ## arbre CLAIRSEMÉ
                for k = 1, 4 do
                    graphics.cube(x, h + k, z,  1, 1, 1)
                end
                graphics.fill(C_LEAF)              ## houppier : 2 couches 3×3 + sommet
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
            heights[#heights + 1] = height_at(x, z)
        end
    end
    for cz = 0, NC - 1 do
        for cx = 0, NC - 1 do
            bake_chunk(cx, cz)     ## cuisson unique (setup)
        end
    end
end

## Souris ET tactile : gauche = regarder, droite = avancer.
func mouse.pressed(x, y)
    pressing = true
    moveMode = x > W / 2
    lastx = x
    lasty = y
end

func mouse.released(x, y)
    pressing = false
end

func mouse.moved(x, y)
    if not pressing then
        return
    end
    yaw = yaw + (x - lastx) * 0.005
    pitch = math.clamp(pitch - (y - lasty) * 0.005, -1.3, 1.3)
    lastx = x
    lasty = y
end

func draw()
    graphics.clear(C_SKY)
    if pressing and moveMode then                 ## avancer (cap horizontal)
        var sp = 16 * deltaTime
        camX = camX + math.sin(yaw) * sp
        camZ = camZ + math.cos(yaw) * sp
    end
    var dx = math.cos(pitch) * math.sin(yaw)       ## direction de visée
    var dy = math.sin(pitch)
    var dz = math.cos(pitch) * math.cos(yaw)
    cam.set_pos(camX, camY, camZ)
    cam.look_at(camX + dx, camY + dy, camZ + dz)

    graphics.noStroke()
    var shown = 0
    graphics.begin3d(cam)
        for c in chunks do
            if graphics.inFrustum(c.wx, 5, c.wz, CS) then   ## ne dessiner que le visible
                shown = shown + 1
                graphics.drawChunk(c)                        ## 1 appel = tout le chunk
            end
        end
    graphics.end3d()

    graphics.draw_text("Glisse : gauche = regarder · droite = avancer", 12, 12, 16, colors.WHITE)
    graphics.draw_text("chunks dessinés : " + shown + " / " + (NC * NC), 12, 34, 16, colors.WHITE)
end
