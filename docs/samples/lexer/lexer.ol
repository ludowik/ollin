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
## The player, the keys and the buttons are those of lib/stage.ol, where they are described. Here, 1 to 4
## pick a program.

import "../lib/stage.ol"
import "tracer.ol"
import "programs.ol"

global stream = {prog: 0, w: 0, h: 0, chips: []}              ## the chips, laid out for one size

## ── loading a program ────────────────────────────────────────────────────────

## A line takes a moment; a token to file, or a sentence to read, takes longer. Paced by hand, every
## line takes the same short time, a token a little longer.
func paceOf(st)
    var dur = 0.2
    var hand = 0.2
    if st.p1 <> st.p0 then
        dur += 0.06
    end
    if st.tok then
        dur += 0.45
        hand = 0.5
    end
    return dur, hand
end

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

    var count = 0
    for st in r.steps do
        st.before = count    ## the tokens filed before this step
        if st.tok then
            count += 1
        end
    end
    prepareSteps(r, paceOf)
    return r
end

## When the lexer gives up, the sentence is followed by the message it would print.
func errorNote(s)
    return "Error on line {s.line}: {s.err}. The lexer stops here: the parser never sees a token after this point."
end

func computeLayout()
    var L = baseLayout()
    var m = L.m
    var top = L.top
    var availH = L.availH
    ## the source panel is as tall as its lines need, and no more
    var srcH = math.min(availH * 0.4, titleHeight() + SIZE * 0.045 + run.lines * SIZE * 0.1)
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

func setup()
    stage.title = "Inside the lexer"
    stage.menu = "Lexer"
    stage.programs = PROGRAMS
    stage.lessons = LESSONS
    stage.build = buildRun
    stage.cpp = CPP
    stage.file = "src/lexer.cpp"
    stage.owner = "Lexer"
    stage.watch = watchLine
    stage.errorNote = errorNote
    graphics.canvas(W, H, "How the lexer works")
    keywordTypes = KEYWORD_TYPES
    openMenu()
    loadProgram(1)
end

func draw()
    beginFrame()
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
