#!/bin/bash
# LINE COVERAGE of the engine by the whole test suite (gcc --coverage + gcov), in a build of its own:
# build-cov/, ignored by git like every build*/ directory.
#
# Usage: bash tools/coverage.sh            the table, the lowest-covered files first, then a synthesis (language, modules)
#        bash tools/coverage.sh --check    also fails when the total falls under tools/coverage-floor
#        bash tools/coverage.sh --floor    records the current total, less half a point, as the floor
#
# What is measured: src/**/*.cpp, by tests/run.sh and tests/samples.sh run with the instrumented binary.
# That is the HEADLESS build, where graphics, image, camera and the other display modules are stubs
# (their real code is not compiled, so it is not in the figures). Headers are left out: the code of an
# inline function is counted once per translation unit that includes it, which makes their percentage mean
# nothing. A line that runs is not a line that is checked: only breaking it and watching the suite fail
# proves that. What the number is for is the lines nothing runs at all — the chained comparisons were one.
#
# Not part of tests/run.sh: building with --coverage takes a couple of minutes the first time.
set -eu
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root"
mode=${1:-}
dir=build-cov
floor_file=tools/coverage-floor

mkdir -p "$dir"
log="$dir/build.log"
cmake -S . -B "$dir" -DCMAKE_BUILD_TYPE=Debug -DCMAKE_CXX_FLAGS="--coverage -O0" \
    -DCMAKE_EXE_LINKER_FLAGS="--coverage" >"$log" 2>&1 || { tail -5 "$log"; exit 1; }
cmake --build "$dir" -j"$(nproc 2>/dev/null || echo 4)" --target ollin >>"$log" 2>&1 || { tail -15 "$log"; exit 1; }
find "$dir" -name '*.gcda' -delete

bin="$root/$dir/ollin"
# Every suite runs: a failure here is not the point (the suite reports it), the counters are.
OLLIN="$bin" bash tests/run.sh >/dev/null 2>&1 || echo "note: tests/run.sh failed with the instrumented binary"
OLLIN="$bin" bash tests/samples.sh >/dev/null 2>&1 || echo "note: tests/samples.sh failed with the instrumented binary"

python3 - "$dir" "$mode" "$floor_file" <<'PYEOF'
import os, re, subprocess, sys

build, mode, floor_file = sys.argv[1:4]
root = os.getcwd()
gcdas = subprocess.run(["find", build, "-name", "*.gcda"], capture_output=True, text=True).stdout.split()
files = {}
for gcda in gcdas:
    where = os.path.dirname(gcda)
    out = subprocess.run(["gcov", "-n", os.path.basename(gcda)], cwd=where, capture_output=True, text=True).stdout
    current = None
    for line in out.splitlines():
        m = re.match(r"File '(.*)'", line)
        if m:
            current = m.group(1)
            continue
        m = re.match(r"Lines executed:([\d.]+)% of (\d+)", line)
        if m and current:
            if current.startswith(root + "/src/") and current.endswith(".cpp"):
                files[os.path.relpath(current, root)] = (float(m.group(1)), int(m.group(2)))
            current = None

total = sum(n for _, n in files.values())
hit = sum(p * n / 100 for p, n in files.values())
percent = 100 * hit / total
print(f"{'covered':>8}  {'lines':>6}  file")
for name, (p, n) in sorted(files.items(), key=lambda kv: kv[1][0]):
    print(f"{p:7.1f}%  {n:6d}  {name}")
print(f"{percent:7.1f}%  {total:6d}  TOTAL ({int(round(hit))} of {total} lines, {len(files)} files)")

# The synthesis: the language (everything outside src/modules/), then one row per module, the stubs
# together on the last row (a display module is a stub in this headless build, so its 0 % means nothing).
LANGUAGE_ROWS = [
    ("lexer", ["src/lexer.cpp"]),
    ("parser", ["src/parser.cpp"]),
    ("compiler", ["src/compiler.cpp", "src/chunk.cpp"]),
    ("vm", ["src/vm.cpp"]),
    ("collections", [f for f in files if f.startswith("src/collections/")]),
    ("paths and sources", ["src/paths.cpp", "src/source_registry.cpp"]),
    ("entry point", ["src/main.cpp"]),
]
named = {f for _, group in LANGUAGE_ROWS for f in group}
other_language = sorted(f for f in files if not f.startswith("src/modules/") and f not in named)
if other_language:
    LANGUAGE_ROWS.append(("other", other_language))
stubs = sorted(f for f in files if f.startswith("src/modules/") and f.endswith("_stub.cpp"))
module_files = sorted(f for f in files if f.startswith("src/modules/") and f not in stubs)


def row(label, names):
    names = [n for n in names if n in files]
    lines = sum(files[n][1] for n in names)
    covered = sum(files[n][0] * files[n][1] / 100 for n in names)
    return label, (100 * covered / lines if lines else 100.0), lines, int(round(lines - covered))


def section(title, rows, counted=None):
    print(f"\n{title}")
    print(f"{'covered':>8}  {'lines':>6}  {'unrun':>5}  area")
    for label, pct, n, miss in rows:
        print(f"{pct:7.1f}%  {n:6d}  {miss:5d}  {label}")
    counted = rows if counted is None else counted
    lines = sum(r[2] for r in counted)
    unrun = sum(r[3] for r in counted)
    note = "subtotal" if counted is rows else "subtotal (stubs left out)"
    print(f"{100 * (lines - unrun) / lines if lines else 100.0:7.1f}%  {lines:6d}  {unrun:5d}  {note}")


print("\nSYNTHESIS")
section("Language", [row(label, group) for label, group in LANGUAGE_ROWS])
module_rows = [row(os.path.basename(f)[:-4].replace("_module", ""), [f]) for f in module_files]
section("Modules", module_rows + [row(f"stubs ({len(stubs)}, expected low)", stubs)], counted=module_rows)

if mode == "--floor":
    floor = round(percent - 0.5, 1)
    open(floor_file, "w").write(f"{floor}\n")
    print(f"floor recorded: {floor}% ({floor_file})")
elif mode == "--check":
    floor = float(open(floor_file).read().strip())
    if percent < floor:
        print(f"FAIL  coverage {percent:.1f}% is under the floor of {floor}%")
        sys.exit(1)
    print(f"OK   coverage {percent:.1f}% (floor {floor}%)")
PYEOF
