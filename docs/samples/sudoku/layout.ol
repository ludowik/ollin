## Where the grid and its controls go.

## The grid and its controls in a column when the area is tall, side by side when it is wide: whichever gives the
## cells the room. Computed again only when W or H change.
func layoutCompute()
    var L = game.layout
    if not areaChanged(L) then
        return
    end
    var m = SIZE * config.margin
    var colH = 15.6
    var rowW = 15.0
    var cp = math.min((W - 2 * m) / N, (H - 2 * m) / colH)
    var cl = math.min((W - 2 * m) / rowW, (H - 2 * m) / N)
    var portrait = cp >= cl
    var c = math.floor(math.max(cp, cl))
    L.c = c
    L.bs = N * c
    L.pad = []
    L.tools = []
    if portrait then
        var top = (H - colH * c) / 2
        L.bx = (W - L.bs) / 2
        L.by = top + 1.9 * c
        L.titleX = L.bx
        L.titleY = top
        L.gear = rectOf(L.bx + L.bs - 1.3 * c, top + 0.1 * c, 1.3 * c, 1.3 * c)
        L.newBtn = rectOf(L.gear.x - 0.3 * c - 3.6 * c, top + 0.1 * c, 3.6 * c, 1.3 * c)
        L.msg = rectOf(L.bx, L.by + L.bs + 0.25 * c, L.bs, 1.3 * c)
        var y0 = L.by + L.bs + 1.75 * c
        for d = 1, N do
            L.pad.push(rectOf(L.bx + (d - 1) * c + 0.04 * c, y0, 0.92 * c, 1.3 * c))
        end
        var tw = (L.bs - 3 * 0.2 * c) / 4
        for k = 1, 4 do
            L.tools.push(rectOf(L.bx + (k - 1) * (tw + 0.2 * c), y0 + 1.65 * c, tw, 1.2 * c))
        end
    else
        var x0 = (W - rowW * c) / 2
        L.bx = x0
        L.by = (H - L.bs) / 2
        var rx = x0 + 9.6 * c
        var rw = 5.4 * c
        L.titleX = rx
        L.titleY = L.by
        L.gear = rectOf(rx + rw - 1.2 * c, L.by, 1.2 * c, 1.2 * c)
        L.newBtn = rectOf(rx, L.by + 1.5 * c, rw, 1.1 * c)
        L.msg = rectOf(rx, L.by + 2.8 * c, rw, 1.6 * c)
        var kw = (rw - 2 * 0.15 * c) / 3
        for d = 1, N do
            var col = (d - 1) % 3
            var row = (d - 1) // 3
            L.pad.push(rectOf(rx + col * (kw + 0.15 * c), L.by + 4.6 * c + row * (0.95 * c + 0.12 * c), kw, 0.95 * c))
        end
        var tw = (rw - 3 * 0.1 * c) / 4
        for k = 1, 4 do
            L.tools.push(rectOf(rx + (k - 1) * (tw + 0.1 * c), L.by + 7.9 * c, tw, 1.1 * c))
        end
    end
end

## The top-left corner of a cell on the screen.
func cellPos(i)
    var L = game.layout
    return L.bx + (board.colOf[i] - 1) * L.c, L.by + (board.rowOf[i] - 1) * L.c
end

## The cell under a point, or 0.
func cellAt(x, y)
    var L = game.layout
    if x < L.bx or y < L.by or x >= L.bx + L.bs or y >= L.by + L.bs then
        return 0
    end
    return boardIdx(math.floor((y - L.by) / L.c) + 1, math.floor((x - L.bx) / L.c) + 1)
end
