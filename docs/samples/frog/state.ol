## What changes as a game runs: the screen it is on, the score, the frog, the lanes and what stands in the homes.

import "field.ol"
import "rules.ol"
import "layout.ol"
import "../lib/keep.ol"

const BEST_KEY     = "best"    ## where the best score is kept between two runs

global state     = "title"     ## "title", "play" or "over"
global paused    = false
global score     = 0
global best      = 0
global lives     = 0
global board     = 1
global extraGiven = false
global clock     = 0.0         ## seconds of play, which the turtles' diving is read from
global timeLeft  = TIME_LIMIT
global laneOff   = []          ## the offset of each lane's strip, lane 0..10
global homes     = []          ## whether a frog is in each home
global frog      = nil         ## {x, row, face, hop, dead (how it died), deadT, ready}
global furthest  = 0           ## the row nearest the homes this frog has reached: a row is only paid for once
global event     = nil         ## what is in a home now: {kind: "fly" or "crocodile", home, left}
global eventWait = EVENT_GAP
global rng       = nil
global viewH     = FIELD_H + PAD_MIN       ## the height of the viewport: the field and the strip of buttons under it
global buttons   = padButtons(FIELD_H + PAD_MIN)
global banner    = nil         ## a short message over the field: {text, left}

func resetLanes()
    laneOff = []
    for lane = 0, 10 do
        laneOff.push(lane * 37.0 % STRIP)       ## offsets that differ from one lane to the next, so the lanes do not start in step
    end
end

func clearHomes()
    homes = []
    for h = 1, HOMES do
        homes.push(false)
    end
end

func placeFrog()
    frog = {x: START_X, row: ROW_START, face: "up", hop: nil, dead: nil, deadT: 0.0, ready: READY_TIME}
    furthest = 0
    timeLeft = TIME_LIMIT
end

## The best score of earlier runs, and keeping a new one.
func loadBest()
    best = wholeOr(data.get(BEST_KEY, 0), 0, SCORE_MAX)
end

func saveBest()
    if score > best then
        best = score
        data.set(BEST_KEY, best)
    end
end

func resetField()
    resetLanes()
    clearHomes()
    placeFrog()
end

## A new game; without a seed, its own Random starts from the clock.
func newGame(seed)
    score = 0
    lives = LIVES
    board = 1
    extraGiven = false
    clock = 0.0
    event = nil
    eventWait = EVENT_GAP
    banner = nil
    if seed == nil then
        rng = Random()
    else
        rng = Random(seed)
    end
    resetField()
    state = "play"
end
