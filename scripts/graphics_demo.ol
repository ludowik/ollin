## demo graphique : fenêtre, grille et diagonales
graphics.canvas(800, 600, "Ollin Demo")

while graphics.is_open()
    graphics.begin_draw()
    graphics.clear(graphics.BLACK)

    ## grille
    for i = 0, 800, 50
        graphics.line(i, 0, i, 600, graphics.GRAY)
    end
    for j = 0, 600, 50
        graphics.line(0, j, 800, j, graphics.GRAY)
    end

    ## diagonales
    graphics.line(0,   0,   800, 600, graphics.RED)
    graphics.line(800, 0,   0,   600, graphics.BLUE)
    graphics.line(400, 0,   400, 600, graphics.WHITE)
    graphics.line(0,   300, 800, 300, graphics.GREEN)

    graphics.end_draw()
end

graphics.close()
