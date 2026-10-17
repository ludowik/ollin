## A copy of src/lexer.cpp that RECORDS every move it makes. trace(source) runs the same rules as
## the engine's lexer, one character at a time, and returns the list of steps the animation replays
## together with the tokens they produced. The test tests/lexer_trace_test.ol checks that the tokens
## are exactly the ones the C++ lexer gives.
##
## A step is a map:
##   fn, at      the lexer.cpp function that is running and the line of its excerpt (programs.ol)
##   note        what happens, in a sentence
##   p0, p1      the read head before and after: the position of the NEXT character to read
##   from        where the lexeme being built began (nil when there is none)
##   drop        true when what was read is thrown away (blanks, comments)
##   tok         the token this step emits, {type, lexeme, from, to}
##   err         the message when the lexer gives up
##   line, depth the source line, and how many lexers deep (an interpolation starts a second one)

const KEYWORDS = {
    "var": "VAR", "global": "GLOBAL", "const": "CONSTANT", "while": "WHILE", "do": "DO",
    "if": "IF", "then": "THEN", "end": "END", "break": "BREAK", "continue": "CONTINUE",
    "true": "TRUE", "false": "FALSE", "try": "TRY", "catch": "CATCH", "throw": "THROW",
    "else": "ELSE", "elseif": "ELSEIF", "func": "FUNC", "return": "RETURN", "nil": "NIL",
    "or": "OR", "and": "AND", "not": "NOT", "for": "FOR", "in": "IN", "import": "IMPORT",
    "as": "AS", "class": "CLASS", "extends": "EXTENDS", "static": "STATIC", "switch": "SWITCH",
    "case": "CASE", "enum": "ENUM", "ref": "REF"
}

## One character, one token.
const SINGLE = {
    ",": "COMMA", "(": "LPAREN", ")": "RPAREN", ";": "SEMICOLON", "&": "AMP", "|": "PIPE",
    "^": "CARET", "~": "TILDE", "\{": "LBRACE", "}": "RBRACE", "[": "LBRACKET", "]": "RBRACKET",
    ":": "COLON", "?": "QUESTION"
}

## A character that may be glued to the next one: the second characters it accepts, then the
## token it gives alone.
const PAIRS = {
    "=": {next: {"=": "EQUAL_EQUAL"}, alone: "EQUALS"},
    "+": {next: {"=": "PLUS_EQUAL"}, alone: "PLUS"},
    "-": {next: {"=": "MINUS_EQUAL"}, alone: "MINUS"},
    "*": {next: {"=": "STAR_EQUAL"}, alone: "STAR"},
    "/": {next: {"=": "SLASH_EQUAL", "/": "SLASH_SLASH"}, alone: "SLASH"},
    "%": {next: {"=": "PERCENT_EQUAL"}, alone: "PERCENT"},
    ">": {next: {"=": "GREATER_EQUAL", ">": "RSHIFT"}, alone: "GREATER"},
    "<": {next: {"=": "LESS_EQUAL", ">": "NOT_EQUAL", "<": "LSHIFT"}, alone: "LESS"}
}

## Ollin strings have no escapes: these characters are spelled by their code.
const BASES = {x: "hexadecimal", o: "octal", b: "binary"}

const QUOTE = string.fromCode(34)
const NEWLINE = string.fromCode(10)
const TAB = string.fromCode(9)
const CR = string.fromCode(13)
const BACKSLASH = string.fromCode(92)

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
    ## `chars` is the source split into characters, shared with the nested lexers; this one reads
    ## the positions lo..hi. `result` collects the steps and the tokens of every lexer.
    func init(chars, lo, hi, depth, line, result)
        self.chars = chars
        self.pos = lo
        self.hi = hi
        self.depth = depth
        self.line = line
        self.result = result
        self.mark = lo    ## where the read head was when the last step was recorded
    end

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

    func text(a, b)
        var out = ""
        for i = a, b - 1 do
            out = out + self.chars[i]
        end
        return out
    end

    ## Records a step AFTER its action was done: the head has already moved to self.pos.
    func rec(f)
        f.depth = self.depth
        f.line = self.line
        f.p0 = f.p0 or self.mark
        f.p1 = f.p1 or self.pos
        self.mark = f.p1
        self.result.steps.push(f)
        if f.tok then
            f.tok.step = #self.result.steps
            f.tok.depth = self.depth
            f.tok.from = f.from
            f.tok.to = f.p1
            self.result.tokens.push(f.tok)
        end
    end

    func fail(msg, f)
        f.err = msg
        self.rec(f)
        throw "lexer error"
    end

    func skipWhitespace()
        var start = self.pos
        while self.peek() == " " or self.peek() == TAB or self.peek() == CR do
            self.advance()
        end
        if self.pos > start then
            self.rec({fn: "skip_whitespace", at: 2, from: start, drop: true,
                      note: "Blanks are skipped: they separate tokens and are never one."})
        end
    end

    func tokenize()
        while true do
            self.skipWhitespace()
            if self.atEnd() then
                break
            end
            self.step()
        end
        self.rec({fn: "tokenize", at: 16, tok: {type: "EOF_T", lexeme: ""},
                  note: "Nothing left to read. The last token, EOF_T, tells the parser the program ends here."})
    end

    ## One turn of the loop of Lexer::tokenize: read a character, and let it decide.
    func step()
        var start = self.pos
        var c = self.advance()
        if c == NEWLINE then
            self.rec({fn: "tokenize", at: 6, from: start, drop: true,
                      note: "A line break is not a token either: the lexer only counts the line."})
            self.line += 1
        elseif SINGLE[c] then
            self.rec({fn: "tokenize", at: 7, from: start,
                      note: "advance() reads '{c}'. It stands alone, so it is a token already.",
                      tok: {type: SINGLE[c], lexeme: c}})
        elseif PAIRS[c] then
            self.pair(c, start)
        elseif c == "." then
            self.dot(start)
        elseif c == QUOTE then
            self.rec({fn: "tokenize", at: 9, from: start,
                      note: "advance() reads a double quote: a string begins, interp_string() takes over."})
            self.interpString(start)
        elseif c == "#" then
            self.hash(start)
        elseif isDec(c) then
            self.rec({fn: "tokenize", at: 12, from: start,
                      note: "advance() reads '{c}', a digit: number() takes over."})
            self.number(start, false)
        elseif isAlpha(c) or c == "_" then
            self.rec({fn: "tokenize", at: 13, from: start,
                      note: "advance() reads '{c}', a letter: identifier() takes over."})
            self.identifier(start)
        else
            self.fail("unexpected character '{c}'", {fn: "tokenize", at: 15, from: start,
                      note: "'{c}' starts no token at all: the lexer gives up."})
        end
    end

    ## = + - * / % > < : the second character decides which token it is.
    func pair(c, start)
        var spec = PAIRS[c]
        var nxt = self.peek()
        var found = spec.next[nxt]
        self.rec({fn: "tokenize", at: 8, from: start,
                  note: "advance() reads '{c}'. Is it alone, or does the next character, {shown(nxt)}, glue to it? match() looks."})
        if c == "*" and nxt == "*" then
            self.fail("'**' no longer exists — use '^' for exponentiation",
                      {fn: "tokenize", at: 8, from: start, note: "'**' is refused with a message that says what to write instead."})
        end
        if found then
            var lexeme = c + nxt
            self.pos += 1
            self.rec({fn: "tokenize", at: 8, from: start, tok: {type: found, lexeme: lexeme},
                      note: "match('{nxt}') succeeds and eats it: the token is the two characters, '{lexeme}'."})
        else
            self.rec({fn: "tokenize", at: 8, from: start, tok: {type: spec.alone, lexeme: c},
                      note: "match() fails, nothing is eaten: the token is just '{c}'."})
        end
    end

    ## A dot is a dot, "..." or the start of a number such as .5
    func dot(start)
        var nxt = self.peek()
        if nxt == "." then
            self.pos += 1
            if self.peek() <> "." then
                self.fail("'..' is not valid syntax (use [a;b] for ranges)",
                          {fn: "tokenize", at: 8, from: start, note: "Two dots and no third: refused, and the message points at ranges."})
            end
            self.pos += 1
            self.rec({fn: "tokenize", at: 8, from: start, tok: {type: "DOT_DOT_DOT", lexeme: "..."},
                      note: "Three dots in a row make one token, the variadic '...'."})
        elseif isDec(nxt) then
            self.rec({fn: "tokenize", at: 8, from: start,
                      note: "A dot followed by a digit begins a number, as in .5: number() takes over."})
            self.number(start, true)
        else
            self.rec({fn: "tokenize", at: 8, from: start, tok: {type: "DOT", lexeme: "."},
                      note: "A lone dot: field access."})
        end
    end

    func identifier(start)
        while isAlnum(self.peek()) or self.peek() == "_" do
            self.advance()
        end
        self.rec({fn: "identifier", at: 2, from: start,
                  note: "While the next character is a letter, a digit or '_', the identifier goes on."})
        var lexeme = self.text(start, self.pos)
        ## has() first: a name such as "len" would otherwise find the map's own len() method.
        var kind = nil
        if KEYWORDS.has(lexeme) then
            kind = KEYWORDS[lexeme]
        end
        if kind then
            self.rec({fn: "identifier", at: 5, from: start, tok: {type: kind, lexeme: lexeme},
                      note: "'{lexeme}' is in the keyword table: the token is {kind}, not a name."})
        else
            self.rec({fn: "identifier", at: 5, from: start, tok: {type: "IDENTIFIER", lexeme: lexeme},
                      note: "'{lexeme}' is not in the keyword table: it is a name, IDENTIFIER."})
        end
    end

    func number(start, leadingDot)
        var first = self.chars[start]
        var nxt = self.peek()
        var prefix = nil
        if not leadingDot and first == "0" then
            if nxt == "x" or nxt == "X" then
                prefix = "x"
            elseif nxt == "o" or nxt == "O" then
                prefix = "o"
            elseif nxt == "b" or nxt == "B" then
                prefix = "b"
            end
        end
        ## What the token will hold: the digits only, the prefix and the exponent letter in lower case.
        var digits = first
        if leadingDot then
            digits = "."
        end
        var lastWasDigit = true
        var underscore = false
        if prefix then
            self.advance()
            digits = digits + prefix
            lastWasDigit = false
            while not self.atEnd() do
                var c = self.peek()
                if c == "_" then
                    if not lastWasDigit then
                        break
                    end
                    self.advance()
                    lastWasDigit = false
                else
                    var ok = false
                    if prefix == "x" then
                        ok = isHex(c)
                    elseif prefix == "o" then
                        ok = c >= "0" and c <= "7"
                    else
                        ok = c == "0" or c == "1"
                    end
                    if not ok then
                        break
                    end
                    digits = digits + self.advance()
                    lastWasDigit = true
                end
            end
            self.rec({fn: "number", at: 2, from: start,
                      note: "The 0 is followed by '{nxt}': a base prefix. Only the digits of that base are read."})
            if not lastWasDigit then
                self.fail("invalid {BASES[prefix]} literal", {fn: "number", at: 5, from: start,
                          note: "A prefix with no digit after it, or a trailing '_': refused."})
            end
        else
            lastWasDigit = not leadingDot
            var dotSeen = leadingDot
            while not self.atEnd() do
                var c = self.peek()
                if isDec(c) then
                    digits = digits + self.advance()
                    lastWasDigit = true
                    underscore = false
                elseif c == "_" and lastWasDigit then
                    self.advance()
                    lastWasDigit = false
                    underscore = true
                elseif c == "." and not dotSeen and not underscore then
                    digits = digits + self.advance()
                    dotSeen = true
                    lastWasDigit = false
                else
                    break
                end
            end
            self.rec({fn: "number", at: 3, from: start,
                      note: "Digits are read; a '_' is allowed only between two digits and one '.' only once."})
            if self.peek() == "e" or self.peek() == "E" then
                if underscore then
                    self.fail("invalid number literal", {fn: "number", at: 4, from: start,
                              note: "An '_' right before the exponent is refused."})
                end
                self.advance()
                digits = digits + "e"
                if self.peek() == "+" or self.peek() == "-" then
                    digits = digits + self.advance()
                end
                var any = false
                while isDec(self.peek()) do
                    digits = digits + self.advance()
                    any = true
                end
                if not any then
                    self.fail("invalid number literal", {fn: "number", at: 4, from: start,
                              note: "An exponent needs at least one digit."})
                end
                self.rec({fn: "number", at: 4, from: start,
                          note: "An 'e' with its digits is the exponent: the number is a float."})
            end
        end
        var after = self.peek()
        if underscore or isAlnum(after) or after == "." or after == "_" then
            var what = "number"
            if prefix then
                what = BASES[prefix]
            end
            self.fail("invalid {what} literal", {fn: "number", at: 6, from: start,
                      note: "Next comes {shown(after)}, glued to the number: '{self.text(start, self.pos)}{after}' is neither a number nor a name, so it is refused."})
        end
        self.rec({fn: "number", at: 7, from: start, tok: {type: "NUMBER", lexeme: digits},
                  note: "Next comes {shown(after)}: nothing is glued to the number. The token is NUMBER."})
    end

    ## # is the length operator, ## a comment to the end of the line, ### a block comment.
    func hash(start)
        if not self.accept("#") then
            self.rec({fn: "comment", at: 1, from: start, tok: {type: "HASH", lexeme: "#"},
                      note: "A single '#' is the length operator: HASH."})
        elseif self.accept("#") then
            var hashes = 0
            var closed = false
            while not self.atEnd() do
                var c = self.advance()
                if c == NEWLINE then
                    self.line += 1
                end
                if c == "#" then
                    hashes += 1
                else
                    hashes = 0
                end
                if hashes == 3 then
                    closed = true
                    break
                end
            end
            if not closed then
                self.fail("unterminated block comment", {fn: "comment", at: 2, from: start,
                          note: "The source ended before the closing ###."})
            end
            self.rec({fn: "comment", at: 2, from: start, drop: true,
                      note: "Three '#' open a block comment, read until the next three. It is dropped: no token."})
        else
            while not self.atEnd() and self.peek() <> NEWLINE do
                self.advance()
            end
            self.rec({fn: "comment", at: 3, from: start, drop: true,
                      note: "Two '#' begin a comment: everything up to the end of the line is dropped. No token."})
        end
    end

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

    func interpString(start)
        var literal = ""
        var hasInterp = false
        var strLine = self.line
        while true do
            var gathered = self.pos
            while not self.atEnd() and self.peek() <> QUOTE and self.peek() <> NEWLINE
                  and self.peek() <> "\{" and self.peek() <> BACKSLASH do
                literal = literal + self.advance()
            end
            var c = self.peek()
            if self.atEnd() or c == QUOTE or c == NEWLINE then
                if self.pos > gathered then
                    self.rec({fn: "interp_string", at: 3, from: start,
                              note: "The text is copied as it is until a double quote, an opening brace or the end of the line."})
                end
                break
            end
            self.advance()
            if c == BACKSLASH then
                if self.accept("\{") then
                    literal = literal + "\{"
                else
                    literal = literal + BACKSLASH
                end
                self.rec({fn: "interp_string", at: 3, from: start,
                          note: "A backslash: only " + BACKSLASH + "\{ is an escape (a literal brace). Any other backslash is kept as it is."})
            else
                literal, hasInterp = self.interpolation(start, literal, hasInterp, strLine)
            end
        end
        if self.atEnd() or self.peek() == NEWLINE then
            self.fail("unterminated string", {fn: "interp_string", at: 9, from: start,
                      note: "The line ended before the closing quote: refused."})
        end
        self.advance()
        if hasInterp then
            self.rec({fn: "interp_string", at: 9, from: start, tok: {type: "INTERP_END", lexeme: literal},
                      note: "The closing quote. The text after the last brace becomes INTERP_END."})
        else
            self.rec({fn: "interp_string", at: 9, from: start, tok: {type: "STRING", lexeme: literal},
                      note: "The closing quote. No brace was met, so the whole text is one STRING token."})
        end
    end

    ## The head has just eaten a '{' inside a string.
    func interpolation(start, literal, hasInterp, strLine)
        var depth = 1
        var brackets = 0
        var innerStart = self.pos
        var specAt = nil
        while not self.atEnd() and depth > 0 do
            var ec = self.peek()
            if ec == NEWLINE then
                break
            end
            if ec == QUOTE then
                self.advance()
                while not self.atEnd() and self.peek() <> QUOTE and self.peek() <> NEWLINE do
                    self.advance()
                end
                self.accept(QUOTE)
            else
                if ec == "\{" then
                    depth += 1
                elseif ec == "}" then
                    depth -= 1
                    if depth == 0 then
                        break
                    end
                elseif ec == "(" or ec == "[" then
                    brackets += 1
                elseif ec == ")" or ec == "]" then
                    brackets -= 1
                elseif ec == ":" and depth == 1 and brackets == 0 and specAt == nil then
                    specAt = self.pos
                end
                self.advance()
            end
        end
        if depth > 0 then
            self.fail("unclosed brace in interpolation", {fn: "interp_string", at: 5, from: start,
                      note: "The line ended before the matching closing brace: refused."})
        end
        var innerEnd = self.pos
        self.rec({fn: "interp_string", at: 5, from: start,
                  note: "A '\{' opens a hole. The lexer captures everything up to the matching '}', nested braces included."})
        self.advance()
        var inner = self.text(innerStart, innerEnd)
        if self.positional(inner) then
            literal = literal + "\{" + inner + "}"
            self.rec({fn: "interp_string", at: 6, from: start,
                      note: "A hole that is empty or only a number is a positional slot, not an expression. It stays in the text and printf fills it in."})
            return literal, hasInterp
        end
        var exprEnd = innerEnd
        if specAt then
            exprEnd = specAt
        end
        var kind = "INTERP_START"
        if hasInterp then
            kind = "INTERP_MID"
        end
        self.rec({fn: "interp_string", at: 7, from: start, tok: {type: kind, lexeme: literal},
                  note: "The text before the hole is emitted as {kind}."})
        if specAt then
            self.rec({fn: "interp_string", at: 8, from: start, tok: {type: "IDENTIFIER", lexeme: "__fmt"},
                      note: "A ':' at the top level of the hole is a format. \{expr:spec} becomes __fmt(expr, spec)."})
            self.rec({fn: "interp_string", at: 8, from: start, tok: {type: "LPAREN", lexeme: "("},
                      note: "The call is written out as tokens, as if the programmer had typed it."})
        end
        self.sub(innerStart, exprEnd - 1, strLine)
        if specAt then
            self.rec({fn: "interp_string", at: 8, from: start, tok: {type: "COMMA", lexeme: ","},
                      note: "The format's text goes in as a second argument."})
            self.rec({fn: "interp_string", at: 8, from: start,
                      tok: {type: "STRING", lexeme: self.text(specAt + 1, innerEnd)},
                      note: "The format, as a STRING."})
            self.rec({fn: "interp_string", at: 8, from: start, tok: {type: "RPAREN", lexeme: ")"},
                      note: "And the call is closed."})
        end
        return "", true
    end

    ## Lexer sub(expr): a brand-new lexer reads only the text between the braces.
    func sub(lo, hi, strLine)
        self.rec({fn: "interp_string", at: 8, from: lo, p0: self.pos, p1: lo,
                  note: "A second Lexer is created for the text between the braces. It reads it alone, and what it finds goes into the same stream."})
        var inner = Tracer(self.chars, lo, hi, self.depth + 1, strLine, self.result)
        inner.tokenizeSub()
        self.mark = self.pos
    end

    ## The nested lexer's run: like tokenize(), but its EOF_T is dropped by the caller.
    func tokenizeSub()
        while true do
            self.skipWhitespace()
            if self.atEnd() then
                break
            end
            self.step()
        end
        self.rec({fn: "interp_string", at: 8, p0: self.pos, p1: self.pos,
                  note: "The nested lexer reaches the end of its text. Its EOF_T is thrown away: only the real end of the source gets one."})
    end
end

func trace(source)
    var chars = []
    for c in source do
        chars.push(c)
    end
    var result = {steps: [], tokens: [], chars: chars, error: nil}
    var t = Tracer(chars, 1, #chars, 0, 1, result)
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
