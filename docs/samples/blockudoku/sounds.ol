## The SOUND of Blockudoku: a few short buffers computed once at startup, so that nothing is
## calculated while one plays. The browser keeps the engine silent until the first gesture, which the
## first piece picked up already is.

global sndPlace = nil
global sndClear = []
global sndBad = nil
global sndOver = nil

## One note per step of the combo: clearing more at once, or in a row, climbs the scale.
const CLEAR_NOTES = ["C5", "E5", "G5", "C6", "E6"]

func buildSounds()
    sndPlace = sound.tone(196, 0.09, "triangle").envelope(0.003, 0.04, 0.5, 0.04).volume(0.35)
    sndClear = []
    for name in CLEAR_NOTES do
        sndClear.push(sound.tone(sound.note(name), 0.3, "triangle").envelope(0.005, 0.08, 0.5, 0.15).volume(0.30))
    end
    sndBad = sound.tone(110, 0.12, "square").envelope(0.003, 0.03, 0.5, 0.06).volume(0.18)
    sndOver = sound.generate(0.9, func(t)
        return math.sin(t * 6.28318 * (330 - 220 * t)) * math.exp(-t * 3)
    end).volume(0.30)
end
