## The size of the field and of what stands in it, shared by the game (invaders.ol) and by what a save may hold
## (save.ol): a save is only trusted when every position, count and picture fits these.

const FIELD_W    = 224          ## the field, in its own pixels — graphics.viewport does the rest
const FIELD_H    = 256
const COLS       = 11
const ROWS       = 5
const MARGIN     = 8            ## the walls the fleet turns at
const SHIELDS      = 4
const SHIELD_W     = 22
const SHIELD_H     = 16
const GUN_W      = 13
const BOMB_MAX   = 3            ## how many bombs the fleet keeps in the air
const UFO_W        = 16
