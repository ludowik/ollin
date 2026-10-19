## The SOUND of Sudoku: a few short buffers computed once at startup, so that nothing is calculated while one plays.
## The browser keeps the engine silent until the first gesture, which the first tap already is.

global sounds = {place: nil, erase: nil, bad: nil, unit: nil, win: [], confirm: nil, on: true}

## Turns the whole sound on or off through the master volume, which also silences what is already playing.
func setSound(on)
    sounds.on = on
    if on then
        audio.volume(1)
    else
        audio.volume(0)
    end
end

const WIN_NOTES = ["C5", "E5", "G5", "C6", "E6", "G6"]

func buildSounds()
    sounds.place = sound.tone(330, 0.07, "triangle").envelope(0.003, 0.03, 0.5, 0.03).volume(0.30)
    sounds.erase = sound.tone(220, 0.06, "triangle").envelope(0.003, 0.03, 0.4, 0.03).volume(0.22)
    sounds.confirm = sound.tone(sound.note("G5"), 0.12, "triangle").envelope(0.003, 0.05, 0.5, 0.05).volume(0.30)
    sounds.bad = sound.tone(110, 0.12, "square").envelope(0.003, 0.03, 0.5, 0.06).volume(0.16)
    sounds.unit = sound.tone(sound.note("C6"), 0.25, "triangle").envelope(0.005, 0.08, 0.5, 0.12).volume(0.28)
    sounds.win = WIN_NOTES.map(func(name)
        return sound.tone(sound.note(name), 0.35, "triangle").envelope(0.005, 0.1, 0.5, 0.2).volume(0.28)
    end)
end
