## What the screens say, with no drawing, so that the original and the modern style show the same thing: the lists of
## items of the three screens before the game, and what the screen of the game says besides the well (the panel, the
## message in the well, the curtain) — the end of the file.
##
## The lists of the screens before the game are both styles paint, in the same places. The places are in points of a screen of 160 by
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

## The first screen: the name, and the pieces, until START.
func titleItems(hint)
    var logo = screenLabel("TETRIS", 80, 30, 24)
    logo.logo = true
    var items = [logo]
    for item in [
        [Piece.I, 14, 48], [Piece.O, 54, 48], [Piece.T, 78, 48], [Piece.Z, 110, 44],
        [Piece.L, 22, 72], [Piece.J, 54, 76], [Piece.S, 86, 72]
    ] do
        items.push({piece: item[1], x: item[2], y: item[3] + 4})
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
