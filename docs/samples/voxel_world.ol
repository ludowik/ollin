## Univers VOXEL façon Minecraft — terrain de cubes généré par bruit de Perlin.
## Tous les cubes (des milliers) sont dessinés en TRÈS peu d'appels grâce à
## l'instancing : même mesh + couleur PAR INSTANCE → 1 seul draw call pour tout.
## Terrain solide + eau + arbres, caméra en orbite auto-cadrée.

global N = 22            ## grille N×N colonnes
global SEA = 2           ## niveau de la mer
global heights = []      ## hauteur de chaque colonne (précalculée dans setup)
global trees = []        ## positions [x, z] des arbres
global cam = graphics.camera(0, 0, 10,  0, 0, 0)

## Palette créée UNE fois (pas d'allocation de couleur par cube).
global C_SKY   = Color(0.53, 0.78, 0.92)
global C_GRASS = Color(0.36, 0.62, 0.24)
global C_DIRT  = Color(0.46, 0.33, 0.20)
global C_STONE = Color(0.50, 0.50, 0.52)
global C_SAND  = Color(0.83, 0.76, 0.48)
global C_SNOW  = Color(0.95, 0.96, 0.98)
global C_WATER = Color(0.20, 0.45, 0.80)
global C_TRUNK = Color(0.40, 0.26, 0.13)
global C_LEAF  = Color(0.20, 0.50, 0.18)

## Hauteur entière d'une colonne : bruit fBm (2 octaves) → 0..8.
func height_at(x, z)
    var n = math.noise(x * 0.12, z * 0.12) * 0.7 + math.noise(x * 0.25, z * 0.25) * 0.3
    return math.floor(n * 8)
end

func setup()
    graphics.canvas(W, H, "Voxel world")
    graphics.ambient(0.45)
    graphics.light("dir", -0.6, -1, -0.4)     ## « soleil »
    math.noise_seed(12)
    for z = 0, N - 1 do
        for x = 0, N - 1 do
            heights[#heights + 1] = height_at(x, z)
        end
    end
    ## quelques arbres sur des colonnes hautes (au-dessus de la mer)
    for k = 1, 7 do
        var tx = math.clamp(math.floor(math.noise(k * 3.1, 1.7) * N), 0, N - 1)
        var tz = math.clamp(math.floor(math.noise(k * 1.3, 5.9) * N), 0, N - 1)
        trees[#trees + 1] = [tx, tz]
    end
    cam.look_at(N / 2, SEA, N / 2)             ## viser le centre du monde
end

## Couleur d'un bloc selon sa hauteur h et son niveau y (surface vs sous-sol).
func block_color(h, y)
    if y >= h then
        if h <= SEA then return C_SAND end
        if h >= 7 then return C_SNOW end
        return C_GRASS
    end
    if y >= h - 1 then return C_DIRT end
    return C_STONE
end

func draw()
    graphics.clear(C_SKY)                       ## ciel + efface la profondeur
    var dist = graphics.fitDistance(N * 0.8) * 1.1
    cam.orbit(elapsedTime * 0.2, dist, dist * 0.5)

    graphics.noStroke()
    graphics.begin3d(cam)
        var i = 1
        for z = 0, N - 1 do
            for x = 0, N - 1 do
                var h = heights[i]
                i = i + 1
                ## colonne solide (sommet → h-3 : assez pour masquer les falaises)
                var bottom = math.max(h - 3, 0)
                for y = bottom, h do
                    graphics.fill(block_color(h, y))
                    graphics.cube(x, y, z,  1, 1, 1)
                end
                if h < SEA then                 ## eau : surface plate sur les creux
                    graphics.fill(C_WATER)
                    graphics.cube(x, SEA, z,  1, 1, 1)
                end
            end
        end
        ## arbres : tronc + houppier
        for t in trees do
            var tx = t[1]
            var tz = t[2]
            var th = heights[tz * N + tx + 1]
            if th > SEA then
                graphics.fill(C_TRUNK)
                for k = 1, 3 do
                    graphics.cube(tx, th + k, tz,  1, 1, 1)
                end
                graphics.fill(C_LEAF)
                for lx = -1, 1 do
                    for lz = -1, 1 do
                        graphics.cube(tx + lx, th + 4, tz + lz,  1, 1, 1)
                    end
                end
                graphics.cube(tx, th + 5, tz,  1, 1, 1)
            end
        end
    graphics.end3d()

    graphics.draw_text("Univers voxel — bruit de Perlin + instancing", 12, 12, 18, colors.WHITE)
end
