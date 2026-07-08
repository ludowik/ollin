## Jeu de la vie de Conway — automate cellulaire.
## Règles B3/S23 : une cellule naît avec 3 voisines, survit avec 2 ou 3.
## Grille torique (les bords se rejoignent). Espace = pause, R = réinitialiser.
## Souris/doigt (aussi sur iPhone, sans clavier) : un appui met en pause ET allume
## la cellule touchée (dessin libre) ; un DOUBLE tap relance la simulation.

const CELL = 8           ## taille d'une cellule en pixels (petites cellules)
const STEP = 0.08        ## secondes entre deux générations

## La grille occupe TOUTE la zone de rendu (globales moteur W, H) → affichage
## complet, format libre (pas forcément carré), quelle que soit la fenêtre.
## COLS/ROWS sont dérivés de W, H (calculés après graphics.canvas, plus bas).
global COLS = 0
global ROWS = 0
## Double buffer : deux grilles allouées UNE fois, échangées à chaque génération
## (pas de réallocation par step). Tableau plat 1-based : index = y*COLS + x + 1.
global cells = []        ## grille courante
global back  = []        ## grille de travail (génération suivante)
global paused = false
global acc = 0.0         ## accumulateur de temps pour cadencer les générations
global last_tap = -1.0   ## instant du dernier appui (détection du double tap)

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

## motifs placés RELATIVEMENT à la taille de grille (set() ignore le hors-champ)
func reset()
    cells = empty_grid()
    back = empty_grid()                       ## alloué une fois ; réutilisé et échangé ensuite
    glider(cells, 1, 1)                        ## planeurs
    glider(cells, COLS // 2, 2)
    glider(cells, COLS - 6, 4)
    blinker(cells, COLS // 4, ROWS // 2)       ## oscillateurs
    blinker(cells, (COLS * 3) // 4, ROWS // 2)
    block(cells, COLS - 4, ROWS - 4)           ## nature morte (stable)
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

## calcule la génération suivante dans `back`, puis échange les deux buffers.
## Chaque cellule est réécrite (0 ou 1) → pas besoin de ré-initialiser `back`.
func step()
    for y = 0, ROWS - 1 do
        for x = 0, COLS - 1 do
            var n = neighbors(x, y)
            var alive = cells[idx(x, y)] == 1
            if (alive and (n == 2 or n == 3)) or (not alive and n == 3) then
                back[idx(x, y)] = 1      ## survie ou naissance
            else
                back[idx(x, y)] = 0      ## mort / reste morte
            end
        end
    end
    var tmp = cells                      ## échange des buffers (pas de réallocation)
    cells = back
    back = tmp
end

graphics.canvas(W, H, "Jeu de la vie")   ## occupe toute la zone de rendu
COLS = W // CELL                          ## grille dérivée de la zone (format libre)
ROWS = H // CELL
reset()

## Espace : pause/reprise — R : réinitialiser
func keyboard.keypressed(key)
    if key == "space" then
        paused = not paused
    elseif key == "r" then
        reset()
    end
end

## Appui souris / doigt (utile sur iPhone, sans clavier) :
##  - simple appui  → PAUSE + allume la cellule touchée (dessin libre) ;
##  - DOUBLE tap (deux appuis < 0,3 s) → relance la simulation (reprise).
## (x, y) en pixels dans le repère de la zone de rendu → conversion en case ;
## set() ignore les coordonnées hors grille.
const DOUBLE_TAP = 0.3                          ## fenêtre du double tap (secondes)
func mouse.pressed(x, y)
    if last_tap >= 0.0 and elapsedTime - last_tap < DOUBLE_TAP then
        paused = false                          ## double tap → relance
        last_tap = -1.0                          ## évite qu'un 3e appui compte comme double
        return
    end
    last_tap = elapsedTime
    paused = true
    set(cells, x // CELL, y // CELL)
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

const GAP = 2                                   ## espace entre cellules (px) — carrés bien détachés
const BLEU = Color(0.62, 0.80, 0.98)            ## bleu pastel clair

func draw()
    graphics.noStroke()                          ## carrés pleins, sans bordure
    ## Faible persistance VISUELLE : on estompe la frame précédente à chaque frame
    ## (alpha élevé = fondu rapide → traînée très courte). La simulation reste exacte.
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
