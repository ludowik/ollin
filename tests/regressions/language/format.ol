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
## an invalid spec gives a clear runtime error
var fmt_err = false
try
    var bad = "{fmt_v:.2z}"
    print(bad)
catch e
    fmt_err = true
end
assert(fmt_err)
