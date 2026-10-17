## The lexer animation (docs/samples/lexer) runs a copy of src/lexer.cpp written in Ollin. This test
## holds that copy to the engine's lexer: every expected token below was checked against the C++
## lexer's own output, so a drift in either one shows here.
import "../docs/samples/lexer/tracer.ol"
import "trace_path.ol"

## The tokens of a program, as "TYPE:lexeme" separated by spaces.
func cut(source)
    return trace(source).tokens.map(func(tok) return tok.type + ":" + tok.lexeme end).join(" ")
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
assert(cut("a ## gone" + NEWLINE + "b") == "IDENTIFIER:a IDENTIFIER:b EOF_T:")
assert(cut("a ### gone" + NEWLINE + "still ### b") == "IDENTIFIER:a IDENTIFIER:b EOF_T:")

## a string with no hole is one token; a hole cuts it, and a second lexer reads the hole
assert(cut(QUOTE + "plain" + QUOTE) == "STRING:plain EOF_T:")
assert(cut(QUOTE + "n = \{x}!" + QUOTE) == "INTERP_START:n =  IDENTIFIER:x INTERP_END:! EOF_T:")
assert(cut(QUOTE + "\{a}\{b}" + QUOTE) == "INTERP_START: IDENTIFIER:a INTERP_MID: IDENTIFIER:b INTERP_END: EOF_T:")
assert(cut(QUOTE + "pi \{x:.2f}" + QUOTE) == "INTERP_START:pi  IDENTIFIER:__fmt LPAREN:( IDENTIFIER:x COMMA:, STRING:.2f RPAREN:) INTERP_END: EOF_T:")
assert(cut(QUOTE + "a {} {1} b" + QUOTE) == "STRING:a {} {1} b EOF_T:")   ## positional slots stay in the text

## what the lexer refuses, and the message it gives
assert(failure("x = 3x") == "invalid number literal")
assert(failure("0xZ") == "invalid hexadecimal literal")
assert(failure("1_") == "invalid number literal")
assert(failure("a ** b") == "'**' no longer exists — use '^' for exponentiation")
assert(failure("1..2") == "invalid number literal")
assert(failure("a .. b") == "'..' is not valid syntax (use [a;b] for ranges)")
assert(failure(QUOTE + "open") == "unterminated string")
assert(failure(QUOTE + "a \{b") == "unclosed brace in interpolation")
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
## called it, then goes round the loop once more to find the end of the source. Each step is given as
## the function and how its line begins, so the test does not depend on where the lines sit in lexer.cpp.
func followsPath(source, expected)
    assertPath(trace(source).steps, CPP, expected)
end

followsPath("a", [
    "tokenize|std::vector<Token> Lexer", "tokenize|std::vector<Token> tokens", "tokenize|tokens.reserve",
    "tokenize|for (;;)", "tokenize|skip_whitespace();",
    "skip_whitespace|while (true)", "skip_whitespace|char c = peek();", "skip_whitespace|if (c != ' '",
    "skip_whitespace|return;",
    "tokenize|if (at_end())", "tokenize|char c = advance();", "tokenize|switch (c)",
    "tokenize|if (is_dec(c))", "tokenize|if (is_alpha(c)", "tokenize|emit(tokens, identifier());",
    "identifier|int start", "identifier|while (is_alnum", "identifier|std::string lex", "identifier|auto it",
    "identifier|return ",
    "tokenize|emit(tokens, identifier());", "tokenize|break;", "tokenize|skip_whitespace();",
    "skip_whitespace|while (true)", "skip_whitespace|char c = peek();", "skip_whitespace|if (c != ' '",
    "skip_whitespace|return;",
    "tokenize|if (at_end())", "tokenize|break;", "tokenize|emit(tokens,", "tokenize|return tokens;"])

## lexer.cpp has a `case` for each of these characters, and none of them may fall to the default and be
## refused: a case added to the engine and left out of the tracer would show here
for label, at in CASE_AT do
    if label.startsWith("case '") then
        var key = label.substr(7, #label - 8)
        if key == "\n" then
            key = NEWLINE
        end
        var error = trace(key).error
        assert(error == nil or not error.startsWith("unexpected character"), "the tracer has no case for {label}")
    end
end

## every step names a line that exists, a token points back at the step that made it, and the run
## ends on EOF_T or on an error
func checkTrace(source)
    var r = trace(source)
    var last = #r.chars + 1
    for k, s in r.steps do
        assert(s.p0 >= 1 and s.p0 <= last and s.p1 >= 1 and s.p1 <= last, "head out of the source at step {k}")
        assert(CPP.has(s.fn), "step {k} runs a function that is not shown: {s.fn}")
        assert(s.at >= 1 and s.at + s.span <= #CPP[s.fn].lines, "step {k} runs a line that does not exist")
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
checkTrace(QUOTE + "pi \{x:.2f} and \{y}" + QUOTE)
checkTrace("var ok = 1" + NEWLINE + "var 3x = 2")
checkTrace("a ### block" + NEWLINE + "comment ### b")
checkTrace("0x1F_FF 0b1 1e+5 .5")

## a hole is read by a second lexer, called from interp_string() and reading the same text; its
## tokens only reach the stream when interp_string() hands them over
var hole = checkTrace(QUOTE + "n = \{x}!" + QUOTE)
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
var lines = trace("a" + NEWLINE + "b" + NEWLINE + "c")
assert(lines.tokens[3].lexeme == "c" and lines.steps[lines.tokens[3].step].line == 3)

print("lexer trace ok")
