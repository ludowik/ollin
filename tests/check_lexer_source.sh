#!/bin/bash
# LEXER ANIMATION guard: docs/samples/lexer shows the engine's own code and follows it line by line,
# so it must notice when src/lexer.cpp changes under it.
#
#   1. cpp_source.ol, the text of the lexer functions the animation shows, is generated from
#      lexer.cpp by tools/gen_lexer_source.py; it must be up to date.
#   2. every line tracer.ol names — `self.run("number", 21, "advance();")`, a function, a line of
#      it and how that line begins — must be that line of lexer.cpp. The calls whose index is
#      computed (`li + 1`) are checked when they run, by tests/lexer_trace_test.ol.
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

python3 tools/gen_lexer_source.py --check || exit 1

python3 - <<'PYEOF'
import re, sys
sys.path.insert(0, "tools")
import gen_lexer_source as g

listing = {name: lines for name, first, lines in g.extract()}
tracer = open("docs/samples/lexer/tracer.ol", encoding="utf-8").read()

# self.run("fn", 12, "start of the line" ...), and the emit / fail variants that take the same three
calls = re.findall(r'self\.(?:run|emit|fail)\("(\w+)", (\d+), "((?:[^"\\]|\\.)*)"', tracer)
errs = []
for fn, index, start in calls:
    index = int(index)
    # the text as the C++ line has it: Ollin writes an opening brace as \{ inside a string
    want = start.replace("\\{", "{")
    if fn not in listing:
        errs.append(f"{fn}: not a function of cpp_source.ol")
    elif not 1 <= index <= len(listing[fn]):
        errs.append(f"{fn} line {index}: the function has {len(listing[fn])} lines")
    elif not listing[fn][index - 1].strip().startswith(want):
        errs.append(f"{fn} line {index}: tracer.ol says '{want}', lexer.cpp has '{listing[fn][index - 1].strip()}'")
if not calls:
    errs.append("no line of lexer.cpp is named by tracer.ol: the pattern of this guard is stale")
if errs:
    print("LEXER TRACE: tracer.ol and src/lexer.cpp disagree")
    for e in errs:
        print("  " + e)
    sys.exit(1)
print(f"OK   lexer trace ({len(calls)} lines named by tracer.ol are lines of lexer.cpp)")
PYEOF
