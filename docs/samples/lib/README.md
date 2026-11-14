# Shared libraries of the samples

One section per library whose use needs more than its header: how to wire it, and what it expects.

## stage.ol and stage_draw.ol — the stage of the step-by-step examples

`stage.ol` is the player: the state, loading a program, the keys and the taps. `stage_draw.ol` is what it looks like: the
palette, and the panels, the chips, the code, the note, the header and the buttons. An example imports `stage.ol` only.

Shared by "How the lexer works" and "How the parser works": the palette, the player (play, pause, step by step, back,
restart, the speed), the panel that shows the engine's own C++ with a bar on the line being run, the panel that explains
what happens, the header and the buttons at the bottom. Both examples are written the same way: copy one.

### Writing an example

An example fills the `stage` map in its `setup()`, then calls `openMenu()` and `loadProgram(1)`. Its `draw()` begins with
`beginFrame()`, takes its room from `baseLayout()` and adds its own panels between `drawHeader()` and `drawFooter()`
(`drawCode`, `drawNote`). Everything but `skip` and `speed` is needed; the fields that are not in this table (`title`, `menu`, `columns`, `watch`, `errorNote`, `keywords`, `pace`…) are described above `global stage` in `stage.ol`:

| field | what it is |
|---|---|
| `programs` | the programs it can show, each a map with a `name` |
| `lessons` | a sentence per program, shown under the title |
| `build(i)` | the trace of program `i`: a map with `steps`, the list the player replays |
| `cpp` | the engine's text, by function: `{first, lines, trimmed}` |
| `skip` | adds the SKIP button, which runs to the next step flagged `event` |

The callbacks `update`, `keyboard.keypressed` and `mouse.pressed` live in `stage.ol`: a module can declare them, a class
cannot. A `const` of the program that imports the file is not visible from it, which is why the example's own words come
through `stage`.

### A step

| field | what it is |
|---|---|
| `fn`, `at`, `span` | the function and the line it lights in the code panel, and how many more lines its statement covers |
| `also` | a second line to mark: the `case` label a switch jumped through |
| `stack` | the calls in progress, as `"tokenize > identifier"` |
| `note` | a sentence, said from there on |
| `err` | the message when the engine gives up |
| `event` | true when the line changed something: what SKIP runs up to |

The stage adds `dur`, `hand`, `said`, `noteId` and, from the example's `watch`, `watchText`. The tracers add their own fields
(see the head of `lexer/tracer.ol` and `parser/tracer.ol`).

### The player

A program plays by itself, and a tap pauses and resumes it. STEP BY STEP is the other way to read it: nothing moves until
you ask, every tap (or the Next button, or the right arrow) runs the next line, and Back (or the left arrow) goes back one.
The Step button, the S key and the menu switch the mode on and off; Play leaves it. SKIP (or the E key) runs up to the next
step flagged `event`.

Keys: space plays and pauses, up and down change the speed, a digit picks a program, `r` restarts. F7, F8 and F9 stand for
the previous, play/pause and next keys of an Apple keyboard (with fn, unless the system uses the F keys as standard).

## joystick.ol and view_distance.ol

Their headers give the wiring. Both are classes, and a class cannot receive a callback, so the host forwards the mouse
events to them by hand.
