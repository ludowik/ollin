## SUTOM — devine le mot. Clavier VIRTUEL (clics souris/tap) + clavier physique.
## Modules : graphics, mouse, keyboard, string, math.
## Rouge = bien placé · Jaune = présent ailleurs · Bleu = absent.

global WORDS = ["MAISON","JARDIN","SOLEIL","BUREAU","GATEAU","ORANGE","BANANE","CERISE","SOURIS","POULET","CANARD","LEZARD","RENARD","TIGRES"]

global W = 520
global H = 760
global ROWS = 6
global CELL = 56
global GAP  = 6
global TOPY = 80

global secret   = ""
global N        = 0
global rows     = []      ## entrées soumises : { word, colors }
global cur      = ""      ## ligne en cours de saisie
global rowIndex = 0
global state    = "playing"
global keys     = []      ## touches virtuelles : { label, kind, x, y, w, h }

func start()
    secret   = WORDS[math.rand_int(1, len(WORDS))]
    N        = len(secret)
    rows     = []
    rowIndex = 0
    state    = "playing"
    cur      = string.char(secret, 1)
end

## ── coloration (gestion des doublons) ───────────────────────────────────
func scoreWord(guess)
    var res = []
    var counts = {}
    for i = 1, N do
        res[i] = 0
        var sc = string.char(secret, i)
        if counts[sc] then counts[sc] = counts[sc] + 1 else counts[sc] = 1 end
    end
    for i = 1, N do
        if string.char(guess, i) == string.char(secret, i) then
            res[i] = 2
            var gc = string.char(guess, i)
            counts[gc] = counts[gc] - 1
        end
    end
    for i = 1, N do
        if res[i] == 0 then
            var gc2 = string.char(guess, i)
            ## counts[gc2] truthy ⟺ non-nil et non-zéro ⟺ encore disponible
            ## (0 et nil sont falsy en Ollin ; and/or n'y court-circuitent pas)
            if counts[gc2] then
                res[i] = 1
                counts[gc2] = counts[gc2] - 1
            end
        end
    end
    return res
end

## ── actions ─────────────────────────────────────────────────────────────
func addChar(ch)
    if state == "playing" and len(cur) < N then
        cur = cur + ch
    end
end

func delChar()
    if state == "playing" and len(cur) > 1 then
        cur = string.substr(cur, 1, len(cur) - 1)
    end
end

func submit()
    if state <> "playing" then
        return
    end
    if len(cur) < N then
        return
    end
    rows[rowIndex + 1] = { word: cur, colors: scoreWord(cur) }
    rowIndex = rowIndex + 1
    if cur == secret then
        state = "won"
    elseif rowIndex >= ROWS then
        state = "lost"
    else
        cur = string.char(secret, 1)
    end
end

## reçoit une chaîne du module keyboard
func onKey(k)
    if k == "return" then
        submit()
    elseif k == "backspace" then
        delChar()
    elseif k == "escape" then
        start()
    elseif len(k) == 1 then
        var up = string.upper(k)
        if up >= "A" and up <= "Z" then
            addChar(up)
        end
    end
end

## ── clavier virtuel ─────────────────────────────────────────────────────
func buildKeys()
    keys = []
    var layout = ["AZERTYUIOP", "QSDFGHJKLM", "WXCVBN"]
    var kw = 44
    var kh = 50
    var kg = 6
    var ky = TOPY + ROWS * (CELL + GAP) + 24
    for r = 1, 3 do
        var rowStr = layout[r]
        var n = len(rowStr)
        var rww = n * (kw + kg) - kg
        var kx = (W - rww) // 2
        for i = 1, n do
            keys[len(keys) + 1] = { label: string.char(rowStr, i), kind: "char", x: kx, y: ky, w: kw, h: kh }
            kx = kx + kw + kg
        end
        ky = ky + kh + kg
    end
    var ew = 110
    var ex = (W - (ew * 2 + kg)) // 2
    keys[len(keys) + 1] = { label: "ENTRER", kind: "enter", x: ex,           y: ky, w: ew, h: kh }
    keys[len(keys) + 1] = { label: "EFFACER", kind: "del",  x: ex + ew + kg, y: ky, w: ew, h: kh }
end

func onClick(mx, my)
    for k in keys do
        if mx >= k.x and mx <= k.x + k.w and my >= k.y and my <= k.y + k.h then
            if k.kind == "char" then
                addChar(k.label)
            elseif k.kind == "enter" then
                submit()
            else
                delChar()
            end
            return
        end
    end
end

## ── rendu ───────────────────────────────────────────────────────────────
func colorFor(c)
    if c == 2 then return { r: 0.90, g: 0.0,  b: 0.16 } end
    if c == 1 then return { r: 1.0,  g: 0.74, b: 0.0  } end
    return { r: 0.05, g: 0.42, b: 0.65 }
end

func letterAt(letter, cx, cy)
    graphics.draw_text(letter, cx + 16, cy + 12, 34, { r: 1, g: 1, b: 1 })
end

func drawGrid()
    var gw  = N * (CELL + GAP) - GAP
    var gx0 = (W - gw) // 2
    for r = 0, ROWS - 1 do
        var cy = TOPY + r * (CELL + GAP)
        for i = 1, N do
            var cx = gx0 + (i - 1) * (CELL + GAP)
            if r < rowIndex then
                var entry = rows[r + 1]
                graphics.fill(colorFor(entry.colors[i]))
                graphics.stroke()
                graphics.rect(cx, cy, CELL, CELL)
                letterAt(string.char(entry.word, i), cx, cy)
            elseif r == rowIndex and state == "playing" then
                graphics.fill()
                graphics.stroke({ r: 0.4, g: 0.4, b: 0.5 }, 2)
                graphics.rect(cx, cy, CELL, CELL)
                if i <= len(cur) then
                    letterAt(string.char(cur, i), cx, cy)
                end
            else
                graphics.fill()
                graphics.stroke({ r: 0.28, g: 0.22, b: 0.28 }, 2)
                graphics.rect(cx, cy, CELL, CELL)
                if i == 1 then
                    letterAt(string.char(secret, 1), cx, cy)
                end
            end
        end
    end
end

func drawKeys()
    for k in keys do
        graphics.fill({ r: 0.20, g: 0.20, b: 0.28 })
        graphics.stroke({ r: 0.45, g: 0.45, b: 0.55 }, 1)
        graphics.rect(k.x, k.y, k.w, k.h)
        graphics.draw_text(k.label, k.x + 10, k.y + 16, 18, { r: 1, g: 1, b: 1 })
    end
end

func frame()
    graphics.clear({ r: 0.10, g: 0.07, b: 0.10 })
    graphics.draw_text("SUTOM", W // 2 - 58, 22, 36, { r: 1, g: 0.74, b: 0 })
    drawGrid()
    drawKeys()
    if state == "won" then
        graphics.draw_text("GAGNE !  (Echap = rejouer)", 16, H - 30, 22, { r: 0.2, g: 0.9, b: 0.3 })
    elseif state == "lost" then
        graphics.draw_text("PERDU : " + secret + "  (Echap)", 16, H - 30, 22, { r: 1, g: 0.35, b: 0.35 })
    end
end

## ── init ────────────────────────────────────────────────────────────────
graphics.canvas(W, H, "SUTOM")
start()
buildKeys()
keyboard.enable(onKey)
mouse.on_down(onClick)
graphics.run(frame)
