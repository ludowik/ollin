# Ollin Frog

The arcade game of 1981 in which a frog crosses a road and a river to fill five homes, as an example for Ollin.

## What comes from the arcade game, and what is ours

**The arcade game's own** (decoded by `tools/convert_frog_data.py` from the analysis published at
<https://computerarcheology.com/Arcade/Frogger/>, and kept in `tiles.ol` and `arcade.ol`):

- every picture: the frog, the vehicles, the logs, the turtles in their three phases of diving, the fly, the crocodile, the
  skull, the letters of the title and of the header — 256 tiles of 8 x 8 and 64 sprites of 16 x 16;
- the lanes: eleven rows (five of river, the median strip, five of road), the picture each one is made of, the length of its
  objects, the gap after them and how many of them a lane holds, for each of the five difficulty tiers (the board's tier
  comes round every five boards); the turtles' three poses of swimming; the way each lane runs, which was read by hand from
  the routine of the program that moves the lanes and is written in `rules.ol`;
- the geometry: the field is the arcade's 224 x 256, a row is 16 pixels, the homes are five and 48 pixels apart;
- what the program's tables say of the rules and that the page names: three frogs, the extra frog at 20 000 points (and one
  more for a board completed), a row of progress paid once, a board completed worth 1 000.

**Ours, set by playing**, because the program's code is not readable that far:

- the SPEEDS of the lanes (`LANE_SPEED` in `rules.ol`) and the rise of 10 % at each board;
- the diving of the turtles: which groups dive, and when (the program draws a sinking turtle as a ring of bubbles, and so does
  this one);
- the clock (30 seconds a frog) and the points for the time left, for a home and for the fly;
- when the fly and the crocodile turn up, and for how long;
- the COLOURS: the colour PROM of the board is not part of the pages, so each picture's four colours are chosen in
  `sprites.ol`;
- the sounds, and the screens.

**Not done**: the snake, the otters and the lady frog, which the arcade game also has; two players; the tunes.

## Provenance

The pictures and the tables are the work of Konami (the Sega-licensed version is the same game). They are in the repository
because its owner chose to have the original look and lanes in an example for his own use. `tiles.ol` and `arcade.ol` are
generated: run `python3 tools/convert_frog_data.py` (it needs the network) to rebuild them, and never edit them by hand.

## Files

| file | what it is |
|---|---|
| `frog.ol` | the entry: setup, the keys and the taps, the frame |
| `field.ol` | the size of the field and the grid |
| `rules.ol` | the rules with no state: lanes, vehicles, support, turtles, homes, score (tested by `rules_test.ol`) |
| `state.ol` | what changes as a game runs |
| `play.ol` | what a frame of play does to the frog (tested by `play_test.ol`) |
| `sprites.ol`, `draw.ol` | the textures built from the decoded pictures, and the drawing |
| `sounds.ol` | the sounds |
| `tiles.ol`, `arcade.ol` | the decoded data |
