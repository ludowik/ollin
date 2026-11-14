## The stage shared by the examples that replay the engine step by step ("How the lexer works", "How the parser works"): the
## palette, the player, the panel that shows the engine's own C++ with a bar on the line being run, the panel that explains
## what happens, the header and the buttons. How to write an example, the format of a step and the keys are in README.md.

import "area.ol"
import "stage_draw.ol"

const MIN_SPEED = 0.25
const MAX_SPEED = 8

global state = {pos: 0.0, playing: true, stepping: false, goal: 0.0, speed: 1.0, prog: 1, name: nil, hold: 0.0}
global run = nil          ## the trace of the program on show
global loaded = {}        ## the traces already made, by program: a trace never changes
global hits = []          ## the buttons drawn at the bottom, for the taps

## What an example hands over, besides the programs and the engine's text above: `title` heads the
## screen, `menu` names the menu, `file` and `owner` name the C++ in the code panel, `columns` is how
## many columns of a line of C++ are shown (a longer line is cut with a "~"), `watch(step)` writes the
## line of locals, `errorNote(step)` the sentence that follows a refusal, `pace(step)` how long a line
## takes (see prepareSteps), `keywords` the token types that are keywords, `speed` the speed it starts
## at, and `skip` adds the button that runs to the next step flagged `event`.
global stage = {title: "", menu: "", programs: [], lessons: [], build: nil, cpp: {}, file: "", owner: "",
                columns: 82, watch: nil, errorNote: nil, skip: false, keywords: {}, speed: 1.0, pace: nil}

## What the player needs of every step: how long it takes, and the sentence being said. `pace` is the
## example's own rule: it returns the time of a line when the program plays by itself and when it is
## paced by hand. A sentence adds to the first the time to read it.
func prepareSteps(r, pace)
    var said = ""
    var noteId = 0
    for st in r.steps do
        st.dur, st.hand = pace(st)
        if st.note or st.err then
            noteId += 1
        end
        if st.note then
            said = st.note
            st.dur += 0.3 + #st.note * 0.006
        end
        st.said = said       ## the last sentence said up to this step
        st.noteId = noteId   ## which sentence it is, to wrap it once
    end
end

func loadProgram(index)
    if loaded[index] == nil then
        loaded[index] = stage.build(index)
        prepareSteps(loaded[index], stage.pace)
    end
    run = loaded[index]
    state.prog = index
    state.name = stage.programs[index].name
    restart()
end

## A position that falls exactly between two steps is the END of the one before: at rest the bar,
## the highlighted number and the explanation then all speak of the line that has just run.
func current()
    var i = math.clamp(math.ceil(state.pos), 1, #run.steps)
    var t = math.clamp(state.pos - (i - 1), 0, 1)
    return i, t
end

## Step by step: nothing moves by itself, and `goal` is how far the next taps have asked it to go.
func setStepping(on)
    state.stepping = on
    if on then
        state.playing = false
        state.goal = state.pos
    else
        state.playing = true
        state.hold = 0.0
    end
end

func onPlaying(on)
    if on and state.stepping then
        setStepping(false)
    end
end

func togglePlay()
    if state.stepping then
        setStepping(false)
    else
        state.playing = not state.playing
    end
end

## Runs the line that is under way to its end, or the next one when it is done.
func stepForward()
    if not state.stepping then
        setStepping(true)
    end
    state.goal = math.min(math.floor(state.goal + 0.000001) + 1, #run.steps)
end

func stepBack()
    if not state.stepping then
        setStepping(true)
    end
    state.goal = math.max(math.ceil(state.goal - 0.000001) - 1, 0)
    state.pos = state.goal
end

## Runs up to the next step flagged `event`, or to the end: the lines in between are done without
## stopping on them.
func skipForward()
    if not stage.skip then
        return nil
    end
    if not state.stepping then
        setStepping(true)
    end
    var n = #run.steps
    var j = math.floor(state.goal + 0.000001) + 1
    while j < n and not run.steps[j].event do
        j += 1
    end
    state.goal = math.min(j, n)
end

func restart()
    state.pos = 0.0
    state.goal = 0.0
    state.hold = 0.0
end

func toggleStepping()
    setStepping(not state.stepping)
end

## What a button does, and what a key stands for.
const ACTIONS = {play: togglePlay, step: toggleStepping, back: stepBack, next: stepForward, skip: skipForward,
                 restart: restart}
const KEYS = {space: "play", f8: "play", s: "step", left: "back", f7: "back", right: "next", f9: "next",
              e: "skip", r: "restart"}

func onProgram(name)
    for i, p in stage.programs do
        if p.name == name then
            loadProgram(i)
        end
    end
end

## The menu: the program, the mode, the speed, and the buttons. Folded to its handle, since the
## animation has the whole screen.
func openMenu()
    var names = stage.programs.map(func(p) return p.name end)
    state.name = names[1]
    state.speed = stage.speed
    var menu = ui.menu(stage.menu)
    menu.list("Program", names, ref state.name, onProgram)
    menu.checkbox("Playing", ref state.playing, onPlaying)
    menu.checkbox("Step by step", ref state.stepping, setStepping)
    menu.slider("Speed", ref state.speed, MIN_SPEED, MAX_SPEED, 1.0)
    menu.button("Back", stepBack)
    menu.button("Next", stepForward)
    menu.button("Restart", restart)
    ui.show(menu)
    ui.close()
end

func keyboard.keypressed(key)
    if KEYS.has(key) then
        ACTIONS[KEYS[key]]()
    elseif key == "up" then
        state.speed = math.min(state.speed * 1.5, MAX_SPEED)
    elseif key == "down" then
        state.speed = math.max(state.speed / 1.5, MIN_SPEED)
    else
        var n = string.number(key)
        if n and n >= 1 and n <= #stage.programs then
            loadProgram(n)
        end
    end
end

func hitAt(x, y)
    for h in hits do
        if inRect(x, y, h) then
            return h.id
        end
    end
    return nil
end

## A tap anywhere else pauses and resumes, or in step by step runs the next line.
func tap()
    if state.stepping then
        stepForward()
    else
        togglePlay()
    end
end

func tapHint()
    if state.stepping then
        return "tap: next line"
    elseif state.playing then
        return "tap: pause"
    end
    return "tap: play"
end

func mouse.pressed(x, y)
    var id = hitAt(x, y)
    if id then
        ACTIONS[id]()
    else
        tap()
    end
end

## Moves the program forward by `budget` seconds, not beyond `limit`. When it is paced by hand
## every line takes the same short time, a token a little longer.
func advance(budget, limit, byHand)
    while budget > 0 and state.pos < limit do
        var i = math.floor(state.pos) + 1
        var d = run.steps[i].dur
        if byHand then
            d = run.steps[i].hand
        end
        var stop = math.min(i, limit)
        var left = (stop - state.pos) * d
        if budget >= left then
            state.pos = stop
            budget -= left
        else
            state.pos += budget / d
            budget = 0
        end
    end
end

func update(dt)
    if state.stepping then
        advance(dt, state.goal, true)
        return
    end
    if not state.playing then
        return
    end
    advance(dt * state.speed, #run.steps, false)
    if state.pos >= #run.steps then
        ## the end of a program: a pause to take it in, then on to the next one
        state.hold += dt
        if state.hold > 3 then
            loadProgram(state.prog % #stage.programs + 1)
        end
    end
end
