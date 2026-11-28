## Regression tests — The Color class.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/color.ol — it must finish without error.

## ── Color.grayscale and Color.pastel: new colours, the alpha kept ──
## Neither method was called by any test.
var colOrig = Color(1, 0, 0, 0.5)
var colGray = colOrig.grayscale()
assert(colGray.r == colGray.g and colGray.g == colGray.b, "a grey has three equal components")
assert(math.abs(colGray.r - 0.299) < 0.000001, "the luminance of Rec. 601: 0.299 for pure red")
assert(colGray.a == 0.5, "the alpha is kept")
assert(math.abs(Color(1, 1, 1).grayscale().r - 1) < 0.000001 and Color(0, 0, 0).grayscale().r == 0, "white stays white, black stays black")
var colSoft = colOrig.pastel()
assert(colSoft.r == 1 and colSoft.g == 0.5 and colSoft.b == 0.5 and colSoft.a == 0.5, "half way to white, the alpha kept")
assert(Color(0, 0, 0).pastel().r == 0.5)
assert(colOrig.r == 1 and colOrig.g == 0 and colOrig.a == 0.5, "the colour itself does not change")
assert(colGray.pastel().a == 0.5 and instanceOf(colSoft.grayscale(), Color), "the results are colours too, of the same class")

## ── Color.__str, Color.gray and the palette module ──
## Color(...) prints its four components with six decimals; interpolation and print go through the same path.
assert(Color(1, 0, 0.5, 1).__str() == "Color(1.000000,0.000000,0.500000,1.000000)")
assert("{Color(0)}" == "Color(0.000000,0.000000,0.000000,1.000000)", "interpolation uses __str")

## Color.gray clamps to [0, 1], keeps alpha 1, and works as a static or through an instance.
var grayHigh = Color.gray(3)
var grayLow = Color.gray(-1)
assert(grayHigh.r == 1 and grayHigh.g == 1 and grayHigh.b == 1 and grayHigh.a == 1)
assert(grayLow.r == 0 and grayLow.a == 1)
assert(Color.gray(0.25).g == 0.25 and instanceOf(Color.gray(0.25), Color) and classOf(Color.gray(0.25)) == classOf(Color(0)))
assert(Color(1, 0, 0).gray(0.5).r == 0.5, "gray ignores the receiver")

## The palette: every constant is a real Color, built from 8-bit components.
assert(palette.BLACK.r == 0 and palette.BLACK.a == 1)
assert(palette.WHITE.r == 1 and palette.WHITE.g == 1 and palette.WHITE.b == 1)
assert(math.abs(palette.RED.r - 230 / 255) < 0.000001 and math.abs(palette.RED.g - 41 / 255) < 0.000001)
assert(instanceOf(palette.RED, Color), "a palette constant is an instance of the Color class")
assert(palette.MAGENTA.r == 1 and palette.MAGENTA.g == 0 and palette.MAGENTA.b == 1)
assert(palette.BLUE.pastel().a == 1, "the methods work on palette constants")
for name in ["BLACK", "WHITE", "RED", "GREEN", "BLUE", "YELLOW", "GRAY", "ORANGE", "PINK", "PURPLE", "BROWN", "DARKGRAY", "SKYBLUE", "LIME", "MAGENTA"] do
    assert(instanceOf(palette[name], Color), "palette.{name} is a Color")
end
assert(len(map.keys(palette)) == 15, "the palette has fifteen colours")

## a Color may be built from any map that has r, g, b and a, the absent ones defaulting to 0 and 1
var cxFromMap = Color({r: 1, g: 0.5, b: 0})
assert(cxFromMap.r == 1 and cxFromMap.g == 0.5 and cxFromMap.b == 0 and cxFromMap.a == 1)

## Color.random draws from the same generator as math.rand: opaque, each channel in [0, 1), and the same after the same seed.
math.seed(4)
var cxRandA = Color.random()
math.seed(4)
var cxRandB = Color.random()
assert(cxRandA.a == 1 and cxRandA.r >= 0 and cxRandA.r < 1 and cxRandA.g >= 0 and cxRandA.g < 1 and cxRandA.b >= 0 and cxRandA.b < 1)
assert(cxRandA.r == cxRandB.r and cxRandA.g == cxRandB.g and cxRandA.b == cxRandB.b, "the same seed, the same colour")
assert(Color.random().r <> Color.random().r, "and two draws differ")
