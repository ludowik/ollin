## Everything the game draws on its own screens: the board, the pad, the tools, the messages and the help.

func drawButton(label, r, fill, textSize, ink = nil)
    var L = game.layout
    if ink == nil then
        ink = config.onButton
    end
    fillC(fill)
    graphics.rect(r.x, r.y, r.w, r.h, L.c * 0.28)
    drawText(label, r.x + r.w / 2, r.y + r.h / 2, fitSize(label, textSize, r.w * 0.88), "center", "center", ink)
end

func drawHeader()
    var L = game.layout
    var c = L.c
    var label = tr("level").upper()
    if game.daily <> nil then
        label = tr("daily").upper()
    end
    drawText(label, L.titleX, L.titleY + 0.05 * c, c * 0.36, "left", "top", config.muted)
    drawText(levelName(game.level), L.titleX, L.titleY + 0.55 * c, fitSize(levelName(game.level), c * 0.95, c * 4.2), "left", "top", config.ink)
    drawButton(tr("newGame"), L.newBtn, config.button, c * 0.42)
    drawGear(L.gear)
end

func drawBoard()
    var L = game.layout
    var c = L.c
    var sel = game.selected
    var digit = game.armed
    if digit == 0 and sel <> 0 then
        digit = game.grid[sel]
    end
    var peerCells = {}
    if sel <> 0 then
        for j in board.peers[sel] do
            peerCells[j] = true
        end
    end
    var hintCells = {}
    if game.hint <> nil and game.hint.kind == "hidden" then
        for j in board.units[game.hint.unit] do
            hintCells[j] = true
        end
    end
    graphics.noStroke()
    for i = 1, CELLS do
        var x, y = cellPos(i)
        var tint = config.boxLight
        if ((board.boxOf[i] - 1) // BOX + (board.boxOf[i] - 1) % BOX) % 2 == 1 then
            tint = config.boxDark
        end
        if hintCells[i] then
            tint = config.hintTint
        end
        if peerCells[i] then
            tint = config.peerTint
        end
        if digit <> 0 and game.grid[i] == digit then
            tint = config.sameTint
        end
        if game.errors and game.conflicts[i] <> 0 then
            tint = config.conflictTint
        end
        if i == sel then
            tint = config.selectTint
        end
        if game.state == "won" then
            var wave = math.clamp(1 - math.abs(game.win.t * 18 - math.abs(board.rowOf[i] - board.rowOf[game.win.cell]) - math.abs(board.colOf[i] - board.colOf[game.win.cell])) / 3, 0, 1)
            if wave > 0 then
                tint = [tint[1] + (config.gold[1] - tint[1]) * wave, tint[2] + (config.gold[2] - tint[2]) * wave, tint[3] + (config.gold[3] - tint[3]) * wave, 1]
            end
        end
        fillC(tint)
        graphics.rect(x, y, c, c)
    end
    for i = 1, CELLS do
        var x, y = cellPos(i)
        var v = game.grid[i]
        if v <> 0 then
            var col = config.blue
            if game.puzzle[i] <> 0 then
                col = config.ink
            end
            if game.errors and game.conflicts[i] <> 0 then
                col = config.red
            end
            var size = c * 0.62
            if i == game.pop.cell then
                size = size * game.pop.s
            end
            drawText("{v}", x + c / 2, y + c / 2, size, "center", "center", col)
        end
    end
    graphics.fontSize(c * 0.27)
    graphics.textMode("center", "center")
    for i = 1, CELLS do
        if game.grid[i] == 0 and game.notes[i] <> 0 then
            var x, y = cellPos(i)
            for d = 1, N do
                if (game.notes[i] & (1 << d)) <> 0 then
                    var col = config.muted
                    if d == digit then
                        col = config.blue
                    end
                    graphics.stroke(col[1], col[2], col[3], col[4])
                    graphics.text("{d}", x + ((d - 1) % 3 + 0.5) * c / 3, y + ((d - 1) // 3 + 0.5) * c / 3)
                end
            end
        end
    end
    graphics.noStroke()
    for k = 0, N do
        var thick = k % BOX == 0
        var w = math.max(1, c * 0.02)
        if thick then
            w = math.max(2, c * 0.07)
            fillC(config.ink)
        else
            fillC(config.thin)
        end
        graphics.rect(L.bx + k * c - w / 2, L.by - w / 2, w, L.bs + w)
        graphics.rect(L.bx - w / 2, L.by + k * c - w / 2, L.bs + w, w)
    end
    if game.hint <> nil then
        var x, y = cellPos(game.hint.cell)
        var pulse = 0.5 + 0.5 * math.sin(elapsedTime * 6)
        graphics.noFill()
        graphics.stroke(config.amber[1], config.amber[2], config.amber[3], 0.6 + 0.4 * pulse)
        graphics.strokeSize(math.max(3, c * 0.1))
        graphics.rect(x + c * 0.06, y + c * 0.06, c * 0.88, c * 0.88, c * 0.2)
        graphics.noStroke()
    end
end

## How many of each digit are placed, so that a digit that is complete leaves the pad.
func drawPad()
    var L = game.layout
    var c = L.c
    for d = 1, N do
        var r = L.pad[d]
        var done = boardDigitCount(game.grid, d) >= N
        var fill = config.pad
        var ink = config.ink
        if done then
            fill = config.padDone
            ink = config.buttonOff
        end
        if game.input == "digit" and game.armed == d then
            fill = config.buttonOn
            ink = config.onButton
        end
        fillC(fill)
        graphics.rect(r.x, r.y, r.w, r.h, c * 0.22)
        drawText("{d}", r.x + r.w / 2, r.y + r.h / 2, math.min(r.h, c * 1.3) * 0.62, "center", "center", ink)
    end
end

func drawTools()
    var L = game.layout
    var c = L.c
    var pencilFill = config.button
    if game.pencil then
        pencilFill = config.buttonOn
    end
    var hintFill = config.button
    if game.hints <= 0 then
        hintFill = config.buttonOff
    end
    var undoFill = config.button
    if len(game.undo) == 0 then
        undoFill = config.buttonOff
    end
    drawButton(tr("pencil"), L.tools[1], pencilFill, c * 0.4)
    drawButton(tr("erase"), L.tools[2], config.button, c * 0.4)
    drawButton(tr("undo"), L.tools[3], undoFill, c * 0.4)
    drawButton("{tr("hint")} {game.hints}", L.tools[4], hintFill, c * 0.4)
end

## The line under the grid.
func drawMessage()
    var L = game.layout
    if game.message == "" then
        return
    end
    var size = L.c * 0.34
    var y = L.msg.y
    for line in wrapText(game.message, size, L.msg.w) do
        drawText(line, L.msg.x, y, size, "left", "top", config.ink)
        y += size * 1.25
    end
end

func drawWon()
    var L = game.layout
    var a = math.clamp((game.win.t - 0.4) / 0.4, 0, 1)
    if a <= 0 then
        return
    end
    var w = math.min(L.bs * 0.9, W - 2 * SIZE * config.margin)
    var h = L.c * 1.5
    var x = L.bx + L.bs / 2 - w / 2
    var y = L.by + L.bs / 2 - h / 2
    graphics.fill(1, 1, 1, a)
    graphics.rect(x, y, w, h, L.c * 0.3)
    drawText(tr("won"), x + w / 2, y + h / 2, fitSize(tr("won"), L.c * 0.8, w * 0.9), "center", "center", config.ink, a)
end

func drawPlay()
    drawHeader()
    drawBoard()
    drawMessage()
    drawPad()
    drawTools()
    drawWon()
end

func drawGenerating()
    var dots = math.floor(elapsedTime * 3) % 4
    var text = tr("generating")
    drawText(text, CX, CY - SIZE * 0.03, fitSize(text, SIZE * 0.06, W * 0.9), "center", "center", config.ink)
    drawText(".".repeat(dots), CX, CY + SIZE * 0.05, SIZE * 0.08, "center", "center", config.muted)
    drawText(levelName(game.job.level), CX, CY + SIZE * 0.15, SIZE * 0.04, "center", "center", config.muted)
end

func helpLines(size, width)
    return wrapParagraphs(tr("help")({box: BOX, size: N, hints: HINTS}), size, width)
end

## The size and the lines of the help, wrapped again only when the area or the language changes.
func helpLayout()
    var key = "{W}x{H} {i18n.lang}"
    var cache = game.help
    if cache.key <> key then
        var width = W - 2 * SIZE * config.textMargin
        var size = SIZE * 0.04
        var lines = helpLines(size, width)
        while len(lines) * size * 1.3 > H - SIZE * 0.2 and size > 8 do
            size = size * 0.92
            lines = helpLines(size, width)
        end
        cache.key = key
        cache.size = size
        cache.lines = lines
    end
    return cache
end

func drawHelp()
    drawScreenTitle(tr("menuHelp"))
    var help = helpLayout()
    var y = SIZE * 0.12
    for line in help.lines do
        if line <> "" then
            drawText(line, SIZE * config.textMargin, y, help.size, "left", "top", config.ink)
        end
        y += help.size * 1.3
    end
    drawText(tr("tapBack"), CX, H - SIZE * 0.04, SIZE * 0.027, "center", "center", config.muted)
end
