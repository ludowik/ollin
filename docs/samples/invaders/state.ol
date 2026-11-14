## The numbers that set the game, and what changes as it runs.

const TICK       = 1.0 / 60.0   ## the logical tick: one alien advances per tick
const CELL_W     = 16           ## the column pitch; a sprite is 8 wide, centred in it
const CELL_H     = 16
const FLEET_X    = 24
const FLEET_Y    = 40
const WAVE_DROP  = 8            ## how much lower each wave starts, and each descent falls
const STEP_X     = 2            ## how far one alien advances
const SHIELD_Y     = 200        ## the four shields, just above the cannon as in the arcade
## The row is CENTRED by calculation: five equal gaps between the walls and the four arches. Written
## as a first position and a pitch, it sat 26 px from the left wall and 8 from the right — a shift
## the eye catches at once, and one that no rewriting of two numbers can be trusted to keep. Whole
## pixels, a shield being read pixel by pixel through its own coordinates.
const SHIELD_GAP   = (FIELD_W - SHIELDS * SHIELD_W) // (SHIELDS + 1)
const GUN_H      = 5
const GUN_Y      = 224          ## the cannon stands close under the shields, not far below them
const GUN_SPEED  = 60           ## field pixels per second
const SHOT_SPEED = 240
const BOMB_SPEED = 90           ## slower than the cannon's shot: a bomb can be outrun
const BOMB_ODDS  = 90           ## one tick in this many drops a bomb, while there is room for one
const LIVES      = 3
const UFO_Y        = 24         ## the mystery ship's lane, above the fleet
const UFO_H        = 7
const UFO_SPEED    = 30         ## field pixels per second
const UFO_PERIOD   = 22.0       ## seconds between two crossings
const UFO_MIN_ALIVE = 8         ## it stays away below this many aliens, as the original does
## The price of the mystery ship, indexed by the number of shots fired. A table, not a random draw:
## a player who counts their shots can aim for the 300.
const UFO_VALUES = [100, 50, 50, 100, 150, 100, 100, 50, 300, 100, 100, 100, 50, 150, 100]
const POPUP_TIME = 0.9          ## how long the value stays written where the ship died
const EXTRA_LIFE  = 1500        ## a life is given each time the score passes another of these
const BLAST_TIME  = 0.18        ## how long a kill is shown coming apart
const PAUSE_BAND  = 20          ## the top band, in field pixels, where a tap pauses on a touch screen: the rest of the screen aims, and no thumb visits this spot while playing
const RESPAWN    = 1.2          ## seconds the field holds still after the cannon is hit

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
global marchStep = 0     ## which of the four notes the next pass plays
global ticks = 0         ## logical ticks, which is what makes the bomb sprite turn

global ufo = nil         ## {x, dir} while it crosses, nil between crossings
global ufoWait = UFO_PERIOD
global ufoDir = 1        ## it comes from the other side each time
global shots = 0         ## shots fired, which is what prices the mystery ship
global popup = nil       ## {text, x, y, left}: what a kill was worth, written where it happened
const BEST_KEY = "best"
global best = 0          ## the best score, kept from one run to the next

global state = "title"   ## "title", "play" or "over": every input asks this first
global paused = false
global bursts = []       ## {x, y, left}: the kills still coming apart
global nextLife = EXTRA_LIFE
global demo = 0.0        ## the title screen's own clock, which animates the three creatures

global aimId = nil       ## the finger aiming, by id — an id can be 0, so only nil means "none"
global touchPlay = false ## a finger has been seen: aiming is by hand, firing by the game (a finger that aims everywhere cannot also tap to fire, and the one-shot rule already paces the cannon)
global grabX = 0.0       ## where the finger landed, and where the cannon was then: a drag is
global grabGun = 0.0     ## RELATIVE, so touching the screen never teleports the cannon
global acc = 0.0
