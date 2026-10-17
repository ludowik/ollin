## The STAGE shared by the examples that replay the engine step by step ("How the lexer works",
## "How the parser works"): the palette, the player (play, pause, step by step, back, restart, the
## speed), the panel that shows the engine's own C++ with a bar on the line being run, the panel that
## explains what happens, the header and the buttons at the bottom.
##
## An example is a program that fills the `stage` map below in its setup() and draws what is its own
## between drawHeader() and drawFooter(), inside its draw():
##
##   stage.programs   the programs it can show, each a map with a `name`
##   stage.lessons    a sentence per program, shown under the title
##   stage.build(i)   the trace of program i: a map with `steps`, the list the player replays. A step
##                    carries `fn`, `at`, `span` (the line it lights in the code panel, and how many
##                    more lines its statement covers), `also` (a second line to mark), `stack` (the
##                    calls in progress), `note` (a sentence, said from there on), `err` (the message
##                    when the engine gives up), and what the example needs besides. prepareSteps()
##                    adds `dur`, `hand`, `said` and `noteId`.
##   stage.cpp        the engine's text, by function: {first, lines, trimmed}
##
## setup() fills `stage` (all of it but `skip` is needed), sets `keywordTypes` (to KEYWORD_TYPES of the
## lexer's tracer), then calls openMenu() and loadProgram(1). draw() begins with beginFrame(), takes its
## room from baseLayout() and adds its own panels to the header, the code panel, the explanation and
## the buttons (drawHeader, drawCode, drawNote, drawFooter). Both examples are written that way: copy one.
## A step also gets `event` (true when the line changed something, which SKIP runs up to) from the
## example, and `watchText` from here.
##
## The player: a program plays by itself, and a tap pauses and resumes it. STEP BY STEP is the other
## way to read it: nothing moves until you ask, every tap (or the Next button, or the right arrow) runs
## the next line, and Back (or the left arrow) goes back one. The Step button, the S key and the menu
## switch the mode on and off; Play leaves it. With `stage.skip`, SKIP (or the E key) runs up to the
## next step flagged `event`. Keys: space plays and pauses, up/down change the speed, a digit picks a
## program, r restarts. F7, F8 and F9 stand for the Apple keyboard's previous, play/pause and next keys
## (with fn, unless the system uses F-keys as standard). The menu and the buttons do the same with a finger.
##
## The callbacks that live here are update, keyboard.keypressed and mouse.pressed: a module can declare
## them, a class cannot. A const of the program that imports this file is not visible from here, which
## is why the example's own words come through `stage`.

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
global keywordTypes = {}  ## the token types that are keywords, filled by the example
global monoRatio = nil    ## the width of a monospaced character, per pixel of font size
global noteCache = {prog: 0, id: 0, w: 0, h: 0, lines: [], size: 0}   ## the sentence, wrapped for one size
global codeCache = {}

## What an example hands over, besides the programs and the engine's text above: `title` heads the
## screen, `menu` names the menu, `file` and `owner` name the C++ in the code panel, `columns` is how
## many columns of a line of C++ are shown (a longer line is cut with a "~"), `watch(step)` writes the
## line of locals, `errorNote(step)` the sentence that follows a refusal, and `skip` adds the button
## that runs to the next step flagged `event`.
global stage = {title: "", menu: "", programs: [], lessons: [], build: nil, cpp: {}, file: "", owner: "",
                columns: 82, watch: nil, errorNote: nil, skip: false}

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

## The end of a text, cut to `max` characters, with a "~" where its beginning was cut.
func clipLeft(text, max)
    if #text > max then
        return "~" + text.substr(#text - max + 2, max - 1)
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

## What the player needs of every step: how long it takes, and the sentence being said. `pace` is the
## example's own rule: it returns the time of a line when the program plays by itself and when it is
## paced by hand. A sentence adds to the first the time to read it.
func prepareSteps(r, pace)
    var said = ""
    var noteId = 0
    for st in r.steps do
        st.dur, st.hand = pace(st)
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
end

func loadProgram(index)
    if loaded[index] == nil then
        loaded[index] = stage.build(index)
    end
    run = loaded[index]
    state.prog = index
    state.name = stage.programs[index].name
    restart()
end

## ── the player ───────────────────────────────────────────────────────────────

## A position that falls exactly between two steps is the END of the one before: at rest the bar,
## the highlighted number and the explanation then all speak of the line that has just run.
func current()
    var i = math.clamp(math.ceil(state.pos), 1, #run.steps)
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

## Runs up to the next step flagged `event`, or to the end: the lines in between are done without
## stopping on them.
func skipForward()
    if not stage.skip then
        return nil
    end
    if not state.stepping then
        setStepping(true)
    end
    var n = #run.steps
    var j = math.floor(state.goal + 0.000001) + 1
    while j < n and not run.steps[j].event do
        j += 1
    end
    state.goal = math.min(j, n)
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
const ACTIONS = {play: togglePlay, step: toggleStepping, back: stepBack, next: stepForward, skip: skipForward,
                 restart: restart}
const KEYS = {space: "play", f8: "play", s: "step", left: "back", f7: "back", right: "next", f9: "next",
              e: "skip", r: "restart"}

func onProgram(name)
    for i, p in stage.programs do
        if p.name == name then
            loadProgram(i)
        end
    end
end

## The menu: the program, the mode, the speed, and the buttons. Folded to its handle, since the
## animation has the whole screen.
func openMenu()
    var names = stage.programs.map(func(p) return p.name end)
    state.name = names[1]
    var menu = ui.menu(stage.menu)
    menu.list("Program", names, ref state.name, onProgram)
    menu.checkbox("Playing", ref state.playing, onPlaying)
    menu.checkbox("Step by step", ref state.stepping, setStepping)
    menu.slider("Speed", ref state.speed, MIN_SPEED, MAX_SPEED, 1.0)
    menu.button("Back", stepBack)
    menu.button("Next", stepForward)
    menu.button("Restart", restart)
    ui.show(menu)
    ui.close()
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
        if n and n >= 1 and n <= #stage.programs then
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
            loadProgram(state.prog % #stage.programs + 1)
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
func codeLines(fn)
    if not codeCache.has(fn) then
        var listing = stage.cpp[fn]
        var rows = []
        for j, code in listing.lines do
            rows.push({text: clip(code, stage.columns), comment: listing.trimmed[j].startsWith("//"),
                       number: "{listing.first + j - 1}"})
        end
        codeCache[fn] = rows
    end
    return codeCache[fn]
end

## The first line of the listing that is on show when the engine is on `step`: it keeps the line being
## run in the upper part of the panel, and never scrolls past the ends of the function.
func codeTop(step, rows)
    var total = #stage.cpp[step.fn].lines
    var middle = step.at + step.span / 2
    return math.clamp(middle - rows * 0.4, 1, math.max(total - rows + 1, 1))
end

func drawCode(r, i, t, s)
    var listing = codeLines(s.fn)
    panel(r, stage.file + "  -  " + stage.owner + "::" + s.fn + "()")
    var pad = SIZE * 0.02
    graphics.font("mono")
    var gutter = 5
    var fs = math.max(math.min((r.w - 2 * pad) / ((stage.columns + gutter) * monoRatio), SIZE * 0.034), 7)
    var cw = fs * monoRatio
    var lh = fs * CODE_LEADING
    var y0 = r.y + titleHeight()

    ## what is being called, and the locals
    graphics.fontSize(fs)
    label(clipLeft(s.stack, stage.columns), r.x + pad, y0, CARET)
    if s.watchText == nil then
        s.watchText = stage.watch(s)    ## a step never changes
    end
    label(s.watchText, r.x + pad, y0 + lh, DIM)
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
        ## when the engine gives up, the sentence is followed by the message it would print
        var parts = [{text: s.said, ink: TEXT}]
        if s.err then
            parts.push({text: stage.errorNote(s), ink: ERROR})
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
