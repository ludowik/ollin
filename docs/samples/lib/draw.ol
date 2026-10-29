## The drawing helpers the samples that paint their own screens share (sudoku, blockudoku, calculator): a colour held as
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

## The size at which the text is no wider than maxW, `size` at most: a translation is not as long as the original.
func fitSize(str, size, maxW)
    graphics.fontSize(size)
    var tw = graphics.textSize(str)
    if tw > maxW then
        return size * maxW / tw
    end
    return size
end
