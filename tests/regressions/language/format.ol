## Regression tests — Formatting an interpolation and printf.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/format.ol — it must finish without error.

## ── Formatting {expr:spec} in an interpolation and {N:spec} in printf, sharing one engine ──
## The spec's ':' is the one at the TOP level: a nested map literal preserves it.
var fmt_v = 3.14159
assert("{fmt_v:.2f}" == "3.14")
assert("{fmt_v:8.3f}" == "   3.142")           ## width and precision
assert("{(255):x}" == "ff")                     ## hex, on a parenthesised expression
assert("{(255):#06x}" == "0x00ff")             ## the # flag, zero padding and a width
assert("{(-7):+d}" == "-7")                     ## a forced sign
assert("{(42):d}" == "42")
assert("{(3.9):d}" == "3")                       ## a float coerced to an int, hence truncated
assert("{"hi":5s}" == "   hi")                 ## width 5, right-aligned, as C defaults to
assert("{"hi":-5s}" == "hi   ")                ## '-' means left-aligned, the C printf syntax, not '>'
## the ':' of a nested map is NOT a spec separator
var fmt_m = {"a": 1}
assert("{fmt_m["a"]}" == "1")
assert("{ {"k": 7}.k }" == "7")
## {N} and {} are positional placeholders, hence LITERALS outside printf
assert("{1}-{2}" == "{1}-{2}")
assert("{}" == "{}")                             ## no more "empty interpolation" error
assert("{4 / 2}" == "2" and "{2.5 * 2}" == "5")     ## a float with a whole value prints without a decimal part
assert("{0 }" == "{0 }")                         ## blanks after the digits do not make it an expression
assert("{1 :.3f}" == "{1 :.3f}")
## an invalid spec gives a clear runtime error
var fmt_err = false
try
    var bad = "{fmt_v:.2z}"
    print(bad)
catch e
    fmt_err = true
end
assert(fmt_err)

## ── the conversions the engine coerces, and printf's positional slots ──
## %c writes the character of a code; it takes a number, and a float is truncated like for %d.
assert("{(65):c}" == "A")
assert("{(66.9):c}" == "B")
assert("{(65):3c}" == "  A", "a width applies to %c")
assert("{3.5:g}" == "3.5" and "{(1.5):e}" == "1.500000e+00")

## typeof() with no argument is "nil", like typeof(nil).
assert(typeof() == "nil")

## printf only prints (nothing to capture), so these check that the slots are accepted: automatic and
## explicit indexes, a spec, an index past the arguments (an empty slot).
printf("{} {} {:5.1f}", 1, "two", 3.14159)
printf("{2} {1} {2:5s}", "a", "b")
printf("{3} past the arguments", 1)
printf("no argument")

## __fmt is the target of the desugaring, but a direct call still validates its arguments.
var fmtDirect = false
try
    __fmt(1)
catch e
    fmtDirect = true
    assert(e == "__fmt: expected (value, spec)")
end
assert(fmtDirect)
