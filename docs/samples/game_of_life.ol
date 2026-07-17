## Jeu de la vie de Conway (B3/S23), grille torique. Espace = pause, R = relance.
## Souris/doigt (aussi iPhone) : appui = pause + allume la cellule, glisser = dessine,
## double tap = relance.

const CELL = 8           ## px
const STEP = 0.08        ## secondes entre deux générations

## Grille dérivée de la zone de rendu (W, H) → format libre. Double buffer alloué
## une fois, échangé à chaque génération. Tableau plat 1-based : index = y*COLS + x + 1.
global COLS = 0
global ROWS = 0
global cells = []
global back  = []
global paused = false
global acc = 0.0         ## accumulateur pour cadencer les générations
global last_tap = -1.0   ## dernier appui (détection du double tap)
global drawing = false   ## true entre appui et relâché → glisser = dessin

func idx(x, y)
    return y * COLS + x + 1
end

func empty_grid()
    var g = []
    for i = 1, COLS * ROWS do
        g[i] = 0
    end
    return g
end

func set(g, x, y)
    if x >= 0 and x < COLS and y >= 0 and y < ROWS then
        g[idx(x, y)] = 1
    end
end

## Pose (dx, dy) autour de (ox, oy) après rotation o ∈ 1..4 → un motif dans les 4
## orientations sans dupliquer les coordonnées.
func put(g, ox, oy, dx, dy, o)
    var rx = dx
    var ry = dy
    if o == 2 then          ## 90°
        rx = -dy
        ry = dx
    elseif o == 3 then      ## 180°
        rx = -dx
        ry = -dy
    elseif o == 4 then      ## 270°
        rx = dy
        ry = -dx
    end
    set(g, ox + rx, oy + ry)
end

func glider(g, ox, oy, o)
    put(g, ox, oy, 1, 0, o)
    put(g, ox, oy, 2, 1, o)
    put(g, ox, oy, 0, 2, o)
    put(g, ox, oy, 1, 2, o)
    put(g, ox, oy, 2, 2, o)
end

func blinker(g, ox, oy, o)
    put(g, ox, oy, 0, 0, o)
    put(g, ox, oy, 1, 0, o)
    put(g, ox, oy, 2, 0, o)
end

func block(g, ox, oy, o)
    put(g, ox, oy, 0, 0, o)
    put(g, ox, oy, 1, 0, o)
    put(g, ox, oy, 0, 1, o)
    put(g, ox, oy, 1, 1, o)
end

## Canon à planeurs de Gosper : émet un planeur toutes les 30 générations.
## Coordonnées relatives à plat [x0,y0, x1,y1, …], posées via set() (hors-champ ignoré).
func gun(g, ox, oy)
    var pts = [
        0, 4,  0, 5,  1, 4,  1, 5,
        10, 4, 10, 5, 10, 6, 11, 3, 11, 7, 12, 2, 12, 8, 13, 2, 13, 8, 14, 5,
        15, 3, 15, 7, 16, 4, 16, 5, 16, 6, 17, 5,
        20, 2, 20, 3, 20, 4, 21, 2, 21, 3, 21, 4, 22, 1, 22, 5,
        24, 0, 24, 1, 24, 5, 24, 6,
        34, 2, 34, 3, 35, 2, 35, 3
    ]
    var i = 1
    while i <= len(pts) do
        set(g, ox + pts[i], oy + pts[i + 1])
        i += 2
    end
end

## Un canon + 5 à 10 motifs de base placés aléatoirement (type, position, orientation).
func reset()
    cells = empty_grid()
    back = empty_grid()
    gun(cells, 2, 2)
    var count = math.randInt(5, 10)
    for i = 1, count do
        var ox = math.randInt(2, COLS - 3)   ## marge de 2 : la rotation peut décaler de ±2
        var oy = math.randInt(2, ROWS - 3)
        var kind = math.randInt(1, 3)
        var o = math.randInt(1, 4)
        if kind == 1 then
            glider(cells, ox, oy, o)
        elseif kind == 2 then
            blinker(cells, ox, oy, o)
        else
            block(cells, ox, oy, o)
        end
    end
end

## Voisines vivantes (8-voisinage), bords toriques.
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

## Génération suivante dans `back` (chaque case réécrite → pas de ré-init), puis échange.
func step()
    for y = 0, ROWS - 1 do
        for x = 0, COLS - 1 do
            var n = neighbors(x, y)
            var alive = cells[idx(x, y)] == 1
            if (alive and (n == 2 or n == 3)) or (not alive and n == 3) then
                back[idx(x, y)] = 1
            else
                back[idx(x, y)] = 0
            end
        end
    end
    var tmp = cells
    cells = back
    back = tmp
end

graphics.canvas(W, H, "Jeu de la vie")
COLS = W // CELL
ROWS = H // CELL
reset()

func keyboard.keypressed(key)
    if key == "space" then
        paused = not paused
    elseif key == "r" then
        reset()
    end
end

const DOUBLE_TAP = 0.3
func mouse.pressed(x, y)
    if last_tap >= 0.0 and elapsedTime - last_tap < DOUBLE_TAP then
        paused = false                          ## double tap → relance
        drawing = false
        last_tap = -1.0                          ## un 3e appui ne compte pas comme double
        return
    end
    last_tap = elapsedTime
    paused = true
    drawing = true
    set(cells, x // CELL, y // CELL)
end

func mouse.moved(x, y)
    if drawing then                             ## `drawing` évite de dessiner au simple survol desktop
        set(cells, x // CELL, y // CELL)
    end
end

func mouse.released(x, y)
    drawing = false
end

## Cadence fixe : une génération tous les STEP, indépendamment du FPS.
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

const GAP = 2                                   ## espace entre cellules (px)
const BLEU = Color(0.62, 0.80, 0.98)

func draw()
    graphics.noStroke()
    ## clear semi-transparent → légère traînée visuelle (la simulation, elle, reste exacte)
    graphics.clear(Color(0.05, 0.06, 0.10, 0.45))
    graphics.fill(BLEU)
    for y = 0, ROWS - 1 do
        for x = 0, COLS - 1 do
            if cells[idx(x, y)] == 1 then
                graphics.rect(x * CELL, y * CELL, CELL - GAP, CELL - GAP)
            end
        end
    end
end
