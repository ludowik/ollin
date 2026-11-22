## The SOUND of Connect Four: a few short buffers computed once at startup, so that nothing is calculated while one plays.

global sndDrop   = nil
global sndLand   = nil
global sndWin    = nil
global sndLose   = nil
global sndDraw   = nil
global sndClick  = nil
global soundOn   = true

func buildSounds()
    sndDrop = sound.tone(300, 0.05, "triangle").envelope(0.002, 0.02, 0.4, 0.02).volume(0.12)
    sndLand = sound.generate(0.14, func(t)
        var n = math.rand() * 2 - 1
        return (n * 0.35 + math.sin(t * math.TAU * (220 - 80 * t))) * math.exp(-t * 28)
    end).volume(0.22)
    sndWin = sound.generate(0.7, func(t)
        var f = 392 * (1 + math.floor(t * 7) * 0.25)
        return math.sin(t * math.TAU * f) * math.exp(-t * 2.2)
    end).volume(0.2)
    sndLose = sound.generate(0.7, func(t)
        var f = 330 - 60 * math.floor(t * 6)
        return math.sin(t * math.TAU * f) * math.exp(-t * 2.5)
    end).volume(0.2)
    sndDraw = sound.tone(260, 0.35, "triangle").envelope(0.005, 0.05, 0.5, 0.2).volume(0.16)
    sndClick = sound.tone(640, 0.04, "square").envelope(0.002, 0.01, 0.4, 0.015).volume(0.1)
end

## Plays a buffer unless the sound is off.
func playSound(snd)
    if soundOn and snd <> nil then
        snd.play()
    end
end
