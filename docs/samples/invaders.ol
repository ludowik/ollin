## Ollin Invaders — phase 1: the fleet, the cannon, one shot.
##
## The RULE that makes this genre work, and the one most often missed: the fleet does not move as a
## block. ONE alien advances per tick. Fifty-five aliens therefore take fifty-five ticks to complete
## a pass, three take three — so the game accelerates as it empties, and that speed is a CONSEQUENCE
## of the rule, never a setting. The wave only drops and reverses at the END of a pass, which is what
## keeps the formation square.
##
## The three creatures are drawn below, and they are ours. Only the MECHANICS are faithful to the
## arcade original, whose sprites are its author's work.
##
## Desktop: left and right arrows, space to fire. Mobile: ONE finger anywhere aims, and firing is
## automatic — a finger that aims everywhere cannot also mean "fire" by tapping, and the one-shot
## rule already paces the cannon: the next shot waits for the previous one to leave the field, which
## is what a good player's thumb does anyway.

const FIELD_W    = 224          ## the field, in its own pixels — graphics.viewport does the rest
const FIELD_H    = 256
const TICK       = 1.0 / 60.0   ## the logical tick: one alien advances per tick
const COLS       = 11
const ROWS       = 5
const CELL_W     = 16           ## the column pitch; a sprite is 8 wide, centred in it
const CELL_H     = 16
const FLEET_X    = 24
const FLEET_Y    = 40
const WAVE_DROP  = 8            ## how much lower each wave starts, and each descent falls
const STEP_X     = 2            ## how far one alien advances
const MARGIN     = 8            ## the walls the fleet turns at
const GUN_W      = 13
const GUN_Y      = 232
const GUN_SPEED  = 60           ## field pixels per second
const SHOT_SPEED = 240

const INK     = Color(0.90, 0.95, 1.00)
const GUN_INK = Color(0.35, 0.95, 0.45)
const TOP_INK = Color(1.00, 0.45, 0.45)
const DIM     = Color(0.55, 0.60, 0.72)

## Two frames per creature, alternating on every pass: that alternation IS the march. Three
## silhouettes of our own — a jellyfish, a spider, a moth — drawn in the idiom of an 8x8 monochrome
## sprite. The arcade original's own creatures are its author's work and are not reproduced here;
## only the MECHANICS are faithful.
const JELLY_A = ["..####..", ".######.", "########", "#.####.#", ".#.##.#.", "#..##..#", ".#....#."]
const JELLY_B = ["..####..", ".######.", "########", "#.####.#", ".#.##.#.", "..#..#..", ".#.##.#."]
const SPIDR_A = ["#......#", ".#....#.", "..####..", ".######.", "..####..", ".#.##.#.", "#.#..#.#"]
const SPIDR_B = [".#....#.", "..#..#..", "..####..", ".######.", "..####..", ".#.##.#.", "#......#"]
const MOTH_A  = ["##....##", "##.##.##", ".######.", "..####..", "..#..#..", ".#....#."]
const MOTH_B  = ["#......#", "##.##.##", "########", ".######.", "..#..#..", "#......#"]
const CANNON  = ["......#......", ".....###.....", ".....###.....", "#############", "#############"]

## One entry per kind: its two frames, what killing it is worth, its colour. The kind comes from the
## ROW, so the fleet's shape decides the score.
global kinds = []
global gunImg = nil

global fleet = []        ## 55 entries {x, y, kind, alive}
global cursor = 1        ## the alien the next tick advances
global heading = 1       ## +1 rightwards, -1 leftwards
global turning = false   ## an alien touched a wall: drop and reverse at the end of the pass
global frame = 1         ## which of the two frames the fleet shows
global alive = 0
global wave = 1
global score = 0

global gunX = 0
global shotX = 0
global shotY = 0
global shotLive = false

global aimId = nil       ## the finger aiming, by id — an id can be 0, so only nil means "none"
global touchPlay = false ## a finger has been seen: aiming is by hand, firing by the game
global acc = 0.0

func buildSprites()
    kinds = [
        {frames: [image.fromPattern(JELLY_A), image.fromPattern(JELLY_B)], points: 30, ink: TOP_INK},
        {frames: [image.fromPattern(SPIDR_A), image.fromPattern(SPIDR_B)], points: 20, ink: INK},
        {frames: [image.fromPattern(MOTH_A), image.fromPattern(MOTH_B)], points: 10, ink: INK}
    ]
    gunImg = image.fromPattern(CANNON)
end

## The fleet is stored bottom row first, left to right — the order the ticks advance it in, so the
## wave ripples upwards as it did on the original hardware.
func newWave()
    fleet = []
    for row = ROWS, 1, -1 do
        for col = 1, COLS do
            var kind = 3
            if row == 1 then
                kind = 1
            elseif row <= 3 then
                kind = 2
            end
            fleet.push({
                x: FLEET_X + (col - 1) * CELL_W,
                y: FLEET_Y + (row - 1) * CELL_H + (wave - 1) * WAVE_DROP,
                kind: kind,
                alive: true
            })
        end
    end
    alive = #fleet
    cursor = 1
    heading = 1
    turning = false
    frame = 1
end

func startGame()
    wave = 1
    score = 0
    gunX = FIELD_W / 2 - GUN_W / 2
    shotLive = false
    newWave()
end

## One tick: the next LIVING alien advances. A dead one costs nothing, and that is the whole
## mechanism of the acceleration. Reaching the end of the fleet ends the pass.
func fleetTick()
    for i = 1, #fleet do
        var a = fleet[cursor]
        cursor += 1
        if cursor > #fleet then
            cursor = 1
            frame = 3 - frame            ## the pass is over: the fleet changes frame
            if turning then
                turning = false
                heading = -heading
                for b in fleet do
                    b.y = b.y + WAVE_DROP
                end
            end
        end
        if a.alive then
            a.x = a.x + STEP_X * heading
            if a.x <= MARGIN or a.x + 8 >= FIELD_W - MARGIN then
                turning = true
            end
            return
        end
    end
end

func fire()
    if shotLive or alive == 0 then
        return
    end
    shotLive = true
    shotX = gunX + GUN_W / 2
    shotY = GUN_Y - 4
end

## A shot hits the first living alien whose 8x8 box holds its tip.
func shotHits()
    for a in fleet do
        if a.alive and shotX >= a.x and shotX < a.x + 8 and shotY >= a.y and shotY < a.y + 8 then
            a.alive = false
            alive -= 1
            score += kinds[a.kind].points
            return true
        end
    end
    return false
end

func aimAt(x)
    gunX = math.clamp(x - GUN_W / 2, MARGIN, FIELD_W - MARGIN - GUN_W)
end

graphics.canvas(W, H, "Ollin Invaders")
## From here on the script knows ONE frame of reference: the engine scales the field to the area and
## hands over the pointer and the contacts already converted.
graphics.viewport(FIELD_W, FIELD_H)
buildSprites()
startGame()

func keyboard.keypressed(key)
    if key == "space" then
        fire()
    end
end

## A single finger also emulates the mouse, so the same gesture arrives twice. Each path is written
## to be IDEMPOTENT: aiming twice at the same place is one aim, and firing twice is one shot, only
## one being allowed in the air.
func touch.began(id, x, y)
    touchPlay = true
    aimId = id
    aimAt(x)
end

func touch.moved(id, x, y)
    if aimId == id then
        aimAt(x)
    end
end

func touch.ended(id, x, y)
    if aimId == id then
        aimId = nil
    end
end

func mouse.pressed(x, y)
    aimAt(x)
    if not touchPlay then    ## a real click, on a desktop: it fires as space does
        fire()
    end
end

func mouse.moved(x, y)
    if mouse.isDown() then
        aimAt(x)
    end
end

func update(dt)
    if keyboard.isDown("left") then
        gunX = math.max(MARGIN, gunX - GUN_SPEED * dt)
    end
    if keyboard.isDown("right") then
        gunX = math.min(FIELD_W - MARGIN - GUN_W, gunX + GUN_SPEED * dt)
    end

    ## Automatic once a finger has played: fire() is a no-op while a shot is in the air, so the
    ## cadence is the shot's travel time and nothing has to time it.
    if touchPlay then
        fire()
    end

    if shotLive then
        shotY -= SHOT_SPEED * dt
        if shotY < MARGIN or shotHits() then
            shotLive = false
        end
    end

    ## A FIXED tick, so the march keeps its pace whatever the frame rate.
    acc += dt
    while acc >= TICK do
        acc -= TICK
        if alive > 0 then
            fleetTick()
        end
    end

    if alive == 0 then
        wave += 1
        newWave()
    end
end

func draw()
    graphics.clear(Color(0.02, 0.03, 0.05))

    for a in fleet do
        if a.alive then
            var k = kinds[a.kind]
            graphics.tint(k.ink)
            graphics.sprite(k.frames[frame], a.x, a.y, 8, 8)
        end
    end

    graphics.tint(GUN_INK)
    graphics.sprite(gunImg, gunX, GUN_Y, GUN_W, 5)
    graphics.noTint()

    if shotLive then
        graphics.noStroke()
        graphics.fill(INK)
        graphics.rect(shotX, shotY, 1, 4)
    end

    graphics.noStroke()
    graphics.fill(GUN_INK)
    graphics.rect(MARGIN, GUN_Y + 8, FIELD_W - 2 * MARGIN, 1)   ## the floor the cannon stands on

    graphics.fontSize(9)
    graphics.stroke(INK)
    graphics.textMode("left", "top")
    graphics.text("SCORE {score}", MARGIN, 8)
    graphics.textMode("right", "top")
    graphics.text("WAVE {wave}", FIELD_W - MARGIN, 8)
    graphics.fontSize(7)
    graphics.stroke(DIM)
    graphics.textMode("center", "bottom")
    var hint = "arrows + space — or one finger to aim, firing is automatic"
    if touchPlay then
        hint = "one finger aims — firing is automatic"
    end
    graphics.text(hint, FIELD_W / 2, FIELD_H - 3)
end
