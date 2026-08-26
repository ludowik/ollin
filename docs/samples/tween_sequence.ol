## The tween module, with a SEQUENCE of steps: `tween.sequence` plays them one after another, each
## starting from what the previous one left. The engine advances them every frame;
## the drawing only READS fields, and never speaks of time.
##
## Click anywhere to pause the scene, or to resume it.

global ball = {x: 0, y: 0, rx: 0, ry: 0, tint: Color(0.45, 0.8, 1)}

global points = []

## The sequence's handle: it serves to read its progress and to suspend it.
global bounce = nil
global paused = false

func radius()
    return H * 0.045
end

func floorY()
    return H * 0.72
end

func ceilingY()
    return H * 0.22
end

## The bounce, in five steps. The squash on impact and the stretch that follows last a tenth of a
## second each: it is that difference between the durations that gives the ball its weight, and it
## is exactly what a sequence of steps can express.
func startBounce()
    var r = radius()
    ball.x = CW
    ball.y = ceilingY()
    ball.rx = r
    ball.ry = r

    bounce = tween.sequence(ball, [
        ## The fall: the ball speeds up, and stretches a little along its motion.
        {to: {y: floorY(), rx: r * 0.88, ry: r * 1.15}, delay: 0.45, curve: "easeInQuad"},
        ## The impact: it squashes. The target is read when the step starts, so it sets off from
        ## the stretch the fall left behind — there is no value to copy out here.
        {to: {rx: r * 1.45, ry: r * 0.55}, delay: 0.08},
        ## The stretch, before setting off again.
        {to: {rx: r * 0.92, ry: r * 1.1}, delay: 0.1},
        ## The rise: it slows as it nears the top and recovers its round shape.
        {to: {y: ceilingY(), rx: r, ry: r}, delay: 0.55, curve: "easeOutQuad"},
        ## A step with no `to`: it merely lets time pass.
        {delay: 0.15},
    ]).repeat()

    ## The same blink for all three dots, offset by a growing delay: an animation's start can be
    ## put off, and its declaration need not wait.
    for i = 1, #points do
        points[i].r = H * 0.008
        tween.to(points[i], {r: H * 0.02}, 0.4, "easeInOutSine").repeat(nil, true).delay(i * 0.13)
    end
end

func setup()
    graphics.canvas(W, H, "tween.sequence")
    for i = 1, 3 do
        points[i] = {r: 0}
    end
    startBounce()
end

func mouse.pressed(x, y)
    paused = not paused
    if paused then
        bounce.pause()
    else
        bounce.resume()
    end
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.13))
    graphics.noStroke()

    ## The ground is decidedly LIGHT: a black shadow laid on a dark background would not
    ## be seen, and it is the shadow that makes the bounce's height readable.
    ## A BAND, not the whole bottom of the screen: the progress bar and the text thus stay
    ## on the dark background, where they are readable.
    var yFloor = floorY() + radius()
    graphics.fill(Color(0.29, 0.33, 0.42))
    graphics.rect(0, yFloor, W, H * 0.055)

    ## The shadow is DERIVED from the ball's height rather than animated: a parallel tween with a
    ## duration of its own would drift against the sequence, and the shadow would spread while the
    ## ball rose, as was observed. The drawing reads the position, and that is all.
    var fall = (ball.y - ceilingY()) / (floorY() - ceilingY())
    var shadowW = radius() * (0.7 + 1.5 * fall)
    var dark = 0.15 + 0.6 * fall
    ## Two concentric ellipses: the wider, paler one softens the edge, with no need for a blur.
    graphics.fill(Color(0.04, 0.05, 0.08, dark * 0.45))
    graphics.ellipse(ball.x, yFloor + radius() * 0.28, shadowW * 2.6, radius() * 0.7)
    graphics.fill(Color(0.04, 0.05, 0.08, dark))
    graphics.ellipse(ball.x, yFloor + radius() * 0.28, shadowW * 1.7, radius() * 0.42)

    graphics.fill(ball.tint)
    graphics.ellipse(ball.x, ball.y, ball.rx * 2, ball.ry * 2)

    ## The progress of the WHOLE sequence, in time: the steps do not share a duration, and yet the
    ## bar advances evenly.
    var barW = W * 0.6
    var left = CW - barW / 2
    var yb = H * 0.9
    graphics.fill(Color(1, 1, 1, 0.1))
    graphics.rect(left, yb, barW, H * 0.008)
    graphics.fill(Color(0.45, 0.8, 1))
    graphics.rect(left, yb, barW * bounce.progress(), H * 0.008)

    ## The three dots, to the right of the bar: they blink even while paused, only the sequence
    ## being suspended.
    graphics.fill(Color(0.65, 0.72, 0.85))
    for i = 1, #points do
        graphics.circle(left + barW + H * 0.03 * i, yb + H * 0.004, points[i].r)
    end

    graphics.fontSize(H * 0.028)
    graphics.stroke(Color(0.85, 0.88, 0.95))
    if paused then
        graphics.text("paused — click to resume", left, H * 0.84)
    else
        graphics.text("click to pause", left, H * 0.84)
    end
end
