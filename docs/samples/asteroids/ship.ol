## The ship: its birth and death, its shots, and how a stick or a key steers it.

func newShip()
    ## `push` is the thrust in [0;1], and it is a field of the SHIP: a ship that no longer exists
    ## cannot leave a stale "thrusting" behind, so nothing has to be unset when one is destroyed.
    ship = {x: FIELD_W / 2, y: FIELD_H / 2, vx: 0.0, vy: 0.0, ang: -math.PI / 2, push: 0.0}
end

func killShip()
    sndDeath.play()
    burst(ship.x, ship.y, 16, 90.0)
    ship = nil
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

## What can kill the ship, all of it in one place: a rock, a saucer's shot, the saucer itself.
func shipHit()
    if ship == nil then
        return
    end
    var r = rockAt(ship.x, ship.y, SHIP_R * 0.7)
    if r <> nil then
        breakRock(r)
        killShip()
        return
    end
    if saucer <> nil and near(ship.x, ship.y, saucer.x, saucer.y, saucer.r + SHIP_R * 0.7) then
        killSaucer()
        killShip()
        return
    end
    for s in saucerShots do
        if near(ship.x, ship.y, s.x, s.y, SHIP_R) then
            s.left = 0.0                ## spent: the ageing pass takes it away, like any other
            killShip()
            return
        end
    end
end

## A ship is only put back when the CENTRE is clear. Dropping it under a rock would cost a life to
## a player who was doing nothing wrong, so the countdown waits instead of expiring.
func centreClear()
    return rockAt(FIELD_W / 2, FIELD_H / 2, CLEAR_R) == nil and saucer == nil
end

## The shortest way round from one angle to the other. Without it the nose took the long way for
## every command that crossed the half-turn — the stick pointing a few degrees the other side of
## straight-up sent the ship spinning all the way round.
## math.frac lands in [0;1) whatever the sign of its argument, so the result is already in
## [-PI;PI) — no wrapping branch is needed after it.
func angleTo(from, to)
    return math.frac((to - from) / math.TAU + 0.5) * math.TAU - math.PI
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
    var m = math.hypot(sx, sy)
    if m > AIM_DEAD then
        ## The stick's y is measured UPWARDS, the field's downwards: the sign is flipped here, once.
        ship.ang += angleTo(ship.ang, math.atan2(-sy, sx)) * math.min(1.0, TURN_SNAP * dt)
        push = math.max(push, math.min(1.0, m))
    end

    ship.push = push
    if push > 0.0 then
        ship.vx += math.cos(ship.ang) * THRUST * push * dt
        ship.vy += math.sin(ship.ang) * THRUST * push * dt
    end
    ## Drag, and a ceiling on the speed: neither is a brake, and the ship keeps its momentum for
    ## many seconds. What they prevent is a ship faster than the player can read.
    var k = 1.0 - DRAG * dt
    ship.vx *= k
    ship.vy *= k
    var sp = math.hypot(ship.vx, ship.vy)
    if sp > MAX_SPEED then
        ship.vx = ship.vx / sp * MAX_SPEED
        ship.vy = ship.vy / sp * MAX_SPEED
    end
    advance(ship, dt)
end
