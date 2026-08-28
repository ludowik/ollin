## The audio and sound modules — EVERYTHING heard here is computed: not one file is loaded.
##
## Put your fingers on the keys: each note SOUNDS AS LONG AS the finger stays down, and several
## fingers play several notes at once — the `touch` module follows them, each by its identifier.
## Drag without lifting and the note follows the key under the finger.
##
## The example shows the `sound` module's TWO kinds of object, each doing what it is good at:
##   an OSCILLATOR held for a pressed key — its duration is not known in advance, and its
##     envelope releases it when the finger lifts;
##   a computed BUFFER for the digits 1 to 8 of the physical keyboard — a short, frozen note,
##     replayed as it is;
##   and one more oscillator in the band at the top, whose frequency follows the finger.
##
## With a mouse there is a single pointer, and the `mouse` module takes over.

global notes = ["C4", "D4", "E4", "F4", "G4", "A4", "B4", "C5"]
global buffers = []          ## one buffer per note, computed once in setup()
global lastKey = 0       ## the key lit up, for visual feedback
global glow = 0.0        ## it decays every frame, so the keyboard "breathes"

global bow = nil         ## the living oscillator
global bowPos = 0.0      ## 0..1, the finger's position across the band
## The contact driving the bow: a finger's identifier, "mouse", or nil when it is silent. It is
## ALWAYS compared with nil, never by truthiness: a finger's identifier may be 0, which the
## language holds to be false — the bow then stayed mute under the browser's first finger. The band
## obeys ONE contact only, or two positions would fight over the same frequency; and "the bow is
## sounding" reads off this single variable, with no flag to keep in step.
global bowHolder = nil

global mouseDown = false      ## the mouse button is down

## One HELD oscillator per contact, created when the finger lands and given back on lifting through
## `free()`. The engine manages the pool: it only takes a released voice back once it has died away.
global voiceOf = {}        ## contact (a finger identifier, or "mouse") → oscillator

## One entry per contact DOWN, a finger or the pointer: its identifier maps to the key it presses.
## That is what allows several notes at once. The pointer appears under the name "mouse",
## as one more contact, so the rest of the program handles it with no special case.
global underFinger = {}
## The keys held, in a map reused from one frame to the next: a fresh map per frame would be an
## allocation, whereas emptying this one costs eight writes.
global heldKeys = {}

## A keyboard digit maps to a note index: comparing the key with `"" + i` would build eight strings
## on every keystroke, including for keys that are not digits.
global DIGIT = {}

## Bounded by the WIDTH as much as by the height: on a phone screen held upright, a size taken from
## the height alone gives lines wider than the screen.
func textSize()
    return math.min(W * 0.055, H * 0.03)
end

func bandTop()
    return H * 0.12
end

func bandBottom()
    return H * 0.42
end

func keyboardTop()
    return H * 0.55
end

func keyWidth()
    return W / #notes
end

func setup()
    graphics.canvas(W, H, "sound")

    ## One buffer per note: the waveform is sampled ONCE, then the envelope is applied to the
    ## samples. Nothing is recomputed on playback.
    for i, name in notes do
        buffers[i] = sound.tone(sound.note(name), 0.5, "triangle")
        buffers[i].envelope(0.01, 0.12, 0.35, 0.25).volume(0.5)
    end

    ## The bow stays silent until the first drag: its volume is zero, and it is `start` that
    ## sets it running, not `play`. A triangle rather than a sawtooth: over a glissando, a
    ## shape rich in harmonics turns shrill in the treble.
    bow = sound.triangle(220).volume(0.0)
    bow.start()

    for i = 1, #notes do
        DIGIT["" + i] = i
    end
end

## This contact's oscillator, created when needed. The envelope gives the attack and the release;
## with no duration passed to `trigger`, the note holds until the finger lifts. The engine may
## refuse when all of its voices are still sounding: a missing note is then better than one stolen
## from a finger still down.
func voiceFor(contact)
    var o = voiceOf[contact]
    if o then
        return o
    end
    try
        o = sound.triangle(440).volume(0.3).envelope(0.01, 0.09, 0.5, 0.18)
    catch e
        return nil
    end
    voiceOf[contact] = o
    return o
end

## Holds a key's note, or releases when the contact presses nothing any more. It returns the key
## REALLY held: zero when no voice was free, since the key would otherwise light with no sound
## coming out, and would stay mute even once a voice was released.
func holdKey(contact, i)
    ## Give the voice back BEFORE asking for one: a finger merely sliding across the band otherwise
    ## tied one up, and three were enough to silence a key.
    if i == 0 then
        releaseVoice(contact)
        return 0
    end
    var o = voiceFor(contact)
    if o == nil then
        return 0
    end
    o.freq(sound.note(notes[i])).trigger()
    lastKey = i
    glow = 1.0
    return i
end

func releaseVoice(contact)
    var o = voiceOf[contact]
    if not o then
        return
    end
    o.free()             ## lets the envelope go and gives the voice back; the note finishes dying away
    voiceOf[contact] = nil
end

## A SHORT note, for the physical keyboard: a frozen buffer, replayed as it is. Replaying starts
## from the beginning, so there is no need to stop it first.
func playBuffer(i)
    buffers[i].play()
    lastKey = i
    glow = 1.0
end

## The key under the point (x, y), or 0 when the point is off the keyboard.
func keyAt(x, y)
    if y < keyboardTop() then
        return 0
    end
    var i = math.floor(x / keyWidth()) + 1
    if i < 1 or i > #notes then
        return 0
    end
    return i
end

## What the contact hovers decides, on landing as on dragging. The note only changes when the KEY
## changes: otherwise a three-pixel move would retrigger it every frame.
func follow(contact, prev, x, y)
    var t = keyAt(x, y)
    if t == prev then
        return prev
    end
    return holdKey(contact, t)
end

func moveBow(x, y)
    bowPos = math.clamp(x / W, 0, 1)
end

func inBand(y)
    return y >= bandTop() and y <= bandBottom()
end

## Multitouch: several fingers, each followed by its identifier.
func touch.began(id, x, y)
    if inBand(y) and bowHolder == nil then
        bowHolder = id
        moveBow(x, y)
    end
    underFinger[id] = follow(id, 0, x, y)
end

func touch.moved(id, x, y)
    if id == bowHolder then
        if inBand(y) then
            moveBow(x, y)
        else
            bowHolder = nil   ## out of the band: it gives the bow back, and can play notes
        end
    end
    underFinger[id] = follow(id, underFinger[id], x, y)
end

func touch.ended(id, x, y)
    if id == bowHolder then
        bowHolder = nil
    end
    releaseVoice(id)          ## lifting the finger releases the note, which dies away along its envelope
    underFinger[id] = nil
end

## The mouse: a single pointer, for a computer.
## On a touch screen the system emulates the mouse under a single finger: both families of callback
## then fire, and the engine filters nothing — the script must choose. Without this guard, one
## finger played the note TWICE, hence twice as loud.
func mouseIgnored()
    return touch.count() > 0
end

func mouse.pressed(x, y)
    if mouseIgnored() then
        return
    end
    mouseDown = true
    if inBand(y) and bowHolder == nil then
        bowHolder = "mouse"
        moveBow(x, y)
    end
    underFinger["mouse"] = follow("mouse", 0, x, y)
end

func mouse.moved(x, y)
    if not mouseDown or mouseIgnored() then
        return
    end
    if bowHolder == "mouse" then
        if inBand(y) then
            moveBow(x, y)
        else
            bowHolder = nil
        end
    end
    underFinger["mouse"] = follow("mouse", underFinger["mouse"], x, y)
end

## No guard here: a voice taken by the pointer must be given back in every case, a finger having
## landed in the meantime included.
func mouse.released(x, y)
    mouseDown = false
    releaseVoice("mouse")
    underFinger["mouse"] = nil
    if bowHolder == "mouse" then
        bowHolder = nil
    end
end

func keyboard.keypressed(key)
    ## The digits 1 to 8 play the eight notes, which is enough to try it on a physical keyboard.
    var i = DIGIT[key]
    if i then
        playBuffer(i)
    end
end

func update()
    ## The oscillator follows the finger: a frequency that moves while the sound comes out, which a
    ## frozen buffer could not do. The volume opens and closes gently.
    var target = 0.0
    if bowHolder <> nil then
        target = 0.25
        bow.freq(110 + bowPos * 660)
    end
    var v = bow.volume()
    bow.volume(v + (target - v) * math.min(1, deltaTime * 8))

    glow = math.max(glow - deltaTime * 2.5, 0)
end

## The keys HELD stay lit, their note lasting as long as the press does. It is read in ONE pass, to
## be reused for all eight keys: querying each key walked the list of contacts as many times.
func collectHeldKeys()
    for i = 1, #notes do
        heldKeys[i] = nil
    end
    for contact, below in underFinger do
        heldKeys[below] = true
    end
end

func draw()
    graphics.clear(Color(0.08, 0.09, 0.13))
    graphics.noStroke()
    graphics.fontSize(textSize())
    ## The geometry is read once: those three functions were being called some thirty times.
    var hb = bandTop()
    var bb = bandBottom()
    var hc = keyboardTop()

    ## The bow's band: its hue says whether it is sounding.
    var warm = (bowHolder <> nil) and 1 or 0
    graphics.fill(Color(0.13 + 0.2 * warm, 0.15, 0.24))
    graphics.rect(0, hb, W, bb - hb)
    if bowHolder <> nil then
        graphics.fill(Color(0.55, 0.85, 1))
        graphics.rect(bowPos * W - 2, hb, 4, bb - hb)
    end
    graphics.stroke(Color(0.75, 0.82, 0.95))
    graphics.text("drag here: a living oscillator", W * 0.04, hb + H * 0.05)
    if bowHolder <> nil then
        graphics.text("{bow.freq():.0f} Hz", W * 0.04, hb + H * 0.11)
    end

    ## The keyboard: eight keys, the last played staying lit for as long as its glow lasts. The key
    ## UNDER THE FINGER is ringed, so that a sweep is seen as much as it is heard.
    graphics.stroke(Color(0.62, 0.7, 0.85))
    graphics.text("hold several fingers down", W * 0.04, hc - H * 0.07)
    graphics.text("digits 1 to 8: short notes", W * 0.04, hc - H * 0.03)
    graphics.noStroke()
    var l = keyWidth()
    collectHeldKeys()
    for i, name in notes do
        var held = heldKeys[i]
        ## Held: full light for as long as the press lasts. Otherwise, the glow of a short note.
        var bright = held and 1 or ((i == lastKey) and glow or 0)
        ## noStroke BEFORE the rectangle, and stroke only for the text: in the other order, the
        ## text's outline rings the following keys as well.
        graphics.noStroke()
        graphics.fill(Color(0.16 + 0.5 * bright, 0.18 + 0.35 * bright, 0.3 + 0.4 * bright))
        graphics.rect(l * (i - 1) + 2, hc, l - 4, H - hc)
        if held then
            graphics.noFill()
            graphics.stroke(Color(0.55, 0.85, 1), 3)
            graphics.rect(l * (i - 1) + 2, hc, l - 4, H - hc)
        end
        graphics.stroke(Color(0.8, 0.86, 0.96))
        graphics.text(name, l * (i - 1) + l * 0.28, hc + H * 0.07)
    end

    ## What a buffer's accessors read: nothing else lets one see them.
    graphics.stroke(Color(0.62, 0.7, 0.85))
    graphics.text("buffer: {buffers[1].duration():.2f} s, peak {buffers[1].peak():.2f}",
                  W * 0.04, bb - H * 0.04)
end
