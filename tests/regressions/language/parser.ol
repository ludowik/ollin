## Regression tests — The parser and the lexer: lvalues, keywords as names, comments and line breaks.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/parser.ol — it must finish without error.

## ── Parser: chained and indexed lvalues ────────────────────────────────────
## #7 assignments to a chained target ("unexpected token '='" before)
global cm = {b: {c: 0}}
cm.b.c = 9
assert(cm.b.c == 9)
cm.b.c += 5
assert(cm.b.c == 14)

global cf = {a: [0, 0]}
cf.a[1] = 7
assert(cf.a[1] == 7)

global nn = [[0]]
nn[1][1] = 9
assert(nn[1][1] == 9)

## self.field.sub = ... inside a method
class Holder
    func init() self.p = {x: 0} end
    func setx(v) self.p.x = v end
end
var ho = Holder()
ho.setx(42)
assert(ho.p.x == 42)

## ── Parser: a left-open range at the top level ──────────────────────────────
## #8 ]a;b] at the top level ("';' is not valid syntax" before)
var openr = 0
for i in ]1; 4] do
    openr += i
end
assert(openr == 9)     ## 2 + 3 + 4

## A KEYWORD is a plain NAME where no keyword can be meant — a map-literal key and a field
## after a '.'. grammar.ebnf says so ({ ref: 12 } is { "ref": 12 }) but the lexer classifies a
## word by its spelling alone, so the parser has to decide it by position. Every way of naming
## a field is covered, since each had its own call site.
## Held in a function: its locals then live in its own frame, the top level of this file being
## close to the 255-register limit.
func checkKeywordNames()
    var kw = {end: 1, in: 2, class: "c", do: 4, case: 5, static: 6, ref: 7, for: 8, while: 9}
    assert(kw.end == 1 and kw.in == 2 and kw.class == "c")
    assert(kw["end"] == kw.end)               ## the same key, written two ways
    kw.end = 99                               ## a field assignment
    assert(kw.end == 99)
    kw.in, kw.as = 7, 8                        ## a multiple assignment on fields
    assert(kw.in == 7 and kw.as == 8)
    func kw.for(x)                             ## a function defined on a field
        return x * 2
    end
    assert(kw.for(21) == 42)
    func bumpRef(r)
        r.set(r.get() + 1)
    end
    bumpRef(ref kw.while)                      ## a field path behind a 'ref'
    assert(kw.while == 10)

    class KwHolder
        func init()
            self.end = 5
        end
        func get()
            return self.end                    ## a field on self, inside a method
        end
    end
    assert(KwHolder().get() == 5)

    ## true, false and nil are LEFT OUT on purpose: they carry a value, so turning them into
    ## strings silently would be a trap (the refusal itself is pinned in test_errors.sh).
    assert(kw[true] == nil)                    ## a boolean key is a key of its own, not "true"
end
checkKeywordNames()

## A bare 'return' as the last statement of a switch arm. The set of tokens meaning "no return
## value" was written out a second time in return_stmt, and 'case' was missing from it: the form
## was refused outright ("unexpected token 'case'"). One predicate now answers for every block.
func armReturn(x)
    switch x
    case 1
        return
    case 2
        return 9
    end
    return 7
end
assert(armReturn(2) == 9)
assert(armReturn(3) == 7)

## An enum whose TARGET is a path through a keyword. Every other position after a '.' accepted a
## keyword; the enum target was the one site still demanding an identifier.
global kwCfg = {}
enum kwCfg.class
    A, B
end
assert(kwCfg.class.A == 1 and kwCfg.class.B == 2)

## A line break is WHITESPACE: a statement ends when the expression can no longer be extended,
## not at the end of its line. Both assertions below are the SAME mechanism, and joining is the
## only sensible reading of either — no statement can begin with a binary operator, so `+ b` and
## `- b` are not statements. Pinned so the rule does not change by accident.
func checkLineContinuation()
    var a = 1
    var b = 2
    var joined = a
                 + b               ## one expression: 3
    assert(joined == 3)
    var minus = 1
    -b                             ## joined to the line above: 1 - b, so -1
    assert(minus == -1)
    var times = 3
    *b                             ## every binary operator continues the same way: 3 * b
    assert(times == 6)
end
checkLineContinuation()

## A comment is WHITESPACE: the lexer drops it, so it terminates nothing. A line ending with a
## comment continues into the next one exactly as a bare line break does.
func cmJoined()
    var a = 1        ## the first term
    var b = 2        ## the second
    return a
           + b       ## joined ACROSS a comment: one expression
end
assert(cmJoined() == 3)

func cmBare()
    return           ## a bare return, its line ending with a comment
end
assert(cmBare() == nil)
