## Regression tests — The string module.
## Each block locks down one precise bug. Run: ./build/ollin tests/regressions/modules/string.ol — it must finish without error.

## ── string and math: the double-to-int cast is guarded (undefined behaviour, and a WASM trap, on a huge index before) ──
assert(string.char("abc", 1e300) == "")         ## an index out of range gives "", and does not trap
assert(string.char("abc", math.sqrt(-1)) == "") ## NaN
assert(string.substr("hello", 1e300) == "")
assert(string.substr("hello", 2, 1e300) == "ello")  ## a huge len is clamped
assert(string.char("abc", 2) == "b")            ## the ordinary case
global str_c = "none"
try
    var r = math.randInt(1e300)                ## an argument out of int64 range gives a clear error
catch e
    str_c = "x"
end
assert(str_c == "x")

func fndTail(...)
    var a, b = string.find("hello world", ...)
    return "{a}/{b}"
end

class JoinPt
    func init(n)
        self.n = n
    end
    func __str()
        return "PT{self.n}"
    end
end

## ── string: indexing by CHARACTER (a UTF-8 codepoint), not by byte ─────────
assert(len("café") == 4)                     ## four characters (é takes two bytes)
assert(len("héllo") == 5)
assert(len("a€b") == 3)                       ## € takes three bytes, and is one character
assert(string.char("café", 4) == "é")        ## before: a fragment of a byte
assert(string.char("a€b", 2) == "€")
assert(string.substr("café", 1, 3) == "caf")
assert(string.substr("café", 4, 1) == "é")
assert(string.substr("héllo", 2, 2) == "él")
assert(len("hello") == 5)                     ## ASCII unchanged
assert(string.char("café", 9) == "")         ## out of bounds gives ""
## upper and lower: ASCII plus accented Latin-1; trim works by codepoint
assert(string.upper("café") == "CAFÉ")
assert(string.lower("ÉÀÙÇ") == "éàùç")
assert(string.upper("straße") == "STRASSE")  ## ß → SS
assert(string.trim("··café··", "·") == "café")  ## trim works by codepoint (· takes two bytes)
assert(string.rtrim("«café»", "»") == "«café")
## string.find: a literal search rendering TWO indices, the start and the one just PAST the
## match, both in codepoints. Grouped in a function, not at the top level: this file has no
## registers to spare up there.

## string.split: a literal split that ALWAYS gives an array, so a text without the separator
## loops like any other. Grouped in a function for the same reason as fndCheck above.

## array.join: the inverse of split. The conversion is BASIC and calls nothing back — an
## instance wears its class name and its __str is NEVER run, unlike print's.

## string.number: the LEXER reads the text, so every form the language accepts is accepted
## here, and number_from_lexeme says what it is worth — the same reading a literal of the source
## gets. Nothing else is a number, and nil says so.

## string.replace: a literal replacement rendering the text AND the count. The search resumes
## after the inserted text, which is what keeps a growing replacement from looping for ever.

## string.startsWith / endsWith: a plain yes or no, case sensitive, and REAL booleans — so `not`
## applies and no comparison to true is needed.

## Every string-module check in ONE function. Each section keeps its own scope in a `do` block, so the
## same short names can be reused from one to the next.
func stringCheck()
    do
        ## It is the only way to locate a substring, and the pair is what composes with substr.
        var fnd_a, fnd_b = string.find("hello world", "wor")
        assert(fnd_a == 7 and fnd_b == 10)
        var fnd_s = "hello world"
        var fnd_p, fnd_q = fnd_s.find("world")
        assert(fnd_s.substr(1, fnd_p - 1) + "there" + fnd_s.substr(fnd_q) == "hello there")
        ## in CODEPOINTS, not bytes: a byte index would put "au" at 7 and "é" at 5
        var fnd_c, fnd_d = string.find("café au lait", "au")
        assert(fnd_c == 6 and fnd_d == 8)
        var fnd_e, fnd_g = string.find("café", "é")
        assert(fnd_e == 4 and fnd_g == 5)
        assert(string.find("hello", "zz") == nil)     ## absent: nil, a single value
        assert(string.find("abc", "abcd") == nil)     ## a needle longer than the string
        assert(string.find("abc", "c", 99) == nil)    ## a start past the end
        var fnd_h, fnd_i = string.find("hello", "l", 4)
        assert(fnd_h == 4 and fnd_i == 5)             ## the search starts at `from`
        var fnd_j, fnd_k = string.find("aaa", "aa")
        assert(fnd_j == 1 and fnd_k == 3)             ## overlapping matches: the FIRST one
        var fnd_l, fnd_m = string.find("abc", "")
        assert(fnd_l == 1 and fnd_m == 1)             ## an empty needle: the insertion point, no width
        var fnd_n, fnd_o = string.find("abc", "", 9)
        assert(fnd_n == 4 and fnd_o == 4)             ## clamped to just past the last character
        ## Both values survive when the call is the TAIL of a variadic one — the only builtin returning
        ## two values that a build without graphics can reach, so the only place tests/run.sh can check it
        assert(fndTail("wor") == "7/10")
    end

    do
        var a = string.split("a,b,c", ",")
        assert(a.len() == 3 and a[1] == "a" and a[2] == "b" and a[3] == "c")
        var b = "nom: Ollin".split(": ")          ## a multi-character separator
        assert(b.len() == 2 and b[1] == "nom" and b[2] == "Ollin")
        var c = string.split("abc", "|")          ## absent: one piece, the whole text
        assert(c.len() == 1 and c[1] == "abc")
        ## Empty pieces are KEPT — dropping them would lose an empty column in silence, and it is what
        ## makes splitting and rejoining give the text back.
        var d = string.split("a,,b", ",")
        assert(d.len() == 3 and d[1] == "a" and d[2] == "" and d[3] == "b")
        var e = string.split("a,", ",")
        assert(e.len() == 2 and e[2] == "")
        var f = string.split(",a", ",")
        assert(f.len() == 2 and f[1] == "")
        var g = string.split("", ",")             ## always an array: one empty piece
        assert(g.len() == 1 and g[1] == "")
        ## max bounds the number of pieces, and the LAST one keeps the whole remainder
        var h = string.split("k=a=b", "=", 2)
        assert(h.len() == 2 and h[1] == "k" and h[2] == "a=b")
        var i = string.split("a,b,c", ",", 1)
        assert(i.len() == 1 and i[1] == "a,b,c")
        var j = string.split("a,b,c", ",", 0)     ## below 1 is clamped to 1, as find clamps `from`
        assert(j.len() == 1 and j[1] == "a,b,c")
        var k = string.split("a,b,c", ",", 99)    ## a max beyond the count changes nothing
        assert(k.len() == 3)
        ## a separator of several bytes, and pieces carrying accents
        var l = string.split("café→thé", "→")
        assert(l.len() == 2 and l[1] == "café" and l[2] == "thé")
        var m = string.split("aaa", "aa")         ## overlapping: the FIRST match, then the remainder
        assert(m.len() == 2 and m[1] == "" and m[2] == "a")
    end

    do
        assert(["a", "b", "c"].join(" | ") == "a | b | c")
        assert([1, 2, 3].join(", ") == "1, 2, 3")       ## numbers convert, as print shows them
        assert(["a", "b"].join() == "ab")               ## no separator: the pieces end to end
        assert([].join(", ") == "")                     ## an empty array gives an empty text
        assert(["seul"].join(", ") == "seul")           ## one element: no separator anywhere
        assert([nil, true, false].join("/") == "nil/true/false")
        ## split then join with the same separator gives the text back — that is why split keeps its
        ## empty pieces.
        assert("a,,b,c".split(",").join(",") == "a,,b,c")
        assert("x=1".split("=").join("=") == "x=1")
        ## A value that is not text wears its label, the same one print uses for it.
        assert([{}, [1]].join(" ") == "\{map} \{array}")
        ## And an INSTANCE wears its class name: join never runs the script's __str, which is the
        ## whole point — no Ollin code executes inside it, so the register file cannot move under it.
        assert([JoinPt(1), JoinPt(2)].join(" ") == "\{JoinPt} \{JoinPt}")
        assert("{JoinPt(1)}" == "PT1")                  ## interpolation, itself, DOES call __str
    end

    do
        assert(string.number("42") == 42)
        assert(string.number("-3.5") == -3.5)
        assert(string.number("+7") == 7)
        assert(string.number(" 42 ") == 42)          ## surrounding spaces are tolerated
        assert(string.number("1e3") == 1000)
        assert(string.number(".5") == 0.5)
        ## the bases and the digit separator of the language, for free and by construction
        assert(string.number("0xFF") == 255)
        assert(string.number("0o17") == 15)
        assert(string.number("0b101") == 5)
        assert(string.number("1_000") == 1000)
        ## INTEGER when the value is whole, so it indexes an array and matches an integer key
        var tbl = [10, 20, 30]
        assert(tbl[string.number("2")] == 20)
        var mp = {}
        mp[7] = "sept"
        assert(mp[string.number("7")] == "sept")
        ## All or nothing: a prefix would let a typo pass for data.
        assert(string.number("42abc") == nil)
        assert(string.number("bonjour") == nil)
        assert(string.number("") == nil)
        assert(string.number("1 2") == nil)          ## two numbers is not one number
        assert(string.number("--3") == nil)
        assert(string.number("4-2") == nil)
        assert(string.number("@") == nil)            ## the lexer refuses it: nil, not an error
        assert(string.number("0x") == nil)
        assert(string.number("99999999999999999999999") == nil)  ## out of range is a failure, not a crash
        ## what it is for: reading the pieces of a split
        var total = 0
        for piece in "10, 20, 30".split(",") do
            total = total + piece.number()
        end
        assert(total == 60)
    end

    do
        var a, an = string.replace("a-b-c", "-", " ")
        assert(a == "a b c" and an == 2)
        var b, bn = string.replace("hello", "l", "")     ## an empty replacement deletes
        assert(b == "heo" and bn == 2)
        var c, cn = string.replace("abc", "z", "!")      ## no match: the text back, and 0
        assert(c == "abc" and cn == 0)
        var d, dn = string.replace("", "x", "y")
        assert(d == "" and dn == 0)
        ## Overlapping: the search resumes AFTER the match, so "aaa" holds one "aa" and a leftover.
        var e, en = string.replace("aaa", "aa", "X")
        assert(e == "Xa" and en == 1)
        ## And it resumes after the INSERTED text, never inside it — otherwise this would never end.
        var f, fn = string.replace("a", "a", "aa")
        assert(f == "aa" and fn == 1)
        var g, gn = string.replace("x-y", "-", "--")     ## a replacement longer than the needle
        assert(g == "x--y" and gn == 1)
        ## max bounds the count; at or below zero it gives the text back, and is NOT clamped to 1 as
        ## split clamps it — zero replacements is a clear request, zero pieces is not.
        var h, hn = string.replace("key=a=b", "=", ": ", 1)
        assert(h == "key: a=b" and hn == 1)
        var i, iin = string.replace("a-b-c", "-", " ", 0)
        assert(i == "a-b-c" and iin == 0)
        var j, jn = string.replace("a-b-c", "-", " ", -5)
        assert(j == "a-b-c" and jn == 0)
        var k, kn = string.replace("a-b-c", "-", " ", 99)
        assert(k == "a b c" and kn == 2)
        ## a needle of several bytes, and the text around it kept intact
        var l, ln = string.replace("café→thé", "→", " | ")
        assert(l == "café | thé" and ln == 1)
        ## Taking only the first value is the common form, and the source is untouched.
        var src = "garde"
        assert(src.replace("a", "A") == "gArde")
        assert(src == "garde")
    end

    do
        assert("config.ol".endsWith(".ol"))
        assert(not "config.ol".endsWith(".OL"))       ## case sensitive
        assert("A.OL".lower().endsWith(".ol"))        ## how to ignore the case: one rule, no parameter
        assert("image.png".startsWith("image"))
        assert(not "image.png".startsWith("img"))
        assert("abc".startsWith("abc") and "abc".endsWith("abc"))   ## the whole text counts
        ## An empty prefix or suffix is TRUE: every text begins and ends with nothing. Unlike split
        ## and replace, where an empty needle leaves the RESULT undefined, the answer is defined here.
        assert("abc".startsWith("") and "abc".endsWith(""))
        assert("".startsWith(""))
        ## Longer than the text: false, not a read past the end.
        assert(not "ab".startsWith("abc"))
        assert(not "ab".endsWith("abc"))
        assert(not "".endsWith("x"))
        ## Bytes are compared, which is exact at both ends: "é" is two bytes and its last one is not
        ## 'e', so a text ending in "é" does not end in "e".
        assert("café".endsWith("é"))
        assert(not "café".endsWith("e"))
        assert("→abc".startsWith("→"))
        ## startsWith only names what find already answered, and the two agree.
        assert("abc".startsWith("ab") == ("abc".find("ab") == 1))
        ## a real boolean, not 1 or 0
        assert("{"x.ol".endsWith(".ol")}" == "true")
    end
end
stringCheck()

## string.len: a length in codepoints, on strings only, unlike the polymorphic global len
assert(string.len("café") == 4)               ## é takes two bytes, and is one character
assert(string.len("a€b") == 3)                ## € takes three bytes, and is one character
assert(string.len("") == 0)
assert(string.len("hello") == len("hello"))   ## consistent with the global len on a string
global str_len_err = "none"
try
    string.len([1, 2, 3])                     ## a non-string is an error, unlike the global len
catch e
    str_len_err = "caught"
end
assert(str_len_err == "caught")

## ---------------------------------------------------------------------------
## A string iterates over its CHARACTERS, not its bytes: an accented text has
## fewer characters than bytes, and taking one byte at a time would cut a
## codepoint in half. The two forms match what an array gives — the value
## alone, or the 1-based index and the value.
func strIterCheck()
    var pieces = ""
    for c in "café" do
        pieces += "[" + c + "]"
    end
    assert(pieces == "[c][a][f][é]")   ## 5 bytes, 4 characters

    var seen = ""
    var last = 0
    for i, c in "héllo" do
        seen += c
        last = i
    end
    assert(seen == "héllo")
    assert(last == 5)                  ## the index counts characters, like len

    ## An empty text is an empty loop, not one turn on "".
    var turns = 0
    for c in "" do
        turns += 1
    end
    assert(turns == 0)

    ## The characters are the same ones char() gives, and there are len() of them.
    var text = "aéb"
    var n = 0
    for i, c in text do
        assert(c == text.char(i))
        n += 1
    end
    assert(n == text.len())

    ## break and continue behave as in any other for-in.
    var upTo = ""
    for c in "abcdef" do
        if c == "d" then break end
        upTo += c
    end
    assert(upTo == "abc")

    ## The loop reads a COPY of the reference, so a variable reassigned during the
    ## loop does not change what is being walked.
    var moving = "abc"
    var walked = ""
    for c in moving do
        moving = "xyz"
        walked += c
    end
    assert(walked == "abc")

    ## One closure per iteration, as for every other for-in.
    var fns = []
    for c in "ab" do
        fns.push(func() return c end)
    end
    assert(fns[1]() == "a" and fns[2]() == "b")
    print("string iteration ok")
end
strIterCheck()

## ---------------------------------------------------------------------------
## string.code gives the Unicode number of a CHARACTER, and nil — never 0 —
## when there is no character there: 0 is a legitimate codepoint and it is
## falsy, so returning it would confuse "a NUL" with "nothing".
func strCodeCheck()
    assert("A".code() == 65)
    assert("é".code() == 233)          ## two bytes, one character
    assert("abc".code(2) == 98)        ## the index counts characters, 1-based

    ## Out of bounds, both ends, and the empty text.
    assert("abc".code(4) == nil)
    assert("abc".code(0) == nil)
    assert("abc".code(-1) == nil)
    assert("".code() == nil)

    ## Accented text: the index is in characters, so code and char agree.
    var text = "café"
    for i, c in text do
        assert(c.code() == text.code(i))
    end
    assert(text.code(4) == 233)        ## é, the 4th CHARACTER of a 5-byte text

    ## The round trip with char: same character, same number.
    assert(text.char(1).code() == text.code(1))

    print("string.code ok")
end
strCodeCheck()

## ---------------------------------------------------------------------------
## string.fromCode is the exact inverse of string.code, and it builds a whole
## word in one call. Anything that is not a codepoint is refused, and nothing
## is built when one argument is wrong — a half-written text would be worse.
func strFromCodeCheck()
    assert(string.fromCode(65) == "A")
    assert(string.fromCode(233) == "é")        ## one character, two bytes
    assert(string.fromCode(233).len() == 1)
    assert(string.fromCode(72, 105, 33) == "Hi!")

    ## The round trip, on a text where a character is not a byte.
    var text = "café"
    for i, c in text do
        assert(string.fromCode(text.code(i)) == c)
    end

    ## The codepoint 0 is a real character, one character long — which is why
    ## code() answers nil rather than 0 when there is none.
    assert(string.fromCode(0).len() == 1)

    ## The refusals leave nothing behind: the text is not half built.
    var caught = 0
    try
        string.fromCode(72, 0xD800)
    catch e
        caught = 1
    end
    assert(caught == 1)

    ## The two ends of the valid range are accepted.
    assert(string.fromCode(0x10FFFF).len() == 1)
    assert(string.fromCode(0xD7FF).len() == 1)  ## just below the surrogates
    assert(string.fromCode(0xE000).len() == 1)  ## just above them
    print("string.fromCode ok")
end
strFromCodeCheck()

## ---------------------------------------------------------------------------
## string.repeat lays a text end to end, with an optional separator BETWEEN the
## copies and not after the last. A count of zero or below is "" and not an
## error: a computed padding reaches zero without anything being wrong.
func strRepeatCheck()
    assert("ab".repeat(3) == "ababab")
    assert("ab".repeat(3, "-") == "ab-ab-ab")   ## two separators for three copies
    assert("ab".repeat(1, "-") == "ab")         ## none for a single copy

    assert("x".repeat(0) == "")
    assert("x".repeat(-5) == "")
    assert("x".repeat(0, "-") == "")            ## no separator without a copy
    assert("".repeat(4) == "")
    assert("".repeat(4, "-") == "---")          ## the separators remain

    ## Characters, not bytes: a two-byte character is repeated whole.
    assert("é".repeat(3) == "ééé")
    assert("é".repeat(3).len() == 3)

    ## The ceiling is on the RESULT, separators included, and it refuses rather
    ## than asking the allocator for something absurd.
    var caught = 0
    try
        string.repeat("x", 2000000)
    catch e
        caught = 1
    end
    assert(caught == 1)
    assert(string.repeat("x", 1048576).len() == 1048576)   ## exactly at the ceiling
    print("string.repeat ok")
end
strRepeatCheck()
