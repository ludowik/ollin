#!/bin/bash
# Guard: the table of renamed names that the web app applies to a user's project on opening (OLD_NAMES in
# docs/lib/pg-migrate.js). A renamed callback does not fail, the engine just stops calling it, so a typo in a pattern
# leaves a project silently broken and nothing else would notice. The app's own migrateText is run on the old spelling
# and on lookalikes that must stay as they are, and every rule of the table must be rewritten by at least one case: a
# rule added with no case fails here.
# Skipped, and said so, when node is missing.
# Usage: bash tests/check_old_names.sh
set -u
cd "$(dirname "$0")/.." || exit 2

if ! command -v node >/dev/null 2>&1; then
    echo "SKIP old names: node is not installed"
    exit 0
fi

node - docs/lib/pg-migrate.js <<'EOF'
const fs = require('fs')
const src = fs.readFileSync(process.argv[2], 'utf8')
// The file is a pure ES module: its `export` keywords are the only thing node's script mode cannot read.
const { OLD_NAMES, migrateText: migrate } = new Function(
  src.replace(/^export /gm, '') + '\nreturn { OLD_NAMES, migrateText }')()

const rewritten = [
  ['graphics.clear(1)', 'gfx.clear(1)'],
  ['keyboard.keypressed = func(key) end', 'keyboard.pressed = func(key) end'],
  ['func keyboard.keyrelease(key)', 'func keyboard.released(key)'],
  ['camera.open(640, 480)', 'webcam.open(640, 480)'],
  ['camera.close()', 'webcam.close()'],
  ['camera.capture()', 'webcam.capture()'],
  ['camera.isOpen()', 'webcam.isOpen()'],
  ['gfx.textSize("a")', 'gfx.measureText("a")'],
  ['math.smoothstep(0, 1, x)', 'math.smoothStep(0, 1, x)'],
  ['gfx.rotateq(q)', 'gfx.rotateQuat(q)'],
  ['image.unload(img)', 'image.free(img)'],
  ['gfx.fill(colors.RED)', 'gfx.fill(palette.RED)'],
  ['gfx.fill(colors.DARKGRAY)', 'gfx.fill(palette.DARK_GRAY)'],
  ['gfx.fill(palette.DARKGRAY)', 'gfx.fill(palette.DARK_GRAY)'],
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
  if (got === after) console.log('OK   old names: ' + before.replace(/\n/g, ' ⏎ '))
  else { console.log('FAIL old names: ' + before + '  gave  ' + got + '  expected  ' + after); fails++ }
}
for (const text of untouched) {
  const got = migrate(text)
  if (got === text) console.log('OK   old names: ' + text.replace(/\n/g, ' ⏎ ') + '  stays')
  else { console.log('FAIL old names: ' + text + '  was rewritten to  ' + got); fails++ }
}
for (const [pattern] of OLD_NAMES) {
  const once = new RegExp(pattern.source, pattern.flags.replace('g', ''))
  if (!rewritten.some(([before]) => once.test(before))) {
    console.log('FAIL old names: no case rewrites the rule ' + pattern)
    fails++
  }
}
process.exit(fails === 0 ? 0 : 1)
EOF
