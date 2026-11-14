## The game in progress, kept from one run to the next.

## The game in progress, as one text: score, streak, the 81 cells (a digit each, 0 for empty), and the
## shape of each of the three pieces ("-" once placed). Written after every move, so closing the page
## loses nothing; loadGame refuses a game that was already lost.
func saveGame()
    var keys = []
    for i = 1, 3 do
        if game.slots[i] == nil then
            keys.push("-")
        else
            keys.push(game.slots[i].shape.key)
        end
    end
    data.set(config.saveKey, "{game.score}|{game.streak}|{game.grid.join()}|{keys.join(",")}")
end

## Puts a saved game back; false (and nothing resumed) when there is none, when it does not read, or when it
## was already lost. Every part is checked before anything is touched.
func loadGame()
    var L = game.layout
    var saved = data.get(config.saveKey)
    if saved == nil then
        return false
    end
    var parts = saved.split("|")
    if len(parts) <> 4 then
        return false
    end
    var savedScore = parts[1].number()
    var savedStreak = parts[2].number()
    var keys = parts[4].split(",")
    if savedScore == nil or savedStreak == nil or len(parts[3]) <> CELLS or len(keys) <> 3 then
        return false
    end
    var g = boardNew()
    for i = 1, CELLS do
        var v = parts[3].char(i).number()
        if v == nil or v < 0 then
            return false
        end
        g[i] = math.min(v, 1)
    end
    var picks = []
    for key in keys do
        if key == "-" then
            picks.push(nil)
        else
            var shape = shapeFromKey(key)
            if shape == nil then
                return false
            end
            picks.push(shape)
        end
    end
    resetGame()
    game.grid = g
    game.score = savedScore
    game.streak = savedStreak
    game.display.score = game.score
    for i = 1, CELLS do
        game.cells[i].v = game.grid[i]
    end
    layoutCompute()
    for i = 1, 3 do
        if picks[i] == nil then
            game.slots[i] = nil
        else
            game.slots[i] = newSlot(picks[i], L.sx[i], L.sy[i], false)
        end
    end
    settleHand()
    return not isGameOver()
end
