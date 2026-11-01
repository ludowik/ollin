## The SOUND of Tetris: the folk tune of the handheld ("Korobeiniki", Type A) played by two oscillators, and the
## effects as a few short buffers computed once at startup, so that nothing is calculated while one plays. The
## browser keeps the engine silent until the first gesture, which the key that starts the game already is.
##
## The tune is a list of [note, beats] and a list of [bass, fifth] per bar; musicUpdate(dt) walks them with a clock
## counted in beats, and plays each note on one of the two oscillators when its turn comes. Sixteen oscillators and
## thirty-two buffers exist in all, which is why the tune is not made of buffers, one for each note.

global sounds = {move: nil, turn: nil, lock: nil, lines: nil, tetris: nil, level: nil, over: nil, start: nil}
global music = {on: true, beat: 0, next: 1, events: [], voice: nil, bass: nil}

const TEMPO = 150               ## beats a minute: a beat is a quarter note
const GATE = 0.88               ## the part of a note's length it sounds, the rest separating it from the next

## The melody, bar by bar (a bar is four beats).
const MELODY = [
    ["E5", 1], ["B4", 0.5], ["C5", 0.5], ["D5", 1], ["C5", 0.5], ["B4", 0.5],
    ["A4", 1], ["A4", 0.5], ["C5", 0.5], ["E5", 1], ["D5", 0.5], ["C5", 0.5],
    ["B4", 1.5], ["C5", 0.5], ["D5", 1], ["E5", 1],
    ["C5", 1], ["A4", 1], ["A4", 2],
    ["D5", 1.5], ["F5", 0.5], ["A5", 1], ["G5", 0.5], ["F5", 0.5],
    ["E5", 1.5], ["C5", 0.5], ["E5", 1], ["D5", 0.5], ["C5", 0.5],
    ["B4", 1], ["B4", 0.5], ["C5", 0.5], ["D5", 1], ["E5", 1],
    ["C5", 1], ["A4", 1], ["A4", 2]
]

## The bass: for each bar the root and the fifth above it, struck on the beats root, fifth, root, fifth.
const BASS = [
    ["A2", "E3"], ["A2", "E3"], ["E2", "B2"], ["A2", "E3"],
    ["D3", "A3"], ["C3", "G3"], ["E2", "B2"], ["A2", "E3"]
]

## One cycle of the tune, in beats.
func musicLength()
    return len(BASS) * 4
end

## The notes in the order they sound, as {beat, voice, note, beats}.
func buildEvents()
    var events = []
    var beat = 0
    for n in MELODY do
        events.push({beat: beat, voice: "voice", note: n[1], beats: n[2]})
        beat += n[2]
    end
    for bar, pair in BASS do
        for b = 0, 3 do
            events.push({beat: (bar - 1) * 4 + b, voice: "bass", note: pair[b % 2 + 1], beats: 1})
        end
    end
    events.sort(func(a, b)
        return a.beat < b.beat
    end)
    return events
end

## A square wave of the frequency f at the time t, between -1 and 1.
func squareAt(f, t)
    return (t * f) % 1 < 0.5 and 1 or -1
end

## A rising run of square notes, one every `stepLength` seconds, fading at the rate `decay`.
func arpeggio(notes, stepLength, length, decay)
    var freqs = notes.map(sound.note)
    return sound.generate(length, func(t)
        var i = math.min(math.floor(t / stepLength) + 1, len(freqs))
        return squareAt(freqs[i], t) * math.exp(-t * decay) * 0.5
    end)
end

func buildSounds()
    music.voice = sound.square(440).envelope(0.004, 0.06, 0.55, 0.04).volume(0.10)
    music.bass = sound.triangle(110).envelope(0.004, 0.08, 0.6, 0.05).volume(0.26)
    music.events = buildEvents()
    sounds.move = sound.tone(300, 0.025, "square").envelope(0.001, 0.01, 0.6, 0.01).volume(0.10)
    sounds.turn = sound.tone(480, 0.045, "square").envelope(0.001, 0.02, 0.5, 0.02).volume(0.12)
    sounds.lock = sound.tone(110, 0.09, "triangle").envelope(0.002, 0.05, 0.4, 0.03).volume(0.35)
    sounds.start = sound.tone("C6", 0.08, "square").envelope(0.002, 0.03, 0.5, 0.03).volume(0.12)
    sounds.lines = arpeggio(["C5", "E5", "G5", "C6"], 0.06, 0.26, 6).volume(0.16)
    sounds.tetris = arpeggio(["C5", "E5", "G5", "C6", "E6", "G6"], 0.075, 0.7, 2.5).volume(0.18)
    sounds.level = arpeggio(["G5", "C6", "E6", "G6"], 0.09, 0.4, 3).volume(0.16)
    sounds.over = sound.generate(1.1, func(t)
        return squareAt(330 - 200 * t, t) * math.exp(-t * 2.2) * 0.5
    end).volume(0.18)
end

## Plays an effect; the music has its own switch.
func playSound(name)
    sounds[name].play()
end

func musicStop()
    music.voice.release()
    music.bass.release()
end

func musicRestart()
    musicStop()
    music.beat = 0
    music.next = 1
end

## Advances the tune by dt seconds and starts the notes that fall due. A long frame plays the notes it skipped over
## at once, which is only heard as a small hiccup.
func musicUpdate(dt)
    if not music.on then
        return
    end
    music.beat += dt * TEMPO / 60
    while music.next <= len(music.events) and music.events[music.next].beat <= music.beat do
        var e = music.events[music.next]
        var v = music[e.voice]
        v.freq(e.note).trigger(e.beats * 60 / TEMPO * GATE)
        music.next += 1
    end
    if music.beat >= musicLength() then
        music.beat -= musicLength()
        music.next = 1
    end
end
