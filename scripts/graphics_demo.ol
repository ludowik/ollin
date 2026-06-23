## demo graphique : fenêtre, grille et diagonales
graphics.canvas(800, 600, "Ollin Demo")

func frame()
    graphics.clear(graphics.BLACK)

    ## grille
    graphics.strokeSize(1)
    graphics.stroke(graphics.GRAY)
    for i = 0, 750, 50 do
        graphics.line(i, 0, i, 600)
    end
    for j = 0, 550, 50 do
        graphics.line(0, j, 800, j)
    end

    ## diagonales
    graphics.stroke(graphics.RED)
    graphics.line(0,   0,   800, 600)
    graphics.stroke(graphics.BLUE)
    graphics.line(800, 0,   0,   600)
    graphics.stroke(graphics.WHITE)
    graphics.line(400, 0,   400, 600)
    graphics.stroke(graphics.GREEN)
    graphics.line(0,   300, 800, 300)

    graphics.stroke(graphics.WHITE)
    graphics.draw_text("FPS: " + graphics.fps(), 720, 580, 16)
end

graphics.run(frame)
