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
#   3. the keyword table of the lexer's tracer.ol is the one of lexer.cpp, entry for entry, and the
#      tables the parser's tracer.ol copies (precedence levels, comparison and assignment operators,
#      the tokens that end a block) are those of parser.cpp.
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
    names = "|".join(re.findall(r'func (\w+)\(fn, index, start', tracer))
    calls = re.findall(r'self\.(?:' + names + r')\("(\w+)", (\d+), "((?:[^"\\]|\\.)*)"', tracer)
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

# the tables the parser's tracer copies from parser.cpp
ptracer = open("docs/samples/parser/tracer.ol", encoding="utf-8").read()
pcpp = open("src/parser.cpp", encoding="utf-8").read()


def pairs(text):
    return re.findall(r'\{TokenType::(\w+), \'(.)\'\}', text)


# the precedence table: the operators of each level, loosest first, and the rank of the comparison
engine_levels = []
levels_text = pcpp[pcpp.index("const BinLevel LEVELS[]"):]
levels_text = levels_text[:levels_text.index("};")]
for item in re.findall(r'LEVEL\((\w+)\)|\{nullptr, 0\}', levels_text):
    if item:
        arr = pcpp[pcpp.index("const BinOp " + item + "[]"):]
        engine_levels.append(pairs(arr[:arr.index("};")]))
    else:
        engine_levels.append([])
block = ptracer[ptracer.index("const LEVELS = ["):]
block = block[:block.index("]\nconst CMP_LEVEL")]
block = re.sub(r"\s+", "", block[len("const LEVELS = ["):])
mine, depth, cur = [], 0, ""
for ch in block:
    if ch == "[":
        depth += 1
    if depth > 0:
        cur += ch
    if ch == "]":
        depth -= 1
        if depth == 0:
            mine.append(re.findall(r'\["(\w+)","(.)"\]', cur))
            cur = ""
cmp_level = int(re.search(r"const int CMP_LEVEL = (\d+);", pcpp).group(1))
errs = []
if [[tuple(p) for p in lv] for lv in engine_levels] != [[tuple(p) for p in lv] for lv in mine]:
    errs.append(f"the precedence levels: parser.cpp has {engine_levels}, tracer.ol has {mine}")
if int(re.search(r"const CMP_LEVEL = (\d+)", ptracer).group(1)) != cmp_level:
    errs.append("CMP_LEVEL is not the one of parser.cpp")
if int(re.search(r"const N_LEVELS = (\d+)", ptracer).group(1)) != len(engine_levels):
    errs.append("N_LEVELS is not the number of levels of parser.cpp")


def body(text, signature):
    start = text.index(signature)
    return text[start:text.index("\n}\n", start)]


def tracer_keys(name):
    inner = re.search(r"const " + name + r" = \{(.*?)\}", ptracer, re.S).group(1)
    return inner


cmp_body = body(pcpp, "static char cmp_char(")
engine_cmp = dict(re.findall(r"TokenType::(\w+)\)\s*return '(.)';", cmp_body))
engine_cmp["LESS"] = re.findall(r"return '(.)';", cmp_body)[-1]    # the token the other tests leave: LESS
mine_cmp = dict(re.findall(r"(\w+): \"(.)\"", tracer_keys("CMP_CHARS")))
if engine_cmp != mine_cmp:
    errs.append(f"the comparison characters: parser.cpp has {engine_cmp}, tracer.ol has {mine_cmp}")
engine_assign = set(re.findall(r"TokenType::(\w+)", body(pcpp, "static bool is_assign_op(")))
mine_assign = set(re.findall(r"(\w+):", tracer_keys("ASSIGN_OPS")))
if engine_assign != mine_assign:
    errs.append(f"the assignment operators: parser.cpp has {sorted(engine_assign)}, tracer.ol has {sorted(mine_assign)}")
engine_ends = set(re.findall(r"case TokenType::(\w+):", body(pcpp, "bool Parser::at_block_terminator() const {")))
mine_ends = set(re.findall(r"(\w+):", tracer_keys("BLOCK_ENDS")))
if engine_ends != mine_ends:
    errs.append(f"the tokens that end a block: parser.cpp has {sorted(engine_ends)}, tracer.ol has {sorted(mine_ends)}")
if errs:
    print("PARSER TRACE: the tables of tracer.ol are not those of parser.cpp")
    for e in errs:
        print("  " + e)
    sys.exit(1)
print(f"OK   parser tables ({len(engine_levels)} precedence levels, {len(engine_cmp)} comparisons, "
      f"{len(engine_assign)} assignment operators, {len(engine_ends)} block ends)")
PYEOF
