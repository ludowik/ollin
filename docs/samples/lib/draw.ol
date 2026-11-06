## The drawing helpers the samples that paint their own screens share (sudoku, blockudoku, calculator, tetris, weather, and the lexer and parser through stage.ol): a colour held as
## an array [r, g, b, a], and text that is placed, sized and coloured by one call. Imported with a path relative to the
## importing file, "../lib/draw.ol".

func fillC(col, alpha = 1)
    graphics.fill(col[1], col[2], col[3], col[4] * alpha)
end

## A text at (x, y), anchored by h and v (see graphics.textMode), `size` high, in the colour col.
func drawText(str, x, y, size, h, v, col, alpha = 1)
    graphics.fontSize(size)
    graphics.textMode(h, v)
    graphics.stroke(col[1], col[2], col[3], col[4] * alpha)
    graphics.text(str, x, y)
    graphics.noStroke()
end

## The whole canvas in `bands` strips of one colour each, from the colour `top` to the colour `bottom` (arrays
## [r, g, b, a]). The strips overlap by a row, so that no seam shows between two of them.
func drawGradient(top, bottom, bands)
    for i = 0, bands - 1 do
        var t = i / (bands - 1)
        graphics.fill(top[1] + (bottom[1] - top[1]) * t, top[2] + (bottom[2] - top[2]) * t,
            top[3] + (bottom[3] - top[3]) * t, 1)
        var y0 = math.floor(H * i / bands)
        graphics.rect(0, y0, W, math.floor(H * (i + 1) / bands) - y0 + 1)
    end
end

## A text cut into the lines that fit `width` at the font size `size`, breaking between words. An empty text has no line.
func wrapText(str, size, width)
    graphics.fontSize(size)
    var lines = []
    var line = ""
    for word in str.split(" ") do
        var trial = line + " " + word
        if line == "" then
            line = word
        elseif graphics.textSize(trial) > width then
            lines.push(line)
            line = word
        else
            line = trial
        end
    end
    if line <> "" then
        lines.push(line)
    end
    return lines
end

## Paragraphs cut into lines by wrapText, with a blank line after each.
func wrapParagraphs(paragraphs, size, width)
    var lines = []
    for text in paragraphs do
        for line in wrapText(text, size, width) do
            lines.push(line)
        end
        lines.push("")
    end
    return lines
end

## The size at which the text is no wider than maxW, `size` at most: a translation is not as long as the original.
func fitSize(str, size, maxW)
    graphics.fontSize(size)
    var tw = graphics.textSize(str)
    if tw > maxW then
        return size * maxW / tw
    end
    return size
end
