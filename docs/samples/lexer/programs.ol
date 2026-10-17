## What the animation shows: the programs it reads. (The code the panel on the right follows is the
## engine's own, in cpp_source.ol.)
##
## Ollin strings have no escape for the double quote, so a program is written with an apostrophe
## where it needs one and the apostrophes are turned into quotes when the program is built.

import "tracer.ol"

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
