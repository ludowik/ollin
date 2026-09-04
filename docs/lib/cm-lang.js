// The Ollin language for CodeMirror 6 — the SINGLE SOURCE shared by the tutorial and the
// playground. This definition used to be duplicated in index.html AND playground.html, so
// every change to the syntax had to be carried over twice. Here there is one place only.
//
// It follows ollin.tmLanguage.json (the VS Code extension). The theme (background colours,
// borders, autocomplete styles) stays private to each view and is therefore NOT here — only
// the tokenizer and the highlighting (roles to colours) are.
import { StreamLanguage, HighlightStyle, tags } from '../vendor/codemirror.js'

// The union of the two former sets: `static` (tutorial) and `default` (playground).
export const KEYWORDS = new Set([
  'var', 'global', 'const', 'while', 'do', 'for', 'in', 'if', 'then', 'elseif', 'end',
  'break', 'true', 'false', 'nil', 'try', 'catch', 'throw', 'else', 'func', 'return',
  'import', 'as', 'or', 'and', 'not', 'class', 'extends', 'static', 'super', 'self',
  'switch', 'case', 'default', 'enum', 'ref',
])
export const BUILTINS = new Set([
  'print', 'printf', 'time', 'assert', 'len', 'typeof', 'Color',
  'math', 'graphics', 'string', 'colors', 'blend', 'window', 'image', 'keyboard', 'mouse', 'data', 'ui',
  'tween', 'camera',
])

export const ollinLang = StreamLanguage.define({
  name: 'ollin',
  startState: () => ({ block: false }),
  token(stream, state) {
    // Block comment ### … ###
    if (state.block) {
      if (stream.match('###')) { state.block = false; return 'comment' }
      stream.next(); return 'comment'
    }
    if (stream.match('###')) { state.block = true; return 'comment' }
    if (stream.eatSpace()) return null
    // Line comment ## (not ###)
    if (stream.match('##')) { stream.skipToEnd(); return 'comment' }
    // String "…"
    if (stream.peek() === '"') {
      stream.next()
      while (!stream.eol()) { const ch = stream.next(); if (ch === '"') break; if (ch === '\\') stream.next() }
      return 'string'
    }
    // Number: hex 0x.., octal 0o.., binary 0b.. (before the decimal form), then .5 / 42 / 42.0
    if (stream.match(/^0[xX][\da-fA-F](?:_?[\da-fA-F])*/)) return 'number'
    if (stream.match(/^0[oO][0-7](?:_?[0-7])*/)) return 'number'
    if (stream.match(/^0[bB][01](?:_?[01])*/)) return 'number'
    if (stream.match(/^\.\d[\d_]*/)) return 'number'
    if (stream.match(/^\d[\d_]*(?:\.[\d_]+)?/)) return 'number'
    // Identifier: keyword or builtin
    if (stream.match(/^[a-zA-Z_]\w*/)) {
      const w = stream.current()
      if (KEYWORDS.has(w)) return 'keyword'
      if (BUILTINS.has(w)) return 'atom'
      return null
    }
    // Operators (the multi-character ones first)
    if (stream.match(/^(\/\/|\+=|-=|\*=|\/=|%=|==|>=|<=|<>|<<|>>|\.\.\.|\.\.)/) ||
        stream.match(/^[+\-*/%><&|^~?\[\]{}:.]/)) return 'operator'
    stream.next(); return null
  },
})

// Roles to colours (the VS Code Dark+ palette). The same for every view.
export const ollinHighlight = HighlightStyle.define([
  { tag: tags.keyword,  color: '#569CD6' },
  { tag: tags.atom,     color: '#DCDCAA' },
  { tag: tags.number,   color: '#B5CEA8' },
  { tag: tags.string,   color: '#CE9178' },
  { tag: tags.comment,  color: '#6A9955', fontStyle: 'italic' },
  { tag: tags.operator, color: '#dde4ef' },
])
