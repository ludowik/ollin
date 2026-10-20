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
