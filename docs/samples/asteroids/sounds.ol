## The SOUND of Ollin Asteroids. Everything that is triggered is a buffer computed ONCE at startup;
## only the two continuous sounds — the thrust and the saucer — are living oscillators, because
## they are held and moved while they play.
##
## The heartbeat is the sound this game is remembered for, and it is not a soundtrack: two notes,
## one low, one lower, alternating, and the tempo is the number of rocks LEFT. The wave therefore
## quickens on its own as it empties, and nothing times it — the same idea as the fleet's march in
## the invaders example.
##
## Wired in from the entry file with a plain `import "sounds.ol"`: a flat import injects these
## names, the globals included, so the game just calls sndFire.play().

global sndFire  = nil
global sndBang  = []       ## one bang per rock size, the big rock the deepest
global sndDeath = nil
global sndSaucerDie = nil
global sndBeat  = []       ## the two heartbeat notes
global thrustVoice = nil
global saucerVoice = nil

const SAUCER_HUM    = 180       ## the saucer's tone, warbled while it crosses
const SAUCER_WARBLE = 60
const SAUCER_RATE   = 9.0

func buildSounds()
    ## Firing: a short blip falling as it leaves, which is what makes it read as departing.
    sndFire = sound.generate(0.10, func(t)
        return math.sin(t * 6.28318 * (1200 - 5000 * t)) * math.exp(-t * 25)
    end).volume(0.14)

    ## A rock coming apart: noise with a ring under it, the ring lower and the tail longer for a
    ## bigger rock. Three buffers, indexed by size, so the ear alone tells what was hit.
    sndBang = []
    for i = 1, 3 do
        var ring = 60 + i * 55        ## size 1 is the small rock: the highest, shortest crack
        var fade = 6 + i * 5
        sndBang.push(sound.generate(0.45, func(t)
            var n = math.rand() * 2 - 1
            return (n * 0.7 + math.sin(t * 6.28318 * ring) * 0.4) * math.exp(-t * fade)
        end).volume(0.24))
    end

    ## The ship coming apart: the heaviest noise of the game, and the slowest to die.
    sndDeath = sound.generate(0.9, func(t)
        var n = math.rand() * 2 - 1
        return (n * 0.8 + math.sin(t * 6.28318 * (110 - 70 * t)) * 0.4) * math.exp(-t * 3.5)
    end).volume(0.30)

    ## The saucer coming apart: a sweep downwards, so it is heard as a fall.
    sndSaucerDie = sound.generate(0.5, func(t)
        return math.sin(t * 6.28318 * (800 - 1400 * t)) * math.exp(-t * 5)
    end).volume(0.22)

    ## The heartbeat: two square thuds, the second a tone lower.
    sndBeat = []
    for f in [58, 46] do
        sndBeat.push(sound.tone(f, 0.13, "square").envelope(0.005, 0.04, 0.6, 0.05).volume(0.30))
    end

    thrustVoice = sound.noise(400).volume(0.07)
    saucerVoice = sound.square(SAUCER_HUM).volume(0.09)
end
