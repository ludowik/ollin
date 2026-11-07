## The size of the field and of what flies in it, shared by the game (asteroids.ol) and by what a save may hold
## (save.ol): a save is only trusted when every position, count and radius fits these.

const FIELD_W = 512            ## the field, in its own pixels — graphics.viewport does the rest
const FIELD_H = 384
const SHOTS_MAX   = 4          ## how many of the player's shots may be in the air
const SAUCER_BIG_R  = 16.0
const SAUCER_SMALL_R = 9.0
