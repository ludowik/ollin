### syntax.ol — the source of truth for the Ollin language
    Covers every construct, in teaching order.
###

## ── 1. Comments ──────────────────────────────────────────────────────────────
## [grammar: line_comment, block_comment]

## an end-of-line comment

###
a multi-line
comment
###

## ── 2. Types and literals ────────────────────────────────────────────────────
## [grammar: NUMBER, exponent, hexDigit, octDigit, binDigit, digit, STRING, strChar, placeholder, fmtSpec, convChar, BOOL, NIL, IDENT, letter]

var n_int   = 42            ## an integer (int64)
var n_float = 3.14          ## a float (double)
var n_lead  = .5            ## a decimal with no leading zero
var n_sep   = 1_000_000     ## underscores are ignored
var n_fsep  = 1_000.12
assert(n_fsep == 1000.12)   ## underscore ignored in a float

var n_sci   = 6.022e23      ## scientific notation gives a float
var n_scin  = 2e-3          ## negative exponent
assert(1e3 == 1000)         ## the exponent gives 1000, an integer after num_value folds it
assert(1E3 == 1000)         ## an upper-case 'E' is accepted
assert(1.5e2 == 150)
assert(n_scin == 0.002)
assert(n_sci > 1e23)

var n_hex   = 0xFF          ## hexadecimal, hence an integer
var n_oct   = 0o10          ## octal gives an integer
var n_bin   = 0b1010        ## binary gives an integer
assert(n_hex == 255)
assert(n_oct == 8)
assert(n_bin == 10)
assert(0xDEAD_BEEF == 3735928559)  ## underscores in hex
assert(0o7_7 == 63)                ## underscores in octal
assert(0b1111_1111 == 255)         ## underscores in binary
assert(0b11111111 == 0xFF)         ## binary == hex
assert((0xF0 | 0x0F) == 0xFF)      ## hex literals with the bitwise operators
assert(0xFFFFFFFFFFFFFFFF == -1)   ## the whole bit pattern, wrapping to int64

var s = "hello"             ## a string, immutable
var s_concat = "hello" + ", " + "world"  ## concatenation with +
assert(s_concat == "hello, world")
var yes  = true            ## a boolean: a type of its own, not an integer
var no  = false
var nothing  = nil          ## no value

## ── 3. Variables ─────────────────────────────────────────────────────────────
## [grammar: varDecl, globalDecl, assignStmt, program, stmt, exprStmt]
## Every variable MUST be declared with `var` before use.
## Reading or assigning an undeclared name is a compile error.
## `var` only ever creates locals.

var x           ## uninitialised, hence nil
assert(x == nil)

var a, b = 10, 20           ## multiple declaration
var p, q, r = 1, 2          ## r is nil: fewer values than names
assert(r == nil)

## plain assignment
a = 99
assert(a == 99)

## multiple assignment to variables ALREADY declared (no `var`): the values are spread as they
## are at declaration, a multi-return call included.
a, b = 1, 2
assert(a == 1 and b == 2)
a, b = b, a                 ## a swap: the right-hand side is evaluated before writing
assert(a == 2 and b == 1)

## compound assignments
var c = 10
c += 3
assert(c == 13)
c -= 5
assert(c == 8)
c *= 2
assert(c == 16)
c /= 4
assert(c == 4.0)
c = 10
c %= 3
assert(c == 1)

## globals: `global` declares a variable visible throughout the program, declarable anywhere,
## readable and writable from any function.
global gcount = 0
func bump()
    gcount += 1        ## writes the global from inside a function
end
bump()
bump()
assert(gcount == 2)

global gmsg            ## with no init, hence nil
assert(gmsg == nil)
gmsg = "ready"
assert(gmsg == "ready")

## multiple declaration
global ga, gb = 1, 2
assert(ga == 1 and gb == 2)

## forward reference: a function declared before the global
func read_fwd()  return gfwd  end
global gfwd = 99
assert(read_fwd() == 99)

## a local shadows the global within its scope
global gshadow = 100
func shadow_test()
    var gshadow = 7
    return gshadow
end
assert(shadow_test() == 7)
assert(gshadow == 100)

## ── 4. Arithmetic ────────────────────────────────────────────────────────────
## [grammar: additive, multiplicative, power, unary, primary, expr]

assert(2 + 3   == 5)
assert(10 - 4  == 6)
assert(3 * 7   == 21)
assert(7 / 2   == 3.5)      ## a division is ALWAYS a float
assert(10 % 3  == 1)
assert(-5 + 5  == 0)        ## unary negation
assert(2 + 3 * 4 == 14)     ## precedence: * before +

## INT op INT gives INT; INT op FLOAT gives FLOAT
assert(1 + 2     == 3)
assert(1 + 2.0   == 3.0)

## concatenation: string + anything gives a string
assert("x" + 1     == "x1")
assert("v=" + 3.14 == "v=3.14")
assert(42 + " !"   == "42 !")

## floor division (//) and exponentiation (^)
assert(7 // 2    == 3)         ## IDIV floors towards -∞
assert(-7 // 2   == -4)
assert(2 ^ 8     == 256)       ## POW: INT^INT>=0 gives INT ('^' is exponentiation, as in Lua)
assert(2.0 ^ -1  == 0.5)       ## a negative exponent gives a float
assert(-2 ^ 2    == -4)        ## '^' binds tighter than unary minus
assert(2 ^ 2 ^ 3 == 256)       ## right-associative: 2^(2^3)

## ── 5. Comparisons ───────────────────────────────────────────────────────────
## [grammar: comparison]

assert(1 == 1)
assert(1 <> 2)
assert(not (5 <> 5))    ## the false case: equal operands
assert(3 > 2)
assert(2 < 3)
assert(3 >= 3)
assert(not (2 >= 3))    ## the false case: left < right
assert(2 <= 3)
assert(not (3 <= 2))    ## the false case: left > right

## across numeric types
assert(1 == 1.0)
assert(1.0 <> 2)

## ── 6. Logic ─────────────────────────────────────────────────────────────────
## [grammar: logical, logicalAnd]

assert(true  or  false)
assert(false or  true)
assert(true  and true)
assert(not false)

## precedence: not > and > or
assert(true or false and false)     ## true or (false and false)

## `and` and `or` return the OPERAND, not a normalised boolean (value semantics)
assert((false and true) == false)   ## the first operand, which is falsy
assert((3 and 7) == 7)              ## the second, the first being truthy
assert((nil or "x") == "x")

## the boolean is a TYPE OF ITS OWN, sealed: `true` is not the integer 1
assert(true  <> 1)
assert(false <> 0)
assert(nil   <> false)
assert(true  == true)
assert(not (true == false))

## `not` and the comparisons PRODUCE a boolean
assert((not 0)   == true)
assert((1 == 1)  == true)
assert((1 <> 1)  == false)
assert((2 > 3)   == false)

## truthiness of each type — the "empty is false" rule, unchanged
assert(not 0)          ## zero is falsy, without being equal to false
assert(not not 1)
assert(not not "x")    ## a non-empty string is truthy
assert(not "")         ## string empty : falsy
assert(not nil)
assert(not {})         ## map empty : falsy
assert(not [])         ## array empty : falsy
assert(not not {a:1})  ## a non-empty map is truthy
assert(not not [1])    ## a non-empty array is truthy

## ── 7. Bitwise operators ─────────────────────────────────────────────────────
## [grammar: bitwiseOr, bitwiseXor, bitwiseAnd, shift]

assert((12 & 10)  == 8)        ## ET
assert((12 | 10)  == 14)       ## OU
assert((12 ~ 10)  == 6)        ## XOR: a binary '~', as in Lua
assert(~0         == -1)       ## NOT : '~' unaire
assert((5 ~ ~0)   == -6)       ## XOR of 5 and (NOT 0) = 5 ~ -1
assert((1 << 3)   == 8)
assert((16 >> 2)  == 4)

## ── 8. If / else if / else ───────────────────────────────────────────────────
## [grammar: ifStmt]

var score = 75
var grade = "F"

if score >= 90 then
    grade = "A"
elseif score >= 70 then
    grade = "C"
else
    grade = "F"
end
assert(grade == "C")

## a one-line if
var ok = false
if true then ok = true end
assert(ok)

## ── 9. While ─────────────────────────────────────────────────────────────────
## [grammar: whileStmt]

var i = 0
while i < 5 do
    i += 1
end
assert(i == 5)

## break
var j = 0
while true do
    j += 1
    if j >= 3 then break end
end
assert(j == 3)

## continue
var sum = 0
var k = 0
while k < 10 do
    k += 1
    if k % 2 == 0 then continue end    ## skips the even ones
    sum += k
end
assert(sum == 25)   ## 1+3+5+7+9

## ── 10. For ──────────────────────────────────────────────────────────────────
## [grammar: forStmt, rangeLit]

## inclusive range [1;5] gives 1,2,3,4,5
var s1 = 0
for i in [1;5] do
    s1 += i
end
assert(s1 == 15)

## numeric, with no step
var s2 = 0
for i = 1, 5 do
    s2 += i
end
assert(s2 == 15)

## positive step
var s3 = 0
for i = 1, 9, 2 do
    s3 += i
end
assert(s3 == 25)    ## 1+3+5+7+9

## negative step
var s4 = 0
for i = 5, 1, -1 do
    s4 += i
end
assert(s4 == 15)

## break inside a for over a range
var s5 = 0
for i in [1;100] do
    if i > 5 then break end
    s5 += i
end
assert(s5 == 15)

## continue inside a for over a range
var s6 = 0
for i in [1;10] do
    if i % 2 == 0 then continue end
    s6 += i
end
assert(s6 == 25)

## right-exclusive range [1;5[ gives 1,2,3,4
var s8 = 0
for i in [1;5[ do
    s8 += i
end
assert(s8 == 10)

## range with a step [1;10;2] gives 1,3,5,7,9
var s9 = 0
for i in [1;10;2] do
    s9 += i
end
assert(s9 == 25)

## a range is first-class: it can be stored in a variable
var rng = [1;5]
var s10 = 0
for i in rng do
    s10 += i
end
assert(s10 == 15)

## left-exclusive range ]1;5[ gives 2,3,4
var s11 = 0
for i in ]1;5[ do
    s11 += i
end
assert(s11 == 9)

## half-open range ]1;5] gives 2,3,4,5
var s12 = 0
for i in ]1;5] do
    s12 += i
end
assert(s12 == 14)

## continue inside a for k,v over a map
var cm = {a: 1, b: 2, c: 3, d: 4}
var cs1 = 0
for k, v in cm do
    if v % 2 == 0 then continue end
    cs1 += v
end
assert(cs1 == 4)   ## 1+3

## continue inside a for v over an array
var cs2 = 0
for v in [1, 2, 3, 4, 5] do
    if v % 2 == 0 then continue end
    cs2 += v
end
assert(cs2 == 9)   ## 1+3+5

## ── 11. Functions ────────────────────────────────────────────────────────────
## [grammar: funcDecl, params, param, returnStmt, retvals, call, lambdaExpr]

## declaration and call
func add(a, b)
    return a + b
end
assert(add(3, 4) == 7)

## postfix on a parenthesised expression: (expr)(args), (expr)[i], (expr).field
assert((func(x) return x * 2 end)(21) == 42)   ## calling a parenthesised lambda
assert(([10, 20, 30])[2] == 20)                 ## index
assert(({a: 7}).a == 7)                         ## champ
## optional call f?(): nil does nothing (nil), a function is called, anything else is an error
assert(add?(3, 4) == 7)     ## callable, hence an ordinary call
var maybe = nil
assert(maybe?() == nil)     ## nil: no call, and no error
var cb = func(n) return n * 2 end
assert(cb?(21) == 42)       ## closure en variable
cb = nil
assert(cb?(21) == nil)
var holder = {fn: func() return "ok" end}
assert(holder["fn"]?() == "ok")  ## an optional call on an expression
assert(holder["absent"]?() == nil)  ## a missing key gives nil, which is ignored

## optional method call: self is injected, and a missing method gives nil
class Box
    func init(v) self.v = v end
    func get() return self.v end
end
var bx = Box(7)
assert(bx.get?() == 7)      ## self is injected
assert(bx.missing?() == nil)## a missing method gives nil

## short circuit: the arguments are NOT evaluated when the callee is not callable
global opt_se
opt_se = 0
func opt_bump() opt_se = opt_se + 1 return opt_se end
var nf = nil
assert(nf?(opt_bump()) == nil)
assert(opt_se == 0)          ## opt_bump() is never called, the callee being nil
assert(bx.missing?(opt_bump()) == nil)
assert(opt_se == 0)          ## likewise for a missing method
assert(add?(opt_bump(), 10) == 11)  ## callable, so the arguments are evaluated (opt_bump gives 1)
assert(opt_se == 1)

## multiple returns
func minmax(a, b)
    if a < b then return a, b end
    return b, a
end
var lo, hi = minmax(7, 3)
assert(lo == 3 and hi == 7)

## the same values, assigned to targets ALREADY declared — a variable, a map field, an array
## element (the spreading itself is exercised in `regressions.ol`).
var target = {}
var tab = [0, 0]
lo, target.min, tab[2] = minmax(5, 1)
assert(lo == 1 and target.min == 5 and tab[2] == nil)

## recursion
func fact(n)
    if n < 2 then return 1 end
    return n * fact(n - 1)
end
assert(fact(0) == 1)    ## the edge case: n=0 takes the n < 2 branch
assert(fact(5) == 120)

## default parameters (literal constants only)
func greet(name, greeting = "Hello")
    return greeting
end
assert(greet("Alice")          == "Hello")
assert(greet("Bob", "Hi")   == "Hi")

## a call with no argument: a parameter with no default gets nil, for want of arguments
func f_nodefault(a, b)
    return a
end
assert(f_nodefault() == nil)

## pure varargs: the function takes any number of arguments
func wrap(...)
    return ...
end
var w1, w2, w3 = wrap(10, 20, 30)
assert(w1 == 10 and w2 == 20 and w3 == 30)

func passthrough(a, ...)
    return a, ...
end
var r1, r2, r3 = passthrough(1, 2, 3)
assert(r1 == 1 and r2 == 2 and r3 == 3)

## a one-line function
func double(x)  return x * 2  end
assert(double(5) == 10)

## definition on a map field: `func obj.field(...)` is `obj.field = func(...)`
var handlers = {}
func handlers.greet(name)
    return "hi " + name
end
assert(handlers.greet("ollin") == "hi ollin")
func handlers.add(a, b = 5)   ## parameters and defaults work here too
    return a + b
end
assert(handlers.add(10) == 15)
assert(handlers.add(10, 20) == 30)

## ── 12. Closures ─────────────────────────────────────────────────────────────
## [grammar: lambdaExpr]

## upvalue: a variable of the enclosing scope
var counter = 0
func inc()  counter += 1  end
inc()  inc()  inc()
assert(counter == 3)

## a factory: each call creates independent state
func make_counter()
    var n = 0
    func next()
        n += 1
        return n
    end
    return next
end

var c1 = make_counter()
var c2 = make_counter()
assert(c1() == 1)
assert(c1() == 2)
assert(c2() == 1)   ## independent state

## nested functions, not exported into the globals
func make_adder(x)
    func add(y)  return x + y  end
    return add
end
var add5 = make_adder(5)
assert(add5(3) == 8)

## anonymous functions (lambdas)
func make_counter2()
    var n = 0
    return func()
        n = n + 1
        return n
    end
end
var cx = make_counter2()
assert(cx() == 1)
assert(cx() == 2)
assert(cx() == 3)

var double = func(x)  return x * 2  end
assert(double(7) == 14)

## ── 13. Error handling ───────────────────────────────────────────────────────
## [grammar: tryStmt, throwStmt]

## throw and catch
var caught = nil
try
    throw "oops"
catch err
    caught = err
end
assert(caught == "oops")

## the else branch runs when nothing was thrown
var ok2 = false
try
    var dummy = 1
catch err
    ok2 = false
else
    ok2 = true
end
assert(ok2)

## throwing a value of any type
try
    throw {code: 42, msg: "failure"}
catch e
    assert(e["code"] == 42)
end

## an empty try / catch / end
try
catch err
end

## ── 14. Maps ─────────────────────────────────────────────────────────────────
## [grammar: mapLit, mapEntry, indexAssign]

## creation
var empty = {}
var m = {
    "a": 1,
    b:   2,         ## an identifier key, with no quotes
    c:   {}         ## a nested map as the value
}

## reading: brackets or a dot
assert(m["a"] == 1)
assert(m.b    == 2)
assert(m["x"] == nil)   ## a missing key gives nil
assert(m.x    == nil)

## literal keys: an identifier, "string" and ["string"] are equivalent (the key is the string)
var lit = {
    a: 1,
    "a2": 2,
    ["a3"]: 3
}
assert(lit["a"]  == 1)
assert(lit["a2"] == 2)
assert(lit["a3"] == 3)

## computed key: [expr] uses the expression's VALUE as the key
var kname = "calculee"
var ck = {
    kname:   1,      ## the literal key "kname"
    [kname]: 2,      ## the key "calculee", the value of kname
    [1 + 1]: "two"  ## the integer key 2
}
assert(ck["kname"]    == 1)
assert(ck["calculee"] == 2)
assert(ck[2]          == "two")
assert(ck["kname"] <> ck["calculee"])

## writing
m["d"] = 4
m.e    = 5
assert(m["d"] == 4)
assert(m.e    == 5)

## compound assignment
m["a"] += 10
m.b    *= 3
assert(m["a"] == 11)
assert(m.b    == 6)

## nested map
var scene = {camera: {fov: 60}}
assert(scene["camera"]["fov"] == 60)
assert(scene.camera.fov       == 60)

## reference semantics
var orig = {x: 1}
var alias = orig          ## `ref` is a keyword, for passing by reference, hence another name
alias.x = 99
assert(orig.x == 99)

## keys of any type, through brackets
var km = {}
km[nil]   = "nil"
km[42]    = "int"
km[3.14]  = "float"
km[true]  = "yes"
km[false] = "faux"
assert(km[nil]   == "nil")
assert(km[42]    == "int")
assert(km[1.0]   == km[1])     ## int equals float as a key, when the numeric value is the same

## keys: an array, a map, a function
var km_arr = [1, 2]
km[km_arr] = "array"
assert(km[km_arr] == "array")

var km_map = {"a": 1}
km[km_map] = "map"
assert(km[km_map] == "map")

func km_fn()  end
km[km_fn] = "func"
assert(km[km_fn] == "func")

## iterating key and value
var total = 0
for k, v in {x: 1, y: 2, z: 3} do
    total += v
end
assert(total == 6)

## iterating keys alone (one variable over a map gives the key)
var key_sum = 0
for k in {a: 1, b: 2, c: 3} do
    key_sum += 1   ## we merely count the iterations
end
assert(key_sum == 3)

## for k,v inside a function
func sum_map_vals(m)
    var s = 0
    for k, v in m do
        s += v
    end
    return s
end
assert(sum_map_vals({x: 1, y: 2, z: 3}) == 6)

## ── 15. Arrays ───────────────────────────────────────────────────────────────
## [grammar: arrayLit]

## creation
var arr = [10, 20, 30]
var vide2 = []
## a comma before the closing bracket is allowed, on one line as on several; between two items
## it is REQUIRED (see test_errors.sh)
var trailing = [1, 2,]
var trailingMap = {a: 1,}
assert(#trailing == 2 and #trailingMap == 1)

## reading and writing (1-based)
assert(arr[1] == 10)
assert(arr[4] == nil)   ## out of bounds gives nil
arr[2] = 99
arr[3] += 1
assert(arr[2] == 99)
assert(arr[3] == 31)

## grows on its own
var a2 = []
a2[3] = "x"
assert(a2[1] == nil)
assert(a2[3] == "x")

## iterating values alone
var s7 = 0
for v in [1, 2, 3, 4, 5] do
    s7 += v
end
assert(s7 == 15)

## iterating index and value
for i, v in arr do
    print("{i}: {v}")
end

## reference semantics
var arr2 = arr
arr2[1] = 0
assert(arr[1] == 0)

## ── 16. Builtins ─────────────────────────────────────────────────────────────

## print — arguments separated by spaces, then a newline
print("hello", 42, true)    ## hello 42 1

## printf — POSITIONAL substitution: {} is automatic, {N} is indexed (no escaping).
## {N:spec} applies a C format (spec being the conversion without the '%').
printf("{} + {} = {}", 1, 2, 3)            ## 1 + 2 = 3  (auto : 1-based)
printf("{1} and {1}", "yes")               ## yes and yes  (index 1 = first argument)
printf("a={1} b={2} a={1}", 10, 20)        ## a=10 b=20 a=10
printf("pi = {1:.3f}", 3.14159)            ## pi = 3.142
printf("hex = {1:04x}", 255)               ## hex = 00ff

## string interpolation: {expr} evaluates the expression, {expr:spec} formats it.
var iname = "world"
var ix = 42
assert("hello {iname}" == "hello world")
assert("x={ix}" == "x=42")
assert("calc: {ix * 2 + 1}" == "calc: 85")
assert("{ix}{ix}" == "4242")
assert("pi~{3.14}" == "pi~3.14")
assert("pi={3.14159:.2f}" == "pi=3.14")            ## format: two decimals
assert("hex={(255):04x}" == "hex=00ff")            ## an expression plus a format, in brackets
assert("pad=[{ix:5d}]" == "pad=[   42]")           ## the width
assert(len("ac\{olade") == 8)    ## \{ is a literal brace, one character
assert("{1} litteral" == "{1} litteral")           ## {N} is a positional placeholder (1-based), and a literal in an interpolation

## assert — throws when the value is falsy
assert(1 + 1 == 2)
assert(true, "must be true")

## time — UNIX seconds, as a float
var t0 = time()
var t1 = time()
assert(t1 >= t0)

## len — the size of a collection or of a string
var lst = [1, 2, 3]
assert(len(lst) == 3)
assert(len("hello") == 5)
assert(len({a: 1, b: 2}) == 2)
assert(len([1;5]) == 5)

## # — syntactic sugar for len()
assert(#lst == 3)
assert(#"hello" == 5)
assert(#{a: 1, b: 2} == 2)
assert(#[1;5] == 5)
assert(#lst == len(lst))

## array methods
assert(lst.len() == len(lst))
assert([10, 20, 30].len() == 3)
var nested = [[1, 2], [3, 4]]
assert(nested.len() == 2)
assert(nested[1].len() == 2)

var ma = [1, 2, 3]
ma.push(4)
assert(ma[4] == 4)
assert(ma.pop() == 4)
assert(ma.len() == 3)
ma.insert(2, 99)
assert(ma[2] == 99)
assert(ma.delete(2) == 99)
assert(ma[2] == 2)

var fifo = []
fifo.enqueue(10)
fifo.enqueue(20)
assert(fifo.dequeue() == 10)
assert(fifo.dequeue() == 20)

## string methods: the `string` module's functions can also be called ON the string, which then
## becomes the first argument. Counting by character, and bounds outside the string, are
## behaviour, hence `regressions.ol`.
assert("Ollin".len() == 5)
assert("Ollin".upper() == "OLLIN")
assert("OLLIN".lower() == "ollin")
assert("  edge  ".trim() == "edge")
assert("  edge  ".ltrim() == "edge  ")
assert("  edge  ".rtrim() == "  edge")
assert("abcdef".substr(2, 3) == "bcd")     ## start at 1, then a length
assert("abcdef".substr(2) == "bcdef")      ## with no length: through to the end
assert("abcdef".char(1) == "a")

## the module form and the method form name the same function
assert(string.upper("Ollin") == "Ollin".upper())

## the result is a string like any other, so calls chain
assert("  MiXte  ".trim().lower().substr(1, 2) == "mi")

## ── 17. Import ───────────────────────────────────────────────────────────────
## [grammar: importStmt]

## flat import: the file's symbols are injected into the current scope
import "utils_test1"
assert(CONST == 42)

## module import, of another file: the symbols are gathered in a map
import "utils_test2" as u
assert(u.mul(3, 4) == 12)
assert(u.VERSION == 2)

## circular import: silently ignored, the file being already imported
import "utils_test1"
assert(CONST == 42)   ## still reachable

## ── 18. Classes ──────────────────────────────────────────────────────────────
## [grammar: classDecl, method, methodCall, superCall]

## a base class
class Animal
    func init(name, sound)
        self.name = name
        self.sound = sound
    end
    func speak()
        return self.name + " says " + self.sound
    end
    func __str()
        return "Animal(" + self.name + ")"
    end
end

var anm = Animal("Dog", "woof")
assert(anm.speak() == "Dog says woof")
assert(anm.name == "Dog")
assert(anm.sound == "woof")

## single inheritance
class Dog extends Animal
    func init(name)
        super.init(name, "woof")
    end
    func fetch()
        return self.name + " fetches!"
    end
    ## `super.` is not only for the constructor: it calls the parent's version of any method,
    ## here overridden under the same name.
    func crier()
        return "[" + super.speak() + "]"
    end
end

var d = Dog("Rex")
assert(d.speak() == "Rex says woof")
assert(d.fetch() == "Rex fetches!")
assert(d.name == "Rex")
assert(d.crier() == "[Rex says woof]")

## inheritance with no init of its own: the parent's is inherited
class Cat extends Animal
    func purr()
        return self.name + " purrs"
    end
end

var catw = Cat("Whiskers", "meow")
assert(catw.speak() == "Whiskers says meow")
assert(catw.purr() == "Whiskers purrs")

## a method that mutates self
class Counter
    func init(start)
        self.n = start
    end
    func increment()
        self.n = self.n + 1
    end
    func value()
        return self.n
    end
end

var ctr = Counter(0)
ctr.increment()
ctr.increment()
ctr.increment()
assert(ctr.value() == 3)

## meta-methods: one language operator per method. The derived comparisons (`>`, `>=`, `<>`) and
## their symmetry are semantics, hence `regressions.ol`.
class Num
    func init(v)
        self.v = v
    end
    func __add(o)  return Num(self.v + o.v)  end
    func __sub(o)  return Num(self.v - o.v)  end
    func __mul(o)  return Num(self.v * o.v)  end
    func __div(o)  return Num(self.v / o.v)  end
    func __mod(o)  return Num(self.v % o.v)  end
    func __neg()   return Num(-self.v)  end
    func __eq(o)   return self.v == o.v  end
    func __lt(o)   return self.v < o.v  end
    func __le(o)   return self.v <= o.v  end
    func __str()   return "Number({self.v})"  end
end

var n10 = Num(10)
var n4 = Num(4)
assert((n10 + n4).v == 14)
assert((n10 - n4).v == 6)
assert((n10 * n4).v == 40)
assert((n10 / n4).v == 2.5)
assert((n10 % n4).v == 2)
assert((-n10).v == -10)
assert(n10 == Num(10))
assert(n4 < n10)
assert(n10 <= Num(10))
assert("{n10}" == "Number(10)")

## static methods: callable on the class, with no self
class Factory
    static func zero()
        return Factory.make(0)
    end
    static func make(val)
        var obj = Factory()
        obj.val = val
        return obj
    end
    func init()
        self.val = -1
    end
    func get()
        return self.val
    end
end

var f0 = Factory.zero()
assert(f0.get() == 0)

var f5 = Factory.make(5)
assert(f5.get() == 5)

## called through an instance: no self is injected
var fi = Factory()
var f7 = fi.make(7)
assert(f7.get() == 7)

print("class tests ok")

## ── 19. Constants ────────────────────────────────────────────────────────────
## [grammar: constDecl]

## 'const': an immutable local, whose initialisation is mandatory
const PI = 3.14159
const MAX = 100
assert(PI  == 3.14159)
assert(MAX == 100)

## a constant inside a function
func circle_area(r)
    const TWO_PI = 2 * PI
    return TWO_PI * r * r
end
assert(circle_area(1) == 2 * PI)

## a constant captured read-only by a closure
const BASE = 10
func with_base(x)  return BASE + x  end
assert(with_base(5) == 15)

## What the engine must REFUSE (an uninitialised const, a write to a constant, the
## redeclaration of a local or a global) is checked by `tests/test_errors.sh`, message included.
## It is not restated here as a comment: two descriptions of the same refusal drift apart
## sooner or later.

## ── 21. The math module ──────────────────────────────────────────────────────

## constants
assert(math.PI  == 3.141592653589793)
assert(math.TAU == 6.283185307179586)
assert(math.TAU == 2 * math.PI)

## abs
assert(math.abs(5)    == 5)
assert(math.abs(-5)   == 5)
assert(math.abs(0)    == 0)
assert(math.abs(-3.5) == 3.5)

## sign
assert(math.sign(10)   == 1)
assert(math.sign(-10)  == -1)
assert(math.sign(0)    == 0)
assert(math.sign(2.5)  == 1)
assert(math.sign(-2.5) == -1)

## floor / ceil
assert(math.floor(2.9)  == 2)
assert(math.floor(-2.1) == -3)
assert(math.ceil(2.1)   == 3)
assert(math.ceil(-2.9)  == -2)

## sqrt
assert(math.sqrt(4)   == 2)
assert(math.sqrt(9)   == 3)
assert(math.sqrt(2.0) > 1.41 and math.sqrt(2.0) < 1.42)

## sin / cos
assert(math.sin(0) == 0)
assert(math.cos(0) == 1)
assert(math.sin(math.PI) > -0.001 and math.sin(math.PI) < 0.001)

## rand — a value in [0, 1)
var rnd = math.rand()
assert(rnd >= 0 and rnd < 1)

## noise — fractal Perlin noise (fBm), in 1, 2 or 3 dimensions, within [0, 1]
var nz1 = math.noise(0.5)
assert(nz1 >= 0 and nz1 <= 1)
var nz2 = math.noise(0.5, 1.5)
assert(nz2 >= 0 and nz2 <= 1)
var nz3 = math.noise(0.5, 1.5, 2.5)
assert(nz3 >= 0 and nz3 <= 1)
## deterministic: the same input gives the same output
assert(math.noise(3.14) == math.noise(3.14))
## noiseSeed: reproducible after an identical reseed
math.noiseSeed(42)
var na = math.noise(1.7)
math.noiseSeed(42)
assert(math.noise(1.7) == na)
## different seeds give different noise
math.noiseSeed(1)
var nb = math.noise(1.7)
math.noiseSeed(2)
assert(math.noise(1.7) <> nb)

## ── 22. Switch ───────────────────────────────────────────────────────────────
## [grammar: switchStmt]

## the base case — an integer value
var sw_r = 0
switch 2
    case 1
        sw_r = 1
    case 2
        sw_r = 2
    case 3
        sw_r = 3
    else
        sw_r = 99
end
assert(sw_r == 2)

## the else branch fires
switch 42
    case 1
        sw_r = 1
    else
        sw_r = 99
end
assert(sw_r == 99)

## with no else: no case matches, and nothing runs
sw_r = 0
switch 7
    case 1
        sw_r = 1
    case 2
        sw_r = 2
end
assert(sw_r == 0)

## several values per case
switch "b"
    case "a", "b"
        sw_r = 1
    case "c"
        sw_r = 2
end
assert(sw_r == 1)

## switch on a string — the first case
switch "hello"
    case "hello"
        sw_r = 10
    case "world"
        sw_r = 20
end
assert(sw_r == 10)

## switch inside a function
func sw_func(n)
    switch n
        case 0
            return "zero"
        case 1, 2
            return "one or two"
        else
            return "other"
    end
end
assert(sw_func(0) == "zero")
assert(sw_func(1) == "one or two")
assert(sw_func(2) == "one or two")
assert(sw_func(5) == "other")

## ── 23. The graphics module (raylib) ─────────────────────────────────────────
##
## Available in the native build as in WASM, which the playground uses. The DEFAULT native build
## uses the stub, where `graphics` is nil. For examples, see docs/samples/.
##
##   graphics.canvas(800, 600, "Title")   ## opens a window
##   func draw()                          ## called on every frame
##       graphics.clear(colors.BLACK)
##       graphics.stroke(colors.RED)      ## style: the current state
##       graphics.line(x1, y1, x2, y2)    ## geometry: the arguments
##   end
##
## The module's RULE: geometry goes through the ARGUMENTS, style comes from the current STATE
## (fill, stroke, strokeSize, fontSize, rectMode, spriteMode). No drawing primitive takes a colour
## or a size as an argument.
##
## Predefined colours: the `colors` module (colors.BLACK, colors.WHITE, colors.RED…)
## Custom colours: Color(r, g, b[, a]), with components from 0 to 1
##   (a packed integer does NOT work: the values are clamped to 1, hence white)
## FPS: graphics.fps() gives an integer
## Text: graphics.text(text, x, y) — in the stroke colour, one writing with a pen
##   graphics.fontSize(n) sets the font size; it takes a fractional value, has no minimum, and is
##   reset to 18 on every frame
## Rectangle anchoring: graphics.rectMode("corner" | "center") — "corner" (the default, x,y being
##   the top-left corner) is restored on every frame; in "center", x,y is the centre
## Anchoring of circle, ellipse and arc: graphics.ellipseMode("center" | "corner") — the default
##   is "center", those primitives being centred; in "corner", the reference box of an arc is
##   that of the whole ellipse, not of the sector drawn
## Image anchoring: graphics.spriteMode("corner" | "center") — it applies to graphics.sprite AND
##   to image.draw; the offset bears on the displayed size

## ── 24. Array instance methods (higher-order functions) ─────────────────────

var am_doubled = [1, 2, 3].map(func(x) return x * 2 end)
assert(am_doubled.len() == 3)
assert(am_doubled[1] == 2 and am_doubled[2] == 4 and am_doubled[3] == 6)

var am_evens = [1, 2, 3, 4, 5].filter(func(x) return x % 2 == 0 end)
assert(am_evens.len() == 2)
assert(am_evens[1] == 2 and am_evens[2] == 4)

var am_sum = [1, 2, 3, 4].reduce(func(acc, x) return acc + x end, 0)
assert(am_sum == 10)

var am_product = [1, 2, 3, 4].reduce(func(acc, x) return acc * x end, 1)
assert(am_product == 24)

var am_idx = ["a", "b"].map(func(v, i) return i end)
assert(am_idx[1] == 1 and am_idx[2] == 2)

var am_sorted = [3, 1, 2].sort()
assert(am_sorted[1] == 1 and am_sorted[2] == 2 and am_sorted[3] == 3)
var am_mixed = [2.5, nil, "z", 1]
am_mixed.sort()
assert(am_mixed[1] == nil and am_mixed[2] == 1 and am_mixed[3] == 2.5 and am_mixed[4] == "z")

## ── 25. The do...end block (lexical scope) ───────────────────────────────────
## [grammar: doStmt]
var do_x = 0
do
    var do_tmp = 42
    do_x = do_tmp + 1
end
assert(do_x == 43)

var do_fns = []
do
    var do_i = 99
    do_fns.push(func() return do_i end)
end
assert(do_fns[1]() == 99)

do
    var do_a = 1
    do
        var do_b = do_a + 1
        assert(do_b == 2)
    end
end

## ── 26. enum (named constants, a frozen map) ─────────────────────────────────
## [grammar: enumDecl, enumTarget, enumItem]
## With no value, the first is 1 and each one follows at +1.
enum Tint RED, GREEN, BLUE end
assert(Tint.RED == 1 and Tint.GREEN == 2 and Tint.BLUE == 3)

## An integer literal sets the value, and the counter resumes at value+1.
enum State IDLE = 0, WALK, JUMP = 10, FALL end
assert(State.IDLE == 0 and State.WALK == 1 and State.JUMP == 10 and State.FALL == 11)

## Any expression is accepted as a value, but does not move the counter.
enum Mixed A, B = "text", C end
assert(Mixed.A == 1 and Mixed.B == "text" and Mixed.C == 2)

## For reading, an enum is a map: len and iteration.
assert(#Tint == 3)
var enum_sum = 0
for k, v in Tint do
    enum_sum = enum_sum + v
end
assert(enum_sum == 6)

## Every write is refused — here through an alias, hence at run time.
var enum_alias = Tint
var enum_bloque = false
try
    enum_alias.RED = 9
catch e
    enum_bloque = true
end
assert(enum_bloque and Tint.RED == 1)

## Declaring into an existing map: enum a.b
global enumCfg = {}
enum enumCfg.mode PLEIN, FENETRE end
assert(enumCfg.mode.PLEIN == 1 and enumCfg.mode.FENETRE == 2)

## ── 27. ref (passing by reference) ───────────────────────────────────────────
## [grammar: refExpr]
## `ref x` gives a function the means to READ and to WRITE the variable x.
## The target stays an ordinary variable: it is read and written as usual.
global refTarget = 1
var refLocal = "a"
global refObj = {field: 10}

func refWrite(r, v)
    r.set(v)          ## writing through the reference
end
func refLire(r)
    return r.get()
end

assert(refLire(ref refTarget) == 1)
refWrite(ref refTarget, 5)
assert(refTarget == 5)         ## the variable itself has changed

refWrite(ref refLocal, "b")    ## a LOCAL can be referenced, through an upvalue
assert(refLocal == "b")

refWrite(ref refObj.field, 20)  ## a field of an object too
assert(refObj.field == 20)

## A reference is a value: it can be stored and passed on.
var refStock = ref refTarget
refStock.set(7)
assert(refTarget == 7)

## ── 28. The ui module (widgets drawn by the engine) ──────────────────────────
## Buttons and checkboxes, stacked in the top-right corner of the drawing area.
## A widget is declared ONCE; the engine draws it and tests it on every frame.
##
##   ui.button(label, function)                     → called on every click
##   ui.checkbox(label, ref variable [, onChange])  → writes true/false into it
##   ui.slider(label, ref v, min, max [, default] [, onChange])
##                                                  → an adjustable number
##   ui.clear()                                     → removes every widget
##
## Widgets can be filed into MENUS. One menu is shown at a time; a sub-menu appears as a
## clickable row, and a "<" row goes back up one level.
##
##   var m = ui.menu(label)       → a menu (at the root, or m.menu(...) for a sub-menu)
##   m.button / m.checkbox        → the same declaration, filed into that menu
##   ui.show(m)                   → replaces the global menu on display (nil = the root)
##   ui.back()                    → goes back up one level; ui.current() is the menu shown
##   ui.open([m]) / ui.close() / ui.toggle()
##                                → unfolds and folds the interface (CLOSED at startup,
##                                  reduced to a handle in the corner)
##   m.open()                     → descends into m, as a click on its row would
##   h.remove() / m.clear()       → removes an element / empties a menu
##
## A checkbox is bound by REFERENCE: the initial state is read from the variable, every click
## writes into it, and the program reads the variable as usual. onChange(newState) is called
## after the change when it is supplied.
##
## A click on a widget is NOT passed on to mouse.pressed; a click elsewhere is. With no graphics
## area, declaring a widget does nothing — but the arguments are still checked (a string label, a
## callable function, a mandatory reference).
global uiFlag = true
func uiAction() end
ui.button("Action", uiAction)
ui.checkbox("Option", ref uiFlag)

## A slider initialises the bound variable when it is nil, to the default, otherwise to min.
global uiVal = nil
ui.slider("Size", ref uiVal, 0, 1, 0.25)
assert(uiVal == 0.25)
global uiVal2 = 7
ui.slider("Other", ref uiVal2, 1, 10)
assert(uiVal2 == 7)

var uiMenu = ui.menu("Settings")
uiMenu.checkbox("Option", ref uiFlag)
var uiSub = uiMenu.menu("Display")
uiSub.button("Action", uiAction)
uiSub.slider("Zoom", ref uiVal, 0, 2)
ui.show(uiMenu)
uiSub.open()
ui.back()
uiSub.remove()
uiMenu.clear()
ui.show(nil)
ui.open()
ui.toggle()
ui.close()
ui.clear()
