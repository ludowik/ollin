## The lexer animation (docs/samples/lexer) runs a copy of src/lexer.cpp written in Ollin. This test
## holds that copy to the engine's lexer: every expected token below was checked against the C++
## lexer's own output, so a drift in either one shows here.
import "../docs/samples/lexer/tracer.ol"

const Q = string.fromCode(34)
const NL = string.fromCode(10)

## The tokens of a program, as "TYPE:lexeme" separated by spaces.
func cut(source)
    var r = trace(source)
    var parts = []
    for tok in r.tokens do
        parts.push(tok.type + ":" + tok.lexeme)
    end
    return parts.join(" ")
end

func failure(source)
    return trace(source).error
end

## keywords come from the table, and a name is a name — "len" is also a method of every map, and the
## table lookup must not find that one
assert(cut("var len = nil") == "VAR:var IDENTIFIER:len EQUALS:= NIL:nil EOF_T:")
assert(cut("if x then end") == "IF:if IDENTIFIER:x THEN:then END:end EOF_T:")
assert(cut("keys values has delete") == "IDENTIFIER:keys IDENTIFIER:values IDENTIFIER:has IDENTIFIER:delete EOF_T:")

## a number keeps its digits only: no underscore, the prefix and the exponent in lower case
assert(cut("1_000") == "NUMBER:1000 EOF_T:")
assert(cut("0xFF_FF 0b1_0 0O17") == "NUMBER:0xFFFF NUMBER:0b10 NUMBER:0o17 EOF_T:")
assert(cut("1E+5 2e-3 .5 1.25") == "NUMBER:1e+5 NUMBER:2e-3 NUMBER:.5 NUMBER:1.25 EOF_T:")

## the next character decides between one token and two
assert(cut("a <> b >= c << d") == "IDENTIFIER:a NOT_EQUAL:<> IDENTIFIER:b GREATER_EQUAL:>= IDENTIFIER:c LSHIFT:<< IDENTIFIER:d EOF_T:")
assert(cut("= == + += / // /=") == "EQUALS:= EQUAL_EQUAL:== PLUS:+ PLUS_EQUAL:+= SLASH:/ SLASH_SLASH:// SLASH_EQUAL:/= EOF_T:")
assert(cut("f(...) . x") == "IDENTIFIER:f LPAREN:( DOT_DOT_DOT:... RPAREN:) DOT:. IDENTIFIER:x EOF_T:")
assert(cut("#a") == "HASH:# IDENTIFIER:a EOF_T:")

## a comment is dropped, a block comment included, and a line break is not a token
assert(cut("a ## gone" + NL + "b") == "IDENTIFIER:a IDENTIFIER:b EOF_T:")
assert(cut("a ### gone" + NL + "still ### b") == "IDENTIFIER:a IDENTIFIER:b EOF_T:")

## a string with no hole is one token; a hole cuts it, and a second lexer reads the hole
assert(cut(Q + "plain" + Q) == "STRING:plain EOF_T:")
assert(cut(Q + "n = \{x}!" + Q) == "INTERP_START:n =  IDENTIFIER:x INTERP_END:! EOF_T:")
assert(cut(Q + "\{a}\{b}" + Q) == "INTERP_START: IDENTIFIER:a INTERP_MID: IDENTIFIER:b INTERP_END: EOF_T:")
assert(cut(Q + "pi \{x:.2f}" + Q) == "INTERP_START:pi  IDENTIFIER:__fmt LPAREN:( IDENTIFIER:x COMMA:, STRING:.2f RPAREN:) INTERP_END: EOF_T:")
assert(cut(Q + "a {} {1} b" + Q) == "STRING:a {} {1} b EOF_T:")   ## positional slots stay in the text

## what the lexer refuses, and the message it gives
assert(failure("x = 3x") == "invalid number literal")
assert(failure("0xZ") == "invalid hexadecimal literal")
assert(failure("1_") == "invalid number literal")
assert(failure("a ** b") == "'**' no longer exists — use '^' for exponentiation")
assert(failure("1..2") == "invalid number literal")
assert(failure("a .. b") == "'..' is not valid syntax (use [a;b] for ranges)")
assert(failure(Q + "open") == "unterminated string")
assert(failure(Q + "a \{b") == "unclosed brace in interpolation")
assert(failure("### open") == "unterminated block comment")
assert(failure("x = $") == "unexpected character '$'")
assert(failure("var ok = 1") == nil)

## every `case` of the switch, and so every line the dispatch names, runs at least once
assert(cut("= == + += - -= * *= / /= // % %= > >= >> < <= <> << & | ^ ~ \{ } [ ] ( ) , : ; ? . ... #x")
       == "EQUALS:= EQUAL_EQUAL:== PLUS:+ PLUS_EQUAL:+= MINUS:- MINUS_EQUAL:-= STAR:* STAR_EQUAL:*= SLASH:/ SLASH_EQUAL:/= "
       + "SLASH_SLASH:// PERCENT:% PERCENT_EQUAL:%= GREATER:> GREATER_EQUAL:>= RSHIFT:>> LESS:< LESS_EQUAL:<= NOT_EQUAL:<> "
       + "LSHIFT:<< AMP:& PIPE:| CARET:^ TILDE:~ LBRACE:\{ RBRACE:} LBRACKET:[ RBRACKET:] LPAREN:( RPAREN:) COMMA:, COLON:: "
       + "SEMICOLON:; QUESTION:? DOT:. DOT_DOT_DOT:... HASH:# IDENTIFIER:x EOF_T:")
assert(cut("0b1 0o7 1e5 1_2.5 a.b") == "NUMBER:0b1 NUMBER:0o7 NUMBER:1e5 NUMBER:12.5 IDENTIFIER:a DOT:. IDENTIFIER:b EOF_T:")

## the trace itself, line by line. `a` is the shortest program with a token: the lexer reads its way
## through tokenize() to the default case, steps into identifier() and comes back to the line that
## called it, then goes round the loop once more to find the end of the source.
func path(source)
    var r = trace(source)
    var parts = []
    for s in r.steps do
        parts.push(s.fn + ":" + s.at)
    end
    return parts.join(" ")
end

assert(path("a") == "tokenize:1 tokenize:2 tokenize:3 tokenize:5 tokenize:6 skip_whitespace:2 skip_whitespace:3 "
       + "skip_whitespace:4 skip_whitespace:5 tokenize:7 tokenize:10 tokenize:11 tokenize:125 tokenize:129 "
       + "tokenize:130 identifier:2 identifier:3 identifier:5 identifier:6 identifier:7 tokenize:130 tokenize:131 "
       + "tokenize:6 skip_whitespace:2 skip_whitespace:3 skip_whitespace:4 skip_whitespace:5 tokenize:7 "
       + "tokenize:8 tokenize:138 tokenize:139")

## every step names a line that exists, a token points back at the step that made it, and the run
## ends on EOF_T or on an error
func checkTrace(source)
    var r = trace(source)
    var last = #r.chars + 1
    for k, s in r.steps do
        assert(s.p0 >= 1 and s.p0 <= last and s.p1 >= 1 and s.p1 <= last, "head out of the source at step {k}")
        assert(CPP.has(s.fn), "step {k} runs a function that is not shown: {s.fn}")
        assert(s.at >= 1 and s.at + (s.span or 0) <= #CPP[s.fn].lines, "step {k} runs a line that does not exist")
        assert(s.stack.startsWith("tokenize") and s.stack.endsWith(s.fn), "step {k} is not on top of its own call stack")
    end
    for tok in r.tokens do
        assert(r.steps[tok.step].tok == tok, "token {tok.type} does not point at its step")
    end
    if r.error then
        assert(r.steps[#r.steps].err == r.error, "the error is not the last step")
    else
        assert(r.tokens[#r.tokens].type == "EOF_T", "the tokens do not end on EOF_T")
    end
    return r
end

checkTrace("var total = 1_200 + x")
checkTrace("if n >= .5 then ## small")
checkTrace(Q + "n = \{x}!" + Q)
checkTrace(Q + "pi \{x:.2f} and \{y}" + Q)
checkTrace("var ok = 1" + NL + "var 3x = 2")
checkTrace("a ### block" + NL + "comment ### b")
checkTrace("0x1F_FF 0b1 1e+5 .5")

## a hole is read by a second lexer, called from interp_string() and reading the same text; its
## tokens only reach the stream when interp_string() hands them over
var hole = checkTrace(Q + "n = \{x}!" + Q)
var nested = false
for s in hole.steps do
    if s.stack == "tokenize > interp_string > tokenize" then
        nested = true
    end
end
assert(nested, "no step runs the second lexer")
var handed = hole.steps[hole.tokens[2].step]
assert(hole.tokens[2].lexeme == "x" and handed.fn == "interp_string" and handed.stack == "tokenize > interp_string")

## without a string, the read head moves on from where the previous step left it
var chain = trace("var total = 1_200 + x * .5 ## end")
for k = 2, #chain.steps do
    assert(chain.steps[k].p0 == chain.steps[k - 1].p1, "the head jumps between steps {k - 1} and {k}")
end

## the line is the one the lexer counts
var lines = trace("a" + NL + "b" + NL + "c")
assert(lines.tokens[3].lexeme == "c" and lines.steps[lines.tokens[3].step].line == 3)

print("lexer trace ok")
