## The text wrapping the samples share (docs/samples/lib/draw.ol): wrapText cuts a text into lines that fit a width at a
## font size, between words, and wrapParagraphs does it for each paragraph of a list. The widths come from the font, so
## it needs a window: it runs under Xvfb (tests/run_gfx.sh) and ends with graphics.quit(). What is checked holds for
## any font, since it compares the lines with the measure of the text and never with a number.

import "../docs/samples/lib/draw.ol"

const TEXTS = [
    "one",
    "two words",
    "a longer text that has to be cut into several lines whatever the width is",
    "a verylongwordthatwillnotfitanywhere between two short words"
]

func joined(lines)
    var text = ""
    for line in lines do
        text = text == "" and line or text + " " + line
    end
    return text
end

func firstWord(line)
    return line.split(" ")[1]
end

func run()
    graphics.font("sans")
    for size in [9, 14, 30] do
        graphics.fontSize(size)
        var oneLine = graphics.textSize(TEXTS[3])
        for width in [1, oneLine * 0.2, oneLine * 0.5, oneLine * 0.9, oneLine * 2] do
            for text in TEXTS do
                var lines = wrapText(text, size, width)
                var label = "'{text}' at {size} in {width}"
                assert(joined(lines) == text, "no word lost or added: " + label)
                for line in lines do
                    assert(line.split(" ").len() == 1 or graphics.textSize(line) <= width, "a line fits, or is one word: " + label)
                end
                for i = 2, #lines do
                    var longer = lines[i - 1] + " " + firstWord(lines[i])
                    assert(graphics.textSize(longer) > width, "a line is as full as it can be: " + label)
                end
            end
        end
    end

    ## the extremes: wide enough for everything is one line, and no width at all is one word a line
    graphics.fontSize(14)
    var wide = wrapText(TEXTS[3], 14, 100000)
    assert(#wide == 1 and wide[1] == TEXTS[3], "a wide area holds the text on one line")
    var narrow = wrapText(TEXTS[2], 14, 1)
    assert(#narrow == 2 and narrow[1] == "two" and narrow[2] == "words", "a narrow one holds a word a line")
    assert(#wrapText("", 14, 100) == 0, "an empty text has no line")

    ## wrapText sets the font size it measures at: the same text is longer at a bigger size, so more lines
    var small = wrapText(TEXTS[3], 9, 300)
    var big = wrapText(TEXTS[3], 30, 300)
    assert(#big > #small, "the size given is the size measured at")

    ## the paragraphs: each is cut on its own and followed by a blank line, an empty one included
    var paragraphs = wrapParagraphs(["a b", "c", ""], 14, 100000)
    assert(#paragraphs == 5 and paragraphs[1] == "a b" and paragraphs[2] == "" and paragraphs[3] == "c"
        and paragraphs[4] == "" and paragraphs[5] == "", "a blank line after each paragraph")
    assert(#wrapParagraphs([], 14, 100) == 0, "no paragraph, no line")
    var cut = wrapParagraphs(["two words"], 14, 1)
    assert(#cut == 3 and cut[1] == "two" and cut[2] == "words" and cut[3] == "", "a paragraph is cut like a text")
end

func draw()
    run()
    graphics.quit()
end
