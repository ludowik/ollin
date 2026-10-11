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
import glob, json, os, re, sys

# A LIBRARY is a file IMPORTED by another one: it is not opened on its own, so the menu must not
# offer it and the catalogue must not list it. That is read from the code rather than kept in a
# list — the list had to be rewritten the day the files moved, and an omission turns this guard
# into a false alarm. The resolution is the parser's: relative to the importing file's directory,
# with "." and ".." collapsed.
def path_is_absolute(p):
    # The parser's rule (paths.h): a leading "/" or a Windows drive letter.
    return p.startswith("/") or (len(p) > 1 and p[1] == ":")


def path_normalise(p):
    absolute = p.startswith("/")
    parts = []
    for seg in p.split("/"):
        if seg == "..":
            if parts and parts[-1] != "..":
                parts.pop()
            elif not absolute:
                parts.append(seg)
        elif seg and seg != ".":
            parts.append(seg)
    return ("/" if absolute else "") + "/".join(parts)

def imported_by(paths):
    libs = set()
    for rel in paths:
        base = rel.rsplit("/", 1)[0] + "/" if "/" in rel else ""
        src = open(os.path.join("docs/samples", rel), encoding="utf-8").read()
        for imp in re.findall(r'(?m)^\s*import\s+["\']([^"\']+)', src):
            if not imp.endswith(".ol"):
                imp += ".ol"
            libs.add(path_normalise(imp if path_is_absolute(imp) else base + imp))
    return libs

errs = []

# RECURSIVE, and by relative path: a sample kept in a sub-directory (an example split over several
# files) is a legitimate layout, and globbing the top level only would let it escape the catalogue
# entirely — exactly the oversight this guard exists to catch. The path is the identity, so two
# files of the same name in different directories no longer collide either.
on_disk = {os.path.relpath(p, "docs/samples").replace(os.sep, "/")
           for p in glob.glob("docs/samples/**/*.ol", recursive=True)}
LIBS = imported_by(on_disk)
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

# The ICONS the home screen shows. An entry may name one (tools/gen_sample_icons.js writes them); a
# name with no file would show a generated tile in its place, so it fails nowhere and nobody sees it,
# and a picture no entry names is dead weight shipped to every visitor. Only existence and weight are
# checked: whether a picture still matches its example is for the generator to renew.
ICON_MAX = 200 * 1024
named = set()
for e in entries:
    icon = e.get("icon")
    if icon is None:
        continue
    f = e.get("file")
    if not (isinstance(icon, str) and icon.startswith("icons/") and icon.endswith(".png")):
        errs.append(f"{f}: 'icon' must be a path under icons/ ending in .png")
        continue
    named.add(icon)
    path = os.path.join("docs/samples", icon)
    if not os.path.isfile(path):
        errs.append(f"{f}: icon {icon} does not exist")
    elif os.path.getsize(path) > ICON_MAX:
        errs.append(f"{icon}: {os.path.getsize(path) // 1024} KB, more than the {ICON_MAX // 1024} KB an icon may weigh")
    elif open(path, "rb").read(8) != b"\x89PNG\r\n\x1a\n":
        errs.append(f"{icon}: not a PNG")
for p in sorted(glob.glob("docs/samples/icons/*")):
    rel = os.path.relpath(p, "docs/samples").replace(os.sep, "/")
    if rel not in named:
        errs.append(f"{rel}: in docs/samples/icons/ but named by no entry of index.json")

for f in listed:
    if listed.count(f) > 1:
        errs.append(f"{f}: listed more than once")
        break

for f in sorted(on_disk - set(listed) - LIBS):
    errs.append(f"{f}: present in docs/samples/ but absent from index.json")
for f in sorted(LIBS - on_disk):
    errs.append(f"{f}: imported by a sample but the file does not exist")


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
print(f"OK   sample catalogue ({len(entries)} samples in {groups} groups, {len(LIBS)} libraries, {len(named)} icons)")
PYEOF
