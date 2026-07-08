## Jeu de la vie de Conway — automate cellulaire.
## Règles B3/S23 : une cellule naît avec 3 voisines, survit avec 2 ou 3.
## Au démarrage : un générateur (canon à planeurs de Gosper) + des motifs aléatoires.
## Grille torique (les bords se rejoignent). Espace = pause, R = réinitialiser.
## Souris/doigt (aussi sur iPhone, sans clavier) : un appui met en pause ET allume
## la cellule touchée ; GLISSER dessine des cellules en continu ; un DOUBLE tap
## relance la simulation.

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
global drawing = false   ## true entre l'appui et le relâché → glisser = dessin

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

## Pose la cellule d'offset (dx, dy) autour de (ox, oy) après rotation selon
## l'orientation o ∈ 1..4 (droite/bas/gauche/haut = 0/90/180/270°). Permet de
## poser un même motif dans les 4 orientations sans dupliquer les coordonnées.
func put(g, ox, oy, dx, dy, o)
    var rx = dx
    var ry = dy
    if o == 2 then          ## 90°  (rotation d'un quart de tour)
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

## motifs classiques, posés autour de (ox, oy) avec l'orientation o (1..4)
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

## Canon à planeurs de Gosper — LE générateur : émet un planeur toutes les 30
## générations. 36 cellules dans une boîte 36×9. Coordonnées relatives (x, y)
## stockées à plat [x0,y0, x1,y1, …] et posées via set() (hors-champ ignoré).
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

## Démarrage : UN générateur (canon à planeurs) posé en haut à gauche, plus entre
## 5 et 10 motifs de base (planeur / oscillateur / nature morte) posés ALÉATOIREMENT
## (type, position ET orientation — haut/bas/gauche/droite — tirés au hasard). Le RNG
## de `math` est auto-initialisé → une configuration différente à chaque lancement.
func reset()
    cells = empty_grid()
    back = empty_grid()                       ## alloué une fois ; réutilisé et échangé ensuite
    gun(cells, 2, 2)                          ## le générateur (émet des planeurs)
    var count = math.rand_int(5, 10)          ## entre 5 et 10 motifs de base
    for i = 1, count do
        ## marge de 2 des deux côtés : la rotation peut décaler le motif de ±2
        var ox = math.rand_int(2, COLS - 3)
        var oy = math.rand_int(2, ROWS - 3)
        var kind = math.rand_int(1, 3)
        var o = math.rand_int(1, 4)           ## orientation : haut/bas/gauche/droite
        if kind == 1 then
            glider(cells, ox, oy, o)          ## planeur
        elseif kind == 2 then
            blinker(cells, ox, oy, o)         ## oscillateur
        else
            block(cells, ox, oy, o)           ## nature morte (stable)
        end
    end
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
##  - simple appui  → PAUSE + allume la cellule touchée, et arme le dessin ;
##  - GLISSER (bouton/doigt maintenu) → dessine des cellules en continu ;
##  - DOUBLE tap (deux appuis < 0,3 s) → relance la simulation (reprise).
## (x, y) en pixels dans le repère de la zone de rendu → conversion en case ;
## set() ignore les coordonnées hors grille.
const DOUBLE_TAP = 0.3                          ## fenêtre du double tap (secondes)
func mouse.pressed(x, y)
    if last_tap >= 0.0 and elapsedTime - last_tap < DOUBLE_TAP then
        paused = false                          ## double tap → relance
        drawing = false
        last_tap = -1.0                          ## évite qu'un 3e appui compte comme double
        return
    end
    last_tap = elapsedTime
    paused = true
    drawing = true                              ## arme le tracé (glisser dessinera)
    set(cells, x // CELL, y // CELL)
end

## Glisser : tant que le bouton/doigt est maintenu, chaque déplacement allume la
## cellule survolée (le drapeau `drawing` évite de dessiner au simple survol desktop).
func mouse.moved(x, y)
    if drawing then
        set(cells, x // CELL, y // CELL)
    end
end

## Relâché : fin du tracé.
func mouse.released(x, y)
    drawing = false
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
