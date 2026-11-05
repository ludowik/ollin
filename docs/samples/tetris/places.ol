## Where things sit on the screen of the handheld, in its 160 by 144 points: the well, the cards of the panel and the cell
## of the next piece. Both styles draw in these places, so that the well, the infos and (through the layout of tetris.ol,
## which scales this screen into the area) the pads are at the same place and of the same size whatever the style.

import "rules.ol"

const SCREEN = {w: 160, h: 144}
const CELL = 8                                           ## the side of a cell of the well, in points
const WELL = {x: 16, y: 0, w: COLS * CELL, h: ROWS * CELL}
const SCORE_CARD = {x: 109, y: 5, w: 46, h: 30}          ## the score, and under its title the number
const LEVEL_CARD = {x: 109, y: 45, w: 46, h: 22}
const LINES_CARD = {x: 109, y: 69, w: 46, h: 22}
const NEXT_CARD = {x: 115, y: 99, w: 42, h: 42}
const NEXT_GRID = {x: 120, y: 104}                       ## the top left of the 4 by 4 cells of the next piece's box
