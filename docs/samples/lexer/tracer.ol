## A copy of src/lexer.cpp that RECORDS every line it runs. trace(source) executes the engine's
## lexer rules on a program, one C++ line at a time, and returns the list of steps the animation
## replays — each step is the line the lexer is on — together with the tokens it produced.
## lexer_test.ol checks that the tokens are exactly the ones the C++ lexer gives, and
## tests/check_trace_source.sh that every line named below is the line of lexer.cpp it claims to be.
##
## Each call `self.run(function, index, "start of the line", {extras})` records one step: `index`
## counts the lines of that function in cpp_source.ol (generated from lexer.cpp), and the text is
## the beginning of the line, so a lexer.cpp that moved on is noticed instead of lighting up the
## wrong line. The helpers peek(), advance(), match(), at_end(), emit() and the is_* tests are
## stepped OVER, as a debugger's "next" would: their effect shows on the line that calls them.
##
## Verified beyond the tests, once, against the engine: lexer.cpp built with gcov ran every program
## of the repository and the number of times each line ran matched the number of steps on it, except
## where this file shows a line differently on purpose — a call line lit twice (when it calls and when
## it gets the result back), a `case` label (marked beside the statement it leads to), a brace. One
## real difference: the engine reads BYTES, this reads characters, so `pos` and the number of turns of
## a loop over accented text differ.
##
## A step is a map:
##   fn, at, span   the function and the line (and how many more lines the statement covers)
##   also           a second line to mark, the `case` label a switch jumped through
##   stack          the calls in progress: "tokenize > identifier"
##   p0, p1         the read head before and after the line: the position of the NEXT character
##   from, hl       the span of the lexeme being built (hl: where it ends, when not at the head)
##   drop           true while what is read is thrown away (blanks, comments)
##   made           the token this line builds, tok the same token when it reaches the final stream
##   err            the message when the lexer gives up
##   note           a sentence, on the lines that deserve one
##   c, w           the locals worth watching: c, and w = [name, value]
##   pos, line      the lexer's own pos (counted from 0 in its own text) and line

import "cpp_source.ol"

const KEYWORDS = {
    "var": "VAR", "global": "GLOBAL", "const": "CONSTANT", "while": "WHILE", "do": "DO",
    "if": "IF", "then": "THEN", "end": "END", "break": "BREAK", "continue": "CONTINUE",
    "true": "TRUE", "false": "FALSE", "try": "TRY", "catch": "CATCH", "throw": "THROW",
    "else": "ELSE", "elseif": "ELSEIF", "func": "FUNC", "return": "RETURN", "nil": "NIL",
    "or": "OR", "and": "AND", "not": "NOT", "for": "FOR", "in": "IN", "import": "IMPORT",
    "as": "AS", "class": "CLASS", "extends": "EXTENDS", "static": "STATIC", "switch": "SWITCH",
    "case": "CASE", "enum": "ENUM", "ref": "REF"
}

## The token types of the keywords, to ask whether a type is one.
func keywordTypesOf(table)
    var types = {}
    for word, ty in table do
        types[ty] = true
    end
    return types
end

const KEYWORD_TYPES = keywordTypesOf(KEYWORDS)

## One character, one token.
const SINGLE = {
    ",": "COMMA", "(": "LPAREN", ")": "RPAREN", ";": "SEMICOLON", "&": "AMP", "|": "PIPE",
    "^": "CARET", "~": "TILDE", "\{": "LBRACE", "}": "RBRACE", "[": "LBRACKET", "]": "RBRACKET",
    ":": "COLON", "?": "QUESTION"
}

## The types of a character that may be glued to the next one: the second characters it accepts, then
## the token it gives alone.
const PAIRS = {
    "=": {next: {"=": "EQUAL_EQUAL"}, alone: "EQUALS"},
    "+": {next: {"=": "PLUS_EQUAL"}, alone: "PLUS"},
    "-": {next: {"=": "MINUS_EQUAL"}, alone: "MINUS"},
    "%": {next: {"=": "PERCENT_EQUAL"}, alone: "PERCENT"},
    "/": {next: {"=": "SLASH_EQUAL", "/": "SLASH_SLASH"}, alone: "SLASH"},
    ">": {next: {"=": "GREATER_EQUAL", ">": "RSHIFT"}, alone: "GREATER"},
    "<": {next: {"=": "LESS_EQUAL", ">": "NOT_EQUAL", "<": "LSHIFT"}, alone: "LESS"}
}

const BASES = {x: "hexadecimal", o: "octal", b: "binary"}

## Ollin strings have no escapes: these characters are spelled by their code.
const QUOTE = string.fromCode(34)
const NEWLINE = string.fromCode(10)
const TAB = string.fromCode(9)
const CR = string.fromCode(13)
const BACKSLASH = string.fromCode(92)

## A program is written with an apostrophe where it needs a quote: Ollin strings have no escapes.
func unquote(text)
    return text.replace("'", QUOTE)
end

## A program to show: its name and its text, written with apostrophes.
func program(name, lines)
    return {name: name, source: unquote(lines.join(NEWLINE))}
end

## The text of C++ functions, from a table of cpp_source.ol: its quotes put back, the dashes and arrows
## the engine's font has no glyph for turned into ASCII, and each line trimmed. The parser example
## loads its own table the same way.
func loadCpp(table)
    var out = {}
    for name, f in table do
        var lines = []
        var trimmed = []
        for l in f.lines do
            var restored = l.replace("¤", QUOTE).replace("—", "-").replace("→", "->").replace("…", "...")
            lines.push(restored)
            trimmed.push(restored.trim())
        end
        out[name] = {first: f.first, lines: lines, trimmed: trimmed}
    end
    return out
end

global CPP = loadCpp(CPP_SOURCE)

## A line a tracer names must be the line of the C++ it claims to be. `cpp` is loadCpp's table.
func checkLine(cpp, fn, index, start)
    if not cpp[fn].trimmed[index].startsWith(start) then
        throw "{fn} line {index} is not '{start}': {cpp[fn].trimmed[index]}"
    end
end

## Where each `case` label of Lexer::tokenize, and its `default:`, is. Found by the text of the line.
func loadCases()
    var at = {}
    for i, l in CPP["tokenize"].trimmed do
        if l.startsWith("case '") or l == "default:" then
            at[l] = i
        end
    end
    return at
end

global CASE_AT = loadCases()

func isDec(c)
    return c >= "0" and c <= "9"
end

func isHex(c)
    return isDec(c) or (c >= "a" and c <= "f") or (c >= "A" and c <= "F")
end

func isAlpha(c)
    return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z")
end

func isAlnum(c)
    return isAlpha(c) or isDec(c)
end

## The name of a character in a sentence: a newline cannot be shown as itself.
func shown(c)
    if c == NEWLINE then
        return "the end of the line"
    elseif c == "" then
        return "the end of the source"
    elseif c == " " then
        return "a space"
    end
    return "'{c}'"
end

class Tracer
    ## `chars` is the source split into characters, shared with the nested lexers; this one reads the
    ## positions lo..hi, as a lexer built on that text alone would. `result` collects the steps and
    ## the final tokens, `stack` is the list of calls that led here.
    func init(chars, lo, hi, depth, line, result, stack)
        self.chars = chars
        self.lo = lo
        self.pos = lo
        self.hi = hi
        self.depth = depth
        self.line = line
        self.result = result
        self.stack = stack
        self.stackText = stack.join(" > ")
        self.tokens = []    ## the vector this lexer's tokenize() returns
        self.mark = lo      ## where the read head was when the last step was recorded
        self.from = nil     ## where the lexeme being built began
        self.drop = false
        self.c = nil
        self.w = nil
    end

    ## ── the C++ helpers, stepped over ────────────────────────────────────────

    func peek()
        if self.pos > self.hi then
            return ""
        end
        return self.chars[self.pos]
    end

    func atEnd()
        return self.pos > self.hi
    end

    func advance()
        var c = self.chars[self.pos]
        self.pos += 1
        return c
    end

    ## Consumes the next character when it is c, like Lexer::match.
    func accept(c)
        if self.peek() <> c then
            return false
        end
        self.pos += 1
        return true
    end

    ## The characters a..b-1.
    func text(a, b)
        if b <= a then
            return ""
        end
        return self.result.source.substr(a, b - a)
    end

    func enter(fn)
        self.stack.push(fn)
        self.stackText = self.stack.join(" > ")
    end

    func leave()
        self.stack.pop()
        self.stackText = self.stack.join(" > ")
        self.w = nil
    end

    ## ── recording ────────────────────────────────────────────────────────────

    ## Records the line `index` of function `fn`, which the lexer has just run. `start` is how that
    ## line begins: checked here, and by tests/check_trace_source.sh for every call.
    func run(fn, index, start, extra)
        checkLine(CPP, fn, index, start)
        var f = extra or {}
        f.fn = fn
        f.at = index
        f.span = f.span or 0
        f.stack = self.stackText
        f.line = self.line
        f.p0 = f.p0 or self.mark
        f.p1 = f.p1 or self.pos
        f.from = f.from or self.from
        f.drop = f.drop or self.drop
        f.c = self.c
        f.w = self.w
        f.pos = self.pos - self.lo
        self.mark = f.p1
        self.result.steps.push(f)
        return f
    end

    ## The line that files a token this lexer has built. The token goes into this lexer's own vector; a
    ## lexer at depth 0 owns the final stream, so there it reaches the animation too.
    func file(tok, fn, index, start, extra)
        self.tokens.push(tok)
        var f = extra or {}
        f.made = tok
        if self.depth == 0 then
            f.tok = tok
        end
        self.run(fn, index, start, f)
        if self.depth == 0 then
            tok.step = #self.result.steps
            tok.line = self.line
            self.result.tokens.push(tok)
        end
    end

    ## The line that hands the token just read to emit().
    func emit(fn, index, start, type, lexeme, extra)
        self.file({type: type, lexeme: lexeme, from: self.from, to: self.pos, depth: self.depth}, fn, index, start, extra)
    end

    func fail(fn, index, start, msg, extra)
        var f = extra or {}
        f.err = msg
        self.run(fn, index, start, f)
        throw "lexer error"
    end

    ## ── Lexer::skip_whitespace ───────────────────────────────────────────────

    func skipWhitespace()
        self.enter("skip_whitespace")
        self.from = self.pos
        self.drop = true
        self.run("skip_whitespace", 2, "while (true)")
        while true do
            var c = self.peek()
            self.run("skip_whitespace", 3, "char c = peek();")
            self.run("skip_whitespace", 4, "if (c != ' '")
            if not (c == " " or c == TAB or c == CR) then
                self.run("skip_whitespace", 5, "return;")
                break
            end
            self.advance()
            self.run("skip_whitespace", 6, "advance();")
        end
        self.leave()
        self.from = nil
        self.drop = false
    end

    ## ── Lexer::tokenize ──────────────────────────────────────────────────────

    ## The index of the line `case 'c':` in tokenize, or 0 when the switch has none.
    func caseLine(c)
        var key = c
        if c == NEWLINE then
            key = "\n"
        end
        var want = "case '" + key + "':"
        if CASE_AT.has(want) then
            return CASE_AT[want]
        end
        return 0
    end

    ## The first line from `index` on that starts with `start`.
    func lineFrom(index, start)
        var trimmed = CPP["tokenize"].trimmed
        for i = index, #trimmed do
            if trimmed[i].startsWith(start) then
                return i
            end
        end
        throw "no line '{start}' after line {index} of Lexer::tokenize"
    end

    func tokenize()
        self.enter("tokenize")
        self.run("tokenize", 1, "std::vector<Token> Lexer::tokenize()")
        self.run("tokenize", 2, "std::vector<Token> tokens;")
        self.run("tokenize", 3, "tokens.reserve(")
        self.run("tokenize", 5, "for (;;)")
        while true do
            self.run("tokenize", 6, "skip_whitespace();")
            self.skipWhitespace()
            var atEnd = self.atEnd()
            self.run("tokenize", 7, "if (at_end())")
            if atEnd then
                self.run("tokenize", 8, "break;")
                break
            end
            var start = self.pos
            var c = self.advance()
            self.from = start
            self.c = c
            self.run("tokenize", 10, "char c = advance();")
            self.dispatch(c)
            self.from = nil
            self.drop = false
        end
        self.emit("tokenize", 138, "emit(tokens, \{TokenType::EOF_T", "EOF_T", "",
                  {note: "Nothing left to read. The last token, EOF_T, tells the parser the program ends here."})
        self.run("tokenize", 139, "return tokens;")
        self.leave()
        return self.tokens
    end

    ## The switch: it jumps straight to the statement under the matching `case`, and the label it went
    ## through is marked beside it.
    func dispatch(c)
        var li = self.caseLine(c)
        var seen = c
        if c == NEWLINE then
            seen = "the line break"
        end
        var note = "No case for '{seen}': the switch falls to default."
        if li > 0 then
            note = "The switch jumps to the case of '{seen}'."
        end
        self.run("tokenize", 11, "switch (c)", {note: note})
        if c == NEWLINE then
            self.line += 1
            self.run("tokenize", li + 1, "line++;", {also: li, drop: true, note: "A line break is not a token: the lexer only counts the line."})
            self.run("tokenize", li + 2, "break;")
        elseif c == "=" or c == "+" or c == "-" or c == "%" then
            var type, lexeme = self.glue(c, "=")
            var span = 0
            if c == "%" then
                span = 1    ## its statement covers two lines
            end
            self.emit("tokenize", li + 1, "emit(tokens,", type, lexeme, {also: li, span: span,
                      note: "match('=') eats the next character only when it is '='. Here the token is '{lexeme}'."})
            self.run("tokenize", self.lineFrom(li, "break;"), "break;")
        elseif c == "*" then
            self.star(li)
        elseif c == "/" then
            self.slash(li)
        elseif c == ">" then
            self.greater(li)
        elseif c == "<" then
            self.less(li)
        elseif c == "." then
            self.dot(li)
        elseif c == QUOTE then
            self.run("tokenize", li + 1, "interp_string(tokens);", {also: li})
            self.interpString()
            self.run("tokenize", li + 2, "break;")
        elseif c == "#" then
            self.hash(li)
        elseif SINGLE.has(c) then
            var si = self.lineFrom(li, "emit(")
            self.emit("tokenize", si, "emit(tokens, \{TokenType::", SINGLE[c], c, {also: li,
                      note: "'{c}' stands alone: it is a token by itself."})
            self.run("tokenize", self.lineFrom(si, "break;"), "break;")
        else
            self.defaultCase(c)
        end
    end

    ## match(second) for the character c just read: the token that comes out, and its text.
    func glue(c, second)
        if self.accept(second) then
            return PAIRS[c].next[second], c + second
        end
        return PAIRS[c].alone, c
    end

    func star(li)
        var matched = self.accept("=")
        self.run("tokenize", li + 1, "if (match('='))", {also: li})
        if matched then
            self.emit("tokenize", li + 2, "emit(tokens, \{TokenType::STAR_EQUAL", "STAR_EQUAL", "*=")
        else
            var second = self.peek() == "*"
            self.run("tokenize", li + 3, "else if (peek() == '*')")
            if second then
                self.fail("tokenize", li + 4, "fail(", "'**' no longer exists — use '^' for exponentiation")
            end
            self.emit("tokenize", li + 6, "emit(tokens, \{TokenType::STAR", "STAR", "*")
        end
        self.run("tokenize", li + 7, "break;")
    end

    func slash(li)
        var type, lexeme = self.glue("/", "=")
        self.run("tokenize", li + 1, "if (match('='))", {also: li})
        if #lexeme == 2 then
            self.emit("tokenize", li + 2, "emit(tokens, \{TokenType::SLASH_EQUAL", type, lexeme)
        else
            type, lexeme = self.glue("/", "/")
            self.emit("tokenize", li + 4, "emit(tokens,", type, lexeme, {span: 1})
        end
        self.run("tokenize", li + 6, "break;")
    end

    func greater(li)
        var type, lexeme = self.glue(">", "=")
        self.run("tokenize", li + 1, "if (match('='))", {also: li})
        if #lexeme == 2 then
            self.emit("tokenize", li + 2, "emit(tokens, \{TokenType::GREATER_EQUAL", type, lexeme)
        else
            type, lexeme = self.glue(">", ">")
            self.emit("tokenize", li + 4, "emit(tokens, match('>')", type, lexeme)
        end
        self.run("tokenize", li + 5, "break;")
    end

    func less(li)
        var type, lexeme = self.glue("<", "=")
        self.run("tokenize", li + 1, "if (match('='))", {also: li})
        if #lexeme == 2 then
            self.emit("tokenize", li + 2, "emit(tokens, \{TokenType::LESS_EQUAL", type, lexeme)
        else
            type, lexeme = self.glue("<", ">")
            self.run("tokenize", li + 3, "else if (match('>'))")
            if #lexeme == 2 then
                self.emit("tokenize", li + 4, "emit(tokens, \{TokenType::NOT_EQUAL", type, lexeme)
            else
                type, lexeme = self.glue("<", "<")
                self.emit("tokenize", li + 6, "emit(tokens, match('<')", type, lexeme)
            end
        end
        self.run("tokenize", li + 7, "break;")
    end

    ## A dot is a dot, "..." or the start of a number such as .5
    func dot(li)
        var twice = self.accept(".")
        self.run("tokenize", li + 1, "if (match('.'))", {also: li})
        if twice then
            var third = self.accept(".")
            self.run("tokenize", li + 2, "if (!match('.'))")
            if not third then
                self.fail("tokenize", li + 3, "fail(", "'..' is not valid syntax (use [a;b] for ranges)")
            end
            self.emit("tokenize", li + 4, "emit(tokens, \{TokenType::DOT_DOT_DOT", "DOT_DOT_DOT", "...",
                      {note: "Three dots in a row make one token, the variadic '...'."})
        else
            var digit = isDec(self.peek())
            self.run("tokenize", li + 5, "} else if (is_dec(peek()))")
            if digit then
                self.run("tokenize", li + 6, "emit(tokens, number(true));")
                var t = self.number(true)
                self.emit("tokenize", li + 6, "emit(tokens, number(true));", t.type, t.lexeme)
            else
                self.emit("tokenize", li + 8, "emit(tokens, \{TokenType::DOT", "DOT", ".")
            end
        end
        self.run("tokenize", li + 10, "break;")
    end

    ## # is the length operator, ## a comment to the end of the line, ### a block comment.
    func hash(li)
        var again = self.accept("#")
        self.run("tokenize", li + 1, "if (!match('#'))", {also: li})
        if not again then
            self.emit("tokenize", li + 2, "emit(tokens, \{TokenType::HASH", "HASH", "#",
                      {note: "A single '#' is the length operator: HASH."})
        else
            var third = self.accept("#")
            self.run("tokenize", li + 3, "else if (match('#'))")
            self.drop = true
            if third then
                self.run("tokenize", li + 4, "block_comment();")
                self.blockComment()
            else
                self.run("tokenize", li + 6, "comment();")
                self.comment()
            end
        end
        self.run("tokenize", li + 7, "break;")
    end

    func defaultCase(c)
        var li = CASE_AT["default:"]
        var digit = isDec(c)
        self.run("tokenize", li + 1, "if (is_dec(c))", {also: li})
        if digit then
            self.run("tokenize", li + 2, "emit(tokens, number(false));")
            var t = self.number(false)
            self.emit("tokenize", li + 2, "emit(tokens, number(false));", t.type, t.lexeme)
            self.run("tokenize", li + 3, "break;")
            return nil
        end
        var letter = isAlpha(c) or c == "_"
        self.run("tokenize", li + 5, "if (is_alpha(c) || c == '_')")
        if letter then
            self.run("tokenize", li + 6, "emit(tokens, identifier());")
            var t = self.identifier()
            self.emit("tokenize", li + 6, "emit(tokens, identifier());", t.type, t.lexeme)
            self.run("tokenize", li + 7, "break;")
            return nil
        end
        self.fail("tokenize", li + 11, "fail(", "unexpected character '{c}'",
                  {note: "'{c}' starts no token at all: the lexer gives up."})
    end

    ## ── Lexer::identifier ────────────────────────────────────────────────────

    func identifier()
        self.enter("identifier")
        var start = self.pos - 1
        self.run("identifier", 2, "int start = pos - 1;")
        while true do
            var more = isAlnum(self.peek()) or self.peek() == "_"
            self.run("identifier", 3, "while (is_alnum(peek())")
            if not more then
                break
            end
            self.advance()
            self.run("identifier", 4, "advance();")
        end
        var lexeme = self.text(start, self.pos)
        self.w = ["lex", lexeme]
        self.run("identifier", 5, "std::string lex =")
        ## has() first: a name such as "len" would otherwise find the map's own len() method.
        var kind = "IDENTIFIER"
        var note = "'{lexeme}' is not in the keyword table: it is a name, IDENTIFIER."
        if KEYWORDS.has(lexeme) then
            kind = KEYWORDS[lexeme]
            note = "'{lexeme}' is in the keyword table: the token is {kind}, not a name."
        end
        self.run("identifier", 6, "auto it = s_keywords.find(lex);")
        self.run("identifier", 7, "return \{it != s_keywords.end()", {note: note})
        self.leave()
        return {type: kind, lexeme: lexeme}
    end

    ## ── Lexer::number ────────────────────────────────────────────────────────

    func number(leadingDot)
        self.enter("number")
        var start = self.pos - 1
        var first = self.chars[start]
        self.run("number", 2, "int start = pos - 1;")
        var digits = ""
        self.w = ["digits", digits]
        self.run("number", 3, "std::string digits;")
        var dotSeen = leadingDot
        self.run("number", 4, "bool dot_seen = leading_dot;")
        self.run("number", 5, "if (leading_dot)")
        if leadingDot then
            digits = "."
            self.w = ["digits", digits]
            self.run("number", 6, "digits += '.';")
        else
            digits = first
            self.w = ["digits", digits]
            self.run("number", 8, "digits += src[start];")
        end
        var prefix = nil
        self.run("number", 13, "if (!leading_dot && src[start] == '0')")
        if not leadingDot and first == "0" then
            var nxt = self.peek().lower()
            if BASES.has(nxt) then
                prefix = nxt
            end
            self.run("number", 14, "char pl =", {span: 3})
            self.run("number", 18, "if (pl != '\0')")
        end
        var lastWasDigit = true
        var underscore = false
        if prefix then
            self.run("number", 19, "const char* kind =")
            self.run("number", 20, "auto invalid =")
            self.advance()
            self.run("number", 21, "advance();")
            digits = digits + prefix
            self.w = ["digits", digits]
            self.run("number", 22, "digits += pl;")
            self.run("number", 23, "auto is_base_digit =", {span: 6})
            lastWasDigit = false
            self.run("number", 30, "bool last_was_digit = false;")
            while true do
                var more = not self.atEnd()
                self.run("number", 31, "while (!at_end())")
                if not more then
                    break
                end
                var c = self.peek()
                self.run("number", 32, "char c = peek();")
                self.run("number", 33, "if (c == '_')")
                if c == "_" then
                    self.run("number", 34, "if (!last_was_digit)")
                    if not lastWasDigit then
                        self.run("number", 35, "break;")
                        break
                    end
                    self.advance()
                    self.run("number", 36, "advance();")
                    lastWasDigit = false
                    self.run("number", 37, "last_was_digit = false;")
                    self.run("number", 38, "continue;")
                else
                    var ok = false
                    if prefix == "x" then
                        ok = isHex(c)
                    elseif prefix == "o" then
                        ok = c >= "0" and c <= "7"
                    else
                        ok = c == "0" or c == "1"
                    end
                    self.run("number", 40, "if (!is_base_digit(c))")
                    if not ok then
                        self.run("number", 41, "break;")
                        break
                    end
                    self.advance()
                    self.run("number", 42, "advance();")
                    digits = digits + c
                    self.w = ["digits", digits]
                    self.run("number", 43, "digits += c;")
                    lastWasDigit = true
                    self.run("number", 44, "last_was_digit = true;")
                end
            end
            self.run("number", 47, "if (!last_was_digit)")
            if not lastWasDigit then
                self.run("number", 48, "invalid();")
                self.fail("number", 20, "auto invalid =", "invalid {BASES[prefix]} literal",
                          {note: "A prefix with no digit after it, or a trailing '_': refused."})
            end
            var after = self.peek()
            self.run("number", 49, "if (is_alnum(peek())")
            if isAlnum(after) or after == "." then
                self.run("number", 50, "invalid();")
                self.fail("number", 20, "auto invalid =", "invalid {BASES[prefix]} literal",
                          {note: "Next comes {shown(after)}, glued to the number: refused."})
            end
            self.run("number", 51, "return \{TokenType::NUMBER",
                     {note: "Next comes {shown(after)}: nothing is glued to the number. The token is NUMBER {digits}."})
            self.leave()
            return {type: "NUMBER", lexeme: digits}
        end

        lastWasDigit = not leadingDot
        self.run("number", 56, "bool last_was_digit = !leading_dot;")
        self.run("number", 57, "bool prev_underscore = false;")
        while true do
            var more = not self.atEnd()
            self.run("number", 58, "while (!at_end())")
            if not more then
                break
            end
            var c = self.peek()
            self.run("number", 59, "char c = peek();")
            self.run("number", 60, "if (is_dec(c))")
            if isDec(c) then
                self.advance()
                self.run("number", 61, "advance();")
                digits = digits + c
                self.w = ["digits", digits]
                self.run("number", 62, "digits += c;")
                lastWasDigit = true
                self.run("number", 63, "last_was_digit = true;")
                underscore = false
                self.run("number", 64, "prev_underscore = false;")
            else
                self.run("number", 65, "} else if (c == '_' && last_was_digit)")
                if c == "_" and lastWasDigit then
                    self.advance()
                    self.run("number", 66, "advance();")
                    lastWasDigit = false
                    self.run("number", 67, "last_was_digit = false;")
                    underscore = true
                    self.run("number", 68, "prev_underscore = true;")
                else
                    self.run("number", 69, "} else if (c == '.' && !dot_seen")
                    if c == "." and not dotSeen and not underscore then
                        self.advance()
                        self.run("number", 70, "advance();")
                        dotSeen = true
                        self.run("number", 71, "dot_seen = true;")
                        digits = digits + "."
                        self.w = ["digits", digits]
                        self.run("number", 72, "digits += '.';")
                        lastWasDigit = false
                        self.run("number", 73, "last_was_digit = false;")
                    else
                        self.run("number", 75, "break;")
                        break
                    end
                end
            end
        end
        var hasExponent = self.peek() == "e" or self.peek() == "E"
        self.run("number", 80, "if (peek() == 'e'")
        if hasExponent then
            self.run("number", 81, "if (prev_underscore)")
            if underscore then
                self.fail("number", 82, "fail(", "invalid number literal",
                          {note: "An '_' right before the exponent is refused."})
            end
            digits = digits + "e"
            self.w = ["digits", digits]
            self.run("number", 83, "digits += 'e';")
            self.advance()
            self.run("number", 84, "advance();")
            var sign = self.peek() == "+" or self.peek() == "-"
            self.run("number", 85, "if (peek() == '+'")
            if sign then
                digits = digits + self.advance()
                self.w = ["digits", digits]
                self.run("number", 86, "digits += advance();")
            end
            var any = false
            self.run("number", 87, "bool exp_digit = false;")
            while true do
                var digit = isDec(self.peek())
                self.run("number", 88, "while (is_dec(peek()))")
                if not digit then
                    break
                end
                digits = digits + self.advance()
                self.w = ["digits", digits]
                self.run("number", 89, "digits += advance();")
                any = true
                self.run("number", 90, "exp_digit = true;")
            end
            self.run("number", 92, "if (!exp_digit)")
            if not any then
                self.fail("number", 93, "fail(", "invalid number literal",
                          {note: "An exponent needs at least one digit."})
            end
        end
        var tail = self.peek()
        self.run("number", 96, "if (prev_underscore ||")
        if underscore or isAlnum(tail) or tail == "." or tail == "_" then
            self.fail("number", 97, "fail(", "invalid number literal",
                      {note: "Next comes {shown(tail)}, glued to the number: '{self.text(start, self.pos)}{tail}' is neither a number nor a name, so it is refused."})
        end
        self.run("number", 98, "return \{TokenType::NUMBER",
                 {note: "Next comes {shown(tail)}: nothing is glued to the number. The token is NUMBER {digits}."})
        self.leave()
        return {type: "NUMBER", lexeme: digits}
    end

    ## ── Lexer::comment and Lexer::block_comment ──────────────────────────────

    func comment()
        self.enter("comment")
        while true do
            var more = not self.atEnd() and self.peek() <> NEWLINE
            self.run("comment", 2, "while (!at_end()")
            if not more then
                break
            end
            self.advance()
            self.run("comment", 3, "advance();")
        end
        self.run("comment", 4, "}", {note: "Everything up to the end of the line is dropped: a comment makes no token."})
        self.leave()
    end

    func blockComment()
        self.enter("block_comment")
        var hashes = 0
        self.run("block_comment", 2, "int hashes = 0;")
        while true do
            var more = not self.atEnd()
            self.run("block_comment", 3, "while (!at_end())")
            if not more then
                break
            end
            var c = self.advance()
            self.run("block_comment", 4, "char c = advance();")
            var newline = c == NEWLINE
            self.run("block_comment", 5, "if (c == '\n')")
            if newline then
                self.line += 1
                self.run("block_comment", 6, "line++;")
            end
            if c == "#" then
                hashes += 1
            else
                hashes = 0
            end
            self.run("block_comment", 7, "hashes = (c == '#')")
            self.run("block_comment", 8, "if (hashes == 3)")
            if hashes == 3 then
                self.run("block_comment", 9, "return;",
                         {note: "Three '#' in a row close the block. Everything between is dropped: no token."})
                self.leave()
                return nil
            end
        end
        self.fail("block_comment", 11, "fail(", "unterminated block comment",
                  {note: "The source ended before the closing ###."})
    end

    ## ── Lexer::interp_string ─────────────────────────────────────────────────

    ## A positional slot is empty or made of digits before an optional ':' — {} {1} {2:.3f}
    func positional(inner)
        var i = 1
        var n = #inner
        while i <= n and (inner.char(i) == " " or inner.char(i) == TAB) do
            i += 1
        end
        while i <= n and isDec(inner.char(i)) do
            i += 1
        end
        while i <= n and (inner.char(i) == " " or inner.char(i) == TAB) do
            i += 1
        end
        return i > n or inner.char(i) == ":"
    end

    func interpString()
        self.enter("interp_string")
        var strLine = self.line
        var literal = ""
        self.w = ["literal", literal]
        self.run("interp_string", 2, "int str_line = line;")
        self.run("interp_string", 3, "std::string literal;")
        var hasInterp = false
        self.run("interp_string", 4, "bool has_interp = false;")
        self.run("interp_string", 6, "while (true)")
        while true do
            ## everything up to the next character of interest is copied in one block
            var stop = self.pos
            while stop <= self.hi and self.chars[stop] <> QUOTE and self.chars[stop] <> NEWLINE
                  and self.chars[stop] <> "\{" and self.chars[stop] <> BACKSLASH do
                stop += 1
            end
            self.run("interp_string", 9, "size_t stop = src.find_first_of(")
            self.run("interp_string", 10, "if (stop == std::string::npos)")
            if stop > self.hi then
                self.run("interp_string", 11, "stop = src.size();")
            end
            literal = literal + self.text(self.pos, stop)
            self.w = ["literal", literal]
            self.run("interp_string", 12, "literal.append(")
            self.pos = stop
            self.run("interp_string", 13, "pos = (int)stop;")
            var done = self.atEnd() or self.peek() == QUOTE or self.peek() == NEWLINE
            self.run("interp_string", 14, "if (at_end() ||")
            if done then
                self.run("interp_string", 15, "break;")
                break
            end
            var c = self.advance()
            self.run("interp_string", 17, "if (advance() ==")
            if c == BACKSLASH then
                if self.accept("\{") then
                    literal = literal + "\{"
                else
                    literal = literal + BACKSLASH
                end
                self.w = ["literal", literal]
                self.run("interp_string", 18, "literal += match(",
                         {note: "A backslash: only " + BACKSLASH + "\{ is an escape (a literal brace). Any other backslash stays as it is."})
                self.run("interp_string", 19, "continue;")
            else
                literal, hasInterp = self.hole(strLine, literal, hasInterp)
            end
        end
        var broken = self.atEnd() or self.peek() == NEWLINE
        self.run("interp_string", 96, "if (at_end() ||")
        if broken then
            self.fail("interp_string", 97, "fail(", "unterminated string",
                      {note: "The line ended before the closing quote: refused."})
        end
        self.advance()
        self.run("interp_string", 98, "advance();")
        var kind = "STRING"
        var note = "The closing quote. No hole was met, so the whole text is one STRING token."
        if hasInterp then
            kind = "INTERP_END"
            note = "The closing quote. The text after the last hole becomes INTERP_END."
        end
        self.emit("interp_string", 100, "emit(out, \{has_interp ? TokenType::INTERP_END", kind, literal, {note: note})
        self.run("interp_string", 101, "}")
        self.leave()
    end

    ## The head has just eaten a '\{' inside a string. Returns the literal and has_interp as the loop
    ## goes on with them.
    func hole(strLine, literal, hasInterp)
        var depth = 1
        var brackets = 0
        self.run("interp_string", 27, "int depth = 1;",
                 {note: "A '\{' opens a hole. The lexer captures everything up to the matching '}', nested braces included."})
        self.run("interp_string", 28, "int brackets = 0;")
        var innerStart = self.pos
        self.run("interp_string", 29, "int inner_start = pos;")
        var specAt = nil
        self.run("interp_string", 30, "int spec_at = -1;")
        while true do
            var more = not self.atEnd() and depth > 0
            self.run("interp_string", 31, "while (!at_end() && depth > 0)")
            if not more then
                break
            end
            var ec = self.peek()
            self.run("interp_string", 32, "char ec = peek();")
            self.run("interp_string", 33, "if (ec == '\n')")
            if ec == NEWLINE then
                self.run("interp_string", 34, "break;")
                break
            end
            self.run("interp_string", 35, "if (ec == '")
            if ec == QUOTE then
                self.advance()
                self.run("interp_string", 36, "advance();")
                while true do
                    var inside = not self.atEnd() and self.peek() <> QUOTE and self.peek() <> NEWLINE
                    self.run("interp_string", 37, "while (!at_end() && peek() !=")
                    if not inside then
                        break
                    end
                    self.advance()
                    self.run("interp_string", 38, "advance();")
                end
                self.accept(QUOTE)
                self.run("interp_string", 39, "match(")
                self.run("interp_string", 40, "continue;")
            else
                self.run("interp_string", 42, "if (ec == '\{')")
                if ec == "\{" then
                    depth += 1
                    self.run("interp_string", 43, "depth++;")
                else
                    var closes = false
                    if ec == "}" then
                        depth -= 1
                        closes = depth == 0
                    end
                    self.run("interp_string", 44, "else if (ec == '}'")
                    if closes then
                        self.run("interp_string", 45, "break;")
                        break
                    end
                    var open = ec == "(" or ec == "["
                    self.run("interp_string", 46, "else if (ec == '(' ||")
                    if open then
                        brackets += 1
                        self.run("interp_string", 47, "brackets++;")
                    else
                        var shut = ec == ")" or ec == "]"
                        self.run("interp_string", 48, "else if (ec == ')' ||")
                        if shut then
                            brackets -= 1
                            self.run("interp_string", 49, "brackets--;")
                        else
                            var colon = ec == ":" and depth == 1 and brackets == 0 and specAt == nil
                            self.run("interp_string", 50, "else if (ec == ':' &&")
                            if colon then
                                specAt = self.pos
                                self.run("interp_string", 51, "spec_at = pos;",
                                         {note: "A ':' at the top level of the hole starts a format, as in \{x:.2f}."})
                            end
                        end
                    end
                end
                self.advance()
                self.run("interp_string", 52, "advance();")
            end
        end
        var unclosed = depth > 0
        self.run("interp_string", 54, "if (depth > 0)")
        if unclosed then
            self.fail("interp_string", 55, "fail(", "unclosed brace in interpolation",
                      {note: "The line ended before the matching closing brace: refused."})
        end
        var innerEnd = self.pos
        var inner = self.text(innerStart, innerEnd)
        self.run("interp_string", 57, "std::string inner =")
        self.advance()
        self.run("interp_string", 58, "advance();")
        var slot = self.positional(inner)
        self.run("interp_string", 61, "if (is_positional_placeholder(inner))")
        if slot then
            literal = literal + "\{" + inner + "}"
            self.w = ["literal", literal]
            self.run("interp_string", 62, "literal += '\{';",
                     {note: "A hole that is empty or only a number is a positional slot, not an expression: it stays in the text and printf fills it in."})
            self.run("interp_string", 63, "literal += inner;")
            self.run("interp_string", 64, "literal += '}';")
            self.run("interp_string", 65, "continue;")
            return literal, hasInterp
        end
        var exprEnd = innerEnd
        if specAt then
            exprEnd = specAt
        end
        self.run("interp_string", 68, "std::string expr_src =")
        self.run("interp_string", 69, "std::string spec =")
        var kind = "INTERP_START"
        if hasInterp then
            kind = "INTERP_MID"
        end
        self.emit("interp_string", 71, "emit(out, \{has_interp ?", kind, literal,
                  {note: "The text before the hole is emitted as {kind}."})
        self.run("interp_string", 72, "has_interp = true;")
        literal = ""
        self.w = ["literal", literal]
        self.run("interp_string", 73, "literal.clear();")
        self.run("interp_string", 75, "auto emit_sub =", {span: 6})
        self.run("interp_string", 83, "if (spec.empty())")
        if specAt then
            self.emit("interp_string", 87, "emit(out, \{TokenType::IDENTIFIER", "IDENTIFIER", "__fmt",
                      {note: "A format turns \{expr:spec} into __fmt(expr, spec), written out as tokens."})
            self.emit("interp_string", 88, "emit(out, \{TokenType::LPAREN", "LPAREN", "(")
            self.emitSub(89, innerStart, exprEnd - 1, strLine)
            self.emit("interp_string", 90, "emit(out, \{TokenType::COMMA", "COMMA", ",")
            self.emit("interp_string", 91, "emit(out, \{TokenType::STRING, spec", "STRING", self.text(specAt + 1, innerEnd))
            self.emit("interp_string", 92, "emit(out, \{TokenType::RPAREN", "RPAREN", ")")
        else
            self.emitSub(84, innerStart, exprEnd - 1, strLine)
        end
        return "", true
    end

    ## The lambda emit_sub: a brand-new lexer reads only the text between the braces, and what it
    ## returns goes into this lexer's own vector.
    func emitSub(callIndex, lo, hi, strLine)
        self.run("interp_string", callIndex, "emit_sub(std::move(expr_src));")
        var here = self.pos
        self.run("interp_string", 76, "Lexer sub(std::move(code)", {p0: here, p1: lo,
                 note: "A second Lexer is built on the text between the braces. It reads that text alone."})
        self.mark = lo
        self.run("interp_string", 77, "sub.line = str_line;")
        self.run("interp_string", 78, "for (auto& t : sub.tokenize())")
        var inner = Tracer(self.chars, lo, hi, self.depth + 1, strLine, self.result, self.stack)
        var made = inner.tokenize()
        self.mark = inner.mark
        for t in made do
            self.run("interp_string", 78, "for (auto& t : sub.tokenize())", {p0: self.pos, p1: self.pos})
            var keep = t.type <> "EOF_T"
            self.run("interp_string", 79, "if (t.type != TokenType::EOF_T)")
            if keep then
                var copy = {type: t.type, lexeme: t.lexeme, from: t.from, to: t.to, depth: t.depth}
                self.file(copy, "interp_string", 80, "emit(out, std::move(t));",
                          {from: t.from, hl: t.to, p0: self.pos, p1: self.pos})
            end
        end
        self.run("interp_string", 78, "for (auto& t : sub.tokenize())", {p0: self.pos, p1: self.pos})
    end
end

func trace(source)
    var chars = []
    for c in source do
        chars.push(c)
    end
    var result = {steps: [], tokens: [], chars: chars, source: source, error: nil}
    var t = Tracer(chars, 1, #chars, 0, 1, result, [])
    try
        t.tokenize()
    catch e
        if e <> "lexer error" then
            throw e
        end
        result.error = result.steps[#result.steps].err
    end
    return result
end
