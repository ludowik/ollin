## SUTOM — devine le mot (façon sutom.nocle.fr). Clavier VIRTUEL (clic/tap) + physique.
## Rouge = bien placé · Rond jaune = présent mal placé · Bleu = absent.
## Mot hors dictionnaire = refusé (la ligne tremble). Responsive (window.width/height).

## Longueurs variées (6 à 9) — le jeu s'adapte (N = longueur du mot tiré).
global WORDS = [
  "MAISON","JARDIN","SOLEIL","BUREAU","ORANGE","BANANE","CERISE","SOURIS","CANARD","RENARD",
  "FLEURS","GARAGE","CHAISE","MIROIR","CHEVAL","BALLON","MELONS","CITRON","POMMES","FRAISE",
  "VOITURE","FENETRE","CHAPEAU","MANTEAU","JOURNAL","CRAYONS","TROUSSE","FROMAGE","RIVIERE","JARDINS",
  "GUITARE","TABLEAU","PINCEAU","CISEAUX","CHEMISE","ECHARPE","POULAIN","BALCONS","ETOILES","MAISONS",
  "MONTAGNE","CAMPAGNE","VACANCES","BATIMENT","CHATEAUX","DRAPEAUX","TROTTOIR","AVENTURE","LUNETTES","CEINTURE",
  "MANTEAUX","FENETRES","ESCALIER","PEINTRES","HORIZONS",
  "BOUTEILLE","PARAPLUIE","CHOCOLATS","PAPILLONS","CROISSANT","TELEPHONE","FRAMBOISE","MANDARINE"
]

global W = 0
global H = 0
global ROWS = 6

global DICT       = {}    ## ensemble des mots valides (lookup O(1))
global secret     = ""
global N          = 0
global rows       = []    ## { word, colors }
global cur        = ""
global rowIndex   = 0
global state      = "playing"
global keys       = []    ## { label, kind, x, y, w, h }
global keyStatus  = {}    ## lettre -> (statut+1) : 1 absent, 2 présent, 3 bien placé
global msg        = ""
global msgUntil   = 0
global shakeUntil = 0

## layout
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

## ── palette : instances Color créées une fois (proche sutom.nocle.fr) ────
global RED, BLUE, YELLOW, BG, CELLC, WHITE
global B_CUR, B_EMPTY, B_KEY, B_OVL, OVERLAY, GREEN, REDISH
func initColors()
    RED     = Color(0.90, 0.10, 0.20)   ## bien placé
    BLUE    = Color(0.20, 0.45, 0.72)   ## absent
    YELLOW  = Color(1.0,  0.78, 0.0)    ## présent (rond)
    BG      = Color(0.04, 0.06, 0.12)   ## fond
    CELLC   = Color(0.09, 0.13, 0.22)   ## case vide / touche
    WHITE   = Color(1, 1, 1)
    B_CUR   = Color(0.40, 0.42, 0.50)   ## bord ligne courante
    B_EMPTY = Color(0.20, 0.24, 0.32)   ## bord ligne vide
    B_KEY   = Color(0.45, 0.45, 0.55)   ## bord touche
    B_OVL   = Color(0.50, 0.50, 0.60)   ## bord overlay
    OVERLAY = Color(0, 0, 0, 0.82)      ## voile overlay
    GREEN   = Color(0.20, 0.90, 0.30)
    REDISH  = Color(1.0, 0.35, 0.35)
end

func start()
    secret   = WORDS[math.rand_int(1, len(WORDS))]
    N        = len(secret)
    rows     = []
    rowIndex = 0
    state    = "playing"
    cur      = string.char(secret, 1)
    keyStatus = {}
    msg = ""
end

## ── coloration (doublons gérés) : 0 absent, 1 présent, 2 bien placé ─────
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
func flash(text)
    msg      = text
    msgUntil = time() + 1.4
end

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
    if state <> "playing" then return end
    if len(cur) < N then
        flash("Complete le mot")
        shakeUntil = time() + 0.4
        return
    end
    if not DICT[cur] then
        flash("Mot inconnu")
        shakeUntil = time() + 0.4
        return
    end
    var colors = scoreWord(cur)
    rows[rowIndex + 1] = { word: cur, colors: colors }
    ## met à jour la couleur des touches (garde le meilleur statut connu)
    for i = 1, N do
        var c = string.char(cur, i)
        var v = colors[i] + 1
        if not keyStatus[c] or v > keyStatus[c] then keyStatus[c] = v end
    end
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
        if up >= "A" and up <= "Z" then addChar(up) end
    end
end

## ── layout responsive ───────────────────────────────────────────────────
func layout()
    MARGIN = math.max(8, math.floor(W * 0.03))
    GAP    = math.max(4, math.floor(W * 0.012))
    KG     = GAP
    KW  = math.floor((W - 2 * MARGIN - 9 * KG) / 10)
    KH  = math.floor(KW * 1.2)
    var kbH = 4 * KH + 4 * KG
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
    var gridH = ROWS * CELL + (ROWS - 1) * GAP
    GY = gridTop + math.max(0, math.floor((gridAvailH - gridH) / 2))
end

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
    keys[len(keys) + 1] = { label: "ENTRER",  kind: "enter", x: MARGIN,           y: ky, w: ew, h: KH }
    keys[len(keys) + 1] = { label: "EFFACER", kind: "del",   x: MARGIN + ew + KG, y: ky, w: ew, h: KH }
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
func letterAt(letter, cx, cy)
    var fz = math.floor(CELL * 0.6)
    graphics.draw_text(letter, cx + math.floor(CELL * 0.26), cy + math.floor(CELL * 0.16), fz, WHITE)
end

func drawCell(cx, cy, c, letter)
    if c == 2 then
        graphics.fill(RED)
        graphics.noStroke()
        graphics.rect(cx, cy, CELL, CELL)
    elseif c == 1 then
        graphics.fill(BLUE)
        graphics.noStroke()
        graphics.rect(cx, cy, CELL, CELL)
        graphics.fill(YELLOW)               ## rond jaune (présent mal placé)
        graphics.noStroke()
        graphics.circle(cx + math.floor(CELL / 2), cy + math.floor(CELL / 2), math.floor(CELL * 0.36))
    else
        graphics.fill(BLUE)
        graphics.noStroke()
        graphics.rect(cx, cy, CELL, CELL)
    end
    letterAt(letter, cx, cy)
end

func drawGrid()
    var shaking = time() < shakeUntil
    for r = 0, ROWS - 1 do
        var cy = GY + r * (CELL + GAP)
        var xoff = 0
        if shaking and r == rowIndex then xoff = math.floor(math.sin(time() * 45) * CELL * 0.12) end
        for i = 1, N do
            var cx = GX + (i - 1) * (CELL + GAP) + xoff
            if r < rowIndex then
                var entry = rows[r + 1]
                drawCell(cx, cy, entry.colors[i], string.char(entry.word, i))
            elseif r == rowIndex and state == "playing" then
                graphics.fill(CELLC)
                graphics.stroke(B_CUR, 2)
                graphics.rect(cx, cy, CELL, CELL)
                if i <= len(cur) then letterAt(string.char(cur, i), cx, cy) end
            else
                graphics.fill(CELLC)
                graphics.stroke(B_EMPTY, 2)
                graphics.rect(cx, cy, CELL, CELL)
                if i == 1 then letterAt(string.char(secret, 1), cx, cy) end
            end
        end
    end
end

func drawKeys()
    var charFz = math.floor(KH * 0.45)
    var wideFz = math.floor(KH * 0.34)
    for k in keys do
        var bg = CELLC
        if k.kind == "char" and keyStatus[k.label] then
            var st = keyStatus[k.label] - 1
            if st == 2 then bg = RED elseif st == 1 then bg = YELLOW else bg = BLUE end
        end
        graphics.fill(bg)
        graphics.stroke(B_KEY, 1)
        graphics.rect(k.x, k.y, k.w, k.h)
        if k.kind == "char" then
            graphics.draw_text(k.label, k.x + math.floor(KW * 0.32), k.y + math.floor(KH * 0.28), charFz, WHITE)
        else
            graphics.draw_text(k.label, k.x + math.floor(k.w * 0.18), k.y + math.floor(KH * 0.32), wideFz, WHITE)
        end
    end
end

func draw()
    graphics.clear(BG)
    graphics.draw_text("SUTOM", math.floor(W / 2 - TITLESZ * 1.6), TITLEY, TITLESZ, YELLOW)
    drawGrid()
    drawKeys()
    ## message transitoire (mot inconnu, etc.)
    if time() < msgUntil then
        var mfz = math.floor(TITLESZ * 0.55)
        graphics.draw_text(msg, math.floor(W / 2 - len(msg) * mfz * 0.28), GY - mfz - GAP, mfz, WHITE)
    end
    if state == "won" or state == "lost" then
        var by = math.floor(H / 2 - CELL * 0.7)
        graphics.fill(OVERLAY)
        graphics.stroke(B_OVL, 1)
        graphics.rect(MARGIN, by, W - 2 * MARGIN, math.floor(CELL * 1.4))
        var efz = math.floor(CELL * 0.4)
        if state == "won" then
            graphics.draw_text("GAGNE !  (Echap = rejouer)", MARGIN + GAP * 2, by + math.floor(CELL * 0.45), efz, GREEN)
        else
            graphics.draw_text("PERDU : " + secret + "  (Echap)", MARGIN + GAP * 2, by + math.floor(CELL * 0.45), efz, REDISH)
        end
    end
end

## ── init ────────────────────────────────────────────────────────────────
initColors()
for w in WORDS do DICT[w] = 1 end
W = window.width
H = window.height
graphics.canvas(W, H, "SUTOM")
start()
layout()
buildKeys()
keyboard.enable(onKey)
mouse.on_down(onClick)
## `draw` est appelée automatiquement à chaque frame par le moteur.
