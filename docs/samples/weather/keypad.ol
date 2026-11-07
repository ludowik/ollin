## The keys of the search panel, with no drawing: what a name may hold, how a key changes the name being typed, and
## where each key is for an area of a given size. The engine's keyboard names the letters, the digits and a few keys,
## and nothing else, so what a name may hold beyond them — the accents of French, which is what the engine's font
## draws, the apostrophe and the hyphen — is on this panel, for a finger and a mouse to press.

## Nine keys to a row.
const KEY_ROWS = ["abcdefghi", "jklmnopqr", "stuvwxyz0", "123456789", "àâäçéèêëî", "ïôöùûüÿœ'"]
const KEY_COLUMNS = 9
const MAX_NAME = 30             ## the longest name that can be typed, in characters

## The last row: the hyphen, the space and the two keys that act on the name. `span` is in columns.
const KEY_CONTROLS = [
    {kind: "char", text: "-", label: "-", span: 1}, {kind: "char", text: " ", label: "space", span: 5},
    {kind: "back", text: "", label: "del", span: 1.5}, {kind: "go", text: "", label: "Go", span: 1.5}
]

## The name once `ch` is added. A space comes only after something, and never twice running.
func appendChar(text, ch)
    if len(text) >= MAX_NAME then
        return text
    end
    if ch == " " and (text == "" or string.endsWith(text, " ")) then
        return text
    end
    return text + ch
end

func eraseLast(text)
    if text == "" then
        return ""
    end
    return string.substr(text, 1, len(text) - 1)
end

## Whether the engine's keyboard names a key that can start or continue a name.
func isNameKey(key)
    return len(key) == 1 and ((key >= "a" and key <= "z") or (key >= "0" and key <= "9"))
end

## The panel for an area of `w` by `h`, at the bottom of it: the keys and where they are, which is what draws them and
## what finds the one under a finger, so the two cannot disagree.
func panelLayout(w, h)
    var width = math.min(w * 0.98, h * 1.15)
    var unit = width / KEY_COLUMNS
    var gap = unit * 0.08
    var kh = math.min(unit * 0.95, h * 0.64 / (#KEY_ROWS + 2.4))
    var lines = #KEY_ROWS + 2                       ## the name, the rows of keys and the row of controls
    var top = h - lines * (kh + gap) - gap * 2
    var left = w / 2 - width / 2
    var keys = []
    for r = 1, #KEY_ROWS do
        for c = 1, KEY_COLUMNS do
            var ch = string.char(KEY_ROWS[r], c)
            keys.push({kind: "char", text: ch, label: ch, x: left + (c - 1) * unit + gap / 2,
                       y: top + gap + r * (kh + gap), w: unit - gap, h: kh})
        end
    end
    var x = left
    for control in KEY_CONTROLS do
        var k = {kind: control.kind, text: control.text, label: control.label}
        k.x = x + gap / 2
        k.y = top + gap + (#KEY_ROWS + 1) * (kh + gap)
        k.w = control.span * unit - gap
        k.h = kh
        keys.push(k)
        x += control.span * unit
    end
    return {top: top, kh: kh, radius: kh * 0.22, keys: keys, fieldX: left + gap / 2, fieldY: top + gap,
            fieldW: width - gap}
end

## The key under a point, or nil.
func keyAt(panel, x, y)
    for k in panel.keys do
        if x >= k.x and x < k.x + k.w and y >= k.y and y < k.y + k.h then
            return k
        end
    end
    return nil
end
