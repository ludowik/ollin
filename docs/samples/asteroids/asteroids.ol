## Ollin Asteroids — the drifting field, the ship with no brake, four shots at a time, the rocks
## that split into faster ones, the saucer that shoots back, and the heartbeat under it all.
##
## The RULE that makes this genre work, and the one most often missed: the ship has NO brake.
## Thrust adds to a velocity that never goes away, so every manoeuvre has to be paid for with the
## opposite one. Turning is free and instant, moving is not — that asymmetry IS the game, and any
## friction strong enough to stop the ship would quietly delete it.
##
## The second rule: shooting a rock does not remove it, it MULTIPLIES it. A large rock becomes two
## medium ones, a medium two small, and each generation moves faster than the one before. Clearing
## a wave therefore makes the field more dangerous before it makes it empty, which is why a careful
## player shoots the small ones first.
##
## Everything wraps: an object leaving an edge comes back on the other side. The field has no
## walls, so there is no corner to hide in — the only shelter is empty space, and it is temporary.
##
## The heartbeat is not a soundtrack. Its tempo is the number of rocks LEFT, so it quickens on its
## own as the wave empties: the sound tells the player how much is still out there without a single
## number being read.
##
## The saucer's aim improves with the SCORE, as the original's did. A beginner is shot at wildly, a
## good player is shot at deliberately — the game gets harder because the player got better, not
## because a wave counter said so.
##
## The game has THREE states, and one variable says which: the title screen, the play, and the end.
## Every input asks that variable first, so no callback has to guess whether the game is running.
##
## Desktop: left and right turn, up thrusts, space fires (held down, it keeps firing), P pauses.
##
## On a touch screen the control is MODERN, not a copy of the cabinet's five buttons. The joystick
## sits under the RIGHT thumb and is read as a DIRECTION, not as a turn: the nose swings to where
## the stick points and the thrust is the stick's own distance from the centre, so a player aims
## where they want to go instead of spelling it out with turn-left, turn-right, thrust. The LEFT
## half of the glass is the trigger, held down rather than tapped. Two thumbs, two jobs, and
## neither ever crosses the other — the first version steered with one thumb and fired with taps of
## the same hand, which is what made it unplayable.

## The look and the sound live apart: the outlines in shapes.ol, the notes and the noises in
## sounds.ol. The joystick is not ours to keep here — it is shared with the voxel example.
import "shapes.ol"
import "sounds.ol"
import "../lib/joystick.ol"

const FIELD_W = 512            ## the field, in its own pixels — graphics.viewport does the rest
const FIELD_H = 384

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
const SHOTS_MAX   = 4          ## how many of the player's shots may be in the air

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
const SAUCER_BIG_R  = 16.0
const SAUCER_SMALL_R = 9.0
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
global best = 0                ## the best score of the session
global lives = LIVES
global wave = 1
global nextExtra = EXTRA_AT

global ship = nil              ## nil while the wreck is shown: no ship on the field
global spawn = 0.0             ## the countdown to the next ship
global waveWait = 0.0          ## the countdown to the next wave

global rocks = []
## Rocks born from a split wait here until the pass that made them is over: the collision pass
## REPLACES `rocks` with a filtered copy, so a child pushed during it would be thrown away with
## its parent. Staging them is the only way the two can both be true at once.
global spawnedRocks = []
global shots = []
global saucer = nil
global saucerShots = []
global saucerTimer = SAUCER_PERIOD
global debris = []             ## the fading sparks of anything that came apart

global beatTimer = 0.0
global beatStep = 0            ## which of the two heartbeat notes comes next
global thrusting = false

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
global fireId = nil            ## the finger holding the trigger, if any
global fireHeld = false
global fireTimer = 0.0         ## the cadence of a held trigger, on the glass as on the keyboard
global touchPlay = false       ## a finger has played: the hint and the mouse relays follow it
global demo = 0.0              ## the title screen's own clock

## ── The field's one law: everything wraps ────────────────────────────────────
## Written once and applied to every moving thing, so nothing can be forgotten on one object and
## leave it flying off into nowhere.
func wrap(o)
    if o.x < 0.0 then
        o.x += FIELD_W
    elseif o.x >= FIELD_W then
        o.x -= FIELD_W
    end
    if o.y < 0.0 then
        o.y += FIELD_H
    elseif o.y >= FIELD_H then
        o.y -= FIELD_H
    end
end

## The distance between two points on a wrapped field is the SHORTEST of the ways round. Ignoring
## that made a shot pass through a rock straddling an edge, the two being a field apart by their
## coordinates and a few pixels apart on the screen.
func near(ax, ay, bx, by, r)
    var dx = math.abs(ax - bx)
    var dy = math.abs(ay - by)
    if dx > FIELD_W / 2 then
        dx = FIELD_W - dx
    end
    if dy > FIELD_H / 2 then
        dy = FIELD_H - dy
    end
    return dx * dx + dy * dy <= r * r
end

func advance(o, dt)
    o.x += o.vx * dt
    o.y += o.vy * dt
    wrap(o)
end

## ── The rocks ────────────────────────────────────────────────────────────────

func addRock(x, y, size)
    var a = math.rand() * math.TAU
    var sp = ROCK_SPEED[size] * (0.6 + math.rand() * 0.7)
    spawnedRocks.push({
        x: x, y: y,
        vx: math.cos(a) * sp, vy: math.sin(a) * sp,
        size: size,
        shape: math.randInt(1, #ROCKS),
        rot: math.rand() * math.TAU,
        spin: (math.rand() * 2 - 1) * ROCK_SPIN
    })
end

func flushRocks()
    for r in spawnedRocks do
        rocks.push(r)
    end
    spawnedRocks = []
end

## A new rock is placed AWAY from the centre, where the ship stands: dropping one on the ship would
## kill it before the player has touched a key, and no reflex could save it.
func newWave()
    if saucer <> nil then
        dropSaucer()
    end
    rocks = []
    spawnedRocks = []
    shots = []
    saucerShots = []
    var n = math.min(WAVE_ROCKS + (wave - 1) * 2, WAVE_MAX)
    for i = 1, n do
        var x = 0.0
        var y = 0.0
        var tries = 0
        ## A bounded search, then whatever it holds: an unbounded one would hang the frame on a
        ## crowded field, and the worst it can give here is a rock a little close.
        while tries < 40 do
            x = math.rand() * FIELD_W
            y = math.rand() * FIELD_H
            tries += 1
            if not near(x, y, FIELD_W / 2, FIELD_H / 2, CLEAR_R + ROCK_R[3]) then
                tries = 40
            end
        end
        addRock(x, y, 3)
    end
    flushRocks()
    saucerTimer = SAUCER_PERIOD
end

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
    end
end

func burst(x, y, n, spread)
    for i = 1, n do
        var a = math.rand() * math.TAU
        var sp = spread * (0.3 + math.rand() * 0.7)
        debris.push({x: x, y: y, vx: math.cos(a) * sp, vy: math.sin(a) * sp, left: 0.35 + math.rand() * 0.4})
    end
end

## Breaking a rock is the game's central act: it REPLACES the rock with two faster, smaller ones,
## and only the smallest leaves nothing behind.
func breakRock(r)
    award(ROCK_SCORE[r.size])
    sndBang[r.size].play()
    burst(r.x, r.y, 6 + r.size * 3, 60.0 + r.size * 20.0)
    if r.size > 1 then
        addRock(r.x, r.y, r.size - 1)
        addRock(r.x, r.y, r.size - 1)
    end
end

## ── The ship ─────────────────────────────────────────────────────────────────

func newShip()
    ship = {x: FIELD_W / 2, y: FIELD_H / 2, vx: 0.0, vy: 0.0, ang: -math.PI / 2}
end

func killShip()
    sndDeath.play()
    burst(ship.x, ship.y, 16, 90.0)
    ship = nil
    thrusting = false
    lives -= 1
    if lives <= 0 then
        state = "over"
        return
    end
    spawn = SPAWN_WAIT
end

func fire()
    if ship == nil or state <> "play" or paused then
        return
    end
    if #shots >= SHOTS_MAX then
        return
    end
    ## The shot leaves the nose and inherits the ship's velocity: flying backwards while firing
    ## forwards must not let the player overtake their own shots.
    shots.push({
        x: ship.x + math.cos(ship.ang) * SHIP_R * 1.4,
        y: ship.y + math.sin(ship.ang) * SHIP_R * 1.4,
        vx: ship.vx + math.cos(ship.ang) * SHOT_SPEED,
        vy: ship.vy + math.sin(ship.ang) * SHOT_SPEED,
        left: SHOT_LIFE
    })
    sndFire.play()
end

## ── The saucer ───────────────────────────────────────────────────────────────
## It enters from one side, crosses in a lane of its own, and swerves now and then so it cannot be
## led like a clay pigeon. The SMALL one only turns up once the player has scored: it is the
## harder target and the bigger prize.

func spawnSaucer()
    var small = score >= SAUCER_SMALL_AT and math.rand() < 0.5
    var dir = 1
    var x = -SAUCER_BIG_R
    if math.rand() < 0.5 then
        dir = -1
        x = FIELD_W + SAUCER_BIG_R
    end
    saucer = {
        x: x, y: 40.0 + math.rand() * (FIELD_H - 80.0),
        vx: SAUCER_SPEED * dir, vy: 0.0,
        small: small,
        r: SAUCER_SMALL_R,
        shoot: SAUCER_SHOT,
        swerve: 1.0
    }
    if not small then
        saucer.r = SAUCER_BIG_R
    end
    saucerVoice.start()
end

func dropSaucer()
    saucer = nil
    saucerVoice.stop()
    saucerTimer = SAUCER_PERIOD
end

## The saucer's AIM is the game's difficulty curve, and it is the score that draws it: the error on
## its shot shrinks from a whole quadrant to almost nothing. The small saucer aims better still, at
## every score.
func saucerFire()
    if ship == nil then
        return
    end
    var aim = math.atan2(ship.y - saucer.y, ship.x - saucer.x)
    var err = math.max(0.05, 0.8 - score / 12000.0)
    if saucer.small then
        err *= 0.4
    end
    aim += (math.rand() * 2 - 1) * err
    saucerShots.push({
        x: saucer.x, y: saucer.y,
        vx: math.cos(aim) * SHOT_SPEED * 0.7,
        vy: math.sin(aim) * SHOT_SPEED * 0.7,
        left: SHOT_LIFE * 1.3
    })
    sndFire.play()
end

func killSaucer()
    var points = SAUCER_BIG_SCORE
    if saucer.small then
        points = SAUCER_SMALL_SCORE
    end
    award(points)
    sndSaucerDie.play()
    burst(saucer.x, saucer.y, 14, 100.0)
    dropSaucer()
end

func saucerUpdate(dt)
    if saucer == nil then
        saucerTimer -= dt
        ## It stays away while the field is nearly clear: the last rocks must not have to be shot
        ## at through it.
        if saucerTimer <= 0.0 and #rocks > 1 and state == "play" then
            spawnSaucer()
        end
        return
    end
    saucer.swerve -= dt
    if saucer.swerve <= 0.0 then
        saucer.vy = (math.rand() * 2 - 1) * SAUCER_SPEED * 0.6
        saucer.swerve = 0.6 + math.rand() * 0.9
    end
    saucer.x += saucer.vx * dt
    saucer.y += saucer.vy * dt
    saucer.y = math.clamp(saucer.y, 20.0, FIELD_H - 20.0)
    saucerVoice.freq(SAUCER_HUM + SAUCER_WARBLE * math.sin(elapsedTime * SAUCER_RATE))
    ## It crosses the field ONCE. It does not wrap: a wrapping saucer would never leave, and the
    ## crossing is what makes it an event.
    if saucer.x < -saucer.r * 2 or saucer.x > FIELD_W + saucer.r * 2 then
        dropSaucer()
        return
    end
    saucer.shoot -= dt
    if saucer.shoot <= 0.0 then
        saucerFire()
        saucer.shoot = SAUCER_SHOT
    end
end

## ── The frame ────────────────────────────────────────────────────────────────

## The heartbeat's tempo is the number of rocks left, from slow on a full field to urgent on the
## last one. Nothing schedules it: this is read from the field itself, every frame.
func beat(dt)
    beatTimer -= dt
    if beatTimer > 0.0 then
        return
    end
    var period = math.clamp(0.28 + #rocks * 0.09, 0.28, 1.1)
    beatTimer = period
    sndBeat[beatStep + 1].play()
    beatStep = (beatStep + 1) % 2
end

## Anything the player fired, or was fired at, dies of OLD AGE — that is what gives a shot its
## range. The two lists differ only in what they hit, so the ageing is written once.
func ageShots(list, dt)
    return list.filter(func(s)
        advance(s, dt)
        s.left -= dt
        return s.left > 0.0
    end)
end

## The player's shots against the rocks and the saucer. A shot is spent by the first thing it
## touches, so it cannot cut a line through a cluster.
func shotsHit()
    shots = shots.filter(func(s)
        if saucer <> nil and near(s.x, s.y, saucer.x, saucer.y, saucer.r) then
            killSaucer()
            return false
        end
        var alive = true
        rocks = rocks.filter(func(r)
            if alive and near(s.x, s.y, r.x, r.y, ROCK_R[r.size]) then
                breakRock(r)
                alive = false
                return false
            end
            return true
        end)
        return alive
    end)
end

## What can kill the ship, all of it in one place: a rock, a saucer's shot, the saucer itself.
func shipHit()
    if ship == nil then
        return
    end
    for r in rocks do
        if near(ship.x, ship.y, r.x, r.y, ROCK_R[r.size] + SHIP_R * 0.7) then
            breakRock(r)
            rocks = rocks.filter(func(o) return o <> r end)
            killShip()
            return
        end
    end
    if saucer <> nil and near(ship.x, ship.y, saucer.x, saucer.y, saucer.r + SHIP_R * 0.7) then
        killSaucer()
        killShip()
        return
    end
    for s in saucerShots do
        if near(ship.x, ship.y, s.x, s.y, SHIP_R) then
            saucerShots = saucerShots.filter(func(o) return o <> s end)
            killShip()
            return
        end
    end
end

## A ship is only put back when the CENTRE is clear. Dropping it under a rock would cost a life to
## a player who was doing nothing wrong, so the countdown waits instead of expiring.
func centreClear()
    for r in rocks do
        if near(FIELD_W / 2, FIELD_H / 2, r.x, r.y, CLEAR_R + ROCK_R[r.size]) then
            return false
        end
    end
    return saucer == nil
end

## The shortest way round from one angle to the other. Without it the nose took the long way for
## every command that crossed the half-turn — the stick pointing a few degrees the other side of
## straight-up sent the ship spinning all the way round.
func angleTo(from, to)
    var d = math.frac((to - from) / math.TAU + 0.5) * math.TAU - math.PI
    if d < -math.PI then
        d += math.TAU
    end
    return d
end

## The stick is a DIRECTION, and its distance from the centre is the throttle. One reading, used
## twice: the nose swings towards it and the thrust follows its length, so half a push is half the
## acceleration and a player can hold a slow drift.
func steerShip(dt)
    var turn = 0.0
    if keyboard.isDown("left") then
        turn -= 1.0
    end
    if keyboard.isDown("right") then
        turn += 1.0
    end
    ship.ang += turn * TURN_SPEED * dt

    var push = 0.0
    if keyboard.isDown("up") then
        push = 1.0
    end
    var sx = pad.steer()
    var sy = pad.throttle()
    var m = math.sqrt(sx * sx + sy * sy)
    if m > AIM_DEAD then
        ## The stick's y is measured UPWARDS, the field's downwards: the sign is flipped here, once.
        ship.ang += angleTo(ship.ang, math.atan2(-sy, sx)) * math.min(1.0, TURN_SNAP * dt)
        push = math.max(push, math.min(1.0, m))
    end

    thrusting = push > 0.0
    if thrusting then
        ship.vx += math.cos(ship.ang) * THRUST * push * dt
        ship.vy += math.sin(ship.ang) * THRUST * push * dt
    end
    ## Drag, and a ceiling on the speed: neither is a brake, and the ship keeps its momentum for
    ## many seconds. What they prevent is a ship faster than the player can read.
    var k = 1.0 - DRAG * dt
    ship.vx *= k
    ship.vy *= k
    var sp = math.sqrt(ship.vx * ship.vx + ship.vy * ship.vy)
    if sp > MAX_SPEED then
        ship.vx = ship.vx / sp * MAX_SPEED
        ship.vy = ship.vy / sp * MAX_SPEED
    end
    advance(ship, dt)
end

func update(dt)
    ## The sparks fade on their own clock: they are shown after the thing that made them is gone,
    ## so they belong to no other state.
    debris = debris.filter(func(d)
        advance(d, dt)
        d.left -= dt
        return d.left > 0.0
    end)

    if state == "title" then
        demo += dt
        for r in rocks do
            r.rot += r.spin * dt
            advance(r, dt)
        end
        return
    end
    if state == "over" or paused then
        if thrustVoice.isPlaying() then
            thrustVoice.stop()
        end
        return
    end

    if ship <> nil then
        steerShip(dt)
    else
        spawn -= dt
        if spawn <= 0.0 and centreClear() then
            newShip()
        end
    end
    ## A held trigger fires on its own clock, the four-shot rule doing the rest: a modern player
    ## holds the button down, and asking for one tap per shot is what a cabinet's spring did.
    fireTimer -= dt
    if (fireHeld or keyboard.isDown("space")) and fireTimer <= 0.0 then
        fire()
        fireTimer = FIRE_RATE
    end

    if thrusting and not thrustVoice.isPlaying() then
        thrustVoice.start()
    elseif not thrusting and thrustVoice.isPlaying() then
        thrustVoice.stop()
    end

    for r in rocks do
        r.rot += r.spin * dt
        advance(r, dt)
    end
    shots = ageShots(shots, dt)
    saucerShots = ageShots(saucerShots, dt)
    saucerUpdate(dt)
    shotsHit()
    shipHit()
    flushRocks()
    beat(dt)

    if #rocks == 0 then
        waveWait -= dt
        if waveWait <= 0.0 then
            wave += 1
            newWave()
            waveWait = WAVE_WAIT
        end
    else
        waveWait = WAVE_WAIT
    end
end

## ── Input ────────────────────────────────────────────────────────────────────

## Any press means "go" on the title screen and on the end screen, and only fires while playing.
## One place decides that, so the four input paths below say the same thing.
func begin()
    if state == "play" then
        return false
    end
    startGame()
    return true
end

func startGame()
    score = 0
    lives = LIVES
    wave = 1
    nextExtra = EXTRA_AT
    debris = []
    paused = false
    fireHeld = false               ## a finger held across the end screen must not fire the new game
    fireId = nil
    state = "play"
    newWave()
    newShip()
    waveWait = WAVE_WAIT
end

func keyboard.keypressed(key)
    if key == "space" then
        if not begin() then
            fire()
        end
    elseif key == "p" and state == "play" then
        paused = not paused
    end
end

## The glass is cut in TWO, and the side a finger lands on decides what it does: the right half
## steers, the left half is the trigger. A side is a whole half and not a button, so neither thumb
## has to find a target while the field is moving — the drawn disc and ring are hints, not the
## hit test.
##
## A single finger also emulates the mouse, so the same gesture arrives twice. Each path is written
## to be IDEMPOTENT: the joystick only takes a finger it does not already have, and holding the
## trigger twice is holding it once.
func touch.began(id, x, y)
    touchPlay = true
    if begin() then
        return
    end
    if x < W / 2 then
        fireId = id
        fireHeld = true
        fireTimer = 0.0             ## the first shot leaves at once; the cadence starts after it
        return
    end
    if padId == nil then
        pad.press(x, y)             ## a floating stick: anywhere on this half arms it
        padId = id
    end
end

func touch.moved(id, x, y)
    if padId == id then
        pad.move(x, y)
    end
end

func touch.ended(id, x, y)
    if padId == id then
        padId = nil
        pad.release()
    elseif fireId == id then
        fireId = nil
        fireHeld = false
    end
end

func mouse.pressed(x, y)
    if begin() or touchPlay then    ## a finger was already answered by touch.began
        return
    end
    fire()                          ## a real click, on a desktop: it fires as space does
end

## ── Drawing ──────────────────────────────────────────────────────────────────

func drawField()
    graphics.noFill()
    graphics.strokeSize(1.4)
    graphics.stroke(INK)

    for r in rocks do
        drawShape(ROCKS[r.shape], r.x, r.y, r.rot, ROCK_R[r.size], FIELD_W, FIELD_H)
    end

    if saucer <> nil then
        graphics.stroke(WARM)
        graphics.polygon(placeShape(SAUCER, saucer.x, saucer.y, 0.0, saucer.r))
        graphics.polyline(placeShape(SAUCER_DECK, saucer.x, saucer.y, 0.0, saucer.r))
        graphics.stroke(INK)
    end

    if ship <> nil then
        drawShape(SHIP, ship.x, ship.y, ship.ang, SHIP_R, FIELD_W, FIELD_H)
        ## The flame is drawn every other frame, so it flickers as the original's did — a steady
        ## flame reads as part of the hull.
        if thrusting and math.frac(elapsedTime * 20.0) < 0.5 then
            graphics.stroke(WARM)
            graphics.polyline(placeShape(FLAME, ship.x, ship.y, ship.ang, SHIP_R))
            graphics.stroke(INK)
        end
    end

    graphics.noStroke()
    graphics.fill(INK)
    for s in shots do
        graphics.circle(s.x, s.y, 1.6)
    end
    graphics.fill(WARM)
    for s in saucerShots do
        graphics.circle(s.x, s.y, 1.6)
    end
    graphics.fill(DIM)
    for d in debris do
        graphics.circle(d.x, d.y, 1.2)
    end
end

## The lives left, as ships: a count of the thing itself reads faster than a number.
func drawLives()
    graphics.noFill()
    graphics.stroke(INK)
    for i = 1, lives - 1 do
        graphics.polygon(placeShape(SHIP, 22 + (i - 1) * 20, 46, -math.PI / 2, 7.0))
    end
end

## The trigger has no hit test of its own — the whole left half fires — so what is drawn is a
## HINT: a ring where the thumb naturally sits, filled while it is held.
func drawTrigger()
    var r = pad.radius() * 0.5
    var cx = W * 0.2
    var cy = H * 0.78
    graphics.noStroke()
    graphics.fill(Color(1, 1, 1, 0.06))
    graphics.circle(cx, cy, r)
    if fireHeld then
        graphics.fill(Color(1.0, 0.55, 0.3, 0.7))
        graphics.circle(cx, cy, r * 0.55)
    else
        graphics.fill(Color(1, 1, 1, 0.16))
        graphics.circle(cx, cy, r * 0.4)
    end
end

func drawTitle()
    graphics.fontSize(30)
    graphics.stroke(INK)
    graphics.textMode("center", "center")
    graphics.text("OLLIN ASTEROIDS", FIELD_W / 2, 120)
    graphics.fontSize(11)
    graphics.stroke(DIM)
    graphics.text("a large rock breaks into two faster ones — and there is no brake", FIELD_W / 2, 158)
    graphics.stroke(INK)
    graphics.fontSize(12)
    graphics.text("large 20    medium 50    small 100    saucer 200 or 1000", FIELD_W / 2, 210)
    graphics.fontSize(11)
    graphics.stroke(WARM)
    var go = "arrows turn, up thrusts, hold space to fire"
    if touchPlay then
        go = "right thumb aims and thrusts — hold the left half to fire"
    end
    graphics.text(go, FIELD_W / 2, 250)
    if math.frac(demo) < 0.6 then
        graphics.stroke(INK)
        graphics.text("press or tap to play", FIELD_W / 2, 280)
    end
    if best > 0 then
        graphics.stroke(DIM)
        graphics.text("BEST {best}", FIELD_W / 2, 310)
    end
end

func draw()
    graphics.clear(Color(0.02, 0.02, 0.04))
    drawField()

    ## The score, the wave and the ships left belong to a game in progress: showing them on the
    ## title screen would announce a score of zero and two spare ships before anything has started.
    if state <> "title" then
        graphics.fontSize(14)
        graphics.stroke(INK)
        graphics.textMode("left", "top")
        graphics.text("{score}", 18, 14)
        graphics.textMode("right", "top")
        graphics.text("WAVE {wave}", FIELD_W - 18, 14)
        drawLives()
    end

    if state == "title" then
        drawTitle()
    elseif state == "over" then
        graphics.fontSize(24)
        graphics.stroke(WARM)
        graphics.textMode("center", "center")
        graphics.text("GAME OVER", FIELD_W / 2, FIELD_H / 2 - 14)
        graphics.fontSize(12)
        graphics.stroke(INK)
        graphics.text("SCORE {score} — press or tap to play again", FIELD_W / 2, FIELD_H / 2 + 14)
    elseif paused then
        graphics.fontSize(20)
        graphics.stroke(WARM)
        graphics.textMode("center", "center")
        graphics.text("PAUSED", FIELD_W / 2, FIELD_H / 2)
    end

    if touchPlay and state == "play" then
        drawTrigger()
        pad.draw()
    end
end

## Everything the program owns is built here, in the order it depends on.
func setup()
    graphics.canvas(W, H, "Ollin Asteroids")
    ## From here on the script knows ONE frame of reference: the engine scales the field to the area
    ## and hands over the pointer and the contacts already converted.
    graphics.viewport(FIELD_W, FIELD_H)
    buildSounds()
    ## The field is laid out but not started: the title screen holds it, and its rocks are the ones
    ## the first wave will drift — nothing is built twice.
    newWave()
end
