#!/bin/bash
# TRACE ANIMATIONS guard: docs/samples/lexer and docs/samples/parser show the engine's own code and
# follow it line by line, so they must notice when src/lexer.cpp or src/parser.cpp changes under them.
#
#   1. each cpp_source.ol, the text of the functions an animation shows, is generated from its C++
#      file by tools/gen_cpp_source.py; it must be up to date.
#   2. every line a tracer.ol names — `self.run("number", 21, "advance();")`, a function, a line of
#      it and how that line begins — must be that line of the C++ file. The calls whose index is
#      computed (`li + 1`) are checked when they run, by tests/lexer_trace_test.ol and
#      tests/parser_trace_test.ol.
#   3. the keyword table of the lexer's tracer.ol is the one of lexer.cpp, entry for entry.
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

python3 tools/gen_cpp_source.py --check || exit 1

python3 - <<'PYEOF'
import re, sys
sys.path.insert(0, "tools")
import gen_cpp_source as g

for name in g.TARGETS:
    listing = {fn: lines for fn, first, lines in g.extract(name)}
    tracer = open(f"docs/samples/{name}/tracer.ol", encoding="utf-8").read()

    # self.run("fn", 12, "start of the line" ...), the emit / fail / need variants that take the same
    # three, and file(token, "fn", 12, "start of the line" ...)
    calls = re.findall(r'self\.(?:run|emit|fail|failAt|expectLine|need|needName|separator)\("(\w+)", (\d+), "((?:[^"\\]|\\.)*)"', tracer)
    calls += re.findall(r'self\.file\(\w+, "(\w+)", (\d+), "((?:[^"\\]|\\.)*)"', tracer)
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
            errs.append(f"{fn} line {index}: tracer.ol says '{want}', "
                        f"{g.TARGETS[name]['source']} has '{listing[fn][index - 1].strip()}'")
    if not calls:
        errs.append("no line of the C++ file is named by tracer.ol: the pattern of this guard is stale")
    if errs:
        print(f"{name.upper()} TRACE: tracer.ol and {g.TARGETS[name]['source']} disagree")
        for e in errs:
            print("  " + e)
        sys.exit(1)
    print(f"OK   {name} trace ({len(calls)} lines named by tracer.ol are lines of {g.TARGETS[name]['source']})")

# the lexer's keywords: `{"var", TokenType::VAR},` in lexer.cpp, `"var": "VAR"` in tracer.ol
tracer = open("docs/samples/lexer/tracer.ol", encoding="utf-8").read()
cpp = open("src/lexer.cpp", encoding="utf-8").read()
table = cpp[cpp.index("s_keywords = {"):]
table = table[:table.index("};")]
engine = dict(re.findall(r'\{"(\w+)", TokenType::(\w+)\}', table))
block = tracer[tracer.index("const KEYWORDS = {"):]
block = dict(re.findall(r'"(\w+)": "(\w+)"', block[:block.index("}")]))
if engine != block:
    print("LEXER TRACE: the keyword table of tracer.ol is not the one of lexer.cpp")
    for k in sorted(set(engine) | set(block)):
        if engine.get(k) != block.get(k):
            print(f"  {k}: lexer.cpp has {engine.get(k)}, tracer.ol has {block.get(k)}")
    sys.exit(1)
print(f"OK   lexer keywords ({len(engine)} entries, the same in tracer.ol and lexer.cpp)")
PYEOF
