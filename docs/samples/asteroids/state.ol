## The numbers that set the game, and what changes as it runs.

const SHIP_R      = 11.0       ## the ship's collision radius; the outline is drawn at this scale
const TURN_SPEED  = 5.2        ## radians per second, on the keyboard — turning is free and instant
const TURN_SNAP   = 14.0       ## radians per second at which the nose swings to the stick's aim
const THRUST      = 340.0      ## field pixels per second, per second
const DRAG        = 0.7        ## a whisper of drag, so a stray push does not last for ever
const MAX_SPEED   = 340.0
const AIM_DEAD    = 0.2        ## how far the stick must leave the centre before it means a direction
const FIRE_RATE   = 0.13       ## seconds between two shots while the trigger is held
const SPAWN_WAIT  = 1.6        ## how long the wreck is shown before the next ship appears
const CLEAR_R     = 70.0       ## the centre must be this clear before a ship is put back

const SHOT_SPEED  = 420.0
const SHOT_LIFE   = 0.9        ## a shot's RANGE, as the time it lives: it does not cross the field

## The three rock sizes, as radii, and what each is worth. Index 3 is the large rock, 1 the small:
## a split lands on `size - 1`, so the table is read by the size itself and no mapping is needed.
const ROCK_R      = [9.0, 18.0, 34.0]
const ROCK_SCORE  = [100, 50, 20]
const ROCK_SPEED  = [78.0, 52.0, 30.0]     ## each generation is faster than its parent
const ROCK_SPIN   = 1.2                    ## how fast a rock turns on itself, at most

const WAVE_ROCKS  = 4          ## the first wave, plus two per wave after it
const WAVE_MAX    = 11
const WAVE_WAIT   = 1.8        ## the breath between a cleared wave and the next

const SAUCER_PERIOD = 16.0     ## seconds between two crossings
const SAUCER_SPEED  = 95.0
const SAUCER_SHOT   = 1.1      ## seconds between the saucer's shots
const SAUCER_SMALL_AT = 4000   ## above this score the small saucer starts to appear
const SAUCER_BIG_SCORE   = 200
const SAUCER_SMALL_SCORE = 1000

const LIVES     = 3
const EXTRA_AT  = 10000        ## an extra ship every ten thousand points

const INK   = Color(0.92, 0.95, 1.0)
const DIM   = Color(0.45, 0.5, 0.6)
const WARM  = Color(1.0, 0.78, 0.35)

global state = "title"
global paused = false
global score = 0
const BEST_KEY = "best"
global best = 0                ## the best score, kept from one run to the next
global lives = LIVES
global wave = 1
global nextExtra = EXTRA_AT

global ship = nil              ## nil while the wreck is shown: no ship on the field
global spawn = 0.0             ## the countdown to the next ship
global waveWait = 0.0

global rocks = []
global shots = []
global saucer = nil
global saucerShots = []
global saucerTimer = SAUCER_PERIOD
global debris = []             ## the fading sparks of anything that came apart

## The outlines at the sizes the game draws them, sized ONCE by buildArt (see shapes.ol).
global rockArt = []           ## [shape][size]
global shipArt = nil
global shipIcon = nil         ## the smaller ship of the lives counter
global flameArt = nil
global saucerArt = nil        ## .big / .small, each with its hull and its deck

global beatTimer = 0.0
global beatStep = 0            ## which of the two heartbeat notes comes next

## The joystick is moved into the bottom-RIGHT corner and made smaller than its default: the whole
## field is played in here, so a disc in the middle would sit over the action — and the ship could
## end up UNDER it. Right, because that is the thumb that steers on every modern handheld, the left
## one being the trigger.
global pad = Joystick()
pad.centerXFrac = 0.8
pad.centerFrac = 0.78
pad.radiusFrac = 0.17
pad.floating = true            ## the stick anchors where the thumb lands: no target to hit
global padId = nil
global fireId = nil            ## the finger holding the trigger, if any — nil means not held
global fireTimer = 0.0         ## the cadence of a held trigger, on the glass as on the keyboard
global touchPlay = false       ## a finger has played: the hint and the mouse relays follow it
global demo = 0.0              ## the title screen's own clock

## Scoring passes through here alone, so the extra ship cannot be missed on one of the four things
## worth points.
func award(points)
    score += points
    while score >= nextExtra do
        lives += 1
        nextExtra += EXTRA_AT
    end
    if score > best then
        best = score
        data.set(BEST_KEY, best)
    end
end

func burst(x, y, n, spread)
    for i = 1, n do
        var a = math.rand() * math.TAU
        var sp = spread * (0.3 + math.rand() * 0.7)
        debris.push({x: x, y: y, vx: math.cos(a) * sp, vy: math.sin(a) * sp, left: 0.35 + math.rand() * 0.4})
    end
end
