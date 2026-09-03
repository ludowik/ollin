## Ollin Invaders — the fleet, the cannon, one shot, the shields, the fleet shooting back, the
## mystery ship crossing above it, the sound, and a title screen to start from.
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
## The mystery ship is worth a value taken from a TABLE indexed by the number of shots the player
## has fired — that is how the original priced it, and it is why 300 can be hunted rather than hoped
## for. It stays away while the wave is nearly cleared, so the last aliens are not shot at through it.
##
## The MARCH is the sound this game is remembered for, and it is not a soundtrack: four descending
## notes, one per pass of the fleet. Since a pass takes one tick per living alien, the beat speeds up
## on its own as the wave empties — the same rule that drives the movement drives the music, and
## nothing times it.
##
## The game has THREE states, and one variable says which: the title screen, the play, and the end.
## Every input asks that variable first, so no callback has to guess whether the game is running.
##
## Desktop: left and right arrows, space to fire, P pauses. On a touch screen the pause is a tap in
## the TOP BAND, where the score is written: the rest of the screen aims, so the pause needs a place
## of its own — and that band is the one spot no thumb visits while playing. Mobile: ONE finger anywhere DRAGS the cannon —
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
const SHIELD_Y     = 200        ## the four shields, just above the cannon as in the arcade
const SHIELDS      = 4
const SHIELD_W     = 22
const SHIELD_H     = 16
## The row is CENTRED by calculation: five equal gaps between the walls and the four arches. Written
## as a first position and a pitch, it sat 26 px from the left wall and 8 from the right — a shift
## the eye catches at once, and one that no rewriting of two numbers can be trusted to keep. Whole
## pixels, a shield being read pixel by pixel through its own coordinates.
const SHIELD_GAP   = (FIELD_W - SHIELDS * SHIELD_W) // (SHIELDS + 1)
## What a hit eats out of a shield. The original carved a fixed PATTERN into the shield's bitmap —
## no circle and no randomness — and the two weapons carved different ones: the cannon's shot takes a
## small bite out of the UNDERSIDE it struck, while a bomb, arriving from above, opens a wider and
## shallower crater. That is why a shield lasts a whole wave there and dissolved here: a jittered
## disc of radius three removed some thirty pixels per shot, against a dozen for these.
const SHOT_BITE = [
    "##.#",
    "####",
    ".###",
    "#.##"
]
const BOMB_BITE = [
    ".####.",
    "######",
    "##.###",
    ".####."
]
const GUN_W      = 13
const GUN_H      = 5
const GUN_Y      = 224          ## the cannon stands close under the shields, not far below them
const GUN_SPEED  = 60           ## field pixels per second
const SHOT_SPEED = 240
const BOMB_SPEED = 90           ## slower than the cannon's shot: a bomb can be outrun
const BOMB_MAX   = 3            ## how many bombs the fleet keeps in the air
const BOMB_ODDS  = 90           ## one tick in this many drops a bomb, while there is room for one
const LIVES      = 3
const UFO_Y        = 24         ## the mystery ship's lane, above the fleet
const UFO_W        = 16
const UFO_H        = 7
const UFO_SPEED    = 30         ## field pixels per second
const UFO_PERIOD   = 22.0       ## seconds between two crossings
const UFO_MIN_ALIVE = 8         ## it stays away below this many aliens, as the original does
## The price of the mystery ship, indexed by the number of shots fired. A table, not a random draw:
## a player who counts their shots can aim for the 300.
const UFO_VALUES = [100, 50, 50, 100, 150, 100, 100, 50, 300, 100, 100, 100, 50, 150, 100]
const POPUP_TIME = 0.9          ## how long the value stays written where the ship died
## The march's four notes, descending — the loop the fleet walks to.
const MARCH_NOTES = [110, 98, 87, 78]
const UFO_HUM     = 220         ## the mystery ship's tone, warbled while it crosses
const UFO_WARBLE  = 70          ## how far the warble swings, in hertz
const UFO_RATE    = 14.0        ## and how fast, in swings per second
const EXTRA_LIFE  = 1500        ## a life is given each time the score passes another of these
const BLAST_TIME  = 0.18        ## how long a kill is shown coming apart
const PAUSE_BAND  = 20          ## the top band, in field pixels: a tap there pauses on a touch screen
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
## What is left of an alien for a fraction of a second: pieces flying apart, not a cloud.
const BURST = [
    "#..#..#..#",
    ".#.#..#.#.",
    "..#.##.#..",
    "#..####..#",
    "..#.##.#..",
    ".#.#..#.#.",
    "#..#..#..#"
]
## The bomb turns as it falls, which is how a falling thing reads at three pixels wide.
## Our own saucer: wide, flat, and lit underneath — nothing of the fleet's silhouette, since it is
## not one of them.
const UFO = [
    "....########....",
    "..############..",
    ".##############.",
    "################",
    "..##.##.##.##...",
    "...#..#..#..#...",
    "....##....##...."
]
const BOMB_A  = ["#..", ".#.", "..#", ".#."]
const BOMB_B  = ["..#", ".#.", "#..", ".#."]

## One entry per kind: its two frames, what killing it is worth, its colour. The kind comes from the
## ROW, so the fleet's shape decides the score.
global kinds = []
global gunImg = nil
global bombImgs = []
global ufoImg = nil
global shields = []      ## four {img, x}: each one its own texture, so each erodes on its own

global fleet = []        ## 55 entries {x, y, kind, alive}
global cursor = 1        ## the alien the next tick advances
global heading = 1       ## +1 rightwards, -1 leftwards
global turning = false   ## an alien touched a wall: drop and reverse at the end of the pass
global landed = false    ## an alien crossed the cannon's line: the game ends this frame
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
global ticks = 0         ## logical ticks, which is what makes the bomb sprite turn

global ufo = nil         ## {x, dir} while it crosses, nil between crossings
global ufoWait = UFO_PERIOD
global ufoDir = 1        ## it comes from the other side each time
global shots = 0         ## shots fired, which is what prices the mystery ship
global popup = nil       ## {text, x, y, left}: what a kill was worth, written where it happened
global best = 0          ## the best score of the session

## Every sound is a buffer computed ONCE, at startup: the formulas below are sampled by the engine
## before the game runs, so nothing is calculated while a note plays. Only the mystery ship needs a
## living oscillator, its tone being moved while it sounds.
global sndMarch = []
global sndShoot = nil
global sndAlien = nil
global sndGun   = nil
global sndUfo   = nil
global ufoVoice = nil
global marchStep = 0     ## which of the four notes the next pass plays

global state = "title"   ## "title", "play" or "over": every input asks this first
global paused = false
global bursts = []       ## {x, y, left}: the kills still coming apart
global nextLife = EXTRA_LIFE
global burstImg = nil
global demo = 0.0        ## the title screen's own clock, which animates the three creatures

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
    ufoImg = image.fromPattern(UFO)
    burstImg = image.fromPattern(BURST)
end

## A fresh set of shields: they are rebuilt for every wave, so a cleared wave hands back four whole
## arches — and the erosion of the previous one is genuinely gone, the textures being new.
func buildSounds()
    sndMarch = []
    for f in MARCH_NOTES do
        sndMarch.push(sound.tone(f, 0.11, "square").envelope(0.005, 0.03, 0.7, 0.04).volume(0.25))
    end
    ## The cannon's shot: a tone falling as it leaves, which is what makes it read as departing.
    sndShoot = sound.generate(0.16, func(t)
        return math.sin(t * 6.28318 * (900 - 3600 * t)) * math.exp(-t * 14)
    end).volume(0.18)
    ## An alien coming apart: noise, with a low ring under it so it is not just a hiss.
    sndAlien = sound.generate(0.22, func(t)
        var n = math.rand() * 2 - 1
        return (n * 0.7 + math.sin(t * 6.28318 * 180) * 0.3) * math.exp(-t * 12)
    end).volume(0.22)
    ## The cannon itself: the same idea, heavier and slower to die.
    sndGun = sound.generate(0.7, func(t)
        var n = math.rand() * 2 - 1
        return (n * 0.8 + math.sin(t * 6.28318 * (90 - 60 * t)) * 0.4) * math.exp(-t * 4)
    end).volume(0.30)
    ## The mystery ship coming apart: a sweep downwards, so it is heard as a fall.
    sndUfo = sound.generate(0.45, func(t)
        return math.sin(t * 6.28318 * (700 - 1200 * t)) * math.exp(-t * 5)
    end).volume(0.22)
    ufoVoice = sound.square(UFO_HUM).volume(0.10)
end

func buildShields()
    shields = []
    for i = 1, SHIELDS do
        shields.push({img: image.fromPattern(SHIELD), x: SHIELD_GAP * i + SHIELD_W * (i - 1)})
    end
end

## Eats a disc out of a shield, in the texture's own coordinates. The jitter keeps two hits at the
## same spot from cutting the same clean circle twice.
## Carves a pattern out of a shield, in the texture's own coordinates. `dir` is where the projectile
## was going: -1 for the cannon's shot, which eats UPWARDS from the pixel it struck, +1 for a bomb,
## which eats downwards. The pattern is centred horizontally and anchored on the impact, so the
## crater opens on the side the hit came from — a bite taken symmetrically would hollow the shield
## from the middle and let a second shot straight through.
func bite(sh, cx, cy, rows, dir)
    var w = len(rows[1])
    var top = cy
    if dir < 0 then
        top = cy - #rows + 1
    end
    image.beginPixels(sh.img)
    for r = 1, #rows do
        for c = 1, w do
            if string.char(rows[r], c) == "#" then
                image.setPixel(sh.img, cx - w // 2 + c - 1, top + r - 1, 0, 0, 0, 0)
            end
        end
    end
    image.endPixels(sh.img)
end

## An alien that has descended into a shield does not nibble it: it erases its whole footprint, which
## is what makes the fleet's arrival final.
func eraseBox(sh, cx, cy, w, h)
    image.beginPixels(sh.img)
    for y = 0, h - 1 do
        for x = 0, w - 1 do
            image.setPixel(sh.img, cx + x, cy + y, 0, 0, 0, 0)
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
    landed = false
    frame = 1
end

func startGame()
    wave = 1
    score = 0
    lives = LIVES
    respawn = 0.0
    ticks = 0
    gunX = FIELD_W / 2 - GUN_W / 2
    state = "play"
    paused = false
    shotLive = false
    bombs = []
    bursts = []
    nextLife = EXTRA_LIFE
    shots = 0
    ufo = nil
    ufoWait = UFO_PERIOD
    ufoDir = 1
    hushUfo()
    popup = nil
    marchStep = 0
    acc = 0.0        ## the previous game's leftover would be spent on this one's first frame
    newWave()
end

## The ship's tone belongs to the crossing: it stops with the ship, whether it left, was shot, or the
## cannon died under it.
func hushUfo()
    if ufoVoice <> nil and ufoVoice.isPlaying() then
        ufoVoice.stop()
    end
end

## The value of the mystery ship for the shot that just hit it, read from the table as the original
## read it — the count wraps, so the 300 comes back within reach.
func ufoValue()
    return UFO_VALUES[1 + shots % #UFO_VALUES]
end

## A life every EXTRA_LIFE points, and the threshold moves up: crossing it twice in one hit still
## gives one life, which is what the original did.
func addScore(points)
    score += points
    if score > best then
        best = score
    end
    if score >= nextLife then
        lives += 1
        nextLife += EXTRA_LIFE
        showPopup("EXTRA LIFE", FIELD_W / 2, SHIELD_Y - 14)
    end
end

func showBurst(x, y)
    bursts.push({x: x, y: y, left: BLAST_TIME})
end

func showPopup(text, x, y)
    popup = {text: text, x: x, y: y, left: POPUP_TIME}
end

## One crossing at a time, from alternating sides, and never while the wave is nearly cleared.
func ufoUpdate(dt)
    if ufo == nil then
        ufoWait -= dt
        if ufoWait <= 0.0 and alive >= UFO_MIN_ALIVE then
            var x = -UFO_W
            if ufoDir < 0 then
                x = FIELD_W
            end
            ufo = {x: x, dir: ufoDir}
            ufoDir = -ufoDir
            ufoWait = UFO_PERIOD
            ufoVoice.start()
        end
        return
    end
    ufo.x = ufo.x + UFO_SPEED * ufo.dir * dt
    ufoVoice.freq(UFO_HUM + UFO_WARBLE * math.sin(elapsedTime * UFO_RATE * 6.28318))
    if ufo.x < -UFO_W or ufo.x > FIELD_W then    ## it left the field: it was worth nothing
        ufo = nil
        hushUfo()
    end
end

func ufoHit()
    if ufo == nil or not shotLive then
        return false
    end
    if shotX < ufo.x or shotX >= ufo.x + UFO_W or shotY > UFO_Y + UFO_H or shotY < UFO_Y then
        return false
    end
    var points = ufoValue()
    sndUfo.play()
    showBurst(ufo.x + 3, UFO_Y)
    hushUfo()
    addScore(points)
    showPopup("{points}", ufo.x + UFO_W / 2, UFO_Y + 3)
    ufo = nil
    return true
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
    sndGun.play()
    showBurst(gunX + 1, GUN_Y - 1)
    hushUfo()
    bombs = []
    shotLive = false
    lives -= 1
    respawn = RESPAWN
    if lives <= 0 then
        state = "over"
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
            bite(sh, b.x - sh.x, b.y - SHIELD_Y, BOMB_BITE, 1)
            gone = true
        elseif b.y + 4 > GUN_Y and b.y < GUN_Y + GUN_H and b.x >= gunX and b.x < gunX + GUN_W then
            hitCannon()
            return
        end
        ## A bomb and the cannon's shot cancel each other: two things crossing in the same lane
        ## cannot pass through one another. A bomb already stopped by a shield is spent, and must not
        ## take a shot down with it.
        if not gone and shotLive and math.abs(b.x - shotX) <= 2 and math.abs(b.y - shotY) <= 4 then
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
            marchStep = marchStep % #sndMarch + 1
            sndMarch[marchStep].play()   ## one note per pass: the beat IS the fleet's speed
            if turning then
                turning = false
                heading = -heading
                ## The descent moves the WHOLE fleet, so the landing is judged here as well: testing
                ## only the alien that advances would leave the fleet standing on the cannon for up
                ## to a full pass before the game noticed.
                for b in fleet do
                    b.y = b.y + WAVE_DROP
                    if b.alive and b.y + 8 >= GUN_Y then
                        landed = true
                    end
                end
            end
        end
        if a.alive then
            a.x = a.x + STEP_X * heading
            if a.x <= MARGIN or a.x + 8 >= FIELD_W - MARGIN then
                turning = true
            end
            ## Level with the shields, it eats its way through: the arch is no shelter once the fleet
            ## reaches it. Tested only when the fleet is low enough — for most of a game the aliens
            ## are a hundred pixels above, and the four rectangles would be compared for nothing.
            if a.y + 8 > SHIELD_Y then
                for sh in shields do
                    if a.x + 8 > sh.x and a.x < sh.x + SHIELD_W and a.y < SHIELD_Y + SHIELD_H then
                        eraseBox(sh, a.x - sh.x, a.y - SHIELD_Y, 8, 8)
                    end
                end
            end
            ## The fleet landing is as fatal as a bomb, and the alien that just moved is the only one
            ## that can have crossed the line: asking the whole fleet once per frame was 55 tests for
            ## at most one transition in a game.
            if a.y + 8 >= GUN_Y then
                landed = true
            end
            return
        end
    end
end

## Is a shield straight above the muzzle? Its own pixels answer, so a hole shot earlier is a clear
## line again — the shelter is asked, not a rectangle around it.
func sheltered()
    var x = gunX + GUN_W / 2
    for y = SHIELD_Y, SHIELD_Y + SHIELD_H - 1 do
        if shieldAt(x, y) <> nil then
            return true
        end
    end
    return false
end

func fire()
    if shotLive or alive == 0 then
        return
    end
    shots += 1
    sndShoot.play()
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
            sndAlien.play()
            showBurst(a.x - 1, a.y)
            addScore(kinds[a.kind].points)
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

## Everything the program owns is built here, in the order it depends on: the window first, since a
## sprite is a texture and a texture needs a graphics context.
func setup()
    graphics.canvas(W, H, "Ollin Invaders")
    ## From here on the script knows ONE frame of reference: the engine scales the field to the area
    ## and hands over the pointer and the contacts already converted.
    graphics.viewport(FIELD_W, FIELD_H)
    buildSprites()
    buildSounds()
    ## The field is laid out but not started: the title screen holds it, and its fleet is the one the
    ## first wave will march — nothing is built twice.
    newWave()
end

## Any press means "go" on the title screen and on the end screen, and only fires while playing.
## One place decides that, so the four input paths below say the same thing.
func begin()
    if state == "play" then
        return false
    end
    startGame()
    return true
end

## A tap in the top band pauses instead of aiming. It answers the same on both input paths — a single
## finger also emulates the mouse — so the band is read in ONE place.
func bandTap(y)
    if state <> "play" or y >= PAUSE_BAND then
        return false
    end
    paused = not paused
    return true
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

## A single finger also emulates the mouse, so the same gesture arrives twice. Each path is written
## to be IDEMPOTENT: aiming twice at the same place is one aim, and firing twice is one shot, only
## one being allowed in the air.
func touch.began(id, x, y)
    touchPlay = true
    if begin() or bandTap(y) then    ## the band pauses, and neither takes hold of the cannon
        return
    end
    aimId = id
    grab(x)
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
    if begin() then
        return
    end
    ## A finger has already been answered by touch.began, band included: the emulated click must not
    ## pause a second time, which would undo it.
    if touchPlay then
        return
    end
    grab(x)
    fire()                                   ## a real click, on a desktop: it fires as space does
end

func mouse.moved(x, y)
    if mouse.isDown() and not touchPlay then
        dragTo(x)
    end
end

## The bursts fade on their own clock: they are shown after the thing that made them is gone, so
## they belong to no other state. A filter says it in one line — the countdown is the only change.
func burstsFade(dt)
    bursts = bursts.filter(func(b)
        b.left -= dt
        return b.left > 0.0
    end)
end

func update(dt)
    burstsFade(dt)
    if state == "title" then
        demo += dt
        return
    end
    if state == "over" or paused then
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
    ## cadence is the shot's travel time and nothing has to time it. It holds fire under a shield —
    ## the finger only aims, and a thumb parked in the shelter would otherwise dig through it at
    ## sixty shots a second. Space still fires wherever the cannon stands: destroying one's own
    ## shelter is the player's right, not an accident of the automatic cadence.
    if touchPlay and not sheltered() then
        fire()
    end

    if shotLive then
        shotY -= SHOT_SPEED * dt
        var hit = shieldAt(shotX, shotY)
        if hit <> nil then
            bite(hit, shotX - hit.x, shotY - SHIELD_Y, SHOT_BITE, -1)
            shotLive = false
        elseif shotY < MARGIN or ufoHit() or shotHits() then
            shotLive = false
        end
    end

    ufoUpdate(dt)
    if popup <> nil then
        popup.left -= dt
        if popup.left <= 0.0 then
            popup = nil
        end
    end

    bombsFall(dt)
    if respawn > 0.0 then     ## the cannon was just hit: this frame is over
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

    ## A landed fleet ends the game outright: a cannon replaced under it would be shot at once, so
    ## the last life goes with the landing.
    if landed then
        lives = 1
        hitCannon()
        return
    end

    if alive == 0 then
        wave += 1
        newWave()
    end
end

## The title screen shows what the three creatures are worth — the score table the cabinet carried,
## and the only place the player is ever told. The frames alternate on the screen's own clock, so the
## fleet is seen marching before a shot is fired.
func drawTitle()
    graphics.clear(Color(0.02, 0.03, 0.05))
    ## The two frames alternate every four tenths of a second — an integer index, since a fractional
    ## one cannot address an array.
    var f = 1
    if math.frac(demo * 1.25) >= 0.5 then
        f = 2
    end

    graphics.fontSize(20)
    graphics.stroke(GUN_INK)
    graphics.textMode("center", "center")
    graphics.text("OLLIN INVADERS", FIELD_W / 2, 52)
    graphics.fontSize(8)
    graphics.stroke(DIM)
    graphics.text("*SCORE ADVANCE TABLE*", FIELD_W / 2, 78)

    ## The four rows are one list, the mystery ship included: written apart, its line could drift
    ## from the three above it without anything saying so.
    var table = []
    for i = 1, #kinds do
        table.push({img: kinds[i].frames[f], w: 8, h: 8, ink: kinds[i].ink,
                    text: "= {kinds[i].points} POINTS"})
    end
    table.push({img: ufoImg, w: UFO_W, h: UFO_H, ink: TOP_INK, text: "= MYSTERY"})

    graphics.fontSize(9)
    graphics.textMode("left", "center")
    for i = 1, #table do
        var row = table[i]
        var y = 96 + (i - 1) * 20
        graphics.tint(row.ink)
        graphics.sprite(row.img, FIELD_W / 2 - 34 - (row.w - 8) / 2, y - row.h / 2, row.w, row.h)
        graphics.noTint()
        graphics.stroke(INK)
        graphics.text(row.text, FIELD_W / 2 - 20, y)
    end

    graphics.fontSize(9)
    graphics.stroke(GUN_INK)
    graphics.textMode("center", "center")
    graphics.text("PRESS SPACE OR TAP TO PLAY", FIELD_W / 2, 190)
    graphics.fontSize(7)
    graphics.stroke(DIM)
    graphics.text("arrows to move, space to fire, P pauses", FIELD_W / 2, 206)
    graphics.text("one finger drags the cannon, firing is automatic", FIELD_W / 2, 218)
    graphics.text("tap the score band to pause", FIELD_W / 2, 228)
    if best > 0 then
        graphics.fontSize(8)
        graphics.stroke(INK)
        graphics.text("BEST {best}", FIELD_W / 2, 242)
    end
end

func draw()
    if state == "title" then
        drawTitle()
        return
    end

    graphics.clear(Color(0.02, 0.03, 0.05))

    ## The fleet is stored by rows, hence by kind, so three tint changes cover all 55 aliens — one
    ## per alien was fifty-five native state changes a frame for the same picture.
    var tinted = 0
    for a in fleet do
        if a.alive then
            var k = kinds[a.kind]
            if a.kind <> tinted then
                graphics.tint(k.ink)
                tinted = a.kind
            end
            graphics.sprite(k.frames[frame], a.x, a.y, 8, 8)
        end
    end

    if ufo <> nil then
        graphics.tint(TOP_INK)
        graphics.sprite(ufoImg, ufo.x, UFO_Y, UFO_W, UFO_H)
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
    for b in bursts do
        graphics.sprite(burstImg, b.x, b.y, 10, 7)
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

    if popup <> nil then
        graphics.fontSize(8)
        graphics.stroke(TOP_INK)
        graphics.textMode("center", "center")
        graphics.text(popup.text, popup.x, popup.y)
    end

    graphics.fontSize(9)
    graphics.stroke(INK)
    graphics.textMode("left", "top")
    graphics.text("SCORE {score}", MARGIN, 8)
    graphics.textMode("center", "top")
    graphics.text("BEST {best}", FIELD_W / 2, 8)
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
    var hint = "arrows + space — P pauses — or play with one finger"
    if touchPlay then
        hint = "drag to move — tap the score band to pause"
    end
    graphics.text(hint, FIELD_W / 2, FIELD_H - 3)

    if paused then
        graphics.fontSize(12)
        graphics.stroke(GUN_INK)
        graphics.textMode("center", "center")
        graphics.text("PAUSED", FIELD_W / 2, 150)
    end

    if state == "over" then
        graphics.fontSize(14)
        graphics.stroke(TOP_INK)
        graphics.textMode("center", "center")
        graphics.text("GAME OVER", FIELD_W / 2, 150)
        graphics.fontSize(8)
        graphics.stroke(INK)
        graphics.text("SCORE {score} — press or tap to play again", FIELD_W / 2, 168)
    end
end
