## What changes as a game runs: the screen it is on, the score, the frog, the lanes and what stands in the homes.

import "field.ol"
import "rules.ol"

const HOP_TIME     = 0.14      ## seconds a hop lasts: the frog cannot be steered meanwhile
const DEATH_TIME   = 1.3       ## how long the wreck is shown before the next frog, or the end
const EVENT_LIFE   = 6.0       ## how long a fly or a crocodile stays in its home
const EVENT_GAP    = 9.0       ## seconds between two, at least; the rest is drawn by the game's own Random
const READY_TIME   = 1.2       ## a new frog is held that long before it can move

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
global frog      = {x: START_X, row: 0, face: "up", hop: nil, dead: nil, deadT: 0.0, ready: 0.0}
global furthest  = 0           ## the row nearest the homes this frog has reached: a row is only paid for once
global event     = nil         ## what is in a home now: {kind: "fly" or "crocodile", home, left}
global eventWait = EVENT_GAP
global rng       = nil
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

func newGame(seed)
    score = 0
    lives = LIVES
    board = 1
    extraGiven = false
    clock = 0.0
    event = nil
    eventWait = EVENT_GAP
    banner = nil
    rng = Random(seed)
    resetLanes()
    clearHomes()
    placeFrog()
    state = "play"
end
