## The SOUND of Frog: a few short buffers computed once at startup, so that nothing is calculated while one plays. They are
## ours — a blip for a hop, a splash, a thud, a rising run for a frog home — and nothing of the arcade game's tunes.

global sndHop    = nil
global sndSplash = nil
global sndThud   = nil
global sndHome   = nil
global sndExtra  = nil
global sndStart  = nil
global soundOn   = true

func buildSounds()
    sndHop = sound.tone(520, 0.07, "square").envelope(0.003, 0.02, 0.5, 0.03).volume(0.16)
    sndSplash = sound.generate(0.45, func(t)
        var n = math.rand() * 2 - 1
        return n * math.exp(-t * 7) * (0.5 + 0.5 * math.sin(t * math.TAU * 22))
    end).volume(0.22)
    sndThud = sound.generate(0.35, func(t)
        var n = math.rand() * 2 - 1
        return (n * 0.5 + math.sin(t * math.TAU * (130 - 90 * t)) * 0.8) * math.exp(-t * 8)
    end).volume(0.3)
    sndHome = sound.generate(0.5, func(t)
        var f = 440 + 880 * math.min(t / 0.4, 1.0)
        return math.sin(t * math.TAU * f) * math.exp(-t * 3.5)
    end).volume(0.2)
    sndExtra = sound.generate(0.6, func(t)
        var f = 660 + 330 * math.floor(t * 12)
        return math.sin(t * math.TAU * f) * math.exp(-t * 2.5)
    end).volume(0.18)
    sndStart = sound.generate(0.5, func(t)
        var f = 330 + 110 * math.floor(t * 8)
        return math.sin(t * math.TAU * f) * math.exp(-t * 3)
    end).volume(0.18)
end

## Plays a buffer unless the sound is off.
func play(snd)
    if soundOn and snd <> nil then
        snd.play()
    end
end
