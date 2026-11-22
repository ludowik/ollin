## The game of Frog applied to the frog (docs/samples/frog/play.ol): hopping and what it earns, what a vehicle, the water, the
## edge of the field and the clock do, the homes, the fly and the crocodile, the extra frogs and the end of the game.

import "play.ol"

## A new game with a frog that can move at once and lanes at a known offset.
func fresh()
    newGame(1)
    frog.ready = 0.0
    for lane = 0, 10 do
        laneOff[lane + 1] = 0.0
    end
end

## Runs the game for a time in steps of a twentieth of a second.
func run(seconds)
    for i = 1, math.floor(seconds / 0.05 + 0.5) do
        updateFrame(0.05)
    end
end

## ── A new game ───────────────────────────────────────────────────────────────────────────────────────────────────────────
newGame(1)
assert(state == "play" and score == 0 and lives == LIVES and board == 1 and #homes == HOMES and #laneOff == 11)
assert(frog.row == ROW_START and frog.x == START_X and frog.dead == nil and not extraGiven)
tryHop("up")
assert(frog.hop == nil, "a new frog is held a moment before it can move")

## ── Hopping ──────────────────────────────────────────────────────────────────────────────────────────────────────────────
fresh()
tryHop("up")
assert(frog.hop <> nil and frog.face == "up" and frog.row == 0, "a hop takes time")
tryHop("left")
assert(frog.hop.toRow == 1 and frog.hop.toX == START_X, "and the frog cannot be steered while it is in the air")
run(HOP_TIME + 0.05)
assert(frog.row == 1 and frog.hop == nil and frog.x == START_X and score == SCORE_HOP, "a hop of a row is worth ten")
tryHop("down")
run(HOP_TIME + 0.05)
assert(frog.row == 0 and score == SCORE_HOP, "going back is worth nothing")
tryHop("up")
run(HOP_TIME + 0.05)
assert(score == SCORE_HOP, "and neither is the row it has already been to")
fresh()
frog.x = COLUMN_X0
tryHop("left")
assert(frog.hop == nil, "a hop that would leave the field is refused")
frog.x = COLUMN_X0 + 16 * 12
tryHop("right")
assert(frog.hop == nil)
fresh()
frog.row = ROW_START
tryHop("down")
assert(frog.hop == nil, "and so is one below the start strip")

## ── The road ─────────────────────────────────────────────────────────────────────────────────────────────────────────────
fresh()
frog.row = 5
frog.x = 8
run(0.1)
assert(frog.dead == "car", "a frog in the way of a truck is run down")
fresh()
frog.row = 5
frog.x = 56
run(0.1)
assert(frog.dead == nil, "in a gap it lives")

## ── The river ────────────────────────────────────────────────────────────────────────────────────────────────────────────
fresh()
frog.row = 8
frog.x = 56
run(0.1)
assert(frog.dead == "drown", "a frog between two logs falls in the water")
fresh()
frog.row = 8
frog.x = 8
run(0.5)
assert(frog.dead == nil and frog.x > 8 and math.abs(frog.x - (8 + 0.5 * LANE_SPEED[4])) < 0.5, "a frog on a log goes where the log goes")
fresh()
frog.row = 8
frog.x = 200
run(1.5)
assert(frog.dead == "edge", "a frog the river carries off the field is lost")
fresh()
frog.row = 8
frog.x = 8
run(0.3)
tryHop("up")
run(HOP_TIME + 0.05)
assert(frog.row == 9, "a hop from a log lands on the next row of the river")

## A frog hit in the air is where it was hit, not where it started the hop.
fresh()
frog.row = 4
frog.x = 20
tryHop("up")
run(0.1)
assert(frog.dead == "car" and frog.row == 5 and frog.hop == nil and frog.x > 20 - 0.1 and frog.x < 20.1 + 0.1, "the wreck is on the row of the truck")

## ── The clock ────────────────────────────────────────────────────────────────────────────────────────────────────────────
fresh()
timeLeft = 0.04
run(0.1)
assert(frog.dead == "time", "a frog that takes too long is lost")
fresh()
run(2.0)
assert(math.abs(timeLeft - (TIME_LIMIT - 2.0)) < 0.01, "the clock runs down while the frog lives")

## ── The homes ────────────────────────────────────────────────────────────────────────────────────────────────────────────
## A frog about to hop from the last row of the river into home h.
func atHome(h)
    fresh()
    frog.row = 11
    frog.x = homeX(h)
    tryHop("up")
    run(HOP_TIME + 0.05)
end

atHome(3)
assert(homes[3] and not homes[2] and frog.row == ROW_START and frog.dead == nil, "a frog that gets home is in it, and the next one starts")
assert(score >= SCORE_HOME + SCORE_SECOND * 28 and score < SCORE_HOME + SCORE_SECOND * 31, "and is paid for the time it has left, and not for the last row too")
assert(timeLeft > TIME_LIMIT - 0.2, "the clock starts again")
fresh()
frog.row = 11
frog.x = 80
tryHop("up")
run(HOP_TIME + 0.05)
assert(frog.dead == "wall" and score == 0, "a frog that arrives between two homes is against the wall, and is paid nothing for the row")
fresh()
homes[3] = true
frog.row = 11
frog.x = homeX(3)
tryHop("up")
run(HOP_TIME + 0.05)
assert(frog.dead == "wall", "and one that arrives in a home that is full")
fresh()
event = {kind: "crocodile", home: 3, left: 5.0}
frog.row = 11
frog.x = homeX(3)
tryHop("up")
run(HOP_TIME + 0.05)
assert(frog.dead == "croc" and not homes[3], "the crocodile in a home eats the frog that comes in")
fresh()
event = {kind: "fly", home: 3, left: 5.0}
frog.row = 11
frog.x = homeX(3)
tryHop("up")
run(HOP_TIME + 0.05)
assert(homes[3] and event == nil and score >= SCORE_FLY + SCORE_HOME, "the fly in a home is eaten and paid for")

## All five homes full: a new board, a faster one, with an extra frog.
fresh()
homes = [true, true, false, true, true]
var livesBefore = lives
frog.row = 11
frog.x = homeX(3)
tryHop("up")
run(HOP_TIME + 0.05)
assert(board == 2 and lives == livesBefore + 1 and homes[3] == false and homes[1] == false, "five frogs home end the board")
assert(banner <> nil and banner.text == "LEVEL 2")

## ── The score and the end ────────────────────────────────────────────────────────────────────────────────────────────────
fresh()
score = EXTRA_AT - 10
earn(50)
assert(lives == LIVES + 1 and extraGiven, "an extra frog at twenty thousand")
earn(50)
assert(lives == LIVES + 1, "only the first time")

fresh()
die("car")
run(DEATH_TIME + 0.1)
assert(lives == LIVES - 1 and frog.dead == nil and frog.row == ROW_START and state == "play", "a death costs a life and the next frog starts")
fresh()
lives = 1
score = 1230
best = 0
die("drown")
run(DEATH_TIME + 0.1)
assert(state == "over" and lives == 0 and best == 1230, "the last life ends the game and the best score is kept")
assert(data.get(BEST_KEY, 0) == 1230)
tryHop("up")
assert(frog.hop == nil, "nothing moves once the game is over")

## ── The fly and the crocodile ────────────────────────────────────────────────────────────────────────────────────────────
fresh()
event = nil
eventWait = 0.0
updateEvent(0.05)
assert(event <> nil and (event.kind == "fly" or event.kind == "crocodile") and event.home >= 1 and event.home <= HOMES, "one turns up when its time comes")
assert(event.left == EVENT_LIFE)
var seen = event
updateEvent(EVENT_LIFE + 1.0)
assert(event == nil and eventWait >= EVENT_GAP, "and goes after a while")
fresh()
homes = [true, true, true, true, false]
eventWait = 0.0
updateEvent(0.05)
assert(event.home == 5, "only an empty home is chosen")
## ── The screens around a game: the lanes run on the title and under the end screen, and a pause stops them ─────────────────
state = "title"
var before = laneOff[1]
updateFrame(0.05)
assert(laneOff[1] <> before, "the lanes run behind the title")
state = "over"
frog.deadT = 0.0
updateFrame(0.05)
assert(frog.deadT == 0.05, "the wreck stays under the end screen")
fresh()
paused = true
before = laneOff[1]
updateFrame(0.05)
assert(laneOff[1] == before, "nothing moves while the game is paused")
paused = false

## ── The buttons ──────────────────────────────────────────────────────────────────────────────────────────────────────────
fresh()
pressButton("up")
assert(frog.hop <> nil and frog.hop.toRow == 1, "the up button hops the frog")
run(HOP_TIME + 0.05)
pressButton("pause")
assert(paused, "the pause button pauses")
pressButton("pause")
assert(not paused, "and pauses again to resume")
var wasOn = soundOn
pressButton("sound")
assert(soundOn <> wasOn, "the sound button switches the sound")
pressButton("sound")
state = "title"
pressButton("pause")
assert(not paused, "there is nothing to pause on the title")
state = "play"

## A tap: the same for a mouse and for every finger.
fresh()
var arrowUp = buttons[1]
tap(arrowUp.x + 2, arrowUp.y + 2)
assert(frog.hop <> nil, "a tap on an arrow hops")
run(HOP_TIME + 0.05)
tap(5, 5)
assert(frog.hop == nil, "a tap elsewhere does nothing")
paused = true
var rowNow = frog.row
tap(arrowUp.x + 2, arrowUp.y + 2)
assert(not paused and frog.hop == nil and frog.row == rowNow, "a tap on an arrow that resumes a paused game does not hop as well")
tap(buttons[5].x + 2, buttons[5].y + 2)
assert(paused, "a tap on PAUSE pauses")
paused = false
state = "over"
frog.deadT = 0.0
tap(5, 5)
assert(state == "over", "a tap during the end of a game does not start another")
frog.deadT = 2.0
tap(5, 5)
assert(state == "play" and lives == LIVES, "a tap on the end screen starts a game")

print("frog play ok")
