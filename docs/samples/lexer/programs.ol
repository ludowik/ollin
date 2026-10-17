## What the animation shows: the programs it reads, and the excerpts of src/lexer.cpp that the
## panel on the right follows. A step of the trace names a function and a line of its excerpt (the
## `fn` and `at` of tracer.ol), so the line that lights up is the one that is running.
##
## Ollin strings have no escape for the double quote, so a program is written with an apostrophe
## where it needs one and the apostrophes are turned into quotes when the program is built.

const PROGRAM_QUOTE = string.fromCode(34)
const PROGRAM_NEWLINE = string.fromCode(10)

func program(name, lines)
    var text, n = lines.join(PROGRAM_NEWLINE).replace("'", PROGRAM_QUOTE)
    return {name: name, source: text}
end

const PROGRAMS = [
    program("Names and numbers", [
        "var total = 1_200 + x"
    ]),
    program("Two characters, one token", [
        "if n >= .5 then ## small"
    ]),
    program("A string with a hole", [
        "print('n = \{x}!')"
    ]),
    program("A program that fails", [
        "var ok = 1",
        "var 3x = 2"
    ])
]

## What each program teaches, in a sentence shown under the title.
const LESSONS = [
    "Letters make a name, unless the name is in the keyword table. Digits make a number.",
    "The next character decides: >= is one token, and a comment disappears.",
    "A string is cut around its holes, and a second lexer reads each hole.",
    "The lexer refuses what it cannot cut, and says on which line."
]

## Excerpts of src/lexer.cpp, shortened. The index of a line is the `at` of the steps that run it.
const EXCERPTS = {
    "tokenize": {
        title: "Lexer::tokenize()",
        lines: [
            "for (;;) \{",
            "    skip_whitespace();",
            "    if (at_end()) break;",
            "    char c = advance();",
            "    switch (c) \{",
            "    case '\n': line++;",
            "    case '(':  emit(LPAREN);",
            "    case '=':  match('=') ? EQUAL_EQUAL : EQUALS",
            "    case '" + PROGRAM_QUOTE + "':  interp_string();",
            "    case '#':  a comment, see below",
            "    default:",
            "        if (is_dec(c)) emit(number());",
            "        else if (is_alpha(c) || c == '_')",
            "            emit(identifier());",
            "        else fail(" + PROGRAM_QUOTE + "unexpected character" + PROGRAM_QUOTE + ");",
            "emit(EOF_T);"
        ]
    },
    "skip_whitespace": {
        title: "Lexer::skip_whitespace()",
        lines: [
            "void Lexer::skip_whitespace() \{",
            "    while (peek() is ' ', '\t' or '\r')",
            "        advance();",
            "}"
        ]
    },
    "identifier": {
        title: "Lexer::identifier()",
        lines: [
            "Token Lexer::identifier() \{",
            "    while (is_alnum(peek()) || peek() == '_')",
            "        advance();",
            "    lex = src.substr(start, pos - start);",
            "    it = s_keywords.find(lex);",
            "    return it ? it->second : IDENTIFIER;",
            "}"
        ]
    },
    "number": {
        title: "Lexer::number()",
        lines: [
            "Token Lexer::number() \{",
            "    // 0x 0o 0b: only the digits of that base",
            "    // decimal: digits, '_' between, one '.'",
            "    if (peek() is 'e' or 'E')    // exponent",
            "    if (!last_was_digit) invalid();",
            "    if (alnum, '.' or '_' follows) fail();",
            "    return \{NUMBER, digits};",
            "}"
        ]
    },
    "interp_string": {
        title: "Lexer::interp_string()",
        lines: [
            "void Lexer::interp_string() \{",
            "    for (;;) \{",
            "        copy text up to a quote, newline, brace",
            "        if (quote or newline) break;",
            "        capture the hole up to its matching }",
            "        if (positional) \{ keep it; continue; }",
            "        emit(INTERP_START / INTERP_MID, literal);",
            "        Lexer sub(expr); emit its tokens, no EOF",
            "    emit(INTERP_END or STRING, literal);"
        ]
    },
    "comment": {
        title: "case '#' and the comments",
        lines: [
            "if (!match('#'))      emit(HASH);",
            "else if (match('#'))  block_comment();",
            "else                  comment();",
            "void Lexer::comment() \{",
            "    while (!at_end() && peek() != '\n')",
            "        advance();",
            "}"
        ]
    }
}
