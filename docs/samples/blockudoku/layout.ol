## Where everything goes: the board and its trays in a column when the area is tall, side by side when it is wide, the
## catalogue of every piece, and the help text cut into lines.

## The board and its trays in a column when the area is tall, side by side when it is wide: whichever
## gives the larger cell. It depends on W and H alone, so it is recomputed only when they change.
func layoutCompute()
    var L = game.layout
    if not areaChanged(L) then
        return
    end
    var m = SIZE * config.margin
    ## What the area must hold, in cells: the height of the column (header, board, trays) when it stands, and the width
    ## of the board plus its side column when they stand together. They add up the offsets placed below.
    var colH = 15.2
    var rowW = 14.3
    var cp = math.min((W - 2 * m) / GRID, (H - 2 * m) / colH)
    var cl = math.min((H - 2 * m) / GRID, (W - 2 * m) / rowW)
    var portrait = cp >= cl
    var c = math.floor(math.max(cp, cl))
    var gear = math.max(SIZE * 0.08, 40)
    L.gear = rectOf(W - m - gear, m, gear, gear)
    if portrait then
        ## The header must not run under the gear: a narrow and short area shrinks the board until it clears.
        while c > 8 and (W + GRID * c) / 2 > L.gear.x - 0.3 * m and (H - colH * c) / 2 < L.gear.y + gear + 0.3 * m do
            c -= 1
        end
    end
    var bs = GRID * c
    L.c = c
    L.bs = bs
    if portrait then
        var top = (H - colH * c) / 2
        L.bx = (W - bs) / 2
        L.by = top + 2.6 * c
        L.scoreX = L.bx
        L.scoreY = top
        L.bestX = L.bx + 3.5 * c
        L.bestY = top
        L.newBtn = rectOf(L.bx + 6.2 * c, top, 2.8 * c, 1.1 * c)
        L.tc = 0.55 * c
        L.sw = 1.5 * c
        L.sh = 1.6 * c
        for i = 1, 3 do
            L.sx[i] = L.bx + bs * (2 * i - 1) / 6
            L.sy[i] = L.by + bs + 2.0 * c
        end
    else
        var x0 = (W - (bs + 0.5 * c + 4.8 * c)) / 2
        var colX = x0 + bs + 0.5 * c
        L.bx = x0
        L.by = (H - bs) / 2
        L.scoreX = colX
        L.scoreY = L.by
        L.bestX = colX
        L.bestY = L.by + 1.6 * c
        L.newBtn = rectOf(colX + 2.5 * c, L.by + 1.65 * c, 2.3 * c, 1.1 * c)
        L.tc = 0.36 * c
        L.sw = 2.4 * c
        L.sh = 1.0 * c
        for i = 1, 3 do
            L.sx[i] = colX + 2.4 * c
            L.sy[i] = L.by + 3.0 * c + (i - 0.5) * 2.0 * c
        end
    end
    L.over = rectOf(L.bx + bs / 2 - 2.2 * c, L.by + 5.2 * c, 4.4 * c, 1.4 * c)
end

## The catalogue: every shape the game can deal, as large as the screen lets them be.
func sheetCompute()
    if not areaChanged(game.sheet) then
        return
    end
    var m = SIZE * config.margin
    var top = SIZE * config.titleBand
    var areaW = W - 2 * m
    var areaH = H - top - m
    var u = math.floor(areaW / 5)
    var items, used = packShapes(u, areaW)
    while used > areaH and u > 4 do
        u -= 1
        items, used = packShapes(u, areaW)
    end
    game.sheet.u = u
    game.sheet.ox = m
    game.sheet.oy = top + (areaH - used) / 2
    game.sheet.items = items
end

## What the help says, one string per paragraph, in the current language. The figures come from config, so the text
## cannot drift from the rules.
func helpParagraphs()
    return tr("help")({box: BOX, cell: config.pointsPerCell, zone: GRID * config.pointsPerClearedCell, streak: config.streakBonus})
end

## The help cut into lines no wider than areaW: a blank line ends each paragraph.
func wrapHelp(size, areaW)
    return wrapParagraphs(helpParagraphs(), size, areaW)
end

## The help at the largest size that fits under the title.
func helpCompute()
    var help = game.help
    if not areaChanged(help) and help.lang == i18n.lang then
        return
    end
    help.lang = i18n.lang
    var m = SIZE * config.textMargin
    var top = SIZE * config.titleBand
    var areaW = W - 2 * m
    var areaH = H - top - m
    var size = math.floor(SIZE * 0.04)
    var lines = wrapHelp(size, areaW)
    while len(lines) * size * 1.35 > areaH and size > 10 do
        size -= 1
        lines = wrapHelp(size, areaW)
    end
    help.x = m
    help.y = top
    help.size = size
    help.lines = lines
end
