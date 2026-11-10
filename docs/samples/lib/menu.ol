## What two games share of their settings: the sound switch, the screens that replace the game with a title and a column of
## buttons, and the gear that opens them. A game calls useMenu(look) once, in setup(), with:
##   ink, button, primary, accent, paper    the colours: text, a button, the main button, the gear, the background
##   margin, width, height                  fractions of SIZE: the margin of a screen, the width and height of a button
##   soundKey                               where the sound choice is kept between two runs
##   drawButton(label, rect, fill, size)    and showScreen(name), which are the game's own
## An entry of a menu is {label, primary, done} and one of: goes (a screen), lang (a language), toggle (a function).

import "draw.ol"
import "area.ol"
import "i18n.ol"

global menuLook = nil
global soundSwitch = {on: true, key: nil}

func useMenu(look)
    menuLook = look
    soundSwitch.key = look.soundKey
    setSound(data.get(look.soundKey, true))
end

## Turns the whole sound on or off through the master volume, which also silences what is already playing.
func setSound(on)
    soundSwitch.on = on
    if on then
        audio.volume(1)
    else
        audio.volume(0)
    end
end

## Flips the sound and keeps the choice. Says whether it is on now.
func switchSound()
    setSound(not soundSwitch.on)
    data.set(soundSwitch.key, soundSwitch.on)
    return soundSwitch.on
end

## The rectangle of the i-th of n entries of a menu, centred in the area.
func optionRect(i, n)
    var look = menuLook
    var w = math.min(W - 2 * SIZE * look.margin, SIZE * look.width)
    var h = math.min(SIZE * look.height, (H * 0.84) / (n * 1.35))
    var gap = h * 0.35
    var top = H / 2 - (n * h + (n - 1) * gap) / 2
    return rectOf(CX - w / 2, top + (i - 1) * (h + gap), w, h)
end

## The title of a screen that replaces the game: the background is already painted.
func drawScreenTitle(title)
    drawText(title.upper(), CX, SIZE * 0.06, SIZE * 0.05, "center", "center", menuLook.ink)
end

func drawEntries(entries)
    for i, entry in entries do
        var r = optionRect(i, len(entries))
        var fill = menuLook.button
        if entry.primary then
            fill = menuLook.primary
        end
        menuLook.drawButton(entry.label, r, fill, r.h * 0.4)
        if entry.done then
            graphics.stroke(1, 1, 1, 1)
            graphics.strokeSize(math.max(3, r.h * 0.1))
            var cx = r.x + r.w - r.h * 0.6
            var cy = r.y + r.h / 2
            graphics.line(cx - r.h * 0.18, cy, cx - r.h * 0.04, cy + r.h * 0.14)
            graphics.line(cx - r.h * 0.04, cy + r.h * 0.14, cx + r.h * 0.2, cy - r.h * 0.16)
            graphics.noStroke()
        end
    end
end

## A press on a menu: the entry under it, if any. An entry that leads nowhere, picks no language and toggles nothing is
## handed to `other`, when the game has one.
func pressEntries(entries, x, y, other = nil)
    for i, entry in entries do
        if inRect(x, y, optionRect(i, len(entries))) then
            if entry.lang <> nil then
                chooseLanguage(entry.lang)
            elseif entry.toggle <> nil then
                entry.toggle()
            elseif entry.goes <> nil then
                menuLook.showScreen(entry.goes)
            elseif other <> nil then
                other(entry)
            end
            return
        end
    end
end

## A screen made of a menu: its title, and the entries that make its buttons (a function, since their labels follow the
## language and the settings).
func menuScreen(titleKey, entries, other = nil)
    return {
        draw: func()
            drawScreenTitle(tr(titleKey))
            drawEntries(entries())
        end,
        press: func(x, y)
            pressEntries(entries(), x, y, other)
        end
    }
end

func languageEntries()
    var entries = []
    for code in i18n.languages do
        entries.push({label: nameOfLanguage(code), lang: code, primary: code == i18n.lang})
    end
    entries.push({label: tr("back"), goes: "options"})
    return entries
end

## The button that opens the settings: a thick toothed wheel with a hole through to the paper.
func drawGear(r)
    var s = r.w
    fillC(menuLook.accent)
    graphics.push()
    graphics.translate(r.x + s / 2, r.y + s / 2)
    graphics.rectMode("center")
    for k = 1, 8 do
        graphics.rect(0, -s * 0.34, s * 0.20, s * 0.20, s * 0.04)
        graphics.rotate(45)
    end
    graphics.pop()
    graphics.circle(r.x + s / 2, r.y + s / 2, s * 0.30)
    graphics.fill(menuLook.paper)
    graphics.circle(r.x + s / 2, r.y + s / 2, s * 0.13)
end
