// Langage Ollin pour CodeMirror 6 — SOURCE UNIQUE partagée par le tutoriel, le
// playground et (à terme) la web app monopage. Avant, cette définition était
// dupliquée dans index.html ET playground.html : toute évolution de la syntaxe
// devait être reportée deux fois. Ici : un seul endroit.
//
// Aligne sur ollin.tmLanguage.json (extension VS Code). Le thème (couleurs de
// fond, bordures, styles d'autocomplétion) reste propre à chaque vue et n'est
// donc PAS ici — seuls le tokenizer et le highlight (rôles → couleurs) le sont.
import { StreamLanguage, HighlightStyle, tags } from './vendor/codemirror.js'

// Union des deux anciens ensembles : `static` (tutoriel) + `default` (playground).
export const KEYWORDS = new Set([
  'var', 'global', 'const', 'while', 'do', 'for', 'in', 'if', 'then', 'elseif', 'end',
  'break', 'true', 'false', 'nil', 'try', 'catch', 'throw', 'else', 'func', 'return',
  'import', 'as', 'or', 'and', 'not', 'class', 'extends', 'static', 'super', 'self',
  'switch', 'case', 'default',
])
export const BUILTINS = new Set([
  'print', 'printf', 'time', 'assert', 'len', 'typeof', 'Color',
  'math', 'graphics', 'string', 'colors', 'blend', 'window', 'image', 'keyboard', 'mouse',
])

export const ollinLang = StreamLanguage.define({
  name: 'ollin',
  startState: () => ({ block: false }),
  token(stream, state) {
    // Commentaire bloc ### … ###
    if (state.block) {
      if (stream.match('###')) { state.block = false; return 'comment' }
      stream.next(); return 'comment'
    }
    if (stream.match('###')) { state.block = true; return 'comment' }
    if (stream.eatSpace()) return null
    // Commentaire ligne ## (pas ###)
    if (stream.match('##')) { stream.skipToEnd(); return 'comment' }
    // Chaîne "…"
    if (stream.peek() === '"') {
      stream.next()
      while (!stream.eol()) { const ch = stream.next(); if (ch === '"') break; if (ch === '\\') stream.next() }
      return 'string'
    }
    // Nombre : hex 0x.. / octal 0o.. / binaire 0b.. (avant le décimal), puis .5 / 42 / 42.0
    if (stream.match(/^0[xX][\da-fA-F](?:_?[\da-fA-F])*/)) return 'number'
    if (stream.match(/^0[oO][0-7](?:_?[0-7])*/)) return 'number'
    if (stream.match(/^0[bB][01](?:_?[01])*/)) return 'number'
    if (stream.match(/^\.\d[\d_]*/)) return 'number'
    if (stream.match(/^\d[\d_]*(?:\.[\d_]+)?/)) return 'number'
    // Identifiant → mot-clé / builtin
    if (stream.match(/^[a-zA-Z_]\w*/)) {
      const w = stream.current()
      if (KEYWORDS.has(w)) return 'keyword'
      if (BUILTINS.has(w)) return 'atom'
      return null
    }
    // Opérateurs (multi-caractères d'abord)
    if (stream.match(/^(\/\/|\+=|-=|\*=|\/=|%=|==|>=|<=|<>|<<|>>|\.\.\.|\.\.)/) ||
        stream.match(/^[+\-*/%><&|^~?\[\]{}:.]/)) return 'operator'
    stream.next(); return null
  },
})

// Rôles → couleurs (palette VS Code Dark+). Identique pour toutes les vues.
export const ollinHighlight = HighlightStyle.define([
  { tag: tags.keyword,  color: '#569CD6' },
  { tag: tags.atom,     color: '#DCDCAA' },
  { tag: tags.number,   color: '#B5CEA8' },
  { tag: tags.string,   color: '#CE9178' },
  { tag: tags.comment,  color: '#6A9955', fontStyle: 'italic' },
  { tag: tags.operator, color: '#c9d1e0' },
])
