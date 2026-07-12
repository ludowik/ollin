## Affichage 3D — éclairage + instancing.
##   graphics.camera(...)                → caméra (objet, pilotée par méthodes)
##   graphics.ambient / graphics.light   → éclairage Blinn-Phong (opt-in)
##   graphics.begin3d(cam) … end3d()     → bloc 3D ; fill = couleur par instance
## Les solides pleins de même type sont dessinés en UN appel (instancing) :
## la grille de cubes ci-dessous ne coûte qu'un draw call, chacun sa couleur.

global cam = graphics.camera(20, 15, 20,  0, 0, 0)   ## regarde l'origine (reculée)

func setup()
    graphics.canvas(W, H, "3D")
    graphics.ambient(0.2)                    ## base ambiante
    graphics.light("dir", -1, -2, -0.5)      ## « soleil » directionnel
end

func draw()
    graphics.clear(colors.BLACK)             ## efface couleur + profondeur
    cam.orbit(elapsedTime * 0.4, 26, 16)     ## orbite reculée (angle en radians)

    graphics.noStroke()
    graphics.begin3d(cam)
        ## grille de cubes colorés — 1 seul draw call malgré N cubes et N couleurs
        for x = -4, 4 do
            for z = -4, 4 do
                var t = elapsedTime * 2 + x + z
                var h = 1 + (math.sin(t) + 1) * 1.5
                graphics.fill(Color((x + 4) / 8, (z + 4) / 8, 0.8))
                graphics.cube(x * 2, h / 2, z * 2,  1.4, h, 1.4)
            end
        end

        ## cube qui tourne au centre — transformations 3D via push/pop
        graphics.push()
            graphics.translate(0, 6, 0)
            graphics.rotateY(elapsedTime * 60)
            graphics.rotate(elapsedTime * 40, 1, 0, 1)   ## + un axe oblique
            graphics.fill(colors.WHITE)
            graphics.cube(0, 0, 0,  2, 2, 2)
        graphics.pop()
    graphics.end3d()

    graphics.draw_text("Ollin 3D — éclairage · instancing · transformations", 12, 12, 20, colors.WHITE)
end
