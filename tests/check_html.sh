#!/bin/bash
# MARKUP guard: every fragment of the web app must be correctly nested.
#
# Why: a tag left unclosed does not break any test — the suite never opens a page — and the
# browser silently repairs the tree by nesting what follows INSIDE the unclosed element. The
# damage is only visible to the eye, and it was: an editing pass overwrote the two `</div>` of
# the playground's side rail, so the file list and the whole "Resources" section ended up inside
# the "Files" header. Reported by the user, not by the suite.
#
# What the script checks: the tags open and close in order, in the markup (everything after the
# view's <style>). It does NOT check the CSS, the appearance or the layout — only the tree.
set -u
here=$(dirname "$0")
root=$(cd "$here/.." && pwd)
cd "$root" || exit 2

python3 - "$@" <<'PYEOF'
import glob, re, sys

# Void elements close themselves, in HTML as in the inline SVG the views carry.
VOID = {"area", "base", "br", "col", "embed", "hr", "img", "input", "link", "meta", "param",
        "source", "track", "wbr",
        "path", "rect", "line", "circle", "ellipse", "polyline", "polygon", "use", "stop",
        "feGaussianBlur", "animate"}

def check(path):
    text = open(path, encoding="utf-8").read()
    # The <style> blocks and the comments are BLANKED, not cut out: CSS braces and a commented-out
    # tag are not markup, yet the line numbers must keep pointing at the real file. Blanking works
    # for a fragment (a view) as it does for a full document (the shell).
    markup = re.sub(r"<style[^>]*>.*?</style>|<!--.*?-->",
                    lambda m: re.sub(r"[^\n]", " ", m.group(0)), text, flags=re.S)
    stack, errs = [], []
    for m in re.finditer(r"<(/?)([a-zA-Z][a-zA-Z0-9]*)([^>]*?)(/?)>", markup):
        closing, tag, self_closing = m.group(1), m.group(2).lower(), m.group(4)
        if tag in VOID or self_closing:
            continue
        line = markup[:m.start()].count("\n") + 1   # the real line in the file
        if not closing:
            stack.append((tag, line))
            continue
        if not stack:
            errs.append(f"line {line}: </{tag}> closes nothing")
        elif stack[-1][0] != tag:
            opened, at = stack.pop()
            errs.append(f"line {line}: </{tag}> closes <{opened}>, opened at line {at}")
        else:
            stack.pop()
    for tag, line in stack:
        errs.append(f"line {line}: <{tag}> is never closed")
    return errs

bad = 0
for path in sorted(glob.glob("docs/views/*.html") + ["docs/index.html"]):
    errs = check(path)
    if errs:
        bad += 1
        for e in errs[:5]:
            print(f"HTML: {path}: {e}")
if bad:
    print(f"FAIL  {bad} file(s) with broken markup")
    sys.exit(1)
print("OK   markup nesting (docs/views/*.html, docs/index.html)")
PYEOF
