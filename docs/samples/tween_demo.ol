## The tween module moves an object's field from its CURRENT value towards a target, over a
## duration, along a curve. The engine advances the tweens every frame: there is nothing to call
## in draw(), one declares and forgets.
##
## Clique n'importe où pour relancer les animations. La liste « Courbe » du menu choisit la
## curve applied to the star, and the slider sets the duration.

global config = {curve: "easeInOutQuad"}

## One mover per curve compared: each carries its position and its colour, which the tween writes
## directly. The drawing merely READS those fields, with no concern for time.
global dots = []
global labels = ["linear", "easeOutQuad", "easeInOutCubic", "easeOutBack", "easeOutElastic", "easeOutBounce"]

## A single object driven by the menu, to compare a curve chosen on the fly.
global star = {x: 0, size: 0, tint: Color(0.3, 0.7, 1)}
global duration = 1.2

func xStart()
    return W * 0.12
end

## The finish sits clear of the menu in the top-right corner, the UNFOLDED list included: the
## overshooting curves — back, elastic — go past the target before coming back, and the dot would
## end up under the choices on display.
func xEnd()
    return W * 0.72
end

func start()
    ## Each dot sets off again from left to right along ITS curve. Declaring a new tween on a
    ## field already animated cancels the previous one, so clicking mid-run does not create two
    ## competing animations.
    for i = 1, #dots do
        var p = dots[i]
        p.x = xStart()
        tween.to(p, {x: xEnd()}, duration, labels[i])
    end

    ## Several fields in one call, a COLOUR among them: a class instance is interpolated field by
    ## field (r, g, b, a), with nothing special to do here.
    star.x = xStart()
    star.size = H * 0.02
    star.tint = Color(0.3, 0.7, 1)
    tween.to(star, {x: xEnd(), size: H * 0.055, tint: Color(1, 0.45, 0.2)},
             duration, config.curve)

    ## The way back starts 0.3 s later, from whatever value the star holds by then: a delay puts
    ## off the READING of the starting value, not only the movement.
    tween.to(star, {size: H * 0.02}, duration * 0.6, "easeInQuad").delay(duration + 0.3)
end

## The callback receives the item chosen; config.curve is already written when it fires, so
## il suffit de relancer.
func onCurve(name)
    start()
end

func setup()
    graphics.canvas(W, H, "tween")

    for i = 1, #labels do
        dots[i] = {x: 0}
    end

    ## ONE list instead of eighteen buttons: it writes config.curve, the name chosen,
    ## puisqu'un tableau renvoie ses valeurs) puis appelle le rappel. Sa source est
    ## tween.curves(), donc elle suit le catalogue du moteur sans le recopier ici.
    var menu = ui.menu("Animation")
    menu.list("Courbe", tween.curves(), ref config.curve, onCurve)
    menu.slider("Duration", ref duration, 0.3, 3)
    ui.show(menu)

    start()
end

func mouse.pressed(x, y)
    start()
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.13))
    graphics.fontSize(H * 0.028)

    ## One row per curve compared: the dot sits where the tween writes it.
    var y = H * 0.18
    var step = H * 0.1
    for i = 1, #dots do
        graphics.stroke(Color(1, 1, 1, 0.12), 1)
        graphics.line(xStart(), y, xEnd(), y)
        graphics.noStroke()
        graphics.fill(Color(0.45, 0.8, 1))
        graphics.circle(dots[i].x, y, H * 0.014)
        graphics.stroke(Color(0.65, 0.72, 0.85))
        graphics.text(labels[i], W * 0.02, y - H * 0.014)
        y += step
    end

    ## The star: position, size and colour animated together.
    graphics.noStroke()
    graphics.fill(star.tint)
    graphics.circle(star.x, H * 0.86, star.size)
    graphics.stroke(Color(0.85, 0.88, 0.95))
    graphics.text(config.curve + " — click to restart", W * 0.02, H * 0.93)
end
