## What the animation shows: the programs it parses. (The code the panel on the right follows is the
## engine's own, in cpp_source.ol, and the tokens come from the lexer of the other example.)
##
## Ollin strings have no escape for the double quote, so a program is written with an apostrophe
## where it needs one and the apostrophes are turned into quotes when the program is built.

func program(name, lines)
    return {name: name, source: lines.join(NEWLINE).replace("'", QUOTE)}
end

const PROGRAMS = [
    program("Precedence", [
        "var total = 1 + 2 * 3"
    ]),
    program("A minus and a power", [
        "var x = -2 ^ 2"
    ]),
    program("An assignment seen late", [
        "player.score = 10"
    ]),
    program("A function", [
        "func double(n)",
        "    return n * 2",
        "end"
    ]),
    program("A program that fails", [
        "if x print(x) end"
    ])
]

## What each program teaches, in a sentence shown under the title.
const LESSONS = [
    "The operators that bind tightest are parsed deepest: 2 * 3 is built before the + that holds it.",
    "A power binds tighter than a minus: this is -(2 ^ 2), as in Lua.",
    "The parser reads an expression first, and only then sees the = that makes it an assignment.",
    "A block is a loop of statements up to an end token, and the tree mirrors that nesting.",
    "The parser refuses what no rule accepts, and says on which line."
]
