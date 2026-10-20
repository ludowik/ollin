## Regression tests — The audio module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/audio.ol — it must finish without error.

## ── The audio module (the session) ─────────────────────────────────────────
## The module ALWAYS exists, device or no device: generating waves is pure computation, and the
## suite runs in a container with no sound card. Only the output is mute.
assert(typeof(audio) == "module")
assert(audio.sampleRate() == 44100)

## With no device, start() returns false and isReady() stays false — without throwing.
var auPret = audio.start()
assert(typeof(auPret) == "bool")
assert(audio.isReady() == auPret)

## The volume reads back as it was set, and is clamped to [0;1] silently: beyond it the output
## would clip, so we correct instead of refusing, as with a colour component.
assert(audio.volume(0.25) == 0.25)
assert(audio.volume() == 0.25)
assert(audio.volume(9) == 1)
assert(audio.volume(-3) == 0)
audio.volume(1)

## Pause belongs to the SESSION: it suspends the mix's PROGRESS, where a zero volume would let
## everything run on in silence and make the sound resume further along.
assert(not audio.isPaused())
audio.pause()
assert(audio.isPaused())
audio.resume()
assert(not audio.isPaused())
