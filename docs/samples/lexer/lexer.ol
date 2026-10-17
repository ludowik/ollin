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
## lexeme being built. The panel on the right shows the engine's own code, copied verbatim from
## src/lexer.cpp into cpp_source.ol, and the bar in it is the line the lexer is running: it moves
## from line to line as the program does, goes down into identifier(), number()... when they are
## called, and comes back to the line that called them. Each token that comes out is filed in the
## stream below, and the program's text is underlined in the colour of the token it became.
##
## It plays by itself, and a tap pauses and resumes it. STEP BY STEP is the other way to read it:
## nothing moves until you ask, and every tap (or the Next button, or the right arrow) runs the
## next line of the lexer, Back (or the left arrow) goes back one. The Step button, the S key and
## the menu switch the mode on and off; Play leaves it.
##
## Keys: space plays and pauses, s steps by tap, left/right go back and forward one line, up/down
## change the speed, 1 to 4 pick a program, r restarts. F7, F8 and F9 stand for the Apple keyboard's
## previous, play/pause and next keys (with fn, unless the system uses F-keys as standard). The menu
## and the buttons at the bottom do the same with a finger.

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

const CODE_INK = Color(0.80, 0.83, 0.92)
const CARET_FILL = Color(CARET.r, CARET.g, CARET.b, 0.22)   ## the line the lexer is on, a button that is on
const ALSO_FILL = Color(0.6, 0.7, 1.0, 0.12)                ## the `case` label the switch went through
const MIN_SPEED = 0.25
const MAX_SPEED = 8
const CODE_LEADING = 1.55    ## the height of a line of code, in font sizes
const NOTE_LEADING = 1.4

const PUNCTUATION = ["COMMA", "LPAREN", "RPAREN", "LBRACE", "RBRACE", "LBRACKET", "RBRACKET", "COLON",
                     "SEMICOLON", "DOT", "DOT_DOT_DOT", "QUESTION"]

global state = {pos: 0.0, playing: true, stepping: false, goal: 0.0, speed: 1.0, prog: 1, name: nil, hold: 0.0}
global run = nil          ## the trace of the program on show
global loaded = {}        ## the traces already made, by program: a trace never changes
global hits = []          ## the buttons drawn at the bottom, for the taps
global keywordTypes = {}
global monoRatio = nil    ## the width of a monospaced character, per pixel of font size
global stream = {prog: 0, w: 0, h: 0, chips: []}              ## the chips, laid out for one size
global noteCache = {prog: 0, id: 0, w: 0, h: 0, lines: [], size: 0}   ## the sentence, wrapped for one size
global codeCache = {}

func lerp(a, b, t)
    return a + (b - a) * t
end

func ease(t)
    return t * t * (3 - 2 * t)
end

## 0 until `from`, 1 from `to`, eased in between.
func ramp(t, from, to)
    return ease(math.clamp((t - from) / (to - from), 0, 1))
end

func fade(c, alpha)
    return Color(c.r, c.g, c.b, alpha)
end

## A text cut to `max` characters, with a "~" where it was cut.
func clip(text, max)
    if #text > max then
        return text.substr(1, max - 1) + "~"
    end
    return text
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
    if tok.color == nil then
        tok.color = KIND_COLORS[kindOf(tok.type)]
    end
    return tok.color
end

func rectOf(x, y, w, h)
    return {x: x, y: y, w: w, h: h}
end

## ── loading a program ────────────────────────────────────────────────────────

## The trace of a program and what the view needs to know about each step.
func buildRun(index)
    var r = trace(PROGRAMS[index].source)

    ## Where each character sits in the text: its line, its column.
    r.lineOf = []
    r.colOf = []
    r.maxCols = 1
    var line = 1
    var col = 0
    for i, c in r.chars do
        col += 1
        r.lineOf[i] = line
        r.colOf[i] = col
        if c == NEWLINE then
            line += 1
            col = 0
        end
        r.maxCols = math.max(r.maxCols, col + 1)
    end
    r.lines = line

    ## A line takes a moment; a token to file, or a sentence to read, takes longer. Paced by hand,
    ## every line takes the same short time, a token a little longer.
    var count = 0
    var said = ""
    var noteId = 0
    for st in r.steps do
        st.before = count    ## the tokens filed before this step
        st.dur = 0.2
        st.hand = 0.2
        if st.p1 <> st.p0 then
            st.dur += 0.06
        end
        if st.tok then
            st.dur += 0.45
            st.hand = 0.5
            count += 1
        end
        if st.note or st.err then
            noteId += 1
        end
        if st.note then
            said = st.note
            st.dur += 0.3 + #st.note * 0.006
        end
        st.said = said       ## the last sentence said up to this step
        st.noteId = noteId   ## which sentence it is, to wrap it once
    end
    return r
end

func loadProgram(index)
    if loaded[index] == nil then
        loaded[index] = buildRun(index)
    end
    run = loaded[index]
    state.prog = index
    state.name = PROGRAMS[index].name
    restart()
end

## ── the player ───────────────────────────────────────────────────────────────

func current()
    var n = #run.steps
    var i = math.min(math.floor(state.pos) + 1, n)
    var t = math.clamp(state.pos - (i - 1), 0, 1)
    return i, t
end

## Step by step: nothing moves by itself, and `goal` is how far the next taps have asked it to go.
func setStepping(on)
    state.stepping = on
    if on then
        state.playing = false
        state.goal = state.pos
    else
        state.playing = true
        state.hold = 0.0
    end
end

func onPlaying(on)
    if on and state.stepping then
        setStepping(false)
    end
end

func togglePlay()
    if state.stepping then
        setStepping(false)
    else
        state.playing = not state.playing
    end
end

## Runs the line that is under way to its end, or the next one when it is done.
func stepForward()
    if not state.stepping then
        setStepping(true)
    end
    state.goal = math.min(math.floor(state.goal + 0.000001) + 1, #run.steps)
end

func stepBack()
    if not state.stepping then
        setStepping(true)
    end
    state.goal = math.max(math.ceil(state.goal - 0.000001) - 1, 0)
    state.pos = state.goal
end

func restart()
    state.pos = 0.0
    state.goal = 0.0
    state.hold = 0.0
end

func toggleStepping()
    setStepping(not state.stepping)
end

## What a button does, and what a key stands for.
const ACTIONS = {play: togglePlay, step: toggleStepping, back: stepBack, next: stepForward, restart: restart}
const KEYS = {space: "play", f8: "play", s: "step", left: "back", f7: "back", right: "next", f9: "next", r: "restart"}

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
    menu.checkbox("Playing", ref state.playing, onPlaying)
    menu.checkbox("Step by step", ref state.stepping, setStepping)
    menu.slider("Speed", ref state.speed, MIN_SPEED, MAX_SPEED, 1.0)
    menu.button("Back", stepBack)
    menu.button("Next", stepForward)
    menu.button("Restart", restart)
    ui.show(menu)
    ui.close()    ## folded to its handle: the animation has the whole screen

    loadProgram(1)
end

func keyboard.keypressed(key)
    if KEYS.has(key) then
        ACTIONS[KEYS[key]]()
    elseif key == "up" then
        state.speed = math.min(state.speed * 1.5, MAX_SPEED)
    elseif key == "down" then
        state.speed = math.max(state.speed / 1.5, MIN_SPEED)
    else
        var n = string.number(key)
        if n and n >= 1 and n <= #PROGRAMS then
            loadProgram(n)
        end
    end
end

func hitAt(x, y)
    for h in hits do
        if x >= h.x and x <= h.x + h.w and y >= h.y and y <= h.y + h.h then
            return h.id
        end
    end
    return nil
end

## A tap anywhere else pauses and resumes, or in step by step runs the next line.
func tap()
    if state.stepping then
        stepForward()
    else
        togglePlay()
    end
end

func tapHint()
    if state.stepping then
        return "tap: next line"
    elseif state.playing then
        return "tap: pause"
    end
    return "tap: play"
end

func mouse.pressed(x, y)
    var id = hitAt(x, y)
    if id then
        ACTIONS[id]()
    else
        tap()
    end
end

## Moves the program forward by `budget` seconds, not beyond `limit`. When it is paced by hand
## every line takes the same short time, a token a little longer.
func advance(budget, limit, byHand)
    while budget > 0 and state.pos < limit do
        var i = math.floor(state.pos) + 1
        var d = run.steps[i].dur
        if byHand then
            d = run.steps[i].hand
        end
        var stop = math.min(i, limit)
        var left = (stop - state.pos) * d
        if budget >= left then
            state.pos = stop
            budget -= left
        else
            state.pos += budget / d
            budget = 0
        end
    end
end

func update(dt)
    if state.stepping then
        advance(dt, state.goal, true)
        return
    end
    if not state.playing then
        return
    end
    advance(dt * state.speed, #run.steps, false)
    if state.pos >= #run.steps then
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

## Where the title of a panel sits, and the height it takes: the content starts below it.
func titleTop()
    return SIZE * 0.016 * 0.7
end

func titleHeight()
    return titleTop() + clampSize(SIZE * 0.02) + SIZE * 0.012
end

func panel(r, title)
    graphics.fill(PANEL)
    graphics.stroke(EDGE, 1.5)
    graphics.rect(r.x, r.y, r.w, r.h, SIZE * 0.014)
    graphics.font("sans")
    graphics.fontSize(clampSize(SIZE * 0.02))
    label(title, r.x + SIZE * 0.016, r.y + titleTop(), DIM)
end

func clampSize(size)
    return math.max(size, 9)
end

func computeLayout()
    var m = SIZE * 0.025
    var top = m + SIZE * 0.1
    var footH = math.max(SIZE * 0.075, 38)
    var availH = H - top - footH - SIZE * 0.06 - m
    ## the source panel is as tall as its lines need, and no more
    var srcH = math.min(availH * 0.4, titleHeight() + SIZE * 0.045 + run.lines * SIZE * 0.1)
    ## the strip under the buttons belongs to the memory and frame counter the engine draws
    var L = {m: m, footH: footH, footY: H - footH - SIZE * 0.06}
    if W >= H * 1.1 then
        var lw = (W - 3 * m) * 0.38
        var rw = W - 3 * m - lw
        L.src = rectOf(m, top, lw, srcH)
        L.stream = rectOf(m, top + srcH + m, lw, availH - srcH - m)
        L.code = rectOf(2 * m + lw, top, rw, availH * 0.76)
        L.note = rectOf(2 * m + lw, top + L.code.h + m, rw, availH - L.code.h - m)
    else
        var w = W - 2 * m
        var room = availH - 3 * m - srcH
        L.src = rectOf(m, top, w, srcH)
        L.code = rectOf(m, top + srcH + m, w, room * 0.5)
        L.note = rectOf(m, L.code.y + L.code.h + m, w, room * 0.14)
        L.stream = rectOf(m, L.note.y + L.note.h + m, w, room - L.code.h - L.note.h)
    end
    return L
end

## ── the source ───────────────────────────────────────────────────────────────

func drawSource(r, t, s)
    panel(r, "SOURCE")
    var pad = SIZE * 0.02
    var chars = run.chars
    var n = #chars
    graphics.font("mono")
    var availW = r.w - 2 * pad
    var availH = r.h - titleHeight() - pad
    var fs = math.min(availW / (run.maxCols * monoRatio), availH / (run.lines * CODE_LEADING), SIZE * 0.07)
    var cw = fs * monoRatio
    var lh = fs * CODE_LEADING
    var ox = r.x + pad
    var oy = r.y + titleHeight() + pad * 0.3

    ## the read head, sweeping from where the step began to where it ends
    var head = lerp(s.p0, s.p1, ramp(t, 0, 0.8))
    var upto = s.hl or head
    var lo = s.from or s.p1

    ## the lexeme under construction: grey when it is thrown away, in its own colour when it
    ## becomes a token, red when the lexer gives up
    var tint = Color(0.45, 0.65, 1.0, 0.30)
    if s.err then
        tint = Color(1.0, 0.35, 0.35, 0.40)
    elseif s.drop then
        tint = Color(0.6, 0.62, 0.7, 0.30)
    elseif s.made then
        tint = fade(tokenColor(s.made), 0.12 + 0.28 * ramp(t, 0.4, 0.8))
    end
    if s.from then
        for idx = s.from, math.min(math.ceil(upto) - 1, n) do
            var x = ox + (run.colOf[idx] - 1) * cw
            var y = oy + (run.lineOf[idx] - 1) * lh
            var w = cw
            if idx + 1 > upto then
                w = cw * (upto - idx)
            end
            box(x, y, w, lh * 0.92, fs * 0.12, tint)
        end
    end

    ## the tokens already cut, underlined in their colour
    var before = s.before
    var shown = before
    if s.tok and t >= 0.5 then
        shown += 1
    end
    for k = 1, shown do
        var tok = run.tokens[k]
        if tok.from and tok.type <> "INTERP_START" and tok.type <> "INTERP_MID" then
            var x = ox + (run.colOf[tok.from] - 1) * cw
            var y = oy + (run.lineOf[tok.from] - 1) * lh + lh * 0.9 + tok.depth * fs * 0.1
            var alpha = 1.0
            if k > before then
                alpha = ramp(t, 0.5, 0.8)
            end
            box(x + cw * 0.05, y, (tok.to - tok.from) * cw - cw * 0.1, math.max(fs * 0.07, 2), 1,
                fade(tokenColor(tok), alpha))
        end
    end

    ## the text itself: what is behind the lexeme is dimmed, what is ahead stays bright
    graphics.fontSize(fs)
    for idx, c in chars do
        if c <> NEWLINE then
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
    if tok.label == nil then
        if tok.type == "EOF_T" then
            tok.label = "end"
        elseif tok.lexeme == "" then
            tok.label = "-"
        else
            tok.label = clip(tok.lexeme, 12)
        end
    end
    return tok.label
end

## Where every chip sits in the stream, computed once per size and program: a chip never moves when
## a new one arrives.
func chipLayout(r)
    if stream.prog == state.prog and stream.w == W and stream.h == H then
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
        chips[k] = {x: x, y: y, w: w, h: rowH}
        x += w + SIZE * 0.012
    end
    stream = {prog: state.prog, w: W, h: H, chips: chips, fs: fs, tfs: tfs, rowH: rowH, pad: pad}
    return stream
end

func drawChip(chip, tok, x, y, alpha, fs, tfs)
    var c = tokenColor(tok)
    graphics.fill(fade(c, 0.16 * alpha))
    graphics.stroke(fade(c, alpha), 1.5)
    graphics.rect(x, y, chip.w, chip.h, SIZE * 0.01)
    graphics.font("mono")
    graphics.textMode("center", "top")
    graphics.fontSize(tfs)
    label(tok.type, x + chip.w / 2, y + SIZE * 0.008, fade(c, alpha))
    graphics.fontSize(fs)
    label(tokenLabel(tok), x + chip.w / 2, y + SIZE * 0.008 + tfs * 1.35, fade(TEXT, alpha))
    graphics.textMode("left", "top")
end

func drawStream(r, t, s, srcInfo)
    panel(r, "TOKENS FOR THE PARSER")
    var L = chipLayout(r)
    var before = s.before
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
    var scroll = math.max(0, L.chips[total].y + L.rowH - room)
    for k = 1, total do
        var chip = L.chips[k]
        var x = r.x + L.pad + chip.x
        var y = top + chip.y - scroll
        if y >= top - 1 and y + chip.h <= top + room + 1 then
            if k <= before then
                drawChip(chip, run.tokens[k], x, y, 1.0, L.fs, L.tfs)
            else
                ## the new token flies in from the text it was cut from
                var u = ramp(t, 0.5, 1)
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

const CODE_COLUMNS = 82   ## the columns of a line that are shown; a longer line is cut with a "~"

## What the code panel shows of a function, prepared once: each line cut to the columns that fit,
## whether it is a comment, and its number in lexer.cpp.
func codeLines(fn)
    if not codeCache.has(fn) then
        var listing = CPP[fn]
        var rows = []
        for j, code in listing.lines do
            rows.push({text: clip(code, CODE_COLUMNS), comment: listing.trimmed[j].startsWith("//"),
                       number: "{listing.first + j - 1}"})
        end
        codeCache[fn] = rows
    end
    return codeCache[fn]
end

## The first line of the listing that is on show when the lexer is on `step`: it keeps the line being
## run in the upper part of the panel, and never scrolls past the ends of the function.
func codeTop(step, rows)
    var total = #CPP[step.fn].lines
    var middle = step.at + step.span / 2
    return math.clamp(middle - rows * 0.4, 1, math.max(total - rows + 1, 1))
end

func showChar(c)
    if c == NEWLINE then
        return "\n"
    end
    return c
end

## The locals worth watching, as a debugger would list them.
func watchLine(s)
    var parts = ["pos {s.pos}", "line {s.line}"]
    if s.c then
        parts.push("c = '{showChar(s.c)}'")
    end
    if s.w then
        parts.push(s.w[1] + " = " + QUOTE + clip(s.w[2].replace(NEWLINE, "\n"), 18) + QUOTE)
    end
    return parts.join("   ")
end

func drawCode(r, i, t, s)
    var listing = codeLines(s.fn)
    panel(r, "src/lexer.cpp  -  Lexer::" + s.fn + "()")
    var pad = SIZE * 0.02
    graphics.font("mono")
    var gutter = 5
    var fs = math.max(math.min((r.w - 2 * pad) / ((CODE_COLUMNS + gutter) * monoRatio), SIZE * 0.034), 7)
    var cw = fs * monoRatio
    var lh = fs * CODE_LEADING
    var y0 = r.y + titleHeight()

    ## what is being called, and the locals
    graphics.fontSize(fs)
    label(s.stack, r.x + pad, y0, CARET)
    if s.watch == nil then
        s.watch = watchLine(s)    ## a step never changes
    end
    label(s.watch, r.x + pad, y0 + lh, DIM)
    var top = y0 + lh * 2 + pad * 0.4
    var bottom = r.y + r.h - pad * 0.5
    var rows = math.max(math.floor((bottom - top) / lh), 1)

    ## the view and the bar glide from the previous line to this one, inside the same function
    var e = ease(math.clamp(t / 0.45, 0, 1))
    var first = codeTop(s, rows)
    var barLine = s.at
    var barSpan = s.span
    if i > 1 and run.steps[i - 1].fn == s.fn then
        var before = run.steps[i - 1]
        first = lerp(codeTop(before, rows), first, e)
        barLine = lerp(before.at, s.at, e)
        barSpan = lerp(before.span, s.span, e)
    end

    var barY = top + (barLine - first) * lh
    if barY >= top - 1 and barY + lh * (1 + barSpan) <= bottom + 1 then
        box(r.x + pad * 0.5, barY - lh * 0.08, r.w - pad, lh * (1 + barSpan), fs * 0.2, CARET_FILL)
        box(r.x + pad * 0.5, barY - lh * 0.08, fs * 0.22, lh * (1 + barSpan), 1, CARET)
    end
    if s.also then
        var y = top + (s.also - first) * lh
        if y >= top - 1 and y + lh <= bottom + 1 then
            box(r.x + pad * 0.5, y - lh * 0.08, r.w - pad, lh, fs * 0.2, ALSO_FILL)
        end
    end

    for j = math.floor(first), math.ceil(first) + rows do
        var y = top + (j - first) * lh
        if j >= 1 and j <= #listing and y >= top - 1 and y + lh <= bottom + 1 then
            var row = listing[j]
            var active = j >= s.at and j <= s.at + s.span
            var ink = CODE_INK
            if active then
                ink = TEXT
            elseif row.comment then
                ink = PROCESSED
            end
            label(row.number, r.x + pad + (4 - #row.number) * cw, y, active and CARET or PROCESSED)
            label(row.text, r.x + pad + gutter * cw, y, ink)
        end
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

func drawNote(r, s)
    panel(r, "WHAT HAPPENS")
    var pad = SIZE * 0.02
    var width = r.w - 2 * pad
    var avail = r.h - titleHeight() - pad
    if noteCache.prog <> state.prog or noteCache.id <> s.noteId or noteCache.w <> W or noteCache.h <> H then
        ## when the lexer gives up, the sentence is followed by the message it would print
        var parts = [{text: s.said, ink: TEXT}]
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
            if #lines * fs * NOTE_LEADING <= avail or fs <= 8 then
                break
            end
            fs *= 0.92
        end
        noteCache = {prog: state.prog, id: s.noteId, w: W, h: H, lines: lines, size: fs}
    end
    graphics.font("sans")
    graphics.fontSize(noteCache.size)
    var y = r.y + titleHeight() + pad * 0.2
    for l in noteCache.lines do
        label(l.text, r.x + pad, y, l.ink)
        y += noteCache.size * NOTE_LEADING
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
    var base = math.max(SIZE * 0.026, 10)
    var fs = base
    graphics.fontSize(fs)
    var room = W - 2 * L.m - SIZE * 0.2
    var w = graphics.textSize(text)
    if w > room then
        fs = fs * room / w
        graphics.fontSize(fs)
        if fs < 9 then
            text = PROGRAMS[state.prog].name   ## too long for a narrow screen: the lesson is left out
            graphics.fontSize(base)
        end
    end
    label(text, L.m, L.m * 0.8 + SIZE * 0.065, DIM)
    ## progress
    var barY = L.m + SIZE * 0.1 - SIZE * 0.012
    box(L.m, barY, W - 2 * L.m, SIZE * 0.006, 2, EDGE)
    box(L.m, barY, (W - 2 * L.m) * state.pos / n, SIZE * 0.006, 2, CARET)
end

func drawFooter(L, i)
    hits = []
    var gap = L.m * 0.6
    var bw = math.clamp((W - 2 * L.m - 4 * gap) / 5, 60, SIZE * 0.2)
    var buttons = [{id: "play", text: state.playing and "Pause" or "Play", on: false}, {id: "step", text: "Step", on: state.stepping},
                   {id: "back", text: "Back", on: false}, {id: "next", text: "Next", on: false},
                   {id: "restart", text: "Restart", on: false}]
    graphics.font("sans")
    var fs = math.clamp(SIZE * 0.028, 11, 22)
    for k, b in buttons do
        var x = L.m + (k - 1) * (bw + gap)
        if b.on then
            graphics.fill(CARET_FILL)
            graphics.stroke(CARET, 2)
        else
            graphics.fill(PANEL)
            graphics.stroke(EDGE, 1.5)
        end
        graphics.rect(x, L.footY, bw, L.footH, SIZE * 0.012)
        graphics.fontSize(fs)
        graphics.textMode("center", "center")
        label(b.text, x + bw / 2, L.footY + L.footH / 2, TEXT)
        hits.push({id: b.id, x: x, y: L.footY, w: bw, h: L.footH})
    end
    graphics.textMode("left", "top")

    ## under the buttons: where the program is, and what a tap does. The right of that strip belongs to
    ## the memory and frame counter the engine draws.
    graphics.fontSize(math.max(fs * 0.85, 10))
    label("step {i} / {#run.steps}   -   {tapHint()}", L.m, L.footY + L.footH + SIZE * 0.012, DIM)
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
    var info = drawSource(L.src, t, s)
    drawStream(L.stream, t, s, info)
    drawCode(L.code, i, t, s)
    drawNote(L.note, s)
    drawFooter(L, i)
end
