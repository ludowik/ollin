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
assert(colGray.pastel().a == 0.5 and colSoft.grayscale().__class__ == colOrig.__class__, "the results are colours too, of the same class")

## ── Color.__str, Color.gray and the colors palette ──
## Color(...) prints its four components with six decimals; interpolation and print go through the same path.
assert(Color(1, 0, 0.5, 1).__str() == "Color(1.000000,0.000000,0.500000,1.000000)")
assert("{Color(0)}" == "Color(0.000000,0.000000,0.000000,1.000000)", "interpolation uses __str")

## Color.gray clamps to [0, 1], keeps alpha 1, and works as a static or through an instance.
var grayHigh = Color.gray(3)
var grayLow = Color.gray(-1)
assert(grayHigh.r == 1 and grayHigh.g == 1 and grayHigh.b == 1 and grayHigh.a == 1)
assert(grayLow.r == 0 and grayLow.a == 1)
assert(Color.gray(0.25).g == 0.25 and Color.gray(0.25).__class__ == Color(0).__class__)
assert(Color(1, 0, 0).gray(0.5).r == 0.5, "gray ignores the receiver")

## The palette: every constant is a real Color, built from 8-bit components.
assert(colors.BLACK.r == 0 and colors.BLACK.a == 1)
assert(colors.WHITE.r == 1 and colors.WHITE.g == 1 and colors.WHITE.b == 1)
assert(math.abs(colors.RED.r - 230 / 255) < 0.000001 and math.abs(colors.RED.g - 41 / 255) < 0.000001)
assert(colors.RED.__class__.__name__ == "Color", "a palette constant is an instance of a class named Color")
assert(colors.MAGENTA.r == 1 and colors.MAGENTA.g == 0 and colors.MAGENTA.b == 1)
assert(colors.BLUE.pastel().a == 1, "the methods work on palette constants")
for name in ["BLACK", "WHITE", "RED", "GREEN", "BLUE", "YELLOW", "GRAY", "ORANGE", "PINK", "PURPLE", "BROWN", "DARKGRAY", "SKYBLUE", "LIME", "MAGENTA"] do
    assert(colors[name].__class__.__name__ == "Color", "colors.{name} is a Color")
end
assert(len(map.keys(colors)) == 15, "the palette has fifteen colours")
