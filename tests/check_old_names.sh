#!/bin/bash
# Guard: the table of renamed names that the web app applies to a user's project on opening
# (OLD_NAMES in docs/lib/pg-store.js). A renamed callback does not fail, the engine just stops calling it, so a typo in
# a pattern leaves a project silently broken and nothing else would notice. The table is read out of the file and
# the app's own migrateText is run on the old spelling and on lookalikes that must stay as they are.
# Skipped, and said so, when node is missing.
# Usage: bash tests/check_old_names.sh
set -u
cd "$(dirname "$0")/.." || exit 2

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP old names: node is not installed"
    exit 0
fi

node - docs/lib/pg-store.js <<'EOF'
const fs = require('fs')
const src = fs.readFileSync(process.argv[2], 'utf8')
const table = src.match(/const OLD_NAMES = \[[\s\S]*?\n\]\n/)
const fn = src.match(/function migrateText\(text\) \{[\s\S]*?\n\}\n/)
if (!table || !fn) {
  console.log('FAIL old names: OLD_NAMES or migrateText was not found in ' + process.argv[2])
  process.exit(1)
}
const migrate = new Function(table[0] + fn[0] + 'return migrateText')()

const rewritten = [
  ['graphics.clear(1)', 'gfx.clear(1)'],
  ['keyboard.keypressed = func(key) end', 'keyboard.pressed = func(key) end'],
  ['func keyboard.keyrelease(key)', 'func keyboard.released(key)'],
  ['camera.open(640, 480)', 'webcam.open(640, 480)'],
  ['camera.isOpen()', 'webcam.isOpen()'],
  ['gfx.textSize("a")', 'gfx.measureText("a")'],
  ['math.smoothstep(0, 1, x)', 'math.smoothStep(0, 1, x)'],
  ['gfx.rotateq(q)', 'gfx.rotateQuat(q)'],
  ['image.unload(img)', 'image.free(img)'],
  ['gfx.fill(colors.RED)', 'gfx.fill(palette.RED)'],
  ['gfx.fill(colors.DARKGRAY)', 'gfx.fill(palette.DARK_GRAY)'],
  ['gfx.fill(palette.SKYBLUE)', 'gfx.fill(palette.SKY_BLUE)'],
  ['func touch.began(id, x, y)', 'func touch.pressed(id, x, y)'],
  ['func touch.ended(id, x, y)', 'func touch.released(id, x, y)'],
]
const untouched = [
  'var a = b.graphics',
  'import "graphics.ol"',
  'var m = {graphics: 1}',
  'var c = gfx.camera(0, 0, 5, 0, 0, 0)',
  'var s = mycolors.RED',
  'gfx.fill(palette.SKY_BLUE)',
  'func touch.pressed(id, x, y)',
  'var s = self.colors.RED',
  'var s = theme.colors.Primary',
  'self.camera.close()',
  'sprite.image.unload()',
  'player.touch.ended = 1',
  'import "graphics-utils.ol"',
  'import "lib/graphics.ol"',
  'var colors = {RED: 1}\nprint(colors.RED)',
  'global colors = {RED: 1}\nprint(colors.RED)',
  'func paint(colors)\n    return colors.RED\nend',
]

let fails = 0
for (const [before, after] of rewritten) {
  const got = migrate(before)
  if (got === after) console.log('OK   old names: ' + before)
  else { console.log('FAIL old names: ' + before + '  gave  ' + got + '  expected  ' + after); fails++ }
}
for (const text of untouched) {
  const got = migrate(text)
  if (got === text) console.log('OK   old names: ' + text + '  stays')
  else { console.log('FAIL old names: ' + text + '  was rewritten to  ' + got); fails++ }
}
process.exit(fails === 0 ? 0 : 1)
EOF
