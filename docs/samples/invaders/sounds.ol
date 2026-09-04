## The SOUND of Ollin Invaders: the four notes of the march and the four noises, all of them
## computed ONCE at startup — the engine samples these formulas before the game runs, so nothing is
## calculated while a note plays.
##
## Only the mystery ship needs a living oscillator, its tone being moved while it sounds; everything
## else is a frozen buffer, triggered by the game.
##
## Wired in from the entry file with a plain `import "sounds.ol"`: a flat import injects these
## names, the globals below included, so the game just calls sndShoot.play().

global sndMarch = []
global sndShoot = nil
global sndAlien = nil
global sndGun   = nil
global sndUfo   = nil
global ufoVoice = nil
global marchStep = 0     ## which of the four notes the next pass plays

## The mystery ship's tone and its warble: they describe a SOUND, so they live with the sounds even
## though the crossing that plays them is the game's business.
const UFO_HUM     = 220         ## the mystery ship's tone, warbled while it crosses
const UFO_WARBLE  = 70          ## how far the warble swings, in hertz
const UFO_RATE    = 14.0        ## and how fast, in swings per second

## The march's four notes, descending — the loop the fleet walks to.
const MARCH_NOTES = [110, 98, 87, 78]

func buildSounds()
    sndMarch = []
    for f in MARCH_NOTES do
        sndMarch.push(sound.tone(f, 0.11, "square").envelope(0.005, 0.03, 0.7, 0.04).volume(0.25))
    end
    ## The cannon's shot: a tone falling as it leaves, which is what makes it read as departing.
    sndShoot = sound.generate(0.16, func(t)
        return math.sin(t * 6.28318 * (900 - 3600 * t)) * math.exp(-t * 14)
    end).volume(0.18)
    ## An alien coming apart: noise, with a low ring under it so it is not just a hiss.
    sndAlien = sound.generate(0.22, func(t)
        var n = math.rand() * 2 - 1
        return (n * 0.7 + math.sin(t * 6.28318 * 180) * 0.3) * math.exp(-t * 12)
    end).volume(0.22)
    ## The cannon itself: the same idea, heavier and slower to die.
    sndGun = sound.generate(0.7, func(t)
        var n = math.rand() * 2 - 1
        return (n * 0.8 + math.sin(t * 6.28318 * (90 - 60 * t)) * 0.4) * math.exp(-t * 4)
    end).volume(0.30)
    ## The mystery ship coming apart: a sweep downwards, so it is heard as a fall.
    sndUfo = sound.generate(0.45, func(t)
        return math.sin(t * 6.28318 * (700 - 1200 * t)) * math.exp(-t * 5)
    end).volume(0.22)
    ufoVoice = sound.square(UFO_HUM).volume(0.10)
end
