## Regression tests — The sound module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/sound.ol — it must finish without error.

## ── The sound module: oscillators ──────────────────────────────────────────
## With no device the whole API still answers: the voices exist, and their parameters can be read
## and written. Only the output is mute, which makes the synthesis testable in a container with no
## sound card.
var osA = sound.sine(440)
assert(osA.freq() == 440 and osA.shape() == "sine")
assert(osA.volume() == 0.5 and osA.pan() == 0)
assert(not osA.isPlaying())

## Writes return the HANDLE, hence they chain; reads return the value.
assert(osA.freq(880).volume(0.25).pan(-1) == osA)
assert(osA.freq() == 880 and osA.volume() == 0.25 and osA.pan() == -1)

## start and stop toggle the state, and chain too.
osA.start()
assert(osA.isPlaying())
osA.stop()
assert(not osA.isPlaying())

## Volume and pan are CLAMPED silently, like the master volume.
assert(osA.volume(5) == osA and osA.volume() == 1)
assert(osA.pan(-9) == osA and osA.pan() == -1)
assert(osA.pan(9) == osA and osA.pan() == 1)

## Each shorthand sets its waveform, and `shape` reads it back by name.
assert(sound.square(100).shape() == "square")
assert(sound.saw(100).shape() == "saw")
assert(sound.triangle(100).shape() == "triangle")
assert(sound.noise().shape() == "noise")
assert(sound.osc(220, "square").shape() == "square")

## The shape can be changed while running, as the frequency can.
assert(osA.shape("saw").shape() == "saw")

## Recycling: when the table is full, the OLDEST stopped voice is taken back — by creation rank,
## not the first slot that comes, which kept hammering the same one. The handle taken back is
## detected as stale instead of naming the next caller's voice.
var osVieux = sound.sine(200)
var osNeuf = nil
for i = 1, 20 do
    osNeuf = sound.sine(300)
end
var osPerime = false
try
    osVieux.freq()
catch e
    osPerime = true
end
assert(osPerime and osNeuf.freq() == 300)

## The envelope is carried by the oscillator, not by a separate object (p5 has one because it can
## modulate any parameter; here the target is unique). Reading it returns a map.
var osE = sound.sine(440)
assert(osE.envelope().attack == 0.01 and osE.envelope().sustain == 0.7)
assert(osE.envelope(0.02, 0.1, 0.5, 0.3) == osE)
var envE = osE.envelope()
assert(envE.attack == 0.02 and envE.decay == 0.1 and envE.sustain == 0.5 and envE.release == 0.3)

## trigger makes the voice audible and release lets it go — the dying away belongs to the mixer,
## hence to the browser, the integration container having no output. The curve's shape is checked
## through the buffers, which apply the SAME function.
assert(not osE.isPlaying())
assert(osE.trigger(0.2) == osE and osE.isPlaying())
assert(osE.release() == osE)

## With no envelope an oscillator behaves as it did before envelopes existed: start and stop alone.
var osSansE = sound.saw(100)
assert(osSansE.start().isPlaying())
osSansE.stop()

## ── The sound module: computed buffers ─────────────────────────────────────
## A buffer is a sound COMPUTED once, then triggered. Its accessors are what makes the synthesis
## checkable with no sound card: the samples are read instead of being listened to.
var bufT = sound.tone(1, 1.0)
assert(math.abs(bufT.duration() - 1.0) < 0.001)
assert(math.abs(bufT.peak() - 1.0) < 0.001)

## A 1 Hz sine over one second passes through 0, +1, 0 and -1 at the quarter turns: it is the
## wave's very shape that is checked, not merely the presence of a buffer.
assert(math.abs(bufT.sample(0)) < 0.001)
assert(math.abs(bufT.sample(0.25) - 1.0) < 0.001)
assert(math.abs(bufT.sample(0.5)) < 0.001)
assert(math.abs(bufT.sample(0.75) + 1.0) < 0.001)

## Outside the buffer a sample is zero — the silence around it, rather than an error.
assert(bufT.sample(-1) == 0 and bufT.sample(99) == 0)

## sound.generate samples an Ollin FORMULA, once, outside the audio callback.
var bufG = sound.generate(0.5, func(t) return 0.5 end)
assert(math.abs(bufG.duration() - 0.5) < 0.001)
assert(math.abs(bufG.peak() - 0.5) < 0.001)
assert(math.abs(bufG.sample(0.1) - 0.5) < 0.001)

## A value outside [-1;1] is brought back into range: beyond it, the output would clip.
assert(math.abs(sound.generate(0.1, func(t) return 5 end).peak() - 1.0) < 0.001)

## The envelope applied to the samples is the SAME function the mixer uses, so this test also
## validates the oscillators' curve — which nothing else can check here.
var bufE = sound.generate(1.0, func(t) return 1 end)
bufE.envelope(0.1, 0.2, 0.5, 0.25)
assert(math.abs(bufE.sample(0.05) - 0.5) < 0.01)    ## halfway through the attack
assert(math.abs(bufE.sample(0.1) - 1.0) < 0.01)     ## the attack's peak
assert(math.abs(bufE.sample(0.2) - 0.75) < 0.01)    ## mid-decay, between 1 and the sustain
assert(math.abs(bufE.sample(0.5) - 0.5) < 0.01)     ## the sustain
assert(bufE.sample(0.999) < 0.01)                   ## the release has run out along with the sound

## Playback: play and stop, and the settings chain as an oscillator's do.
assert(not bufE.isPlaying())
assert(bufE.play().isPlaying())
assert(bufE.volume(0.3).pan(0.5).rate(2).volume() == 0.3)
assert(bufE.pan() == 0.5 and bufE.rate() == 2)
assert(bufE.loop() == bufE)
bufE.stop()
assert(not bufE.isPlaying())

## Named notes: equal temperament around A 440, with no table of frequencies copied out. A NAME is
## accepted wherever a frequency is, so a single point of passage in the engine covers sound.osc,
## sound.tone and osc.freq.
assert(math.abs(sound.note("A4") - 440.0) < 0.01)
assert(math.abs(sound.note("a4") - 440.0) < 0.01)      ## the case does not matter
assert(math.abs(sound.note("C4") - 261.626) < 0.01)
assert(math.abs(sound.note("A0") - 27.5) < 0.01)
assert(math.abs(sound.note("C-1") - 8.1758) < 0.001)   ## the lowest octave

## A sharp and a flat give the same pitch when they name the same note.
assert(math.abs(sound.note("C#4") - sound.note("Db4")) < 0.001)

## All three places a frequency is used accept the name.
assert(math.abs(sound.osc("A4").freq() - 440.0) < 0.01)
assert(math.abs(sound.sine(100).freq("E4").freq() - 329.628) < 0.01)
assert(math.abs(sound.tone("A5", 0.1).duration() - 0.1) < 0.001)

## `free()` gives the voice back to the engine AND makes the handle stale: reusing it must be
## reported, not silently ignored. Without that explicit release, every polyphonic script had to
## pre-allocate a pool, for want of knowing when a stopped slot would be recycled.
var oscLibre = sound.sine(440)
oscLibre.free()
var perime = false
try
    oscLibre.freq(880)
catch e
    perime = true
end
assert(perime)
## A voice given back with NO envelope is free at once: as many can be created as the table
## holds, one after another.
for i = 1, 40 do
    sound.sine(220 + i).free()
end
## A slot is only protected while something makes it SOUND. With no audio output — a headless
## build, or the browser before the first gesture — no envelope ever finishes, so a voice given
## back by free() must become available at once: otherwise the seventeenth creation failed with
## "no oscillator available", although every voice had indeed been released.
for i = 1, 20 do
    var v = sound.sine(330 + i).envelope(0.01, 0.05, 0.5, 5.0)
    v.trigger(0.05)
    v.free()
end
var other = sound.sine(660)
assert(other.isPlaying() == false)
other.free()
