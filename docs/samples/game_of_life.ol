## Jeu de la vie de Conway — automate cellulaire.
## Règles B3/S23 : une cellule naît avec 3 voisines, survit avec 2 ou 3.
## Grille torique (les bords se rejoignent). Espace = pause, R = réinitialiser.

const COLS = 60
const ROWS = 40
const CELL = 12          ## taille d'une cellule en pixels
const STEP = 0.08        ## secondes entre deux générations

global cells = []        ## grille courante, tableau plat 1-based : index = y*COLS + x + 1
global paused = false
global acc = 0.0         ## accumulateur de temps pour cadencer les générations

func idx(x, y)
    return y * COLS + x + 1
end

## nouvelle grille toute morte (toutes les cases définies à 0)
func empty_grid()
    var g = []
    for i = 1, COLS * ROWS do
        g[i] = 0
    end
    return g
end

## allume la cellule (x, y) si elle est dans la grille
func set(g, x, y)
    if x >= 0 and x < COLS and y >= 0 and y < ROWS then
        g[idx(x, y)] = 1
    end
end

## motifs classiques, posés à partir d'un coin (ox, oy)
func glider(g, ox, oy)
    set(g, ox + 1, oy + 0)
    set(g, ox + 2, oy + 1)
    set(g, ox + 0, oy + 2)
    set(g, ox + 1, oy + 2)
    set(g, ox + 2, oy + 2)
end

func blinker(g, ox, oy)
    set(g, ox + 0, oy)
    set(g, ox + 1, oy)
    set(g, ox + 2, oy)
end

func block(g, ox, oy)
    set(g, ox, oy)
    set(g, ox + 1, oy)
    set(g, ox, oy + 1)
    set(g, ox + 1, oy + 1)
end

func reset()
    cells = empty_grid()
    glider(cells, 1, 1)          ## planeurs qui traversent la grille
    glider(cells, 25, 3)
    glider(cells, 45, 8)
    blinker(cells, 10, 25)       ## oscillateurs
    blinker(cells, 30, 30)
    block(cells, 50, 32)         ## nature morte (stable)
end

## nombre de voisines vivantes (8-voisinage) avec bords toriques
func neighbors(x, y)
    var n = 0
    for dy = -1, 1 do
        for dx = -1, 1 do
            if not (dx == 0 and dy == 0) then
                var nx = (x + dx + COLS) % COLS
                var ny = (y + dy + ROWS) % ROWS
                n += cells[idx(nx, ny)]
            end
        end
    end
    return n
end

## calcule la génération suivante (double buffer)
func step()
    var nxt = empty_grid()
    for y = 0, ROWS - 1 do
        for x = 0, COLS - 1 do
            var n = neighbors(x, y)
            var alive = cells[idx(x, y)] == 1
            if alive and (n == 2 or n == 3) then
                nxt[idx(x, y)] = 1        ## survie
            elseif not alive and n == 3 then
                nxt[idx(x, y)] = 1        ## naissance
            end
        end
    end
    cells = nxt
end

graphics.canvas(COLS * CELL, ROWS * CELL, "Jeu de la vie")
reset()

## Espace : pause/reprise — R : réinitialiser
func keyboard.keypressed(key)
    if key == "space" then
        paused = not paused
    elseif key == "r" then
        reset()
    end
end

## logique cadencée : une génération tous les STEP, indépendamment du FPS
func update(dt)
    if paused then
        return
    end
    acc += dt
    while acc >= STEP do
        step()
        acc -= STEP
    end
end

func draw()
    graphics.clear(colors.BLACK)
    graphics.fill(colors.LIME)
    for y = 0, ROWS - 1 do
        for x = 0, COLS - 1 do
            if cells[idx(x, y)] == 1 then
                graphics.rect(x * CELL, y * CELL, CELL - 1, CELL - 1)
            end
        end
    end
end
