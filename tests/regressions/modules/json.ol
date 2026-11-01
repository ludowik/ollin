## Regression tests — The json module.
## Run: ./build/ollin tests/regressions/modules/json.ol — it must finish without error.
## A string literal cannot hold a double quote, so the texts are written with ' and turned into " by q().

func q(t)
    return t.replace("'", string.fromCode(34))
end

const NL = string.fromCode(10)
const TAB = string.fromCode(9)
const QUOTE = string.fromCode(34)

## Catches an error and returns its message, nil when there is none.
func failure(f)
    var message = nil
    try
        f()
    catch e
        message = e
    end
    return message
end

## ── parse: the types of the language ───────────────────────────────────────
assert(json.parse("42") == 42 and typeof(json.parse("42")) == "int")
assert(json.parse("-7") == -7 and json.parse("-0") == 0)
assert(json.parse("2.5") == 2.5 and typeof(json.parse("2.5")) == "float")
assert(json.parse("1e2") == 100 and json.parse("-3E-1") == -0.3 and json.parse("1.5e+1") == 15)
assert(typeof(json.parse("99999999999999999999")) == "float", "an integer too large for 64 bits is read as a float")
assert(json.parse("true") == true and json.parse("false") == false and json.parse("null") == nil)
assert(json.parse(q("'abc'")) == "abc" and json.parse(q("''")) == "")
assert(len(json.parse("  {NL}{TAB} [ ] ")) == 0 and len(json.parse(" \{}")) == 0)

## ── parse: strings ─────────────────────────────────────────────────────────
assert(json.parse(q("'a\\b'")) == "a\b", "a backslash")
assert(json.parse(q("'\u00e9\u00E9'")) == "éé", "\\u gives UTF-8")
assert(json.parse(q("'\ud83d\ude00'")) == "😀", "a surrogate pair is ONE code point")
assert(json.parse(q("'\u0041\/'")) == "A/")
assert(json.parse(q("'tab\there'")) == "tab" + TAB + "here")
assert(json.parse(q("'a\nb'")) == "a" + NL + "b")
assert(json.parse(q("'\") + QUOTE + q("'")) == QUOTE, "an escaped quote")
assert(json.parse(q("'caf") + "é" + q("'")) == "café", "UTF-8 text goes through as it is")

## ── parse: containers ──────────────────────────────────────────────────────
var doc = json.parse(q("\{'name': 'Paris', 'coords': [48.85, 2.35], 'tags': \{'a': true, 'b': null}, 'n': 3}"))
assert(doc.name == "Paris" and doc.coords[1] == 48.85 and doc.coords[2] == 2.35 and len(doc.coords) == 2)
assert(doc.tags.a == true and doc.n == 3)
assert(not doc.tags.has("b"), "a null in a map is not stored: a map holds no nil")
var holes = json.parse("[1, null, 3]")
assert(len(holes) == 3 and holes[1] == 1 and holes[2] == nil and holes[3] == 3, "a null in an array keeps its place")
var deep = json.parse(string.repeat("[", 150) + string.repeat("]", 150))
assert(len(deep) == 1)

## ── parse: what it refuses, and where ──────────────────────────────────────
assert(failure(func() json.parse("[1, 2") end) == "json.parse: expected ',' or ']' at position 6")
assert(failure(func() json.parse(q("\{'a' 1}")) end) == "json.parse: expected ':' at position 6")
assert(failure(func() json.parse("") end) == "json.parse: unexpected end of text at position 1")
assert(failure(func() json.parse("1 2") end) == "json.parse: unexpected text after the value at position 3")
assert(failure(func() json.parse("tru") end) == "json.parse: unexpected character 't' at position 1")
assert(failure(func() json.parse("01") end) == "json.parse: unexpected text after the value at position 2", "no leading zero")
assert(failure(func() json.parse("1.") end) == "json.parse: bad number at position 3")
assert(failure(func() json.parse("-") end) == "json.parse: bad number at position 2")
assert(failure(func() json.parse(q("'abc")) end) == "json.parse: unterminated string at position 5")
assert(failure(func() json.parse(q("'\x'")) end) == "json.parse: bad escape at position 3")
assert(failure(func() json.parse(q("'\ud83d'")) end) == "json.parse: lone surrogate at position 8")
assert(failure(func() json.parse(q("'\ude00'")) end) == "json.parse: lone surrogate at position 8")
assert(failure(func() json.parse(q("'\u00zz'")) end) == "json.parse: bad \u escape at position 6")
assert(failure(func() json.parse(q("'a") + NL + q("b'")) end) == "json.parse: control character in string at position 3")
assert(failure(func() json.parse("[1,]") end) == "json.parse: unexpected character ']' at position 4")
assert(failure(func() json.parse(string.repeat("[", 300)) end) == "json.parse: nested too deeply at position 202")
assert(failure(func() json.parse(5) end) == "json.parse: expected string")
assert(failure(func() json.parse() end) == "json.parse: missing argument")

## ── stringify: values ──────────────────────────────────────────────────────
assert(json.stringify(nil) == "null" and json.stringify(true) == "true" and json.stringify(false) == "false")
assert(json.stringify(7) == "7" and json.stringify(-2) == "-2" and json.stringify(0.1) == "0.1")
assert(json.stringify(2.5) == "2.5" and json.stringify(1e300) == "1e+300")
assert(json.stringify("a") == q("'a'") and json.stringify("") == q("''"))
assert(json.stringify([]) == "[]" and json.stringify({}) == "{}")
assert(json.stringify([1, nil, "x"]) == q("[1,null,'x']"), "a nil in an array is written null")

## ── stringify: strings are escaped ─────────────────────────────────────────
var tricky = "a" + QUOTE + "b\c" + NL + TAB + string.fromCode(1) + "é"
var written = q("'a\") + QUOTE + q("b\\c\n\t\u0001é'")
assert(json.stringify(tricky) == written)

## ── stringify: maps have sorted keys, and indentation ──────────────────────
assert(json.stringify({b: 1, a: [1, 2], c: {z: true, y: "t"}}) == q("\{'a':[1,2],'b':1,'c':\{'y':'t','z':true}}"))
assert(json.stringify({b: 1, a: [1, 2]}, 2) == q("\{{NL}  'a': [{NL}    1,{NL}    2{NL}  ],{NL}  'b': 1{NL}}"))
assert(json.stringify([[]], 2) == "[{NL}  []{NL}]", "an empty container stays on one line")
assert(json.stringify([1, {a: 2}], 4).split(NL)[3] == "    \{", "four spaces a level")
assert(json.stringify({a: 1}, nil) == q("\{'a':1}"), "a nil indent is no indent")

## An instance is written by its fields, not by its class.
class Pt
    func init(x, y)
        self.x = x
        self.y = y
    end
end
assert(json.stringify(Pt(1, 2)) == q("\{'x':1,'y':2}"))

## ── stringify: what it refuses ─────────────────────────────────────────────
assert(failure(func() json.stringify(func() return 1 end) end) == "json.stringify: cannot write a function")
assert(failure(func() json.stringify({[1]: 2}) end) == "json.stringify: a map key must be a string, got int")
assert(failure(func() json.stringify(math.sqrt(-1)) end) == "json.stringify: a number that is not finite has no JSON form")
assert(failure(func() json.stringify([1], 17) end) == "json.stringify: indent must be a whole number from 0 to 16")
assert(failure(func() json.stringify([1], 1.5) end) == "json.stringify: indent must be a whole number from 0 to 16")
assert(failure(func() json.stringify([1], "2") end) == "json.stringify: argument 2 expected number, got string")
assert(failure(func() json.stringify() end) == "json.stringify: missing argument")
var cyc = {}
cyc.me = cyc
assert(failure(func() json.stringify(cyc) end) == "json.stringify: nested too deeply (or the value contains itself)")
cyc.me = nil

## ── A round trip gives back the value ──────────────────────────────────────
var original = {title: "Météo", days: [{t: 12.5, rain: false}, {t: -3, rain: true}], note: "line" + NL + "two"}
var again = json.parse(json.stringify(original))
assert(again.title == "Météo" and again.days[1].t == 12.5 and again.days[2].t == -3 and again.days[2].rain == true)
assert(again.note == original.note and json.stringify(again) == json.stringify(original))
assert(json.stringify(json.parse(json.stringify(original, 3))) == json.stringify(original), "indentation changes nothing")
