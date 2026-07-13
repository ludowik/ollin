## Univers VOXEL façon Minecraft — grand monde découpé en CHUNKS, rendu seulement
## pour les chunks VISIBLES (culling par frustum).
##   • terrain de cubes généré par bruit de Perlin (math.noise)
##   • le monde est divisé en chunks CS×CS colonnes ; à chaque frame on ne dessine
##     QUE les chunks dans le champ de vision (graphics.inFrustum) → le monde peut
##     être bien plus grand sans tout dessiner.
##   • instancing : les cubes des chunks visibles = 1 seul draw call.

global CS = 8               ## côté d'un chunk (colonnes)
global NC = 10              ## chunks par côté  → monde de CS*NC = 80 colonnes
global WORLD = CS * NC
global SEA = 2
global heights = []         ## hauteur de chaque colonne (précalculée)
global cam = graphics.camera(0, 0, 10,  0, 0, 0)

## Palette créée UNE fois (aucune allocation de couleur par cube).
global C_SKY   = Color(0.53, 0.78, 0.92)
global C_GRASS = Color(0.36, 0.62, 0.24)
global C_DIRT  = Color(0.46, 0.33, 0.20)
global C_STONE = Color(0.50, 0.50, 0.52)
global C_SAND  = Color(0.83, 0.76, 0.48)
global C_SNOW  = Color(0.95, 0.96, 0.98)
global C_WATER = Color(0.20, 0.45, 0.80)

func height_at(x, z)
    var n = math.noise(x * 0.09, z * 0.09) * 0.7 + math.noise(x * 0.2, z * 0.2) * 0.3
    return math.floor(n * 6)
end

func setup()
    graphics.canvas(W, H, "Voxel chunks")
    graphics.ambient(0.45)
    graphics.light("dir", -0.6, -1, -0.4)
    math.noise_seed(12)
    for z = 0, WORLD - 1 do
        for x = 0, WORLD - 1 do
            heights[#heights + 1] = height_at(x, z)
        end
    end
    cam.look_at(WORLD / 2, SEA, WORLD / 2)
end

func block_color(h, y)
    if y >= h then
        if h <= SEA then return C_SAND end
        if h >= 8 then return C_SNOW end
        return C_GRASS
    end
    if y >= h - 1 then return C_DIRT end
    return C_STONE
end

## Dessine toutes les colonnes d'un chunk (cx, cz).
func draw_chunk(cx, cz)
    var x0 = cx * CS
    var z0 = cz * CS
    for z = z0, z0 + CS - 1 do
        for x = x0, x0 + CS - 1 do
            var h = heights[z * WORLD + x + 1]
            ## vue plongeante → 1 cube par colonne (le sommet) suffit : léger et net
            graphics.fill(block_color(h, h))
            graphics.cube(x, h, z,  1, 1, 1)
            if h < SEA then
                graphics.fill(C_WATER)
                graphics.cube(x, SEA, z,  1, 1, 1)
            end
        end
    end
end

func draw()
    graphics.clear(C_SKY)
    ## orbite plongeante autour du centre : on ne voit qu'une PARTIE du grand monde
    ## → les chunks hors-champ ne sont pas dessinés (voir le compteur en haut).
    cam.orbit(elapsedTime * 0.12, 15, 17)

    graphics.noStroke()
    var shown = 0
    graphics.begin3d(cam)
        for cz = 0, NC - 1 do
            for cx = 0, NC - 1 do
                ## centre monde du chunk + rayon englobant (demi-diagonale + hauteur)
                var wx = cx * CS + CS / 2
                var wz = cz * CS + CS / 2
                if graphics.inFrustum(wx, 4, wz, CS) then   ## ne dessiner QUE si visible
                    shown = shown + 1
                    draw_chunk(cx, cz)
                end
            end
        end
    graphics.end3d()

    graphics.draw_text("Chunks visibles : " + shown + " / " + (NC * NC), 12, 12, 18, colors.WHITE)
end
