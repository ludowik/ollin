## What the screens say, with no drawing, so that the original and the modern style show the same thing: the lists of
## items of the three screens before the game, and what the screen of the game says besides the well (the panel, the
## message in the well, the curtain) — the end of the file.
##
## Both styles paint the lists of the screens before the game in the same places. The places are in points of a screen of 160 by
## 144, a style scales them; an item is a label {text, x, y, size, dim} (the name of the game also has `logo`), a choice {text, x, y, w, h, size, lit} or a
## piece {piece, x, y}. A label is centred on its place, a choice is the box that holds its text, and a piece is its
## 4 by 4 cells with the top left at its place. `lit` is the choice that is on, and the chosen one of the line the arrows
## are on blinks, so these lists change with the frame.

import "rules.ol"
import "play.ol"

func screenLabel(text, x, y, size, dim = false)
    return {text: text, x: x, y: y, size: size, dim: dim}
end

func screenChoice(text, x, y, w, h, size, chosen, focused)
    return {text: text, x: x, y: y, w: w, h: h, size: size, lit: chosen and (not focused or game.frame % 40 < 28)}
end

## The line that tells which style the key V switches to, and START, which blinks.
func screenHint(hint)
    return screenLabel(hint, 80, 133, 6, true)
end

func pushStart()
    return screenLabel("PUSH START", 80, 124, 8)
end

## The end of a list the screens before the game share: the blinking "PUSH START", then the hint of the style.
func withFooter(items, hint)
    if blinkOn() then
        items.push(pushStart())
    end
    items.push(screenHint(hint))
    return items
end

const TITLE_GAP = 10            ## points between two pieces of the title: more than a cell (8), so that none touches another

## A row of pieces centred across the screen, each given as [piece, lift]: the blocks of neighbours are TITLE_GAP apart
## whatever the boxes of the pieces hold, and a lift moves a piece up (negative) or down.
func titleRow(row, y)
    var bounds = []
    var width = TITLE_GAP * (len(row) - 1)
    for entry in row do
        var x0, x1 = shapeBounds(entry[1], 1)
        bounds.push([x0, x1])
        width += (x1 - x0 + 1) * 8
    end
    var x = 80 - width / 2
    var items = []
    for i = 1, len(row) do
        var x0, x1 = bounds[i][1], bounds[i][2]
        items.push({piece: row[i][1], x: x - x0 * 8, y: y + row[i][2]})
        x += (x1 - x0 + 1) * 8 + TITLE_GAP
    end
    return items
end

## The pieces of the title, laid out once: the places never change, and the title is drawn every frame.
global titlePieces = nil

## The first screen: the name, and the pieces, until START.
func titleItems(hint)
    var logo = screenLabel("TETRIS", 80, 30, 24)
    logo.logo = true
    var items = [logo]
    if titlePieces == nil then
        titlePieces = titleRow([[Piece.I, 0], [Piece.O, 0], [Piece.T, 0], [Piece.Z, -4]], 52)
        for item in titleRow([[Piece.L, 0], [Piece.J, 4], [Piece.S, 0]], 76) do
            titlePieces.push(item)
        end
    end
    for item in titlePieces do
        items.push(item)
    end
    return withFooter(items, hint)
end

## The second screen: the type of game, and the music.
func menuItems(hint)
    var onType = game.focus == "type"
    var onMusic = game.focus == "music"
    var items = [
        screenLabel("GAME TYPE", 80, 20, 8),
        screenChoice("A-TYPE", 18, 30, 60, 28, 8, game.type == "A", onType),
        screenChoice("B-TYPE", 82, 30, 60, 28, 8, game.type == "B", onType),
        screenLabel("MUSIC", 80, 78, 8),
        screenChoice("MUSIC-A", 18, 88, 60, 20, 8, music.on, onMusic),
        screenChoice("OFF", 82, 88, 60, 20, 8, not music.on, onMusic)
    ]
    return withFooter(items, hint)
end

## The third screen: the level the game begins at, and for a B game the height of its rubble.
func levelItems()
    var onLevel = game.focus == "level"
    var items = [screenLabel(game.type + "-TYPE", 80, 16, 10), screenLabel("LEVEL", 80, 32, 8)]
    for i = 0, config.maxStartLevel do
        items.push(screenChoice("{i}", 20 + i % 5 * 24, 40 + i // 5 * 18, 20, 14, 8, i == game.startLevel, onLevel))
    end
    if game.type == "B" then
        items.push(screenLabel("HEIGHT", 80, 88, 8))
        for i = 0, config.maxHeight do
            items.push(screenChoice("{i}", 12 + i * 22, 96, 18, 14, 8, i == game.height, not onLevel))
        end
    end
    items.push(screenLabel("HIGH {game.best:06d}", 80, 124, 8, true))
    return items
end

## The items of a screen before the game, or nil for the game itself, which a style draws its own way.
func screenItems(hint)
    if game.state == "title" then
        return titleItems(hint)
    elseif game.state == "menu" then
        return menuItems(hint)
    elseif game.state == "level" then
        return levelItems()
    end
    return nil
end

## ── The screen of the game ─────────────────────────────────────────────────────────────────────────

## What the panel shows: the numbers of the three cards and the piece to come.
func panelInfo()
    return {score: game.score, level: game.level, lines: linesShown(), next: game.next}
end

## The message in the well, or nil when there is none: {kind: "pause"} while the game waits, and once a game is over
## (for a lost one, when the curtain is down) {kind: "over", won, newBest, best, blink}, `blink` telling whether PUSH
## START is lit on this frame. A style words it and places it its own way.
func wellMessage()
    if game.state == "paused" then
        return {kind: "pause"}
    end
    if game.state == "over" and overDone() then
        return {kind: "over", won: game.won, newBest: game.newBest, best: game.best, blink: blinkOn()}
    end
    return nil
end

## The rows of the curtain that have come down on a lost game, from the bottom: none for another state, or a won game.
func curtainShown()
    if game.state == "over" and not game.won then
        return curtainRows()
    end
    return 0
end
