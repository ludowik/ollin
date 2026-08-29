## The ui module: widgets drawn by the ENGINE, at the top right of the drawing area. There is no
## dependency on the browser — the same code runs natively and in the playground.
##
## A widget is declared ONCE. The engine draws it and tests it every frame.
## Widgets are filed into menus and sub-menus; ui.show changes the menu on display.
## A checkbox, a slider and a list each receive a REFERENCE: `ref` accepts a path of fields, so
## the settings fit in ONE `config` object rather than in as many global
## variables. The program reads them as usual — see `config.grid` and
## `config.speed` in draw().

global config = {
    grid: true,
    anim: true,
    thick: false,
    speed: nil,    ## the slider initialises it to its default
    branches: 3,
    tint: 0.55,
    shape: nil,      ## the list initialises it to its first item
    direction: nil
}

## What a list draws from: an ARRAY gives its values, an ENUM or a map its keys.
global shapes = ["circle", "square", "triangle"]
enum Direction
    clockwise,
    counterClockwise
end

## The animation's state, which is not a setting, and the colour derived from the tint.
global turns = 0
global t = 0
global armColor

func reset()
    t = 0
    turns = 0
end

func onDirection(value)
    ## The callback receives the item chosen: here the enum's key, a string.
    print("direction: " + value)
end

func onTint(value)
    ## The callback receives the NEW value, so the colour is computed when it changes rather than
    ## every frame, as a read inside draw() would.
    armColor = Color(value, 0.85, 1 - value * 0.6)
end

func onThick(on)
    ## Called on every change, with the new state, which is handy for reacting at once instead of
    ## comparing the variable every frame.
    if on then
        print("thick stroke")
    else
        print("thin stroke")
    end
end

## setup() is called ONCE before the first frame: that is where all the initialisation happens —
## the drawing area, the menus, the starting state.
func setup()
    graphics.canvas(W, H, "ui")

    var main = ui.menu("Main")
    main.button("Reset", reset)
    main.checkbox("Animation", ref config.anim)
    ## `config.speed` being nil, the slider initialises it to its default, 1.0.
    main.slider("Speed", ref config.speed, 0.25, 3, 1.0)
    ## Integer bounds AND an integer start give an integer slider, with no decimals shown.
    main.slider("Branches", ref config.branches, 1, 8)

    ## A list is single-selection: the row shows the item chosen, and a click unfolds
    ## the choices. An array gives back the VALUE chosen, an enum its KEY.
    main.list("Shape", shapes, ref config.shape)
    main.list("Direction", Direction, ref config.direction, onDirection)

    var appearance = main.menu("Appearance")
    appearance.checkbox("Grid", ref config.grid)
    appearance.checkbox("Thick stroke", ref config.thick, onThick)
    appearance.slider("Tint", ref config.tint, 0, 1, onTint)

    ## ui.show replaces the menu on display, which is enough to move from one screen to another
    ## (pause, game over) without rebuilding the interface. The menus are locals of
    ## setup, captured by the buttons' closures.
    var pause = ui.menu("Pause")
    pause.button("Resume", func() ui.show(main) end)
    main.button("Pause", func() ui.show(pause) end)
    ui.show(main)

    onTint(config.tint)   ## the callback only fires on a change, so the initial colour is set here
end

## The shape at the end of an arm comes from the list: the program reads config.shape like an
## ordinary variable.
func drawShape(x, y, radius)
    if config.shape == "square" then
        graphics.rect(x - radius, y - radius, radius * 2, radius * 2)
    elseif config.shape == "triangle" then
        graphics.polygon([x, y - radius, x + radius, y + radius, x - radius, y + radius])
    else
        graphics.circle(x, y, radius)
    end
end

func drawGrid()
    graphics.stroke(Color(1, 1, 1, 0.10), 1)
    var step = H / 12
    for x = 0, W, step do
        graphics.line(x, 0, x, H)
    end
    for y = 0, H, step do
        graphics.line(0, y, W, y)
    end
end

func draw()
    graphics.clear(Color(0.09, 0.10, 0.14))
    if config.grid then
        drawGrid()
    end
    if config.anim then
        t += deltaTime * config.speed
    end

    ## As many arms as `config.branches`: every widget acts on the drawing at once.
    var side = math.min(W, H)
    var r = side * 0.28
    var radius = side * 0.06
    var gap = math.TAU / config.branches
    graphics.stroke(armColor, config.thick and 8 or 2)
    graphics.noFill()
    var direction = config.direction == "clockwise" and 1 or -1
    for i = 1, config.branches do
        var angle = direction * t + gap * i
        var cx = CX + math.cos(angle) * r
        var cy = CY + math.sin(angle) * r
        drawShape(cx, cy, radius)
        graphics.line(CX, CY, cx, cy)
    end

    if t > math.TAU then
        t -= math.TAU
        turns += 1
    end

    graphics.stroke(Color(0.85, 0.88, 0.95))
    graphics.fontSize(H * 0.035)
    graphics.text("turns: " + turns, W * 0.05, H * 0.12)
end
