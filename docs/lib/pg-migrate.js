// Ollin playground — the rewrite of renamed names in a project's scripts (pure text, no browser API: the guard
// tests/check_old_names.sh loads this file in node).
//
// TEMPORARY, to remove once the existing projects have been opened: names of the engine were renamed with no alias,
// so a project written before fails (`graphics`: "undeclared variable") or silently stops being called (a keyboard
// callback). Opening a project rewrites the old names in its scripts (pg-store.js, getProject), and the rewrite is
// KEPT: stored, and flagged to be pushed, so the project is updated for good and not at every opening.
//
// One line per rename: `renamed(old, new)` for a plain `module.name`, a hand-written rule when the name needs more.
// tests/check_old_names.sh fails for a rule that none of its cases rewrites: add the case with the rule.
//
// NO line, on purpose: a name too common to rewrite blindly, whose old use fails loudly instead of going silent.
//   array.contains -> array.has      `.contains(` would also rewrite the method of a class of the user
//   request.done   -> request.isDone `.done(` is a name too many scripts own (a `done` field, a `done` method)
//   array.add (removed)              nothing to rewrite to: `push` is the call
// A word inside a string or a comment is rewritten like code, and a variable the user named like an old module is not
// told from the module: both need a lexer, and are accepted.

// Not preceded by `.` or a word character: `self.camera.close()` is a field of the user, not the old module.
const alone = '(?<![.\\w])'

function renamed(from, to) {
  return [new RegExp(alone + from.replace(/\./g, '\\.') + '\\b', 'g'), to]
}

export const OLD_NAMES = [
  // `graphics` alone: not a path or a file name (`graphics.ol`, `graphics-utils.ol`), not a map key (`graphics:`).
  [/(?<![.\w/-])graphics\b(?![\w-]|\.ol|\s*:)/g, 'gfx'],
  renamed('keyboard.keypressed', 'keyboard.pressed'),
  renamed('keyboard.keyrelease', 'keyboard.released'),
  // The module of the webcam; gfx.camera is the 3D camera, untouched.
  renamed('camera.open', 'webcam.open'),
  renamed('camera.close', 'webcam.close'),
  renamed('camera.capture', 'webcam.capture'),
  renamed('camera.isOpen', 'webcam.isOpen'),
  // It measures a text; fontSize and strokeSize set a size.
  renamed('gfx.textSize', 'gfx.measureText'),
  renamed('math.smoothstep', 'math.smoothStep'),
  renamed('gfx.rotateq', 'gfx.rotateQuat'),
  renamed('image.unload', 'image.free'),
  // The module of the named colours. A project that declares its own `colors` (a variable or a parameter) keeps it:
  // `colors.RED` is then its field. The third element is tested on the whole script.
  [new RegExp(alone + 'colors\\.([A-Z])', 'g'), 'palette.$1',
   /\b(?:var|global|const)\s+colors\b|\bfunc\b[^\n(]*\([^\n)]*\bcolors\b/],
  renamed('palette.DARKGRAY', 'palette.DARK_GRAY'),
  renamed('palette.SKYBLUE', 'palette.SKY_BLUE'),
  renamed('touch.began', 'touch.pressed'),
  renamed('touch.ended', 'touch.released'),
]

export function migrateText(text) {
  let migrated = text
  for (const [oldName, newName, skipIf] of OLD_NAMES) {
    if (skipIf && skipIf.test(text)) continue
    migrated = migrated.replace(oldName, newName)
  }
  return migrated
}
