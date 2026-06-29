## SUTOM — devine le mot. Clavier VIRTUEL (clics souris/tap) + clavier physique.
## Responsive : la grille et le clavier s'adaptent à window.width / window.height.
## Rouge = bien placé · Jaune = présent ailleurs · Bleu = absent.

global WORDS = ["MAISON","JARDIN","SOLEIL","BUREAU","GATEAU","ORANGE","BANANE","CERISE","SOURIS","POULET","CANARD","LEZARD","RENARD","TIGRES"]

global W = 0
global H = 0
global ROWS = 6

global secret   = ""
global N        = 0
global rows     = []      ## entrées soumises : { word, colors }
global cur      = ""      ## ligne en cours de saisie
global rowIndex = 0
global state    = "playing"
global keys     = []      ## touches virtuelles : { label, kind, x, y, w, h }

## layout calculé (layout())
global MARGIN = 0
global GAP = 0
global CELL = 0
global GX = 0
global GY = 0
global KW = 0
global KH = 0
global KG = 0
global KBY = 0
global TITLEY = 0
global TITLESZ = 0

func start()
    secret   = WORDS[math.rand_int(1, len(WORDS))]
    N        = len(secret)
    rows     = []
    rowIndex = 0
    state    = "playing"
    cur      = string.char(secret, 1)
end

## ── layout responsive ───────────────────────────────────────────────────
func layout()
    MARGIN = math.max(8, math.floor(W * 0.03))
    GAP    = math.max(4, math.floor(W * 0.012))
    KG     = GAP
    ## clavier : la rangée la plus large fait 10 touches
    KW  = math.floor((W - 2 * MARGIN - 9 * KG) / 10)
    KH  = math.floor(KW * 1.2)
    var kbH = 4 * KH + 4 * KG          ## 3 rangées lettres + 1 rangée entrer/effacer
    KBY = H - kbH - MARGIN
    TITLESZ = math.max(20, math.floor(H * 0.05))
    TITLEY  = MARGIN
    var gridTop    = TITLEY + TITLESZ + GAP * 2
    var gridAvailH = KBY - gridTop - GAP
    var cellH = math.floor((gridAvailH - (ROWS - 1) * GAP) / ROWS)
    var cellW = math.floor((W - 2 * MARGIN - (N - 1) * GAP) / N)
    CELL = math.min(cellW, cellH)
    var gridW = N * CELL + (N - 1) * GAP
    GX = math.floor((W - gridW) / 2)
    ## centre la grille verticalement dans l'espace au-dessus du clavier
    var gridH = ROWS * CELL + (ROWS - 1) * GAP
    GY = gridTop + math.max(0, math.floor((gridAvailH - gridH) / 2))
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
    var rowsKb = ["AZERTYUIOP", "QSDFGHJKLM", "WXCVBN"]
    var ky = KBY
    for r = 1, 3 do
        var rowStr = rowsKb[r]
        var nk = len(rowStr)
        var rww = nk * (KW + KG) - KG
        var kx = math.floor((W - rww) / 2)
        for i = 1, nk do
            keys[len(keys) + 1] = { label: string.char(rowStr, i), kind: "char", x: kx, y: ky, w: KW, h: KH }
            kx = kx + KW + KG
        end
        ky = ky + KH + KG
    end
    var ew = math.floor((W - 2 * MARGIN - KG) / 2)
    keys[len(keys) + 1] = { label: "ENTRER",  kind: "enter", x: MARGIN,             y: ky, w: ew, h: KH }
    keys[len(keys) + 1] = { label: "EFFACER", kind: "del",   x: MARGIN + ew + KG,   y: ky, w: ew, h: KH }
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
    var fz = math.floor(CELL * 0.6)
    graphics.draw_text(letter, cx + math.floor(CELL * 0.26), cy + math.floor(CELL * 0.16), fz, { r: 1, g: 1, b: 1 })
end

func drawGrid()
    for r = 0, ROWS - 1 do
        var cy = GY + r * (CELL + GAP)
        for i = 1, N do
            var cx = GX + (i - 1) * (CELL + GAP)
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
    var charFz = math.floor(KH * 0.45)
    var wideFz = math.floor(KH * 0.34)
    for k in keys do
        graphics.fill({ r: 0.20, g: 0.20, b: 0.28 })
        graphics.stroke({ r: 0.45, g: 0.45, b: 0.55 }, 1)
        graphics.rect(k.x, k.y, k.w, k.h)
        if k.kind == "char" then
            graphics.draw_text(k.label, k.x + math.floor(KW * 0.32), k.y + math.floor(KH * 0.28), charFz, { r: 1, g: 1, b: 1 })
        else
            graphics.draw_text(k.label, k.x + math.floor(k.w * 0.18), k.y + math.floor(KH * 0.32), wideFz, { r: 1, g: 1, b: 1 })
        end
    end
end

func frame()
    graphics.clear({ r: 0.10, g: 0.07, b: 0.10 })
    graphics.draw_text("SUTOM", math.floor(W / 2 - TITLESZ * 1.6), TITLEY, TITLESZ, { r: 1, g: 0.74, b: 0 })
    drawGrid()
    drawKeys()
    if state == "won" or state == "lost" then
        var by = math.floor(H / 2 - CELL * 0.7)
        graphics.fill({ r: 0, g: 0, b: 0, a: 0.8 })
        graphics.stroke({ r: 0.5, g: 0.5, b: 0.6 }, 1)
        graphics.rect(MARGIN, by, W - 2 * MARGIN, math.floor(CELL * 1.4))
        var fz = math.floor(CELL * 0.4)
        if state == "won" then
            graphics.draw_text("GAGNE !  (Echap = rejouer)", MARGIN + GAP * 2, by + math.floor(CELL * 0.45), fz, { r: 0.2, g: 0.9, b: 0.3 })
        else
            graphics.draw_text("PERDU : " + secret + "  (Echap)", MARGIN + GAP * 2, by + math.floor(CELL * 0.45), fz, { r: 1, g: 0.35, b: 0.35 })
        end
    end
end

## ── init ────────────────────────────────────────────────────────────────
W = window.width
H = window.height
graphics.canvas(W, H, "SUTOM")
start()
layout()
buildKeys()
keyboard.enable(onKey)
mouse.on_down(onClick)
graphics.run(frame)
