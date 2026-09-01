## Ollin Invaders — the fleet, the cannon, one shot, the shields, and the fleet shooting back.
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
## The fleet answers: only the LOWEST living alien of a column may drop a bomb, three bombs at most
## in the air. Being shot costs a life, and so does letting the fleet reach the cannon's line.
##
## Desktop: left and right arrows, space to fire. Mobile: ONE finger anywhere DRAGS the cannon —
## the movement is relative, so touching the screen never teleports it — and firing is
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
const SHIELD_Y     = 192        ## the four shields, between the fleet and the cannon
const SHIELD_X0    = 26
const SHIELD_PITCH = 56
const SHIELD_W     = 22
const SHIELD_H     = 16
const BLAST        = 3          ## the radius a hit eats out of a shield
const GUN_W      = 13
const GUN_H      = 5
const GUN_Y      = 232
const GUN_SPEED  = 60           ## field pixels per second
const SHOT_SPEED = 240
const BOMB_SPEED = 90           ## slower than the cannon's shot: a bomb can be outrun
const BOMB_MAX   = 3            ## how many bombs the fleet keeps in the air
const BOMB_ODDS  = 90           ## one tick in this many drops a bomb, while there is room for one
const LIVES      = 3
const RESPAWN    = 1.2          ## seconds the field holds still after the cannon is hit

const INK     = Color(0.90, 0.95, 1.00)
const GUN_INK = Color(0.35, 0.95, 0.45)
const SHIELD_INK = Color(0.30, 0.85, 0.40)
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
## Our own arch: what matters is that it is a TEXTURE, eaten pixel by pixel, and not a rectangle
## that would vanish whole.
const SHIELD = [
    "......##########......",
    "....##############....",
    "...################...",
    "..##################..",
    ".####################.",
    "######################",
    "######################",
    "######################",
    "######################",
    "######################",
    "######################",
    "#########....#########",
    "########......########",
    "#######........#######",
    "######..........######",
    "#####............#####"
]
const CANNON  = ["......#......", ".....###.....", ".....###.....", "#############", "#############"]
## The bomb turns as it falls, which is how a falling thing reads at three pixels wide.
const BOMB_A  = ["#..", ".#.", "..#", ".#."]
const BOMB_B  = ["..#", ".#.", "#..", ".#."]

## One entry per kind: its two frames, what killing it is worth, its colour. The kind comes from the
## ROW, so the fleet's shape decides the score.
global kinds = []
global gunImg = nil
global bombImgs = []
global shields = []      ## four {img, x}: each one its own texture, so each erodes on its own

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

global bombs = []        ## up to BOMB_MAX {x, y}
global lives = LIVES
global respawn = 0.0     ## > 0: the cannon was hit, and the field holds still
global over = false      ## the last life is gone, or the fleet landed: a press starts a new game
global ticks = 0         ## logical ticks, which is what makes the bomb sprite turn

global aimId = nil       ## the finger aiming, by id — an id can be 0, so only nil means "none"
global touchPlay = false ## a finger has been seen: aiming is by hand, firing by the game
global grabX = 0.0       ## where the finger landed, and where the cannon was then: a drag is
global grabGun = 0.0     ## RELATIVE, so touching the screen never teleports the cannon
global acc = 0.0

func buildSprites()
    kinds = [
        {frames: [image.fromPattern(JELLY_A), image.fromPattern(JELLY_B)], points: 30, ink: TOP_INK},
        {frames: [image.fromPattern(SPIDR_A), image.fromPattern(SPIDR_B)], points: 20, ink: INK},
        {frames: [image.fromPattern(MOTH_A), image.fromPattern(MOTH_B)], points: 10, ink: INK}
    ]
    gunImg = image.fromPattern(CANNON)
    bombImgs = [image.fromPattern(BOMB_A), image.fromPattern(BOMB_B)]
end

## A fresh set of shields: they are rebuilt for every wave, so a cleared wave hands back four whole
## arches — and the erosion of the previous one is genuinely gone, the textures being new.
func buildShields()
    shields = []
    for i = 1, 4 do
        shields.push({img: image.fromPattern(SHIELD), x: SHIELD_X0 + (i - 1) * SHIELD_PITCH})
    end
end

## Eats a disc out of a shield, in the texture's own coordinates. The jitter keeps two hits at the
## same spot from cutting the same clean circle twice.
func erode(sh, cx, cy, radius)
    image.beginPixels(sh.img)
    for dy = -radius, radius do
        for dx = -radius, radius do
            if dx * dx + dy * dy <= radius * radius + math.randInt(0, radius) then
                image.setPixel(sh.img, cx + dx, cy + dy, 0, 0, 0, 0)
            end
        end
    end
    image.endPixels(sh.img)
end

## The first shield whose SOLID pixel is under (x, y) — a hole is passed through, which is the whole
## point of eroding a texture rather than shrinking a box.
func shieldAt(x, y)
    for sh in shields do
        if x >= sh.x and x < sh.x + SHIELD_W and y >= SHIELD_Y and y < SHIELD_Y + SHIELD_H then
            var r, g, b, a = image.getPixel(sh.img, x - sh.x, y - SHIELD_Y)
            if a > 0.5 then
                return sh
            end
        end
    end
    return nil
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
                col: col,
                kind: kind,
                alive: true
            })
        end
    end
    buildShields()
    alive = #fleet
    cursor = 1
    heading = 1
    turning = false
    frame = 1
end

func startGame()
    wave = 1
    score = 0
    lives = LIVES
    over = false
    respawn = 0.0
    ticks = 0
    gunX = FIELD_W / 2 - GUN_W / 2
    shotLive = false
    bombs = []
    newWave()
end

## The fleet is stored bottom row first, so the FIRST living alien of a column is its lowest one —
## the only one with a clear line to the cannon. No column bookkeeping is needed: the storage order
## already answers the question.
func lowestOf(col)
    for a in fleet do
        if a.alive and a.col == col then
            return a
        end
    end
    return nil
end

func dropBomb()
    if #bombs >= BOMB_MAX or alive == 0 then
        return
    end
    if math.randInt(1, BOMB_ODDS) <> 1 then
        return
    end
    var a = lowestOf(math.randInt(1, COLS))
    if a == nil then
        return
    end
    bombs.push({x: a.x + 4, y: a.y + 8})
end

## Losing a life clears the air: the bombs already falling belonged to the cannon that just died,
## and a fresh one must not walk into them.
func hitCannon()
    bombs = []
    shotLive = false
    lives -= 1
    respawn = RESPAWN
    if lives <= 0 then
        over = true
    end
end

func bombsFall(dt)
    var i = 1
    while i <= #bombs do
        var b = bombs[i]
        b.y = b.y + BOMB_SPEED * dt
        var gone = b.y > FIELD_H
        var sh = shieldAt(b.x, b.y)
        if sh <> nil then
            erode(sh, b.x - sh.x, b.y - SHIELD_Y, BLAST)
            gone = true
        elseif b.y + 4 > GUN_Y and b.y < GUN_Y + GUN_H and b.x >= gunX and b.x < gunX + GUN_W then
            hitCannon()
            return
        end
        ## A bomb and the cannon's shot cancel each other: two things crossing in the same lane
        ## cannot pass through one another.
        if shotLive and math.abs(b.x - shotX) <= 2 and math.abs(b.y - shotY) <= 4 then
            shotLive = false
            gone = true
        end
        if gone then
            bombs.delete(i)
        else
            i += 1
        end
    end
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
            ## Descended onto a shield, it eats its way through: the arch is no shelter once the
            ## fleet is level with it.
            for sh in shields do
                if a.x + 8 > sh.x and a.x < sh.x + SHIELD_W
                   and a.y + 8 > SHIELD_Y and a.y < SHIELD_Y + SHIELD_H then
                    erode(sh, a.x + 4 - sh.x, a.y + 4 - SHIELD_Y, 5)
                end
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

## Taking hold: the cannon stays where it is, and the offset between the finger and it is what the
## drag preserves.
func grab(x)
    grabX = x
    grabGun = gunX
end

## The cannon follows the finger's DISPLACEMENT. When the wall stops it, the hold is re-anchored on
## the spot: without that, a finger carried on past the wall would owe the same distance back before
## the cannon moved again — a dead zone that feels like a stuck control.
func dragTo(x)
    var wanted = grabGun + (x - grabX)
    var stopped = math.clamp(wanted, MARGIN, FIELD_W - MARGIN - GUN_W)
    if stopped <> wanted then
        grabX = x
        grabGun = stopped
    end
    gunX = stopped
end

graphics.canvas(W, H, "Ollin Invaders")
## From here on the script knows ONE frame of reference: the engine scales the field to the area and
## hands over the pointer and the contacts already converted.
graphics.viewport(FIELD_W, FIELD_H)
buildSprites()
startGame()

func keyboard.keypressed(key)
    if key == "space" then
        if over then
            startGame()
        else
            fire()
        end
    end
end

## A single finger also emulates the mouse, so the same gesture arrives twice. Each path is written
## to be IDEMPOTENT: aiming twice at the same place is one aim, and firing twice is one shot, only
## one being allowed in the air.
func touch.began(id, x, y)
    touchPlay = true
    aimId = id
    grab(x)
    if over then
        startGame()
    end
end

func touch.moved(id, x, y)
    if aimId == id then
        dragTo(x)
    end
end

func touch.ended(id, x, y)
    if aimId == id then
        aimId = nil
    end
end

func mouse.pressed(x, y)
    grab(x)
    if over then
        startGame()
    elseif not touchPlay then    ## a real click, on a desktop: it fires as space does
        fire()
    end
end

func mouse.moved(x, y)
    if mouse.isDown() then
        dragTo(x)
    end
end

func update(dt)
    if over then
        return
    end

    ## The field holds still while the cannon is being replaced — the pause is what tells the player
    ## they were hit, so nothing marches, falls or fires during it.
    if respawn > 0.0 then
        respawn -= dt
        if respawn <= 0.0 then
            gunX = FIELD_W / 2 - GUN_W / 2
        end
        return
    end

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
        var hit = shieldAt(shotX, shotY)
        if hit <> nil then
            erode(hit, shotX - hit.x, shotY - SHIELD_Y, BLAST)
            shotLive = false
        elseif shotY < MARGIN or shotHits() then
            shotLive = false
        end
    end

    bombsFall(dt)
    if respawn > 0.0 or over then     ## the cannon was just hit: this frame is over
        return
    end

    ## A FIXED tick, so the march keeps its pace whatever the frame rate.
    acc += dt
    while acc >= TICK do
        acc -= TICK
        ticks += 1
        if alive > 0 then
            fleetTick()
            dropBomb()
        end
    end

    ## The fleet landing is as fatal as a bomb, and it ends the game outright: a cannon replaced
    ## under a landed fleet would be shot at once.
    for a in fleet do
        if a.alive and a.y + 8 >= GUN_Y then
            lives = 0
            hitCannon()
            over = true
            return
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

    graphics.tint(SHIELD_INK)
    for sh in shields do
        graphics.sprite(sh.img, sh.x, SHIELD_Y, SHIELD_W, SHIELD_H)
    end

    ## During the pause the cannon blinks, so the eye finds where it died before it comes back.
    if respawn <= 0.0 or math.frac(respawn * 6.0) < 0.5 then
        graphics.tint(GUN_INK)
        graphics.sprite(gunImg, gunX, GUN_Y, GUN_W, GUN_H)
    end
    graphics.tint(INK)
    for b in bombs do
        graphics.sprite(bombImgs[1 + (ticks // 6) % 2], b.x - 1, b.y, 3, 4)
    end
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
    ## The lives left, as cannons: a count of the thing itself reads faster than a number.
    graphics.tint(GUN_INK)
    for i = 1, lives - 1 do
        graphics.sprite(gunImg, MARGIN + (i - 1) * (GUN_W + 4), FIELD_H - 13, GUN_W, GUN_H)
    end
    graphics.noTint()

    graphics.fontSize(7)
    graphics.stroke(DIM)
    graphics.textMode("center", "bottom")
    var hint = "arrows + space — or drag with one finger, firing is automatic"
    if touchPlay then
        hint = "drag to move — firing is automatic"
    end
    graphics.text(hint, FIELD_W / 2, FIELD_H - 3)

    if over then
        graphics.fontSize(14)
        graphics.stroke(TOP_INK)
        graphics.textMode("center", "center")
        graphics.text("GAME OVER", FIELD_W / 2, 150)
        graphics.fontSize(8)
        graphics.stroke(INK)
        graphics.text("SCORE {score} — press or tap to play again", FIELD_W / 2, 168)
    end
end
