## Conway's Game of Life (B3/S23) on a toroidal grid. Space pauses, R restarts.
## Mouse or finger (an iPhone included): a press pauses and lights the cell, dragging draws,
## a double tap restarts.

const CELL = 8           ## px
const STEP = 0.08        ## seconds between two generations

## The grid derives from the render area (W, H), so any shape goes. The double buffer is
## allocated once and swapped every generation. A flat 1-based array: index = y*COLS + x + 1.
global COLS = 0
global ROWS = 0
global cells = []
global back  = []
global paused = false
global acc = 0.0         ## the accumulator that paces the generations
global lastTap = -1.0   ## the last press, for detecting a double tap
global drawing = false   ## true between press and release, so dragging draws

func idx(x, y)
    return y * COLS + x + 1
end

func emptyGrid()
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

## Places (dx, dy) around (ox, oy) after a rotation o in 1..4, which gives a pattern in all four
## orientations without duplicating the coordinates.
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

## Gosper's glider gun: it emits a glider every thirty generations.
## Relative coordinates, laid out flat as [x0,y0, x1,y1, …] and placed through set(), which
## ignores anything off the grid.
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

## One gun plus five to ten basic patterns placed at random, by kind, position and orientation.
func reset()
    cells = emptyGrid()
    back = emptyGrid()
    gun(cells, 2, 2)
    var count = math.randInt(5, 10)
    for i = 1, count do
        var ox = math.randInt(2, COLS - 3)   ## a margin of 2: the rotation can shift by up to two
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

## The next generation goes into `back`, every cell being rewritten so no reset is needed, then the buffers are swapped.
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

graphics.canvas(W, H, "Game of Life")
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
    if lastTap >= 0.0 and elapsedTime - lastTap < DOUBLE_TAP then
        paused = false                          ## a double tap restarts
        drawing = false
        lastTap = -1.0                          ## a third press does not count as another double
        return
    end
    lastTap = elapsedTime
    paused = true
    drawing = true
    set(cells, x // CELL, y // CELL)
end

func mouse.moved(x, y)
    if drawing then                             ## `drawing` keeps a mere desktop hover from drawing
        set(cells, x // CELL, y // CELL)
    end
end

func mouse.released(x, y)
    drawing = false
end

## A fixed pace: one generation every STEP, whatever the frame rate.
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
    ## a semi-transparent clear leaves a slight visual trail; the simulation itself stays exact
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
