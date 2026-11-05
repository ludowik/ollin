## The save of Tetris (docs/samples/tetris/save.ol): that a game written and read back is the same game, that every
## screen comes back as it was, that a game that was running comes back in pause, and that a save that cannot be
## trusted is refused whole and changes nothing. The state goes through `data` as a map, as the game would write it.

import "save.ol"

gameInit()

## A game under way, with everything a save has to keep: rubble, a falling piece, a score, the tune half played.
func arrange()
    game.state = "play"
    game.focus = "level"
    game.type = "B"
    game.height = 3
    game.won = false
    game.resume = "play"
    game.well = newWell()
    for r = 10, 17 do
        for c = 0, COLS - 1 do
            if (c * 7 + r * 3) % 5 <> 0 then
                game.well[wellIdx(c, r)] = 1 + (c + r) % KINDS
            end
        end
    end
    game.kind = Piece.T
    game.turn = 3
    game.x = 4
    game.y = 2
    game.next = Piece.S
    game.score = 6629
    game.lines = 12
    game.level = 3
    game.startLevel = 2
    game.best = 40000
    game.newBest = true
    game.fall = 17
    game.softFrames = 1
    game.downLock = true
    game.dasDir = -1
    game.dasFrames = 9
    game.wait = 0
    game.clearing = []
    game.levelUp = true
    game.frame = 777
    game.clock = 0.012
    game.held = {left: true, right: false, down: true}
    game.pressed = {start: true}
    music.beat = 5.25
    music.next = 4
end

## Everything a save keeps, as one text, to compare two games (a map has no order, json.stringify sorts its keys).
func snapshot()
    return json.stringify(saveState())
end

## The state as a copy of its own, that no later change of the game reaches.
func copyState()
    return json.parse(snapshot())
end

func scramble()
    game.state = "title"
    game.focus = "type"
    game.type = "A"
    game.well = newWell()
    game.score = 0
    game.lines = 99
    game.level = 0
    game.kind = 0
    game.next = 1
    game.clearing = [1, 2]
    game.frame = 5
    game.held = {left: false, right: false, down: false}
    game.pressed = {}
    music.beat = 0
    music.next = 1
end

## A game written, then read back in a scrambled one: the same, but in pause because it was running.
arrange()
var kept = copyState()
var before = snapshot()
scramble()
assert(snapshot() <> before)
var t = readSave(kept)
assert(t <> nil, "the save of a game was refused")
restoreSave(t)
assert(game.state == "paused" and game.resume == "play", "a running game comes back in pause")
game.state = "play"                              ## as START would put it
assert(snapshot() == before, "the game is not the one that was saved")
assert(game.well[wellIdx(2, 17)] == 1 + (2 + 17) % KINDS or game.well[wellIdx(2, 17)] == 0)
assert(game.frame == 0 and game.clock == 0 and game.held.left == false and len(game.pressed) == 0)
assert(music.beat == 5.25 and music.next == 4)

## Every screen and every running state comes back as it was; the running ones in pause, with where they return to.
for st in ["title", "menu", "level", "play", "clearing", "entry", "paused", "over"] do
    arrange()
    game.state = st
    game.resume = st == "paused" and "entry" or "play"
    if st == "clearing" then
        game.clearing = [16, 17]
        game.wait = 12
    end
    if st == "over" then
        game.won = true
        game.wait = 30
    end
    var line = copyState()
    scramble()
    restoreSave(readSave(line))
    var running = st == "play" or st == "clearing" or st == "entry"
    assert(game.state == (running and "paused" or st), "{st}: the screen is {game.state}")
    assert(game.resume == (running and st or (st == "paused" and "entry" or "play")), "{st}: it returns to {game.resume}")
    assert(game.focus == "level" and game.type == "B" and game.height == 3 and game.score == 6629)
    if st == "clearing" then
        assert(len(game.clearing) == 2 and game.clearing[1] == 16 and game.wait == 12)
    end
    if st == "over" then
        assert(game.won == true and game.wait == 30)
    end
end

## What is refused, and refused whole: the text is changed in one place and must not be read.
arrange()
var good = snapshot()
assert(readSave(copyState()) <> nil)
var rejected = 0
func refuse(why, change)
    var m = json.parse(good)
    change(m)
    assert(readSave(m) == nil, "this save was accepted: {why}")
    rejected += 1
end
refuse("another version", func(m) m.v = 2 end)
refuse("no version", func(m) m.v = nil end)
refuse("an unknown screen", func(m) m.state = "settings" end)
refuse("a screen that is not a text", func(m) m.state = 3 end)
refuse("an unknown focus", func(m) m.focus = "volume" end)
refuse("a type C", func(m) m.type = "C" end)
refuse("a resume that is not a running state", func(m) m.resume = "title" end)
refuse("a well of 179 cells", func(m) m.well.pop() end)
refuse("a well of 181 cells", func(m) m.well.push(0) end)
refuse("a cell of the 8th piece", func(m) m.well[3] = 8 end)
refuse("a cell below 0", func(m) m.well[3] = -1 end)
refuse("a cell that is not whole", func(m) m.well[3] = 1.5 end)
refuse("a cell that is a text", func(m) m.well[3] = "1" end)
refuse("a well that is a map", func(m) m.well = {} end)
refuse("a piece out of the pieces", func(m) m.kind = 9 end)
refuse("a turn the piece has not", func(m) m.kind = Piece.O m.turn = 2 end)
refuse("a turn of 0", func(m) m.turn = 0 end)
refuse("no next piece", func(m) m.next = 0 end)
refuse("a negative score", func(m) m.score = -1 end)
refuse("a score above the limit", func(m) m.score = config.maxScore + 1 end)
refuse("a score that is a float", func(m) m.score = 10.5 end)
refuse("a start level beyond the menu", func(m) m.startLevel = config.maxStartLevel + 1 end)
refuse("a height beyond the menu", func(m) m.height = config.maxHeight + 1 end)
refuse("a column that is a text", func(m) m.x = "4" end)
refuse("a row far below the well", func(m) m.y = 99 end)
refuse("a direction of 2", func(m) m.dasDir = 2 end)
refuse("a counter of frames below 0", func(m) m.fall = -1 end)
refuse("a boolean that is a number", func(m) m.won = 1 end)
refuse("a missing boolean", func(m) m.downLock = nil end)
refuse("a missing counter", func(m) m.wait = nil end)
refuse("rows that flash outside the well", func(m) m.clearing = [18] end)
refuse("five rows that flash", func(m) m.clearing = [1, 2, 3, 4, 5] end)
refuse("rows that are not an array", func(m) m.clearing = "16" end)
refuse("a tune before its start", func(m) m.beat = -1 end)
refuse("a tune past its end", func(m) m.beat = musicLength() + 1 end)
refuse("a note that does not exist", func(m) m.beatNext = len(music.events) + 2 end)
refuse("a falling piece in the rubble", func(m) m.well[wellIdx(4, 2) + 2 * COLS] = 1 m.well[wellIdx(5, 2)] = 1 end)
refuse("a falling piece out of the well", func(m) m.x = 9 end)
assert(rejected == 38)

## A paused game that was falling is held to the same rule; one that was not falling is not asked for a piece.
refuse("a paused falling game with its piece in the rubble", func(m)
    m.state = "paused"
    m.resume = "play"
    m.x = 9
end)
var m = json.parse(good)
m.state = "title"
m.kind = 0
m.x = 0
assert(readSave(m) <> nil, "a title screen does not ask for a piece")
for bad in ["", "not json", "[]", "5", nil, 5, true, [], {}] do
    assert(readSave(bad) == nil, "{bad} was accepted")
end

## Writing and reading through `data`: the map goes in and comes back whole, and a refused value changes nothing.
data.delete(SAVE_KEY)
arrange()
saveGame()
assert(json.stringify(data.get(SAVE_KEY)) == good, "what data keeps is not the state")
var back = readSave(data.get(SAVE_KEY))
assert(back <> nil and back.well[wellIdx(2, 17)] == game.well[wellIdx(2, 17)] and back.beat == 5.25)
game.score = 7000
saveGame()
assert(data.get(SAVE_KEY).score == 7000, "a changed game is not written")
scramble()
assert(loadGame() == true and game.score == 7000 and game.state == "paused")
data.set(SAVE_KEY, "garbage")
scramble()
var scrambled = snapshot()
assert(loadGame() == false, "a garbage save was loaded")
assert(snapshot() == scrambled, "a refused save changed the game")
data.set(SAVE_KEY, [1, 2, 3])
assert(loadGame() == false, "an array was loaded")
data.delete(SAVE_KEY)
assert(loadGame() == false)

## The autosave: written when the screen changes, and twice a second, not at every step.
data.delete(SAVE_KEY)
saved.state = ""
arrange()
game.frame = 1
autosave()
assert(data.get(SAVE_KEY) <> nil, "the first state is not kept")
game.frame = 2
game.score += 40
autosave()
assert(data.get(SAVE_KEY).score == 6629, "written at a step that is neither a change of screen nor the 30th")
game.frame = 30
autosave()
assert(data.get(SAVE_KEY).score == 6669, "not written at the 30th step")
game.score += 40
autosave()
assert(data.get(SAVE_KEY).score == 6669, "written twice at the 30th step")
game.frame = 31
game.score += 40
game.state = "paused"
autosave()
assert(data.get(SAVE_KEY).score == 6749 and data.get(SAVE_KEY).state == "paused", "not written at a change of screen")
data.delete(SAVE_KEY)

print("tetris save ok")
