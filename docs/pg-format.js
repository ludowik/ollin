// On-demand Ollin formatter — reindentation by blocks, line by line and without an AST. It
// changes ONLY the indentation and the superfluous spaces, never the meaning. Conventions
// (see tests/syntax.ol):
//   func / if…then / while…do / for…do / class / try / enum → +1 level, closed by `end`
//   switch                                            → +1 (the level of the `case`s)
//   case / else (inside a switch) / default            → at the switch's level, body +1
//   case … do                                          → the `do` is an ordinary block of the
//     case's body; it shares the case's level and it is ITS `end` that closes it
//   else / elseif / catch                              → the line is outdented, the body is not
// A line that opens BOTH a block and a delimiter — `f(x, func()` — counts for ONE level only:
// the block "absorbs" the delimiters left open on its opening line, without which its body
// would be indented twice.
// Strings "…" and comments (## a line, ### a block ###) never have their content touched.
// On unbalanced blocks it returns { ok:false } and reformats nothing.

const UNIT = '    '
// Every keyword opening a block closed by `end` (see docs/grammar.ebnf); `switch` and `do` are
// handled apart (their own stack, and an opener only at the start of a line).
const OPENERS = /\b(?:func|if|while|for|class|try|enum)\b/g
const count = (s, re) => (s.match(re) || []).length

// Removes strings and the end-of-line comment, leaving only the "bare" code, so that keywords
// can be counted and spotted without false positives.
function bareCode(s) {
  let r = '', i = 0, inStr = false
  while (i < s.length) {
    const c = s[i]
    if (inStr) {
      if (c === '\\') { i += 2; continue }
      if (c === '"') inStr = false
      i++; continue
    }
    if (c === '"') { inStr = true; i++; continue }
    if (c === '#' && s[i + 1] === '#') break   // ## ou ### → reste = commentaire
    r += c; i++
  }
  return r
}

export function formatOllin(src) {
  const lines = src.split('\n')
  const out = []
  // Stack of BLOCK contexts. Each entry is { kind: 'block'|'switch'|'case', absorb: the
  // delimiters left open on the block's opening line, already counted by it }.
  const st = []
  let delim = 0                 // profondeur des délimiteurs ouverts { [ ( (map/array/appels)
  let absorbed = 0              // somme des `absorb` de la pile
  let inBlockComment = false
  const top = () => (st.length ? st[st.length - 1].kind : undefined)
  const pushBlock = (kind, absorb = 0) => { st.push({ kind, absorb }); absorbed += absorb }
  const popBlock = () => { const e = st.pop(); absorbed -= e.absorb; return e }
  const level = () => st.length + delim - absorbed

  for (const raw of lines) {
    const trimmed = raw.replace(/\s+$/, '')   // enlève les espaces de fin
    const body = trimmed.trim()

    // Block comment ### … ###: the content is kept verbatim.
    const hashes = (body.match(/###/g) || []).length
    if (inBlockComment) {
      out.push(trimmed)                        // ne pas reformater l'intérieur
      if (hashes % 2 === 1) inBlockComment = false
      continue
    }

    if (body === '') { out.push(''); continue }

    const code = bareCode(body)
    const first = (code.match(/^([A-Za-z_]\w*)/) || [])[1] || ''
    const inSwitch = top() === 'case' || top() === 'caseblock' || top() === 'switch'

    let show = level()             // niveau d'indentation d'affichage de la ligne

    if (first === 'end') {
      if (top() === 'caseblock') {
        // `case … do`: this `end` closes the body's do block; the case itself runs to the
        // next case or to the switch's `end`.
        st[st.length - 1].kind = 'case'
        show = level() - 1
      } else {
        if (top() === 'case') popBlock()            // fin du corps de case
        if (st.length === 0) return { ok: false, error: '« end » sans bloc ouvert' }
        const closed = popBlock()                   // ferme le bloc/switch
        // `end` aligns with the line that opened the block: its absorbed delimiters still
        // count, since they are only closed here (`end)`).
        show = level() - closed.absorb
      }
    } else if (first === 'case' || first === 'default' ||
               (first === 'else' && inSwitch)) {
      if (top() === 'case') popBlock()              // fin du case précédent
      show = level()                           // au niveau du switch
      // `case … do`: the body's do block shares the case's level, and its `end` closes only
      // that block (the case runs to the next case or to the switch's `end`).
      pushBlock(/\bdo\s*$/.test(code) ? 'caseblock' : 'case')
    } else if (first === 'else' || first === 'elseif' || first === 'catch') {
      show = level() - 1                       // ligne dé-indentée, pile inchangée
    } else {
      // A line starting with a closing delimiter is outdented by one step.
      if (/^[})\]]/.test(code)) show = level() - 1
      // Net BLOCK openings and closings on the line (a one-liner nets zero).
      const sw = count(code, /\bswitch\b/g)
      // A standalone `do` (doStmt) is an opener only when it is the line's first word: in
      // `while x do` or `for i=1,10 do`, `first` is `while` or `for`, not `do`.
      const doBlock = first === 'do' ? 1 : 0
      let net = count(code, OPENERS) - count(code, /\bend\b/g)
      const opened = st.length
      while (net > 0) { pushBlock('block'); net-- }
      while (net < 0) { if (top() === 'case') popBlock(); if (st.length) popBlock(); net++ }
      for (let k = 0; k < sw; k++) pushBlock('switch')
      for (let k = 0; k < doBlock; k++) pushBlock('block')
      // Delimiters left open by this line are already represented by the level of the block it
      // opens, so the innermost block absorbs them.
      const openDelims = delimBalance(code)
      if (st.length > opened && openDelims > 0) {
        st[st.length - 1].absorb = openDelims
        absorbed += openDelims
      }
    }

    out.push(UNIT.repeat(Math.max(0, show)) + body)

    delim = Math.max(0, delim + delimBalance(code))   // maj délimiteurs pour la suite

    // A ### left open on this line (an odd number of ### outside a string) starts a comment block.
    if (bareCodeHashes(body) % 2 === 1) inBlockComment = true
  }

  if (st.length !== 0) return { ok: false, error: 'bloc non fermé (« end » manquant)' }
  return { ok: true, code: out.join('\n') }
}

// Balance of the delimiters on a line of bare code: { } (maps), ( ) (calls and groups) and
// [ ] (arrays). Brackets are ambiguous in Ollin — in a range, "[a;b[" closes with "[" and
// "]a;b]" opens with "]" — but a range ALWAYS holds a ";" between its bounds, so on a line
// carrying one the brackets are not counted. Without that, an array written over several lines
// would have its content outdented.
function delimBalance(code) {
  const brackets = !code.includes(';')
  let n = 0
  for (const c of code) {
    if (c === '{' || c === '(') n++
    else if (c === '}' || c === ')') n--
    else if (brackets && c === '[') n++
    else if (brackets && c === ']') n--
  }
  return n
}

// Counts the ### that really are outside a string, for the comment-block state.
function bareCodeHashes(s) {
  let n = 0, i = 0, inStr = false
  while (i < s.length) {
    const c = s[i]
    if (inStr) { if (c === '\\') { i += 2; continue } if (c === '"') inStr = false; i++; continue }
    if (c === '"') { inStr = true; i++; continue }
    if (c === '#' && s[i + 1] === '#' && s[i + 2] === '#') { n++; i += 3; continue }
    i++
  }
  return n
}
