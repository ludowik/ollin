## Affichage 3D — caméra qui tourne autour d'une scène de cubes et sphères.
##   graphics.camera(px,py,pz, tx,ty,tz [, fovy]) → caméra (regarde la cible)
##   graphics.begin3d(cam) … graphics.end3d()      → bloc de dessin 3D
##   fill/stroke pilotent plein / fil de fer, comme en 2D.

func setup()
    graphics.canvas(W, H, "3D")
end

func draw()
    ## clear opaque = efface la couleur ET la profondeur (obligatoire en 3D)
    graphics.clear(colors.BLACK)

    ## caméra en orbite autour de l'origine (rayon 12, hauteur 7)
    var a = elapsedTime * 0.5
    var cam = graphics.camera(math.cos(a) * 12, 7, math.sin(a) * 12,  0, 0, 0)

    graphics.begin3d(cam)
        graphics.grid(12, 1)                  ## repère au sol

        ## cube plein rouge, arêtes noires
        graphics.fill(colors.RED)
        graphics.stroke(colors.BLACK)
        graphics.cube(-3, 1, 0,  2, 2, 2)

        ## sphère pleine bleue (sans arêtes)
        graphics.noStroke()
        graphics.fill(colors.SKYBLUE)
        graphics.sphere(3, 1, 0,  1.5)

        ## cylindre fil de fer seulement
        graphics.noFill()
        graphics.stroke(colors.LIME)
        graphics.cylinder(0, 0, 3,  0.2, 1.2, 3,  16)
    graphics.end3d()

    ## HUD 2D par-dessus la 3D (même frame)
    graphics.draw_text("Ollin 3D", 12, 12, 22, colors.WHITE)
end
