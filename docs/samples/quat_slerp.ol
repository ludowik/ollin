## Rotations par quaternion — interpolation lisse (slerp) entre deux orientations.
##   graphics.quat_axis(ax,ay,az, deg) → un Quat (rotation autour d'un axe)
##   qa.slerp(qb, t)                   → orientation interpolée (t ∈ [0,1])
##   graphics.rotateq(q)               → applique la rotation (comme rotate)

global cam = graphics.camera(0, 3, 9,  0, 0, 0)
global qa = graphics.quat_axis(1, 0, 0, 0)      ## orientation de départ
global qb = graphics.quat_euler(35, 200, 20)    ## orientation d'arrivée (Euler)

func setup()
    graphics.canvas(W, H, "Quaternions — slerp")
    graphics.ambient(0.2)
    graphics.light("dir", -1, -2, -0.5)
end

func draw()
    graphics.clear(colors.BLACK)
    graphics.noStroke()

    ## t fait un va-et-vient 0 → 1 → 0 en douceur
    var t = (math.sin(elapsedTime * 1.5) + 1) / 2
    var q = qa.slerp(qb, t)

    graphics.begin3d(cam)
        graphics.grid(10, 1)
        graphics.push()
            graphics.rotateq(q)                  ## la même orientation…
            graphics.fill(colors.SKYBLUE)
            graphics.cube(0, 0, 0,  3, 3, 3)
        graphics.pop()
        ## un satellite qui tourne autour, orienté par le quaternion inverse
        graphics.push()
            graphics.rotateq(q.inverse())
            graphics.translate(4, 0, 0)
            graphics.fill(colors.ORANGE)
            graphics.cube(0, 0, 0,  1, 1, 1)
        graphics.pop()
    graphics.end3d()

    graphics.draw_text("slerp", 12, 12, 20, colors.WHITE)
end
