## A pocket calculator. Operations run in the order they are typed, as on a simple pocket calculator: 2 + 3 x 4 = gives 20,
## not 14. Tap the keys, or use the keyboard: digits, return for "=", backspace to delete a digit, escape to clear.
##
## engine.ol holds the arithmetic (it has its own test); this file is the keypad: the layout, the input and the drawing.
## The layout follows the area (graphics.fitArea) and is computed again at each frame, so nothing has to be kept in step.

import "engine.ol"
import "../lib/draw.ol"

const COLS = 4
const ROWS = 5
const KEYS = [
    ["AC", "+/-", "%", "/"],
    ["7", "8", "9", "*"],
    ["4", "5", "6", "-"],
    ["1", "2", "3", "+"],
    ["0", ".", "<", "="]
]
const DISPLAY_ROWS = 1.7             ## the display is this many key rows high
const FLASH = 0.12                   ## seconds a key stays lit after a tap

const BACKGROUND = [0.07, 0.08, 0.11, 1]
const DIGIT_FILL = [0.20, 0.22, 0.28, 1]
const FUNCTION_FILL = [0.62, 0.65, 0.72, 1]
const OPERATOR_FILL = [0.96, 0.62, 0.12, 1]
const LIGHT_INK = [1, 1, 1, 1]
const DARK_INK = BACKGROUND
const MUTED = FUNCTION_FILL
const ERROR_INK = [1, 0.55, 0.55, 1]

global calc = calcNew()
global lit = {key: nil, since: 0}    ## the key just tapped, for its flash

## Where everything goes, from the size of the area: computed again whenever it is needed, so it is never stale.
func layoutOf()
    var layout = {}
    var margin = SIZE * 0.04
    var availW = W - 2 * margin
    var availH = H - 2 * margin
    var cell = math.min(availW / COLS, availH / (ROWS + DISPLAY_ROWS))
    layout.cell = cell
    layout.pad = cell * 0.06
    layout.radius = cell * 0.28
    layout.x = (W - cell * COLS) / 2
    layout.y = (H - cell * (ROWS + DISPLAY_ROWS)) / 2
    layout.keysY = layout.y + cell * DISPLAY_ROWS
    return layout
end

## The key under (x, y) or nil.
func keyAt(x, y)
    var layout = layoutOf()
    var c = math.floor((x - layout.x) / layout.cell) + 1
    var r = math.floor((y - layout.keysY) / layout.cell) + 1
    if c < 1 or c > COLS or r < 1 or r > ROWS then
        return nil
    end
    return KEYS[r][c]
end

func pressKey(key)
    lit.key = key
    lit.since = elapsedTime
    if key == "AC" then
        key = calcClearLabel(calc)
    end
    calcPress(calc, key)
end

func mouse.pressed(x, y)
    var key = keyAt(x, y)
    if key <> nil then
        pressKey(key)
    end
end

## The keyboard has no key names for the operators: only what it names is mapped.
func keyboard.keypressed(key)
    if key == "return" then
        pressKey("=")
    elseif key == "backspace" or key == "delete" then
        pressKey("<")
    elseif key == "escape" then
        pressKey("AC")
    elseif key.number() <> nil and key.len() == 1 then
        pressKey(key)
    end
end

## The colour of a key and of what is written on it.
func keyColors(key)
    if key == "AC" or key == "+/-" or key == "%" then
        return FUNCTION_FILL, DARK_INK
    elseif SYMBOLS[key] <> nil or key == "=" then
        return OPERATOR_FILL, DARK_INK
    end
    return DIGIT_FILL, LIGHT_INK
end

func keyLabel(key)
    if key == "AC" then
        return calcClearLabel(calc)
    end
    if SYMBOLS[key] <> nil then
        return SYMBOLS[key]
    end
    return key
end

func drawKey(L, key, r, c)
    var x = L.x + (c - 1) * L.cell + L.pad
    var y = L.keysY + (r - 1) * L.cell + L.pad
    var size = L.cell - 2 * L.pad
    var fill, ink = keyColors(key)
    var glow = 0
    if lit.key == key and elapsedTime - lit.since < FLASH then
        glow = 1 - (elapsedTime - lit.since) / FLASH
    end
    fillC(fill)
    graphics.rect(x, y, size, size, L.radius)
    if glow > 0 then
        fillC(LIGHT_INK, 0.45 * glow)
        graphics.rect(x, y, size, size, L.radius)
    end
    if calc.op == key and calc.fresh and not calc.error then
        graphics.noFill()
        graphics.stroke(1, 1, 1, 1)
        graphics.strokeSize(L.cell * 0.04)
        graphics.rect(x, y, size, size, L.radius)
        graphics.noStroke()
    end
    var label = keyLabel(key)
    drawText(label, x + size / 2, y + size / 2, fitSize(label, L.cell * 0.4, size * 0.8), "center", "center", ink)
end

func drawDisplay(L)
    var right = L.x + L.cell * COLS - L.pad * 2
    var width = L.cell * COLS - L.pad * 4
    var ink = LIGHT_INK
    if calc.error then
        ink = ERROR_INK
    end
    drawText(calc.history, right, L.y + L.cell * 0.35, fitSize(calc.history, L.cell * 0.3, width), "right", "center", MUTED)
    var bottom = L.y + L.cell * (DISPLAY_ROWS - 0.55)
    drawText(calc.display, right, bottom, fitSize(calc.display, L.cell * 0.95, width), "right", "center", ink)
end

func setup()
    graphics.canvas(W, H, "Calculator")
    graphics.fitArea()
end

func draw()
    var L = layoutOf()
    graphics.clear(BACKGROUND[1], BACKGROUND[2], BACKGROUND[3])
    graphics.noStroke()
    drawDisplay(L)
    for r = 1, ROWS do
        for c = 1, COLS do
            drawKey(L, KEYS[r][c], r, c)
        end
    end
end
