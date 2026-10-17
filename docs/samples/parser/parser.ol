## How the parser works. The parser is the second stage of the engine: it takes the TOKENS the lexer
## cut and assembles them into a TREE, the shape of the program — which statement holds which
## expression, which operator applies to which operands. This example replays that assembly, one line
## of the engine's code at a time.
##
## What runs here is a copy of src/parser.cpp written in Ollin (tracer.ol) that records every line it
## runs and what the line did to the tree, so the animation shows the engine's real rules and not a
## drawing of them: the same precedence table, the same order of attempts, the same refusals.
## tests/parser_trace_test.ol checks that it builds exactly the trees the C++ parser builds. The
## tokens are the ones the lexer of the other example cuts.
##
## The top left shows the tokens, and an arrow under the one the parser is looking at, peek(). The
## bottom left is the tree being built: a node appears when the engine makes it, and goes under its
## parent when the engine puts it there, so pieces that are finished wait side by side until a parent
## picks them up. The panel on the right shows the engine's own code, copied verbatim from
## src/parser.cpp into cpp_source.ol, and the bar in it is the line the parser is running: it goes
## down into expr(), binary_level()... as they are called, and comes back to the line that called them.
##
## It plays by itself, and a tap pauses and resumes it. STEP BY STEP is the other way to read it:
## nothing moves until you ask, and every tap (or the Next button, or the right arrow) runs the next
## line of the parser, Back (or the left arrow) goes back one. SKIP (or the E key) runs up to the next
## line that reads a token or changes the tree: a single expression takes a few hundred lines.
##
## Keys: space plays and pauses, s steps by tap, left/right go back and forward one line, e skips to the
## next event, up/down change the speed, 1 to 5 pick a program, r restarts. F7, F8 and F9 stand for the
## Apple keyboard's previous, play/pause and next keys (with fn, unless the system uses F-keys as
## standard). The menu and the buttons at the bottom do the same with a finger.

import "../lib/stage.ol"
import "tracer.ol"
import "programs.ol"

const ROW = 3.4          ## the height between two levels of the tree, in lines of text
const BOX_HEIGHT = 2.4   ## the height of a node, in lines of text
const SIBLING_GAP = 1.2  ## the width between two nodes side by side, in characters
const TREE_GAP = 3.0     ## the width between two trees, in characters
const LINE = 1.5         ## the height of a line of text, in font sizes

## The operators the parser writes as one character, as they are spelled in a program.
const OP_NAMES = {"|": "or", "&": "and", "o": "|", "x": "~", "b": "&", "l": "<<", "r": ">>", "q": "//",
                  "p": "^", "=": "==", "G": ">=", "L": "<=", "N": "<>", "!": "not"}
const TOKEN_SYMBOLS = {EQUALS: "=", PLUS_EQUAL: "+=", MINUS_EQUAL: "-=", STAR_EQUAL: "*=", SLASH_EQUAL: "/=",
                       PERCENT_EQUAL: "%="}

## The colour group of each kind of node, in the colours of the tokens; statements are the rest.
const NODE_GROUPS = {
    Program: "ending", VarExpr: "name", VarArgExpr: "name", NumberExpr: "number", StringExpr: "text",
    InterpExpr: "text", BoolExpr: "text", NilExpr: "text", BinaryExpr: "operator", UnaryExpr: "operator",
    ChainedCompareExpr: "operator", RangeExpr: "operator", ElseIfClause: "punct", MapEntry: "punct",
    CallExpr: "punct", ExprCallExpr: "punct", MethodCallExpr: "punct", IndexExpr: "punct", ArrayExpr: "punct",
    MapExpr: "punct", FuncExpr: "punct"
}

const EMPTY_TREE = {items: [], by: {}, w: 1, h: 1}

global tokenChips = {w: 0, h: 0, chips: []}   ## the token chips, laid out for one size

## ── what a node says about itself ────────────────────────────────────────────

func opSymbol(code)
    if OP_NAMES.has(code) then
        return OP_NAMES[code]
    end
    return code
end

## A kind without its Expr or Stmt suffix: the colour says which of the two it is.
func shortKind(kind)
    if kind.endsWith("Stmt") or kind.endsWith("Expr") then
        return kind.substr(1, #kind - 4)
    end
    return kind
end

func paramsText(a)
    var text = a.params.join(", ")
    if a.variadic then
        if text == "" then
            return "..."
        end
        return text + ", ..."
    end
    return text
end

## The fields of a node worth writing in its box.
func nodeDetail(n)
    var a = n.attrs
    var k = n.kind
    if k == "VarDeclStmt" then
        var word = "var"
        if a.is_global then
            word = "global"
        elseif a.is_constant then
            word = "const"
        end
        if #a.names == 0 then
            return word
        end
        return word + " " + a.names.join(", ")
    elseif k == "AssignStmt" then
        if a.name == "" then
            return ""
        end
        return a.name + " " + a.op + "="
    elseif k == "IndexAssignStmt" then
        if a.obj == "" then
            return TOKEN_SYMBOLS[a.op]
        end
        return a.obj + " " + TOKEN_SYMBOLS[a.op]
    elseif k == "FuncDeclStmt" then
        if a.name == "" then
            return ""
        end
        return a.name + "(" + paramsText(a) + ")"
    elseif k == "FuncExpr" then
        return "(" + paramsText(a) + ")"
    elseif k == "ForIterStmt" then
        if a.var2 <> "" then
            return a.var1 + ", " + a.var2
        end
        return a.var1
    elseif k == "ReturnStmt" then
        if a.spread_varargs then
            return "..."
        end
        return ""
    elseif k == "BoolExpr" or k == "NumberExpr" then
        return "{a.value}"
    elseif k == "StringExpr" then
        return QUOTE + clip(a.value, 10) + QUOTE
    elseif k == "VarExpr" then
        return a.name
    elseif k == "BinaryExpr" or k == "UnaryExpr" then
        return opSymbol(a.op)
    elseif k == "ChainedCompareExpr" then
        return a.ops.map(func(c) return opSymbol(c) end).join(" ")
    elseif k == "CallExpr" then
        if a.callee == "" then
            return ""
        end
        return a.callee + "()"
    elseif k == "ExprCallExpr" then
        return "()"
    elseif k == "MethodCallExpr" then
        if a.method == "" then
            return ""
        end
        return "." + a.method + "()"
    elseif k == "InterpExpr" then
        return QUOTE + clip(a.literals.join("\{}"), 10) + QUOTE
    end
    return ""
end

func nodeColor(kind)
    if NODE_GROUPS.has(kind) then
        return KIND_COLORS[NODE_GROUPS[kind]]
    end
    return KIND_COLORS.keyword
end

## ── the forest after each step ───────────────────────────────────────────────

## Width of a node, subtree widths and details, in `lay`, by node id.
func measure(n, lay)
    var detail = nodeDetail(n)
    var own = math.max(#shortKind(n.kind), #detail, #n.slot) + 2
    var kids = 0
    for k in n.kids do
        measure(k, lay)
        kids += lay[k.id].sw
    end
    if #n.kids > 1 then
        kids += SIBLING_GAP * (#n.kids - 1)
    end
    lay[n.id] = {own: own, sw: math.max(own, kids), kids: kids, detail: detail}
end

## Puts the node in the middle of the room its subtree has, its children side by side below it.
func place(n, left, depth, lay, items)
    var l = lay[n.id]
    items.push({id: n.id, kind: shortKind(n.kind), group: n.kind, detail: l.detail, slot: n.slot, parent: n.parent,
                x: left + l.sw / 2, y: depth * ROW, w: l.own})
    var x = left + (l.sw - l.kids) / 2
    for k in n.kids do
        place(k, x, depth + 1, lay, items)
        x += lay[k.id].sw + SIBLING_GAP
    end
end

## Every tree on show, side by side: the Program first, then the pieces that are finished and wait for a parent.
func layoutForest(nodes, count)
    var lay = {}
    var items = []
    var left = 0.0
    for id = 1, count do
        if nodes.has(id) and nodes[id].parent == 0 then
            measure(nodes[id], lay)
            place(nodes[id], left, 0, lay, items)
            left += lay[id].sw + TREE_GAP
        end
    end
    var by = {}
    var deepest = 0
    for item in items do
        by[item.id] = item
        deepest = math.max(deepest, item.y)
    end
    return {items: items, by: by, w: math.max(left - TREE_GAP, 1), h: deepest + BOX_HEIGHT + 1.2}
end

## ── loading a program ────────────────────────────────────────────────────────

## A line takes a moment; a line that reads a token or changes the tree takes longer. Paced by hand,
## every line takes the same short time, a line that changes the tree a little longer.
func paceOf(st)
    var dur = 0.1
    var hand = 0.2
    if st.p1 <> st.p0 then
        dur += 0.05
    end
    for e in st.fx do
        if e.op == "new" or e.op == "put" then
            dur += 0.3
            hand = 0.5
            break
        end
    end
    return dur, hand
end

func buildRun(index)
    var r = parseTrace(PROGRAMS[index].source)
    if #r.steps == 0 then
        throw "the program does not get as far as the parser: {r.error}"
    end
    var nodes = {}
    for st in r.steps do
        for e in st.fx do
            applyEffect(nodes, e)
        end
        st.tree = layoutForest(nodes, r.nodeCount)
    end
    prepareSteps(r, paceOf)
    return r
end

## When the parser gives up, the sentence is followed by the message it would print.
func errorNote(s)
    return "Error on line {s.errLine}: {s.err.replace("—", "-")}. The parser stops here: nothing after this point is looked at."
end

## What the parser is looking at, and its locals, as a debugger would list them.
func watchLine(s)
    var tok = run.tokens[s.p1]
    var parts = ["peek() = {tok.type}"]
    if tok.lexeme <> "" then
        parts[1] = "peek() = {tok.type} " + QUOTE + clip(tok.lexeme, 12) + QUOTE
    end
    for pair in s.w do
        parts.push(pair[1] + " = " + clip(pair[2], 20))
    end
    return parts.join("   ")
end

## ── the layout of the screen ─────────────────────────────────────────────────

## The chips of the tokens, laid out for a panel of width `width`: a chip never moves when the parser
## goes on, and the pointer needs the room under its row.
func chipLayout(width)
    if tokenChips.w == W and tokenChips.h == H and tokenChips.prog == state.prog then
        return tokenChips
    end
    var pad = SIZE * 0.02
    var fs = math.min(SIZE * 0.026, width / 34)
    var tfs = fs * 0.7
    var chips = []
    var x = 0
    var y = 0
    var chipH = fs + tfs + SIZE * 0.03
    var rowH = chipH + fs * 2.0
    var availW = width - 2 * pad
    graphics.font("mono")
    for k, tok in run.tokens do
        graphics.fontSize(fs)
        var w1 = graphics.textSize(tokenLabel(tok))
        graphics.fontSize(tfs)
        var w2 = graphics.textSize(tok.type)
        var w = math.max(w1, w2) + SIZE * 0.022
        if x > 0 and x + w > availW then
            x = 0
            y += rowH
        end
        chips[k] = {x: x, y: y, w: w, h: chipH}
        x += w + SIZE * 0.012
    end
    tokenChips = {w: W, h: H, prog: state.prog, chips: chips, fs: fs, tfs: tfs, chipH: chipH, rowH: rowH, pad: pad,
                  height: y + rowH}
    return tokenChips
end

func computeLayout()
    var L = baseLayout()
    var m = L.m
    var top = L.top
    var availH = L.availH
    if W >= H * 1.1 then
        var lw = (W - 3 * m) * 0.44
        var rw = W - 3 * m - lw
        var tokensH = math.min(availH * 0.3, titleHeight() + chipLayout(lw).height + SIZE * 0.02)
        L.tokens = rectOf(m, top, lw, tokensH)
        L.tree = rectOf(m, top + tokensH + m, lw, availH - tokensH - m)
        L.code = rectOf(2 * m + lw, top, rw, availH * 0.76)
        L.note = rectOf(2 * m + lw, top + L.code.h + m, rw, availH - L.code.h - m)
    else
        var w = W - 2 * m
        var tokensH = math.min(availH * 0.2, titleHeight() + chipLayout(w).height + SIZE * 0.02)
        var room = availH - 3 * m - tokensH
        L.tokens = rectOf(m, top, w, tokensH)
        L.tree = rectOf(m, top + tokensH + m, w, room * 0.4)
        L.code = rectOf(m, L.tree.y + L.tree.h + m, w, room * 0.42)
        L.note = rectOf(m, L.code.y + L.code.h + m, w, room - L.tree.h - L.code.h)
    end
    return L
end

## ── the tokens ───────────────────────────────────────────────────────────────

func drawTokens(r, t, s)
    panel(r, "TOKENS FROM THE LEXER")
    var L = chipLayout(r.w)
    var top = r.y + titleHeight()
    ## where peek() is, sliding from where the line began to where it ends
    var cur = lerp(s.p0, s.p1, ramp(t, 0, 0.8))
    for k, tok in run.tokens do
        var chip = L.chips[k]
        var consumed = math.clamp(cur - k, 0, 1)
        drawChip(chip, tok, r.x + L.pad + chip.x, top + chip.y, 1 - 0.6 * consumed, L.fs, L.tfs)
    end
    var at = math.min(math.floor(cur), #run.tokens)
    var next = math.min(at + 1, #run.tokens)
    var a = L.chips[at]
    var b = L.chips[next]
    var frac = cur - at
    var x = lerp(r.x + L.pad + a.x + a.w / 2, r.x + L.pad + b.x + b.w / 2, frac)
    var y = lerp(top + a.y + a.h, top + b.y + b.h, frac)
    var size = L.fs * 0.5
    graphics.noStroke()
    graphics.fill(CARET)
    graphics.polygon([x - size, y + size * 1.6, x + size, y + size * 1.6, x, y + size * 0.2])
    graphics.font("mono")
    graphics.fontSize(L.tfs)
    graphics.textMode("center", "top")
    label("peek()", x, y + size * 1.7, CARET)
    graphics.textMode("left", "top")
end

## ── the tree ─────────────────────────────────────────────────────────────────

## Where every node of a forest sits in the pixels of the panel `r`, worked out once per size: the
## whole forest shares one font size, so that it always fits.
func forestPixels(tree, r)
    if tree.sigW == W and tree.sigH == H then
        return tree.px
    end
    var pad = SIZE * 0.02
    var availW = r.w - 2 * pad
    var availH = r.h - titleHeight() - pad
    var fs = math.clamp(math.min(availW / (tree.w * monoRatio), availH / (tree.h * LINE)), 6, SIZE * 0.032)
    var cw = fs * monoRatio
    var lh = fs * LINE
    var ox = r.x + pad + (availW - tree.w * cw) / 2
    var oy = r.y + titleHeight() + pad * 0.3
    var px = {}
    for item in tree.items do
        px[item.id] = {x: ox + item.x * cw, y: oy + item.y * lh, w: item.w * cw, h: BOX_HEIGHT * lh, fs: fs}
    end
    tree.sigW = W
    tree.sigH = H
    tree.px = px
    return px
end

## The nodes a step touched: made, changed, or given a child.
func focusOf(s)
    if s.focus == nil then
        var ids = {}
        for e in s.fx do
            if e.op == "put" then
                ids[e.child] = true
                ids[e.parent] = true
            elseif e.op <> "free" then
                ids[e.id] = true
            end
        end
        s.focus = ids
    end
    return s.focus
end

func drawNode(item, f, alpha, glow, returned)
    var c = nodeColor(item.group)
    var x = f.x - f.w / 2
    graphics.font("mono")
    if returned then
        graphics.noFill()
        graphics.stroke(fade(CARET, 0.55 * alpha), 1.5)
        graphics.rect(x - 4, f.y - 4, f.w + 8, f.h + 8, f.fs * 0.5)
    end
    graphics.fill(fade(c, 0.16 * alpha))
    if glow then
        graphics.stroke(fade(CARET, alpha), 2.5)
    else
        graphics.stroke(fade(c, alpha), 1.4)
    end
    graphics.rect(x, f.y, f.w, f.h, f.fs * 0.35)
    graphics.textMode("center", "top")
    graphics.fontSize(f.fs * 0.8)
    label(item.kind, f.x, f.y + f.fs * 0.3, fade(c, alpha))
    graphics.fontSize(f.fs)
    label(item.detail, f.x, f.y + f.fs * 1.5, fade(TEXT, alpha))
    graphics.textMode("left", "top")
end

func drawTree(r, i, t, s)
    panel(r, "THE TREE BEING BUILT")
    var cur = s.tree
    var before = EMPTY_TREE
    if i > 1 then
        before = run.steps[i - 1].tree
    end
    var pc = forestPixels(cur, r)
    var pb = forestPixels(before, r)
    var e = ramp(t, 0.05, 0.8)
    var arrive = ramp(t, 0.1, 0.6)
    var focus = focusOf(s)

    ## the frame of every node: where it is now, between where it was and where it goes
    var frames = {}
    for item in cur.items do
        var f = pc[item.id]
        var alpha = 1.0
        if before.by.has(item.id) then
            var o = pb[item.id]
            f = {x: lerp(o.x, f.x, e), y: lerp(o.y, f.y, e), w: lerp(o.w, f.w, e), h: lerp(o.h, f.h, e),
                 fs: lerp(o.fs, f.fs, e)}
        else
            alpha = arrive
            var grow = 0.85 + 0.15 * arrive
            f = {x: f.x, y: f.y + f.h * (1 - grow) / 2, w: f.w * grow, h: f.h * grow, fs: f.fs * grow}
        end
        f.alpha = alpha
        frames[item.id] = f
    end

    graphics.noFill()
    for item in cur.items do
        if item.parent <> 0 then
            var f = frames[item.id]
            var p = frames[item.parent]
            graphics.stroke(fade(DIM, 0.8 * math.min(f.alpha, p.alpha)), 1.2)
            graphics.line(p.x, p.y + p.h, f.x, f.y)
        end
    end

    ## the name of the field each node is held in, on the edge that leads to it
    graphics.font("mono")
    graphics.textMode("center", "top")
    for item in cur.items do
        if item.slot <> "" then
            var f = frames[item.id]
            graphics.fontSize(f.fs * 0.7)
            var w = graphics.textSize(item.slot) + f.fs * 0.5
            var y = f.y - f.fs * 1.25
            box(f.x - w / 2, y, w, f.fs * 0.95, f.fs * 0.3, fade(PANEL, 0.9 * f.alpha))
            label(item.slot, f.x, y + f.fs * 0.1, fade(DIM, f.alpha))
        end
    end
    graphics.textMode("left", "top")

    ## a node the line destroyed fades where it was
    for item in before.items do
        if not cur.by.has(item.id) then
            var o = pb[item.id]
            drawNode(item, o, 1 - e, false, false)
        end
    end
    for item in cur.items do
        var f = frames[item.id]
        drawNode(item, f, f.alpha, focus.has(item.id), s.ret == item.id)
    end
end

## ── the whole frame ──────────────────────────────────────────────────────────

func setup()
    stage.title = "Inside the parser"
    stage.menu = "Parser"
    stage.programs = PROGRAMS
    stage.lessons = LESSONS
    stage.build = buildRun
    stage.cpp = PCPP
    stage.file = "src/parser.cpp"
    stage.owner = "Parser"
    stage.watch = watchLine
    stage.errorNote = errorNote
    stage.columns = 96
    stage.skip = true
    state.speed = 2.0
    graphics.canvas(W, H, "How the parser works")
    for k, v in KEYWORDS do
        keywordTypes[v] = true
    end
    openMenu()
    loadProgram(1)
end

func draw()
    beginFrame()
    var L = computeLayout()
    var i, t = current()
    var s = run.steps[i]
    drawHeader(L)
    drawTokens(L.tokens, t, s)
    drawTree(L.tree, i, t, s)
    drawCode(L.code, i, t, s)
    drawNote(L.note, s)
    drawFooter(L, i)
end
