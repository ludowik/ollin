## The name being typed in the search of the weather example, with no drawing: what a key adds to it, and where the field
## and the button of the search are on an area of a given size. keyboard.typed gives the text the keys produced, accents,
## hyphen and apostrophe included, and the keyboard of a phone is raised by keyboard.show: nothing here is a key.

const MAX_NAME = 30             ## the longest name that can be typed, in characters

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

## The name once every character of `chars` is added: a fast typist or a paste gives several in one call.
func appendText(text, chars)
    for ch in chars do
        text = appendChar(text, ch)
    end
    return text
end

func eraseLast(text)
    if text == "" then
        return ""
    end
    return string.substr(text, 1, len(text) - 1)
end

## Where the field and the button of the search are on an area of `w` by `h`. They sit under the title, at the top: a
## phone's keyboard comes from the bottom, so nothing is hidden by it. The same rectangles draw them and find the one
## under a finger, so the two cannot disagree.
func searchLayout(w, h)
    var width = math.min(w * 0.96, h * 1.1)
    var height = math.max(math.min(width * 0.13, h * 0.1), 40)
    var gap = height * 0.2
    var button = height * 2.2
    var left = w / 2 - width / 2
    var top = h * 0.15
    return {radius: height * 0.22, hintY: top + height + gap * 2.2,
            field: {x: left, y: top, w: width - button - gap, h: height},
            go: {x: left + width - button, y: top, w: button, h: height}}
end

## Whether a point is inside a rectangle {x, y, w, h}.
func within(rect, x, y)
    return x >= rect.x and x < rect.x + rect.w and y >= rect.y and y < rect.y + rect.h
end
