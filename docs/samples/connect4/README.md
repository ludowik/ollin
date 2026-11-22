# Connect Four

Connect Four against the computer, as an example for Ollin: drop discs in a grid of seven columns by six rows, and be the first to line
up four, across, up or on a diagonal.

## How the computer plays

- **The grid is two integers.** Each player's discs are one 49-bit integer, a bit per square: a column takes seven bits, its six squares
  and a guard bit above them that is never set, so that a line cannot run from the top of one column into the foot of the next. A line
  of four is then four shifts and four ANDs (`hasFour` in `board.ol`). That is what makes a search fast enough for an interpreter: a
  complete random game is played in well under a millisecond, and the test checks the bits against a plain scan of a grid it keeps by
  itself, on four hundred random games.
- **Negamax with alpha-beta pruning** (`ai.ol`), the columns tried from the middle outwards. A position where the player to move can
  win at once is a win without looking further; one where the other side has a winning disc to drop must stop it, and with two it has
  lost. These shortcuts change no value: the test compares the search with a plain minimax, one that has none of them, on random
  positions, at four depths. When it stops looking, a position is worth the weight of the columns its discs are in, and the empty
  squares that would complete four for each side.
- **Ties are broken at random**, among the columns that are equally good, so two games are not the same.
- **Three levels**: Easy looks two moves ahead and plays a column at random three times in ten; Medium looks five ahead; Hard looks nine.
  Measured in the browser, a search of nine moves takes between a quarter of a second and six tenths of one; ten took up to two
  seconds, which was too much for a phone.
- **It thinks between frames.** The search is a coroutine that gives the screen back every 500 positions with a bare `yield`, and the
  game gives it six milliseconds a frame (`thinkFor`). The grid goes on being drawn while the computer thinks, and the computer waits
  at least 0.45 seconds before it answers, however quick it was, so that a reply is seen to come. Outside a coroutine the same function
  simply goes on to the end, which is how the tests run it.

## What is kept

- **The game in progress**, after every disc: the list of columns played, the level and who plays first. The game is played again from
  the list when it comes back, so a save is small and easy to check; one that is not a game that could have been played — a column that
  does not exist, a seventh disc in a column, a move after the game was won — is refused whole.
- **The scores**, when a game ends: wins, losses and draws at each level, the run of wins that is going on, the best run and the fewest
  moves a game was won in.
- A game that is **given up** — by starting another over it — is not counted. **Undo** takes back the human's last disc and the
  computer's reply to it; the computer's opening disc is not the human's to take back, and a game that is over stays over.

## Files

| file | what it is |
|---|---|
| `connect4.ol` | the entry: setup, the fit to the screen, the callbacks of the keys, the mouse and the fingers |
| `board.ol` | the rules, with nothing else: the grid, the legal moves, the lines of four (tested by `board_test.ol`) |
| `ai.ol` | the search, the levels and the coroutine that thinks (`ai_test.ol`) |
| `scores.ol` | the scores and their store (`scores_test.ol`) |
| `state.ol` | what changes as a game runs |
| `save.ol` | the game in progress and its store (`save_test.ol`) |
| `play.ol` | what a frame does: a disc falling, the computer's turn, the end of a game, undo (`play_test.ol`) |
| `layout.ol` | where everything is, for a field as tall as the area's shape asks (`layout_test.ol`) |
| `screens.ol` | what a touch, a click and a key do on each screen (`screens_test.ol`) |
| `draw.ol`, `sounds.ol` | the drawing and the sounds |
| `connect4_testlib.ol` | what the tests share |
