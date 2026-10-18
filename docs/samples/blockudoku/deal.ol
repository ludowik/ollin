## HOW A HAND IS DRAWN: three pieces, by the rules of board.ol and the weights of pieces.ol. At level 0 the game helps:
## the hand can be played to the end, one of its pieces clears something when the grid allows it, and a nearly full
## grid is given a small piece. The help fades out linearly up to DIFFICULTY.helpEnd, where only the rule of the game
## before levels is left: at least one piece of the hand must fit.

const DEAL_ATTEMPTS = 8       ## helped hands tried, in each phase, before falling back on a plain draw
const LEGACY_ATTEMPTS = 60
const RELIEF_FILL = 0.55      ## the share of filled cells from which a small piece is given, at level 0

func fitsSomewhere(g, picks)
    for s in picks do
        if boardAnyMove(g, s) then
            return true
        end
    end
    return false
end

func drawPicks(level)
    var picks = []
    for i = 1, 3 do
        picks.push(randomShape(level))
    end
    return picks
end

## The shapes of one or two cells, which fit almost anywhere.
func smallShapes()
    var out = []
    for s in pieces.shapes do
        if s.n <= 2 then
            out.push(s)
        end
    end
    return out
end

func hasSmall(picks)
    for s in picks do
        if s.n <= 2 then
            return true
        end
    end
    return false
end

## The slot of the hand holding the biggest piece, leaving out `kept` (0 when no slot is to be kept).
func biggestSlot(picks, kept)
    var slot = 0
    for i, s in picks do
        if i <> kept and (slot == 0 or s.n > picks[slot].n) then
            slot = i
        end
    end
    return slot
end

## Changes the hand in place: one piece that clears a zone, with a chance that is the help of the level, and a small
## piece when the grid is filling up. The piece that clears is never the one given up for the small one.
func assist(g, picks, help, completing, small)
    var kept = 0
    if len(completing) > 0 and math.rand() < help then
        for i, s in picks do
            if completing.contains(s) then
                kept = i
                break
            end
        end
        if kept == 0 then
            kept = math.randInt(1, 3)
            picks[kept] = completing[math.randInt(1, len(completing))]
        end
    end
    var fill = boardFilled(g) / CELLS
    if fill >= RELIEF_FILL + 0.5 * (1 - help) and not hasSmall(picks) then
        var options = []
        for s in small do
            if boardAnyMove(g, s) then
                options.push(s)
            end
        end
        if len(options) > 0 then
            picks[biggestSlot(picks, kept)] = options[math.randInt(1, len(options))]
        end
    end
end

## The hand a plain draw gives: redrawn until at least one piece fits, since a hand that cannot be played at all
## ends the game on the spot, which is no fault of the player's.
func drawPlayable(g, level)
    var picks = drawPicks(level)
    for attempt = 2, LEGACY_ATTEMPTS do
        if fitsSomewhere(g, picks) then
            break
        end
        picks = drawPicks(level)
    end
    return picks
end

## Three shapes for the grid `g` at `level`. A hand that can be played to the end is looked for first, with the
## chance the help has at that level; a crowded grid often has none, and then the help is kept with the rule of the
## game before levels (one piece that fits) before giving it up.
func drawHand(g, level)
    var help = helpAt(level)
    if help > 0 then
        var completing = boardCompleting(g, pieces.shapes)
        var small = smallShapes()
        var wholeHand = math.rand() < help
        for phase = 1, 2 do
            if phase == 2 or wholeHand then
                for attempt = 1, DEAL_ATTEMPTS do
                    var picks = drawPicks(level)
                    assist(g, picks, help, completing, small)
                    var ok = fitsSomewhere(g, picks)
                    if phase == 1 then
                        ok = boardPlayAll(g, picks)
                    end
                    if ok then
                        return picks
                    end
                end
            end
        end
    end
    return drawPlayable(g, level)
end
