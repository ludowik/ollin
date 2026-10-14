## The SOUND of Blockudoku: a few short buffers computed once at startup, so that nothing is
## calculated while one plays. The browser keeps the engine silent until the first gesture, which the
## first piece picked up already is.

global sounds = {place: nil, clear: [], bad: nil, over: nil}

## One note per step of the combo.
const CLEAR_NOTES = ["C5", "E5", "G5", "C6", "E6"]

func buildSounds()
    sounds.place = sound.tone(196, 0.09, "triangle").envelope(0.003, 0.04, 0.5, 0.04).volume(0.35)
    sounds.clear = CLEAR_NOTES.map(func(name)
        return sound.tone(sound.note(name), 0.3, "triangle").envelope(0.005, 0.08, 0.5, 0.15).volume(0.30)
    end)
    sounds.bad = sound.tone(110, 0.12, "square").envelope(0.003, 0.03, 0.5, 0.06).volume(0.18)
    sounds.over = sound.generate(0.9, func(t)
        return math.sin(t * math.TAU * (330 - 220 * t)) * math.exp(-t * 3)
    end).volume(0.30)
end

## The note follows the combo: clearing more at once, or in a row, climbs the scale up to its top.
func playClear(zones, streak)
    sounds.clear[math.min(zones + streak - 1, len(sounds.clear))].play()
end
