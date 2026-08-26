#!/bin/bash
# CATALOGUE guard: docs/samples/index.json and the sample files must agree.
#
# Why: the catalogue is the only link between the playground's menu and the files. Renaming a
# sample leaves a dangling entry that NO test sees — the failure only shows when a reader opens
# the menu in the browser and gets nothing. Adding a sample without listing it is the symmetric
# mistake: the example exists in the repository and is reachable from nowhere.
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

python3 - <<'PYEOF'
import glob, json, os, sys

# The LIBRARIES are imported by other samples (import "trackball.ol"), not opened on their own:
# they have no setup() and no draw(), so the menu must not offer them.
LIBS = {"trackball.ol", "joystick.ol", "view_distance.ol"}

errs = []
try:
    entries = json.load(open("docs/samples/index.json", encoding="utf-8"))
except Exception as e:
    print(f"SAMPLES: index.json is unreadable: {e}")
    sys.exit(1)

listed = []
for i, e in enumerate(entries):
    for key in ("group", "name", "file"):
        if not isinstance(e.get(key), str) or not e[key]:
            errs.append(f"entry {i + 1}: '{key}' is missing or is not a string")
    f = e.get("file")
    if isinstance(f, str):
        listed.append(f)
        if not os.path.isfile(os.path.join("docs/samples", f)):
            errs.append(f"{f}: listed but the file does not exist")
        if f in LIBS:
            errs.append(f"{f}: a library must not be offered as a sample")

for f in listed:
    if listed.count(f) > 1:
        errs.append(f"{f}: listed more than once")
        break

on_disk = {os.path.basename(p) for p in glob.glob("docs/samples/*.ol")}
for f in sorted(on_disk - set(listed) - LIBS):
    errs.append(f"{f}: present in docs/samples/ but absent from index.json")

# A group split in two by a stray entry in between would show TWICE in the menu, the order of the
# groups being that of their first appearance.
seen, prev = [], None
for e in entries:
    g = e.get("group")
    if g != prev and g in seen:
        errs.append(f"group '{g}': its entries are not contiguous, so the menu would show it twice")
    if g != prev:
        seen.append(g)
    prev = g

if errs:
    for e in errs[:8]:
        print(f"SAMPLES: {e}")
    print(f"FAIL  {len(errs)} problem(s) in the sample catalogue")
    sys.exit(1)
groups = len(dict.fromkeys(e["group"] for e in entries))
print(f"OK   sample catalogue ({len(entries)} samples in {groups} groups, {len(LIBS)} libraries)")
PYEOF
