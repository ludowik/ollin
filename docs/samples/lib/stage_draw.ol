## What the stage looks like: the palette, the colours of the tokens, and the panels, the chips, the code, the note, the header and
## the buttons that stage.ol puts on the screen.

import "draw.ol"
import "area.ol"

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
const CARET_FILL = Color(CARET.r, CARET.g, CARET.b, 0.22)   ## the line the engine is on, a button that is on
const ALSO_FILL = Color(0.6, 0.7, 1.0, 0.12)                ## the `case` label the switch went through
const CODE_LEADING = 1.55    ## the height of a line of code, in font sizes
const NOTE_LEADING = 1.4
const CODE_GUTTER = 5        ## the columns the line numbers take, in characters
const MIN_CODE_FONT = 10     ## the smallest code a narrow screen is given, in pixels
const MIN_CHIP_TYPE_FONT = 8.5   ## the smallest name of a token type on a chip

const PUNCTUATION = ["COMMA", "LPAREN", "RPAREN", "LBRACE", "RBRACE", "LBRACKET", "RBRACKET", "COLON",
                     "SEMICOLON", "DOT", "DOT_DOT_DOT", "QUESTION"]

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

## The end of a text, cut to `max` characters, with a "~" where its beginning was cut.
func clipLeft(text, max)
    if #text > max then
        return "~" + text.substr(#text - max + 2, max - 1)
    end
    return text
end

func kindOf(ty)
    if stage.keywords[ty] then
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

## The room the example's panels share: the margin, the strip of buttons at the bottom (the strip
## under it belongs to the memory and frame counter the engine draws), and the height between the
## header and the buttons.
func baseLayout()
    var m = SIZE * 0.025
    var top = m + SIZE * 0.1
    var footH = math.max(SIZE * 0.075, 38)
    return {m: m, top: top, footH: footH, footY: H - footH - SIZE * 0.06, availH: H - top - footH - SIZE * 0.06 - m}
end

func beginFrame()
    graphics.clear(BG)
    if monoRatio == nil then
        graphics.font("mono")
        graphics.fontSize(100)
        monoRatio = graphics.textSize("M") / 100
    end
end

## ── a token as a chip ────────────────────────────────────────────────────────

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

## The chips of the tokens in rows of width `availW`: a chip is as wide as the wider of its two texts,
## and `rowGap` is the room left under a row. `bottom` is where the rows end.
func layoutChips(tokens, fs, availW, rowGap)
    var tfs = math.max(fs * 0.7, MIN_CHIP_TYPE_FONT)
    var chipH = fs + tfs + SIZE * 0.03
    var chips = []
    var x = 0
    var y = 0
    graphics.font("mono")
    for k, tok in tokens do
        graphics.fontSize(fs)
        var w1 = graphics.textSize(tokenLabel(tok))
        graphics.fontSize(tfs)
        var w2 = graphics.textSize(tok.type)
        var w = math.max(w1, w2) + SIZE * 0.022
        if x > 0 and x + w > availW then
            x = 0
            y += chipH + rowGap
        end
        chips[k] = {x: x, y: y, w: w, h: chipH}
        x += w + SIZE * 0.012
    end
    return {chips: chips, tfs: tfs, chipH: chipH, bottom: y + chipH + rowGap}
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

## ── the engine's code ────────────────────────────────────────────────────────

## What the code panel shows of a function, prepared once: each line cut to the columns that fit,
## whether it is a comment, and its number in the C++ file.
func codeLines(fn, cols)
    var key = "{cols}/{fn}"
    if not codeCache.has(key) then
        var listing = stage.cpp[fn]
        var rows = []
        for j, code in listing.lines do
            rows.push({text: clip(code, cols), comment: listing.trimmed[j].startsWith("//"),
                       number: "{listing.first + j - 1}"})
        end
        codeCache[key] = rows
    end
    return codeCache[key]
end

## The font size of the code and the columns it shows. The whole of `stage.columns` is shown when
## it fits at a size that can be read; on a narrow screen the lines are cut instead, since a font
## too small to read shows nothing.
func codeFit(width)
    var avail = width - 2 * SIZE * 0.02
    var fs = math.min(avail / ((stage.columns + CODE_GUTTER) * monoRatio), SIZE * 0.034)
    var cols = stage.columns
    if W < H and fs < MIN_CODE_FONT then
        fs = MIN_CODE_FONT
        cols = math.max(math.floor(avail / (fs * monoRatio)) - CODE_GUTTER, 20)
    end
    return math.max(fs, 7), cols
end

## The first line of the listing that is on show when the engine is on `step`: it keeps the line being
## run in the upper part of the panel, and never scrolls past the ends of the function.
func codeTop(step, rows)
    var total = #stage.cpp[step.fn].lines
    var middle = step.at + step.span / 2
    return math.clamp(middle - rows * 0.4, 1, math.max(total - rows + 1, 1))
end

func drawCode(r, i, t, s)
    var fs, cols = codeFit(r.w)
    var listing = codeLines(s.fn, cols)
    panel(r, stage.file + "  -  " + stage.owner + "::" + s.fn + "()")
    var pad = SIZE * 0.02
    graphics.font("mono")
    var cw = fs * monoRatio
    var lh = fs * CODE_LEADING
    var y0 = r.y + titleHeight()

    ## what is being called, and the locals
    graphics.fontSize(fs)
    label(clipLeft(s.stack, cols), r.x + pad, y0, CARET)
    if s.watchText == nil then
        s.watchText = stage.watch(s)    ## a step never changes
    end
    label(clip(s.watchText, cols + CODE_GUTTER), r.x + pad, y0 + lh, DIM)
    var top = y0 + lh * 2 + pad * 0.4
    var bottom = r.y + r.h - pad * 0.5
    var rows = math.max(math.floor((bottom - top) / lh), 1)

    ## the view and the bar glide from the previous line to this one, inside the same function
    var e = math.smoothstep(0, 0.45, t)
    var first = codeTop(s, rows)
    var barLine = s.at
    var barSpan = s.span
    if i > 1 and run.steps[i - 1].fn == s.fn then
        var before = run.steps[i - 1]
        first = math.lerp(codeTop(before, rows), first, e)
        barLine = math.lerp(before.at, s.at, e)
        barSpan = math.lerp(before.span, s.span, e)
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
            label(row.text, r.x + pad + CODE_GUTTER * cw, y, ink)
        end
    end
end

## ── the explanation ──────────────────────────────────────────────────────────

func drawNote(r, s)
    panel(r, "WHAT HAPPENS")
    var pad = SIZE * 0.02
    var width = r.w - 2 * pad
    var avail = r.h - titleHeight() - pad
    if noteCache.prog <> state.prog or noteCache.id <> s.noteId or noteCache.w <> W or noteCache.h <> H then
        ## when the engine gives up, the sentence is followed by the message it would print
        var parts = [{text: s.said, ink: TEXT}]
        if s.err then
            parts.push({text: stage.errorNote(s), ink: ERROR})
        end
        var fs = math.max(math.min(SIZE * 0.034, 26), 11)
        graphics.font("sans")
        var lines = []
        while true do
            lines = []
            for part in parts do
                for l in wrapText(part.text, fs, width) do
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

## ── the header and the buttons ───────────────────────────────────────────────

func drawHeader(L)
    var n = #run.steps
    graphics.font("sans")
    graphics.fontSize(math.max(SIZE * 0.05, 14))
    label(stage.title, L.m, L.m * 0.8, TEXT)
    ## the program and what it teaches, shrunk to leave the right end to the menu's handle
    var text = stage.programs[state.prog].name + "  -  " + stage.lessons[state.prog]
    var base = math.max(SIZE * 0.026, 10)
    var fs = base
    graphics.fontSize(fs)
    var room = W - 2 * L.m - SIZE * 0.2
    var w = graphics.textSize(text)
    if w > room then
        fs = fs * room / w
        graphics.fontSize(fs)
        if fs < 9 then
            text = stage.programs[state.prog].name   ## too long for a narrow screen: the lesson is left out
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
    var buttons = [{id: "play", text: state.playing and "Pause" or "Play", on: false},
                   {id: "step", text: "Step", on: state.stepping},
                   {id: "back", text: "Back", on: false}, {id: "next", text: "Next", on: false}]
    if stage.skip then
        buttons.push({id: "skip", text: "Skip", on: false})
    end
    buttons.push({id: "restart", text: "Restart", on: false})
    var gap = L.m * 0.6
    var bw = math.min(math.max((W - 2 * L.m - (#buttons - 1) * gap) / #buttons, 40), SIZE * 0.2)
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
