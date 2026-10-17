## How the lexer works. The lexer is the first stage of the engine: it reads the program's TEXT, one
## character at a time, and cuts it into TOKENS — the words the parser then assembles into
## statements. This example replays that cut, step by step.
##
## What runs here is a copy of src/lexer.cpp written in Ollin (tracer.ol) that records every move it
## makes, so the animation shows the engine's real rules and not a drawing of them: the same keyword
## table, the same two-character operators, the same refusals. tests/lexer_trace_test.ol checks that
## it cuts a program into exactly the tokens the C++ lexer gives.
##
## The caret is the read head: the character the lexer is about to read. The highlighted span is the
## lexeme being built, and the panel on the right lights up the line of lexer.cpp that is running.
## Each token that comes out is filed in the stream below, and the program's text is underlined in
## the colour of the token it became.
##
## Space plays and pauses, the arrows step (left/right) and change the speed (up/down), 1 to 4
## pick a program, R restarts. A tap pauses and resumes. The menu does the same with the finger.

import "tracer.ol"
import "programs.ol"

const BG = Color(0.07, 0.08, 0.12)
const PANEL = Color(0.11, 0.12, 0.17)
const EDGE = Color(0.26, 0.28, 0.37)
const TEXT = Color(0.93, 0.95, 0.99)
const DIM = Color(0.62, 0.66, 0.77)
const PROCESSED = Color(0.50, 0.54, 0.65)
const CARET = Color(1.0, 0.84, 0.30)
const ERROR = Color(1.0, 0.45, 0.45)

## One colour per kind of token. The same colour underlines the text and edges the chip.
const KIND_COLORS = {
    keyword: Color(0.78, 0.62, 1.0),
    name: Color(0.52, 0.79, 1.0),
    number: Color(1.0, 0.73, 0.42),
    text: Color(0.56, 0.89, 0.60),
    operator: Color(1.0, 0.57, 0.65),
    punct: Color(0.74, 0.78, 0.88),
    ending: Color(0.72, 0.74, 0.80)
}

const PUNCTUATION = ["COMMA", "LPAREN", "RPAREN", "LBRACE", "RBRACE", "LBRACKET", "RBRACKET", "COLON",
                     "SEMICOLON", "DOT", "DOT_DOT_DOT", "QUESTION"]

global state = {pos: 0.0, playing: true, speed: 1.0, prog: 1, name: nil, hold: 0.0}
global run = nil          ## the trace of the program on show
global durations = []     ## how long each step lasts, in seconds at speed 1
global emitted = []       ## emitted[i]: how many tokens exist once step i is done
global keywordTypes = {}
global monoRatio = nil    ## the width of a monospaced character, per pixel of font size
global stream = {key: nil, chips: []}
global noteCache = {key: nil, lines: [], size: 0}

func lerp(a, b, t)
    return a + (b - a) * t
end

func ease(t)
    return t * t * (3 - 2 * t)
end

func kindOf(ty)
    if keywordTypes[ty] then
        return "keyword"
    elseif ty == "IDENTIFIER" then
        return "name"
    elseif ty == "NUMBER" then
        return "number"
    elseif ty == "STRING" or ty == "INTERP_START" or ty == "INTERP_MID" or ty == "INTERP_END" then
        return "text"
    elseif ty == "EOF_T" then
        return "ending"
    elseif PUNCTUATION.contains(ty) then
        return "punct"
    end
    return "operator"
end

func tokenColor(tok)
    return KIND_COLORS[kindOf(tok.type)]
end

func rectOf(x, y, w, h)
    return {x: x, y: y, w: w, h: h}
end

## ── loading a program ────────────────────────────────────────────────────────

func loadProgram(index)
    state.prog = index
    state.name = PROGRAMS[index].name
    state.pos = 0.0
    state.hold = 0.0
    run = trace(PROGRAMS[index].source)

    ## Where each character sits in the text: its line, its column.
    run.lineOf = []
    run.colOf = []
    run.maxCols = 1
    var line = 1
    var col = 0
    for i, c in run.chars do
        if c == string.fromCode(10) then
            col += 1
            run.lineOf[i] = line
            run.colOf[i] = col
            line += 1
            col = 0
        else
            col += 1
            run.lineOf[i] = line
            run.colOf[i] = col
        end
        run.maxCols = math.max(run.maxCols, col + 1)
    end
    run.lines = line

    ## A step lasts longer when it carries more to read, to sweep, or a token to file.
    durations = []
    emitted = []
    var count = 0
    for i, s in run.steps do
        var sweep = math.min(math.abs(s.p1 - s.p0), 14)
        var d = 0.7 + #s.note * 0.008 + sweep * 0.05
        if s.tok then
            d += 0.25
            count += 1
        end
        durations[i] = d
        emitted[i] = count
    end
    stream.key = nil
    noteCache.key = nil
end


## ── the player ───────────────────────────────────────────────────────────────

func current()
    var n = #run.steps
    var i = math.min(math.floor(state.pos) + 1, n)
    var t = math.clamp(state.pos - (i - 1), 0, 1)
    return i, t
end

func stepForward()
    state.playing = false
    state.pos = math.min(math.floor(state.pos + 0.000001) + 1, #run.steps)
end

func stepBack()
    state.playing = false
    state.pos = math.max(math.ceil(state.pos - 0.000001) - 1, 0)
end

func restart()
    state.pos = 0.0
    state.hold = 0.0
end

func onProgram(name)
    for i, p in PROGRAMS do
        if p.name == name then
            loadProgram(i)
        end
    end
end

func setup()
    graphics.canvas(W, H, "How the lexer works")
    for k, v in KEYWORDS do
        keywordTypes[v] = true
    end

    var names = PROGRAMS.map(func(p) return p.name end)
    state.name = names[1]
    var menu = ui.menu("Lexer")
    menu.list("Program", names, ref state.name, onProgram)
    menu.checkbox("Playing", ref state.playing)
    menu.slider("Speed", ref state.speed, 0.5, 4, 1.0)
    menu.button("Step back", stepBack)
    menu.button("Step forward", stepForward)
    menu.button("Restart", restart)
    ui.show(menu)
    ui.close()    ## folded to its handle: the animation has the whole screen

    loadProgram(1)
end

func keyboard.keypressed(key)
    if key == "space" then
        state.playing = not state.playing
    elseif key == "right" then
        stepForward()
    elseif key == "left" then
        stepBack()
    elseif key == "up" then
        state.speed = math.min(state.speed * 1.5, 4)
    elseif key == "down" then
        state.speed = math.max(state.speed / 1.5, 0.5)
    elseif key == "r" then
        restart()
    else
        var n = string.number(key)
        if n and n >= 1 and n <= #PROGRAMS then
            loadProgram(n)
        end
    end
end

func mouse.pressed(x, y)
    state.playing = not state.playing
end

func update(dt)
    var n = #run.steps
    if not state.playing then
        return
    end
    var budget = dt * state.speed
    while budget > 0 and state.pos < n do
        var i = math.floor(state.pos) + 1
        var left = (i - state.pos) * durations[i]
        if budget >= left then
            state.pos = i
            budget -= left
        else
            state.pos += budget / durations[i]
            budget = 0
        end
    end
    if state.pos >= n then
        ## the end of a program: a pause to take it in, then on to the next one
        state.hold += dt
        if state.hold > 3 then
            loadProgram(state.prog % #PROGRAMS + 1)
        end
    end
end

## ── drawing helpers ──────────────────────────────────────────────────────────

func box(x, y, w, h, radius, color)
    graphics.noStroke()
    graphics.fill(color)
    graphics.rect(x, y, w, h, radius)
end

func label(value, x, y, color)
    graphics.stroke(color)
    graphics.text(value, x, y)
end

func panel(r, title)
    var pad = SIZE * 0.016
    graphics.fill(PANEL)
    graphics.stroke(EDGE, 1.5)
    graphics.rect(r.x, r.y, r.w, r.h, SIZE * 0.014)
    graphics.font("sans")
    graphics.fontSize(clampSize(SIZE * 0.02))
    label(title, r.x + pad, r.y + pad * 0.7, DIM)
end

func clampSize(size)
    return math.max(size, 9)
end

## The height reserved for a panel's title.
func titleHeight()
    return SIZE * 0.016 * 0.7 + clampSize(SIZE * 0.02) + SIZE * 0.012
end

func computeLayout()
    var m = SIZE * 0.025
    var top = m + SIZE * 0.1
    var availH = H - top - SIZE * 0.045 - m
    ## the source panel is as tall as its lines need, and no more
    var srcH = math.min(availH * 0.4, titleHeight() + SIZE * 0.045 + run.lines * SIZE * 0.1)
    var L = {m: m}
    if W >= H * 1.1 then
        var lw = (W - 3 * m) * 0.5
        var rw = W - 3 * m - lw
        L.src = rectOf(m, top, lw, srcH)
        L.stream = rectOf(m, top + srcH + m, lw, availH - srcH - m)
        L.code = rectOf(2 * m + lw, top, rw, availH * 0.5)
        L.note = rectOf(2 * m + lw, top + L.code.h + m, rw, availH - L.code.h - m)
    else
        var w = W - 2 * m
        var room = availH - 3 * m - srcH
        L.src = rectOf(m, top, w, srcH)
        L.note = rectOf(m, top + srcH + m, w, room * 0.27)
        L.code = rectOf(m, L.note.y + L.note.h + m, w, room * 0.3)
        L.stream = rectOf(m, L.code.y + L.code.h + m, w, room - L.note.h - L.code.h)
    end
    return L
end

## ── the source ───────────────────────────────────────────────────────────────

func drawSource(r, i, t, s)
    panel(r, "SOURCE")
    var pad = SIZE * 0.02
    var chars = run.chars
    var n = #chars
    graphics.font("mono")
    var availW = r.w - 2 * pad
    var availH = r.h - titleHeight() - pad
    var fs = math.min(availW / (run.maxCols * monoRatio), availH / (run.lines * 1.55), SIZE * 0.07)
    var cw = fs * monoRatio
    var lh = fs * 1.55
    var ox = r.x + pad
    var oy = r.y + titleHeight() + pad * 0.3

    ## the read head, sweeping from where the step began to where it ends
    var head = lerp(s.p0, s.p1, ease(math.clamp(t / 0.6, 0, 1)))
    var lo = s.from or s.p1

    ## the lexeme under construction: grey when it is thrown away, in its own colour when it
    ## becomes a token, red when the lexer gives up
    var tint = Color(0.45, 0.65, 1.0, 0.30)
    if s.err then
        tint = Color(1.0, 0.35, 0.35, 0.40)
    elseif s.drop then
        tint = Color(0.6, 0.62, 0.7, 0.30)
    elseif s.tok then
        var c = tokenColor(s.tok)
        tint = Color(c.r, c.g, c.b, 0.12 + 0.28 * ease(math.clamp((t - 0.4) / 0.4, 0, 1)))
    end
    if s.from then
        for idx = s.from, math.min(math.ceil(head) - 1, n) do
            var x = ox + (run.colOf[idx] - 1) * cw
            var y = oy + (run.lineOf[idx] - 1) * lh
            var w = cw
            if idx + 1 > head then
                w = cw * (head - idx)
            end
            box(x, y, w, lh * 0.92, fs * 0.12, tint)
        end
    end

    ## the tokens already cut, underlined in their colour
    var before = 0
    if i > 1 then
        before = emitted[i - 1]
    end
    var shown = before
    if s.tok and t >= 0.5 then
        shown += 1
    end
    for k = 1, shown do
        var tok = run.tokens[k]
        if tok.from and tok.type <> "INTERP_START" and tok.type <> "INTERP_MID" then
            var c = tokenColor(tok)
            var x = ox + (run.colOf[tok.from] - 1) * cw
            var y = oy + (run.lineOf[tok.from] - 1) * lh + lh * 0.9 + tok.depth * fs * 0.1
            var alpha = 1.0
            if k > before then
                alpha = ease(math.clamp((t - 0.5) / 0.3, 0, 1))
            end
            box(x + cw * 0.05, y, (tok.to - tok.from) * cw - cw * 0.1, math.max(fs * 0.07, 2), 1,
                Color(c.r, c.g, c.b, alpha))
        end
    end

    ## the text itself: what is behind the lexeme is dimmed, what is ahead stays bright
    graphics.fontSize(fs)
    for idx, c in chars do
        if c <> string.fromCode(10) then
            var ink = TEXT
            if idx < lo then
                ink = PROCESSED
            end
            label(c, ox + (run.colOf[idx] - 1) * cw, oy + (run.lineOf[idx] - 1) * lh, ink)
        end
    end

    ## the caret: where the next character will be read
    var at = math.min(math.floor(head), n)
    var frac = head - math.floor(head)
    var cx = ox + (run.colOf[at] - 1) * cw + frac * cw
    if head >= n + 1 then
        cx = ox + run.colOf[n] * cw
        at = n
    end
    var cy = oy + (run.lineOf[at] - 1) * lh
    box(cx - fs * 0.05, cy - fs * 0.04, math.max(fs * 0.11, 2), lh * 0.95, 1, CARET)
    box(cx - fs * 0.16, cy - fs * 0.12, fs * 0.38, fs * 0.1, 1, CARET)

    return {ox: ox, oy: oy, cw: cw, lh: lh}
end

## ── the stream of tokens ─────────────────────────────────────────────────────

func tokenLabel(tok)
    if tok.type == "EOF_T" then
        return "end"
    elseif tok.lexeme == "" then
        return "-"
    elseif #tok.lexeme > 12 then
        return tok.lexeme.substr(1, 11) + "~"
    end
    return tok.lexeme
end

## Where every chip sits in the stream, computed once per size and program: a chip never moves when
## a new one arrives.
func chipLayout(r)
    var key = "{W}x{H}/{state.prog}"
    if stream.key == key then
        return stream
    end
    var pad = SIZE * 0.02
    var fs = math.min(SIZE * 0.032, r.w / 24)
    var tfs = fs * 0.7
    var chips = []
    var x = 0
    var y = 0
    var rowH = fs + tfs + SIZE * 0.03
    var availW = r.w - 2 * pad
    graphics.font("mono")
    for k, tok in run.tokens do
        graphics.fontSize(fs)
        var w1 = graphics.textSize(tokenLabel(tok))
        graphics.fontSize(tfs)
        var w2 = graphics.textSize(tok.type)
        var w = math.max(w1, w2) + SIZE * 0.022
        if x > 0 and x + w > availW then
            x = 0
            y += rowH + SIZE * 0.012
        end
        chips[k] = {x: x, y: y, w: w, h: rowH, row: y}
        x += w + SIZE * 0.012
    end
    stream.key = key
    stream.chips = chips
    stream.fs = fs
    stream.tfs = tfs
    stream.rowH = rowH
    stream.pad = pad
    stream.height = y + rowH
    return stream
end

func drawChip(chip, tok, x, y, alpha, fs, tfs)
    var c = tokenColor(tok)
    graphics.fill(Color(c.r, c.g, c.b, 0.16 * alpha))
    graphics.stroke(Color(c.r, c.g, c.b, alpha), 1.5)
    graphics.rect(x, y, chip.w, chip.h, SIZE * 0.01)
    graphics.font("mono")
    graphics.textMode("center", "top")
    graphics.fontSize(tfs)
    label(tok.type, x + chip.w / 2, y + SIZE * 0.008, Color(c.r, c.g, c.b, alpha))
    graphics.fontSize(fs)
    label(tokenLabel(tok), x + chip.w / 2, y + SIZE * 0.008 + tfs * 1.35, Color(TEXT.r, TEXT.g, TEXT.b, alpha))
    graphics.textMode("left", "top")
end

func drawStream(r, i, t, s, srcInfo)
    panel(r, "TOKENS FOR THE PARSER")
    var L = chipLayout(r)
    var before = 0
    if i > 1 then
        before = emitted[i - 1]
    end
    var total = before
    if s.tok then
        total += 1
    end
    if total == 0 then
        return
    end
    ## scrolls so that the newest row stays in view
    var top = r.y + titleHeight()
    var room = r.h - titleHeight() - L.pad * 0.5
    var scroll = math.max(0, L.chips[total].row + L.rowH - room)
    for k = 1, total do
        var chip = L.chips[k]
        var x = r.x + L.pad + chip.x
        var y = top + chip.row - scroll
        if y >= top - 1 and y + chip.h <= top + room + 1 then
            if k <= before then
                drawChip(chip, run.tokens[k], x, y, 1.0, L.fs, L.tfs)
            else
                ## the new token flies in from the text it was cut from
                var u = ease(math.clamp((t - 0.5) / 0.5, 0, 1))
                if u > 0 then
                    var tok = run.tokens[k]
                    var sx = srcInfo.ox + (run.colOf[tok.from or 1] - 1) * srcInfo.cw - chip.w / 2
                    var sy = srcInfo.oy + (run.lineOf[tok.from or 1] - 1) * srcInfo.lh
                    drawChip(chip, tok, lerp(sx, x, u), lerp(sy, y, u), u, L.fs, L.tfs)
                end
            end
        end
    end
end

## ── the code of lexer.cpp ────────────────────────────────────────────────────

func drawCode(r, s)
    var ex = EXCERPTS[s.fn]
    panel(r, "src/lexer.cpp  -  " + ex.title)
    var pad = SIZE * 0.02
    var total = #ex.lines
    var widest = 1
    for l in ex.lines do
        widest = math.max(widest, #l)
    end
    graphics.font("mono")
    var fs = math.min((r.w - 2 * pad) / (widest * monoRatio), SIZE * 0.03)
    fs = math.max(fs, 7)
    var lh = fs * 1.55
    var rows = math.max(math.floor((r.h - titleHeight() - pad) / lh), 1)
    var first = math.clamp(s.at - math.floor(rows / 2), 1, math.max(total - rows + 1, 1))
    var y = r.y + titleHeight() + pad * 0.3
    graphics.fontSize(fs)
    for j = first, math.min(total, first + rows - 1) do
        if j == s.at then
            box(r.x + pad * 0.5, y - lh * 0.1, r.w - pad, lh, fs * 0.2, Color(1.0, 0.84, 0.30, 0.20))
            box(r.x + pad * 0.5, y - lh * 0.1, fs * 0.2, lh, 1, CARET)
            label(ex.lines[j], r.x + pad, y, TEXT)
        else
            label(ex.lines[j], r.x + pad, y, DIM)
        end
        y += lh
    end
end

## ── the explanation ──────────────────────────────────────────────────────────

## Cuts a text into lines no wider than `width`, at the current font and size.
func wrap(text, width)
    var lines = []
    var current = ""
    for word in text.split(" ") do
        var trial = word
        if current <> "" then
            trial = current + " " + word
        end
        if current <> "" and graphics.textSize(trial) > width then
            lines.push(current)
            current = word
        else
            current = trial
        end
    end
    if current <> "" then
        lines.push(current)
    end
    return lines
end

func drawNote(r, s, i)
    panel(r, "WHAT HAPPENS")
    var pad = SIZE * 0.02
    var width = r.w - 2 * pad
    var avail = r.h - titleHeight() - pad
    var key = "{state.prog}/{i}/{W}x{H}"
    if noteCache.key <> key then
        ## when the lexer gives up, the sentence is followed by the message it would print
        var parts = [{text: s.note, ink: TEXT}]
        if s.err then
            parts.push({text: "Error on line {s.line}: {s.err}. The lexer stops here: the parser never sees a token after this point.",
                        ink: ERROR})
        end
        var fs = math.max(math.min(SIZE * 0.034, 26), 11)
        graphics.font("sans")
        var lines = []
        while true do
            graphics.fontSize(fs)
            lines = []
            for part in parts do
                for l in wrap(part.text, width) do
                    lines.push({text: l, ink: part.ink})
                end
            end
            if #lines * fs * 1.4 <= avail or fs <= 8 then
                break
            end
            fs *= 0.92
        end
        noteCache.key = key
        noteCache.lines = lines
        noteCache.size = fs
    end
    graphics.font("sans")
    graphics.fontSize(noteCache.size)
    var y = r.y + titleHeight() + pad * 0.2
    for l in noteCache.lines do
        label(l.text, r.x + pad, y, l.ink)
        y += noteCache.size * 1.4
    end
end

## ── the whole frame ──────────────────────────────────────────────────────────

func drawHeader(L)
    var n = #run.steps
    graphics.font("sans")
    graphics.fontSize(math.max(SIZE * 0.05, 14))
    label("Inside the lexer", L.m, L.m * 0.8, TEXT)
    ## the program and what it teaches, shrunk to leave the right end to the menu's handle
    var text = PROGRAMS[state.prog].name + "  -  " + LESSONS[state.prog]
    var fs = math.max(SIZE * 0.026, 10)
    graphics.fontSize(fs)
    var room = W - 2 * L.m - SIZE * 0.2
    var w = graphics.textSize(text)
    if w > room then
        fs = fs * room / w
        graphics.fontSize(fs)
        if fs < 9 then
            text = PROGRAMS[state.prog].name   ## too long for a narrow screen: the lesson is left out
            fs = math.max(SIZE * 0.026, 10)
            graphics.fontSize(fs)
        end
    end
    label(text, L.m, L.m * 0.8 + SIZE * 0.065, DIM)
    ## progress
    var barY = L.m + SIZE * 0.1 - SIZE * 0.012
    box(L.m, barY, W - 2 * L.m, SIZE * 0.006, 2, EDGE)
    box(L.m, barY, (W - 2 * L.m) * state.pos / n, SIZE * 0.006, 2, CARET)
end

func draw()
    graphics.clear(BG)
    if monoRatio == nil then
        graphics.font("mono")
        graphics.fontSize(100)
        monoRatio = graphics.textSize("M") / 100
    end
    var L = computeLayout()
    var i, t = current()
    var s = run.steps[i]
    drawHeader(L)
    var info = drawSource(L.src, i, t, s)
    drawStream(L.stream, i, t, s, info)
    drawCode(L.code, s)
    drawNote(L.note, s, i)
    var status = "step {i} / {#run.steps}"
    if not state.playing then
        status += "  (paused)"
    end
    graphics.font("sans")
    graphics.fontSize(math.max(SIZE * 0.02, 9))
    label(status, L.m, H - SIZE * 0.04, TEXT)
    ## the keys when they fit beside the status, else the gesture a finger has
    var hint = "space: play/pause   left/right: step   up/down: speed   1-4: program   r: restart"
    ## the right corner belongs to the memory and frame counter the engine draws
    var edge = W - L.m - SIZE * 0.2
    if graphics.textSize(hint) > edge - L.m - graphics.textSize(status) - SIZE * 0.05 then
        hint = "tap: play/pause   menu: more"
    end
    graphics.textMode("right", "top")
    label(hint, edge, H - SIZE * 0.04, DIM)
    graphics.textMode("left", "top")
end
