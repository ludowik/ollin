#!/bin/bash
# API COVERAGE guard: every function the engine exposes to scripts must be NAMED by at least one test.
#
# Why: a function nobody calls is a function nobody checks. A line-coverage measurement (gcov, over the
# whole suite) found ten math functions, two Color methods and tween.curves() that no test had ever
# called, and a compiler visitor (chained comparisons) that nothing had ever run. This guard is the
# cheap, permanent half of that measurement: it runs in a second, in run.sh.
#
# What it reads: the names the modules register — `.fn("x")`, `.static_fn("x")`, `.set("x", make_builtin)`
# and `map_set(Value(std::string("x")), make_builtin)` in src/modules/*.cpp — and the text of the tests
# (tests/syntax.ol, tests/test_errors.sh, tests/regressions/, the fixtures of tests/, and the tests of the
# samples). A name is NAMED when a test writes `.name` or `name(`.
#
# What it does NOT do: it compares NAMES, it does not run anything. It sees a function nobody mentions,
# not a function whose test asserts the wrong thing; and `.play(` anywhere in a test names every `play` of
# every module. The numbers of a real line-coverage run are the other half (tools/coverage.sh).
#
# EXCLUDED, with the reason: the modules that need a display or a device and are `nil` or inert in the
# headless build this suite runs on — graphics (2D, 3D, quaternions), image, camera, mouse, keyboard — and
# the stubs, whose names are those of the real module. The ui module is checked: its stub has the same names.
# The meta names (`__str`, `__fmt`...) are the engine's own hooks, not API.
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

python3 - <<'PYEOF'
import collections, glob, os, re, sys

EXCLUDE = {"graphics_module", "graphics3d", "graphics_quat", "image_module", "camera_module",
           "keyboard_module", "mouse_module"}
PATTERNS = [
    r'\.(?:fn|static_fn)\("([A-Za-z_]\w*)"',
    r'\.set\("([A-Za-z_]\w*)",\s*Value::make_(?:static_)?builtin',
    r'map_set\(Value\(std::string\("([A-Za-z_]\w*)"\)\),\s*Value::make_(?:static_)?builtin',
]

names = collections.defaultdict(set)
for path in sorted(glob.glob("src/modules/*.cpp")):
    stem = os.path.basename(path)[:-4]
    if stem in EXCLUDE or stem.endswith("_stub"):
        continue
    src = open(path, encoding="utf-8", errors="replace").read()
    for pattern in PATTERNS:
        for m in re.finditer(pattern, src):
            if not m.group(1).startswith("__"):
                names[stem].add(m.group(1))

tests = (["tests/syntax.ol", "tests/test_errors.sh"] + glob.glob("tests/regressions/*/*.ol")
         + glob.glob("tests/*_test.ol") + glob.glob("tests/gfx_*.ol")
         + glob.glob("docs/samples/**/*_test.ol", recursive=True))
text = "\n".join(open(t, encoding="utf-8", errors="replace").read() for t in tests)

total = sum(len(ns) for ns in names.values())
missing = []
for stem, ns in sorted(names.items()):
    for n in sorted(ns):
        if not (re.search(r"\." + re.escape(n) + r"\b", text) or re.search(r"\b" + re.escape(n) + r"\s*\(", text)):
            missing.append(f"{stem.replace('_module', '')}.{n}")

if missing:
    for m in missing[:12]:
        print(f"API: {m} is exposed but no test names it")
    print(f"FAIL  {len(missing)} of {total} exposed functions are named by no test")
    sys.exit(1)
print(f"OK   API coverage ({total} exposed functions, each named by a test)")
PYEOF
