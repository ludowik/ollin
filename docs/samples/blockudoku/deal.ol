## HOW A HAND IS DRAWN: pieces by the rules of board.ol and the weights of pieces.ol. At level 0 the game helps:
## the hand can be played to the end, one of its pieces clears something when the grid allows it, and a nearly full
## grid is given a small piece. The help fades out linearly up to DIFFICULTY.helpEnd, where only the rule of the game
## before levels is left: at least one piece of the hand must fit.

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
    for i = 1, HAND do
        picks.push(randomShape(level))
    end
    return picks
end

func hasSmall(picks)
    for s in picks do
        if s.n <= SMALL_CELLS then
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
func assist(g, picks, help, completing)
    var kept = 0
    if len(completing) > 0 and math.rand() < help then
        for i, s in picks do
            if completing.contains(s) then
                kept = i
                break
            end
        end
        if kept == 0 then
            kept = math.randInt(1, len(picks))
            picks[kept] = completing[math.randInt(1, len(completing))]
        end
    end
    var fill = boardFilled(g) / CELLS
    if fill >= DIFFICULTY.reliefFill + DIFFICULTY.reliefSpread * (1 - help) and not hasSmall(picks) then
        var options = pieces.small.filter(func(s) return boardAnyMove(g, s) end)
        if len(options) > 0 then
            picks[biggestSlot(picks, kept)] = options[math.randInt(1, len(options))]
        end
    end
end

## The hand a plain draw gives: redrawn until at least one piece fits, since a hand that cannot be played at all
## ends the game on the spot, which is no fault of the player's.
func drawPlayable(g, level)
    var picks = []
    for attempt = 1, DIFFICULTY.plainAttempts do
        picks = drawPicks(level)
        if fitsSomewhere(g, picks) then
            break
        end
    end
    return picks
end

## A helped hand, or nil when none was found in DIFFICULTY.dealAttempts tries: one that can be played to the end
## when `whole`, one with a piece that fits otherwise.
func helpedHand(g, level, help, completing, whole)
    for attempt = 1, DIFFICULTY.dealAttempts do
        var picks = drawPicks(level)
        assist(g, picks, help, completing)
        var ok = false
        if whole then
            ok = boardPlayAll(g, picks)
        else
            ok = fitsSomewhere(g, picks)
        end
        if ok then
            return picks
        end
    end
    return nil
end

## A hand for the grid `g` at `level`. A hand that can be played to the end is looked for first, with the chance
## the help has at that level; a crowded grid often has none, and then the help is kept with the rule of the game
## before levels (one piece that fits) before giving it up.
func drawHand(g, level)
    var help = helpAt(level)
    if help > 0 then
        var completing = boardCompleting(g, pieces.shapes)
        var picks = nil
        if math.rand() < help then
            picks = helpedHand(g, level, help, completing, true)
        end
        if picks == nil then
            picks = helpedHand(g, level, help, completing, false)
        end
        if picks <> nil then
            return picks
        end
    end
    return drawPlayable(g, level)
end
