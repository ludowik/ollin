## The settings menu games share (docs/samples/lib/menu.ol): everything that does not draw.

import "menu.ol"

## No window here: the area is a portrait phone.
W = 400
H = 700
CX = 200
CY = 350
SIZE = 400

useLanguages(["a", "b"], {a: {name: "Aye", back: "Back"}, b: {name: "Bee", back: "Retour"}}, "menu_test.lang")
var shown = []
useMenu({ink: [0, 0, 0, 1], button: [1, 1, 1, 1], primary: [1, 0, 0, 1], accent: [0, 0, 1, 1], paper: 1,
         margin: 0.04, width: 0.8, height: 0.1, soundKey: "menu_test.sound",
         drawButton: func(label, r, fill, size) end, showScreen: func(name) shown.push(name) end})

## The sound switch turns the master volume with it and keeps the choice.
setSound(true)
assert(soundSwitch.on and audio.volume() == 1, "the sound on")
assert(switchSound() == false and not soundSwitch.on and audio.volume() == 0, "switching it off mutes the master volume")
assert(data.get("menu_test.sound", true) == false, "and keeps the choice")
assert(switchSound() == true and audio.volume() == 1, "switching it on restores the volume")
setSound(true)

## The entries are stacked, centred, inside the area, and never overlap.
for n = 1, 6 do
    var last = nil
    for i = 1, n do
        var r = optionRect(i, n)
        assert(math.abs(r.x + r.w / 2 - CX) < 1e-9 and r.w <= SIZE * 0.8, "entry {i} of {n} is centred and not too wide")
        assert(r.y >= 0 and r.y + r.h <= H, "entry {i} of {n} is inside the area")
        if last <> nil then
            assert(r.y >= last.y + last.h, "entry {i} of {n} does not overlap the one above")
        end
        last = r
    end
end

## A press goes to the entry under it, and the kind of entry decides what happens.
var toggled = 0
var handed = []
var entries = [
    {label: "help", goes: "help"},
    {label: "sound", toggle: func() toggled += 1 end},
    {label: "language", lang: "b"},
    {label: "level", level: 3}
]
func middleOf(i)
    var r = optionRect(i, len(entries))
    return r.x + r.w / 2, r.y + r.h / 2
end
func pressOn(i)
    var x, y = middleOf(i)
    pressEntries(entries, x, y, func(entry) handed.push(entry.level) end)
end
pressOn(1)
assert(len(shown) == 1 and shown[1] == "help", "an entry that leads somewhere shows the screen")
pressOn(2)
assert(toggled == 1, "an entry that toggles calls its function")
pressOn(3)
assert(i18n.lang == "b" and data.get("menu_test.lang", "") == "b", "an entry that picks a language picks it and keeps it")
pressOn(4)
assert(len(handed) == 1 and handed[1] == 3, "any other entry is handed to the game")
pressEntries(entries, -5, -5)
assert(len(shown) == 1 and toggled == 1 and len(handed) == 1, "a press on no entry does nothing")
setLanguage("a")

var languages = languageEntries()
assert(len(languages) == 3 and languages[1].label == "Aye" and languages[1].primary and not languages[2].primary)
assert(languages[2].lang == "b" and languages[3].label == "Back" and languages[3].goes == "options")
print("menu ok")
