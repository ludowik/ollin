## What a game keeps from one run to the next: the puzzle in progress, and the daily puzzles done.

func saveGame()
    if game.state <> "play" then
        return
    end
    data.set(config.saveKey, gameEncode(game.puzzle, game.grid, game.notes, game.hints, game.level, game.daily))
end

func saveDone()
    data.set(config.dailyKey, game.done.keys().join(","))
end

func loadDone()
    game.done = {}
    var text = data.get(config.dailyKey, "")
    if typeof(text) == "string" and text <> "" then
        for k in text.split(",") do
            game.done[k] = true
        end
    end
end

## Puts a saved game back; false (and nothing resumed) when there is none, when it does not read, when its puzzle has
## not one solution, or when it was already solved. Every part is checked before anything is touched.
func loadGame()
    var saved = gameDecode(data.get(config.saveKey), HINTS, 4)
    if saved == nil then
        return false
    end
    var found = solverCount(saved.puzzle, 2, nil)
    if found.count <> 1 or boardComplete(saved.grid) then
        return false
    end
    installPuzzle({puzzle: saved.puzzle, solution: found.solution}, saved.level, saved.daily)
    game.grid = saved.grid
    game.notes = saved.notes
    game.hints = saved.hints
    refreshConflicts()
    return true
end
