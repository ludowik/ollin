## Everything the game draws: the cells, the pieces, the board and its trays, the end screen, the help and the catalogue.

## The top-left corner on the screen of the cell at row r, column c.
func cellOrigin(r, c)
    var L = game.layout
    return L.bx + (c - 1) * L.c, L.by + (r - 1) * L.c
end

## The rectangle of a cell, inset to leave the gap between neighbours.
func cellRect(x, y, s)
    graphics.rect(x + s * 0.05, y + s * 0.05, s * 0.9, s * 0.9, s * 0.16)
end

## A block: the one blue, or the washed-out one of a piece that fits nowhere.
func drawCell(x, y, s, alpha = 1, stuck = false)
    var col = config.blue
    if stuck then
        col = config.blueStuck
    end
    var g = s * 0.05
    var inner = s - 2 * g
    graphics.fill(col[1], col[2], col[3], alpha)
    graphics.rect(x + g, y + g, inner, inner, s * 0.18)
    graphics.fill(1, 1, 1, 0.22 * alpha)
    graphics.rect(x + g + s * 0.08, y + g + s * 0.06, inner - s * 0.16, inner * 0.32, s * 0.12)
end

## The blocks of a shape whose top-left corner is at (x0, y0), s wide each.
func drawShape(shape, x0, y0, s, alpha = 1, stuck = false)
    for off in shape.cells do
        drawCell(x0 + off[2] * s, y0 + off[1] * s, s, alpha, stuck)
    end
end

func drawPiece(p, alpha = 1, stuck = false)
    drawShape(p.shape, p.x - p.shape.w * p.size / 2, p.y - p.shape.h * p.size / 2, p.size, alpha, stuck)
end

func drawButton(label, r, fill, textSize, alpha = 1)
    var L = game.layout
    graphics.fill(fill[1], fill[2], fill[3], alpha)
    graphics.rect(r.x, r.y, r.w, r.h, L.c * 0.3)
    drawText(label, r.x + r.w / 2, r.y + r.h / 2, fitSize(label, textSize, r.w * 0.9), "center", "center", config.onButton, alpha)
end

func drawHeader()
    var L = game.layout
    var c = L.c
    drawText(tr("score").upper(), L.scoreX, L.scoreY, c * 0.36, "left", "top", config.muted)
    drawText("{math.round(game.display.score)}", L.scoreX, L.scoreY + c * 0.5, c * 0.95 * game.display.pop, "left", "top", config.ink)
    drawText(tr("best").upper(), L.bestX, L.bestY, c * 0.36, "left", "top", config.muted)
    drawText("{game.best}", L.bestX, L.bestY + c * 0.5, c * 0.7, "left", "top", config.ink)
    drawButton(tr("newGame"), L.newBtn, config.button, c * 0.42)
    drawGear(L.gear)
end

## The points in flight: each grows where it was earned, then flies to the score, smaller as it goes.
func drawFloaters()
    var L = game.layout
    var c = L.c
    var tx = L.scoreX + c * 0.6
    var ty = L.scoreY + c * 1.0
    var ink = config.outlineInk
    graphics.textMode("center", "center")
    for f in game.floaters do
        if f.age > 0 then
            var u = math.min(f.age / config.floatPop, 1) - 1
            var grow = 1 + 2.70158 * u * u * u + 1.70158 * u * u          ## easeOutBack
            var q = math.clamp((f.age - config.floatPop - config.floatHold) / config.floatFlight, 0, 1)
            var k = q * q                                                  ## easeInQuad: it picks up speed
            var ox, oy = cellOrigin(f.row, f.col)
            var x0 = ox + c / 2
            var y0 = oy + c / 2
            var x = x0 + (tx - x0) * k
            var y = y0 + (ty - y0) * k
            var size = c * 0.46 * grow * (1 - 0.75 * k)
            var alpha = 1 - math.max(0, (k - 0.8) / 0.2)
            var edge = size * 0.07
            graphics.fontSize(size)
            graphics.stroke(ink[1], ink[2], ink[3], ink[4] * alpha * 0.9)
            for off in config.outline do
                graphics.text(f.text, x + off[1] * edge, y + off[2] * edge)
            end
            graphics.stroke(f.tint[1], f.tint[2], f.tint[3], f.tint[4] * alpha)
            graphics.text(f.text, x, y)
        end
    end
    graphics.noStroke()
end

func drawBoard()
    var L = game.layout
    var c = L.c
    ## The empty cells, the two greys of the 3x3 boxes one after the other: a fill per grey, not per cell.
    for tint = 0, 1 do
        graphics.fill(config.cellLight - (config.cellLight - config.cellDark) * tint)
        for r = 1, GRID do
            for col = 1, GRID do
                if ((r - 1) // BOX + (col - 1) // BOX) % 2 == tint then
                    var x, y = cellOrigin(r, col)
                    cellRect(x, y, c)
                end
            end
        end
    end
    for r = 1, GRID do
        for col = 1, GRID do
            var cell = game.cells[boardIdx(r, col)]
            if cell.v <> 0 and cell.s > 0.01 then
                var size = c * cell.s
                var ox, oy = cellOrigin(r, col)
                var x = ox + (c - size) / 2
                var y = oy + (c - size) / 2
                drawCell(x, y, size)
                if cell.f > 0.01 then
                    graphics.fill(1, 1, 1, cell.f * 0.9)
                    cellRect(x, y, size)
                end
            end
        end
    end
end

## The shadow of the held piece where it would land, and the cells that landing would clear.
func drawPreview()
    var L = game.layout
    var held = game.held
    if held == nil then
        return
    end
    var c = L.c
    var t = game.target
    if t.valid then
        var x0, y0 = cellOrigin(t.r, t.c)
        drawShape(held.shape, x0, y0, c, 0.38)
    else
        graphics.fill(config.invalid[1], config.invalid[2], config.invalid[3], 0.55)
        for off in held.shape.cells do
            if boardInside(t.r + off[1], t.c + off[2]) then
                var x, y = cellOrigin(t.r + off[1], t.c + off[2])
                cellRect(x, y, c)
            end
        end
    end
    graphics.fill(1, 1, 1, 0.5)
    for idx in game.previewCells do
        var x, y = cellOrigin(boardRow(idx), boardCol(idx))
        cellRect(x, y, c)
    end
end

func drawTrays()
    for i = 1, 3 do
        var p = game.slots[i]
        if p <> nil and p <> game.held then
            drawPiece(p, 1, p.stuck)
        end
    end
end

func drawOver()
    var L = game.layout
    if game.fade.a < 0.01 then
        return
    end
    var c = L.c
    graphics.fill(config.paper, 0.85 * game.fade.a)
    graphics.rect(0, 0, W, H)
    var mx = L.bx + L.bs / 2
    drawText(tr("gameOver"), mx, L.by + 2.3 * c, fitSize(tr("gameOver"), c * 1.1, L.bs * 0.95), "center", "center", config.ink, game.fade.a)
    drawText("{tr("score")} {game.score}", mx, L.by + 3.6 * c, c * 0.7, "center", "center", config.ink, game.fade.a)
    if game.newBest then
        drawText(tr("newBest"), mx, L.by + 4.4 * c, c * 0.5, "center", "center", config.gold, game.fade.a)
    else
        drawText("{tr("best")} {game.best}", mx, L.by + 4.4 * c, c * 0.5, "center", "center", config.muted, game.fade.a)
    end
    drawButton(tr("newGame"), L.over, config.buttonPrimary, c * 0.55, game.fade.a)
end

func drawHelp()
    helpCompute()
    var help = game.help
    drawScreenTitle(tr("menuHelp"))
    var y = help.y
    for line in help.lines do
        if line <> "" then
            drawText(line, help.x, y, help.size, "left", "top", config.ink)
        end
        y += help.size * 1.35
    end
    drawText(tr("tapBack"), CX, H - SIZE * 0.04, SIZE * 0.027, "center", "center", config.muted)
end

func drawGallery()
    sheetCompute()
    drawScreenTitle(tr("menuPieces"))
    drawText("{len(pieces.shapes)} {tr("shapes")}, {tr("tapBack")}", CX, SIZE * 0.11, SIZE * 0.027, "center", "center", config.muted)
    var sheet = game.sheet
    for item in sheet.items do
        drawShape(item.shape, sheet.ox + item.x, sheet.oy + item.y, sheet.u)
    end
end
