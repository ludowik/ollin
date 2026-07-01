## demo graphique : fenêtre, grille et diagonales
graphics.canvas(800, 600, "Ollin Demo")

## `draw` est appelée automatiquement à chaque frame par le moteur.
func draw()
    graphics.clear(colors.BLACK)

    ## grille
    graphics.strokeSize(1)
    graphics.stroke(colors.GRAY)
    for i = 0, 750, 50 do
        graphics.line(i, 0, i, 600)
    end
    for j = 0, 550, 50 do
        graphics.line(0, j, 800, j)
    end

    ## diagonales
    graphics.stroke(colors.RED)
    graphics.line(0,   0,   800, 600)
    graphics.stroke(colors.BLUE)
    graphics.line(800, 0,   0,   600)
    graphics.stroke(colors.WHITE)
    graphics.line(400, 0,   400, 600)
    graphics.stroke(colors.GREEN)
    graphics.line(0,   300, 800, 300)
end
