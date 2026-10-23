## Regression tests — Operators: the length operator, literal operands read from the constant pool.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/language/operators.ol — it must finish without error.

## '#' is a real unary OPERATOR (the LEN opcode), not a call by name to `len`. It was desugared
## into len(x), resolved in the user's scope, so a variable called len intercepted it and the
## program died on "call on non-function value" — the very trap ref's __ref_v parameter avoids.
func checkLengthOperator()
    var len = 7               ## shadows the builtin: '#' must not go through the name
    assert(#[1, 2, 3] == 3)
    assert(len == 7)
    assert(#"café" == 4)      ## in codepoints, as the builtin counts
    assert(#{a: 1, b: 2} == 2)
    assert(#nil == 0)
    assert(#42 == 1)
    assert(#[1;5] == 5)       ## a range knows its length
end
checkLengthOperator()

## A literal on the RIGHT of + - * == <> < <= > >= is read from the constant pool (ADDK, SUBK, ...), not loaded
## into a register first. The handlers are the generic ones, so every behaviour must be the one of the register
## form: integer and float typing, wrap-around, strings, nil and booleans, and the metamethods of an instance.
class ConstN
    func init(v) self.v = v end
    func __add(o) return ConstN(self.v + o) end
    func __lt(o) return self.v < o end
    func __le(o) return self.v <= o end
    func __eq(o) return self.v == o end
end

enum ConstTint RED, GREEN, BLUE end

func constOperandCheck()
    var n = 7
    assert(n + 1 == 8 and n - 1 == 6 and n * 3 == 21)
    assert(typeof(n + 1) == "int" and typeof(n * 3) == "int")
    assert(n < 8 and n <= 7 and n > 6 and n >= 7 and n == 7 and n <> 8)
    assert(not (n < 7) and not (n > 7) and not (n == 8) and not (n <> 7))

    ## A float constant promotes, an integer one does not.
    assert(n + 0.5 == 7.5 and typeof(n + 0.5) == "float")
    assert(n * 2.5 == 17.5 and typeof(n * 2.5) == "float")
    assert(n < 7.5 and n >= 6.5)

    ## Integer arithmetic wraps, the same as with two registers.
    var big = 9223372036854775807
    assert(big + 1 < 0)
    assert(big * 2 == -2)

    ## Strings: concatenation, equality and lexicographic order against a literal.
    var s = "abc"
    assert(s + "z" == "abcz")
    assert(s == "abc" and s <> "abd")
    assert(s < "b" and s <= "abc" and s > "ab" and s >= "abc")

    ## nil and booleans are constants too.
    var none = nil
    assert(none == nil and not (none <> nil))
    assert(n <> nil and not (n == nil))
    var flag = true
    assert(flag == true and flag <> false)

    ## An enum member is a constant of the pool.
    var t = ConstTint.GREEN
    assert(t == ConstTint.GREEN and t <> ConstTint.BLUE)

    ## An instance on the left still reaches its metamethods; the constant is the argument.
    var v = ConstN(2)
    assert((v + 3).v == 5)
    assert(v < 3 and not (v < 2))
    assert(v <= 2 and not (v <= 1))
    assert(v > 1 and not (v > 2))
    assert(v >= 2 and not (v >= 3))
    assert(v == 2 and not (v == 3))
    assert(v <> 3 and not (v <> 2))

    ## Compound assignment on a local takes the same path.
    var m = 10
    m += 5
    m -= 3
    m *= 2
    assert(m == 24)
    var str = "a"
    str += "b"
    assert(str == "ab")

    ## A failure is the one of the register form: arithmetic on nil is refused, and caught.
    var caught = 0
    try
        var z = nil
        var w = z + 1
    catch e
        caught = 1
    end
    assert(caught == 1)
    print("constant operands ok")
end
constOperandCheck()

## ── Chained comparisons: a < b < c is (a < b) and (b < c), each operand evaluated once ──
## No test exercised the compiler's chained form: only the single comparison was covered.
var chCalls = 0
func chFive()
    chCalls += 1
    return 5
end
assert(1 < chFive() < 10)
assert(chCalls == 1)                    ## the middle operand is evaluated ONCE, not once per comparison
assert(not (1 < chFive() < 3))
assert(not (10 < chFive() < 20))
assert(chCalls == 3)
## every operator takes part, and each pair is judged on its own
assert(1 <= 1 <= 1 and not (1 < 1 <= 2))
assert(3 > 2 > 1 and not (3 > 2 > 2))
assert(3 >= 3 >= 2 and not (3 >= 3 >= 4))
assert(1 == 1 == 1 and not (1 == 1 == 2))
assert(1 <> 2 <> 1 and not (1 <> 1 <> 2))
## different operators in one chain: each pair keeps ITS operator (using the first one for all would change these)
assert(1 < 2 <= 2 and not (2 <= 2 < 2) and 2 > 1 >= 1 and not (2 > 1 > 1))
assert(1 < 3 == 3 and not (1 < 3 == 4) and 3 == 3 > 2 and not (3 == 3 > 3) and 1 <> 2 < 3 and not (1 <> 1 < 3))
assert(1 < 2 < 3 < 4 and not (1 < 2 < 4 < 3) and not (2 < 1 < 3 < 4))   ## longer chains: one failing pair is enough
## strings compare the way they do alone
assert("a" < "b" < "c" and not ("a" < "c" < "b"))
## the result is a real boolean, usable as one
assert(typeof(1 < 2 < 3) == "bool" and typeof(3 < 2 < 1) == "bool")
assert((1 < 2 < 3) == true and (3 < 2 < 1) == false)
## an instance with __lt serves as the middle operand, on the right of one comparison and the left of the next
class ChN
    func init(v) self.v = v end
    func __lt(o) return self.v < o end
    func __le(o) return self.v <= o end
end
assert(0 < ChN(3) < 5 and not (5 < ChN(3) < 9) and not (0 < ChN(3) < 2) and not (0 < ChN(7) < 5))

## ── Compiler: compound assignment on an index or a field, ranges with a step ──
## `/=` and `%=` on a container slot take the same path as `+=`, one opcode each
var cxT = {x: 12, y: 13}
cxT.x /= 4
cxT.y %= 5
assert(cxT.x == 3 and cxT.y == 3)
var cxA = [10, 11]
cxA[1] /= 4
cxA[2] %= 4
assert(cxA[1] == 2.5 and cxA[2] == 3)

## a range VALUE with a step, closed and open on the left (the left bound moves by one step)
func cxCollect(r)
    var out = []
    for v in r do
        out.push(v)
    end
    return out
end
var cxClosed = cxCollect([1;10;3])
assert(#cxClosed == 4 and cxClosed[2] == 4 and cxClosed[4] == 10)
var cxOpen = cxCollect(]1;10;3])
assert(#cxOpen == 3 and cxOpen[1] == 4)

## a chained comparison whose middle operand is computed: it needs a temporary register of its own
func cxId(x) return x end
var cxU = 1
assert(cxU < cxId(2) < 3 and cxId(1) < cxId(2) <= cxId(3) and 1 < cxU + 1 < 5)
## ... and a call with no argument leaves its result at the very top of the registers in use
func cxOne()
    return 1
end
assert(0 < cxOne() < 3 and not (1 < cxOne() < 3))

## float remainder and float floor division keep the sign rules of their integer forms
assert(5.5 % 2 == 1.5 and -5.5 % 2 == -1.5)
assert(5.5 // 2 == 2 and -5.5 // 2 == -3)
