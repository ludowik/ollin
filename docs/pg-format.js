// Formateur Ollin « à la demande » — réindentation par blocs (heuristique ligne
// par ligne, pas d'AST). Ne change QUE l'indentation et les espaces superflus,
// jamais la sémantique. Conventions (cf. tests/syntax.ol) :
//   func / if…then / while…do / for…do / class / try  → +1 niveau, fermé par `end`
//   switch                                            → +1 (niveau des `case`)
//   case / else(dans switch) / default                → au niveau du switch, corps +1
//   else / elseif / catch                             → ligne dé-indentée, corps au niveau
// Chaînes "…" et commentaires (## ligne, ### bloc ###) : contenu jamais touché.
// En cas de blocs déséquilibrés, renvoie { ok:false } sans rien reformater.

const UNIT = '    '
const OPENERS = /\b(?:func|if|while|for|class|try)\b/g   // switch traité à part
const count = (s, re) => (s.match(re) || []).length

// Retire chaînes et commentaire de fin de ligne → ne reste que le code « nu »
// pour compter/repérer les mots-clés sans faux positifs.
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
  const st = []                 // pile de contextes de BLOC : 'block' | 'switch' | 'case'
  let delim = 0                 // profondeur des délimiteurs ouverts { [ ( (map/array/appels)
  let inBlockComment = false
  const top = () => st[st.length - 1]

  for (const raw of lines) {
    const trimmed = raw.replace(/\s+$/, '')   // enlève les espaces de fin
    const body = trimmed.trim()

    // ── commentaire bloc ### … ### : contenu verbatim ──────────────────────
    const hashes = (body.match(/###/g) || []).length
    if (inBlockComment) {
      out.push(trimmed)                        // ne pas reformater l'intérieur
      if (hashes % 2 === 1) inBlockComment = false
      continue
    }

    if (body === '') { out.push(''); continue }

    const code = bareCode(body)
    const first = (code.match(/^([A-Za-z_]\w*)/) || [])[1] || ''
    const inSwitch = top() === 'case' || top() === 'switch'

    let show = st.length + delim   // niveau d'indentation d'affichage de la ligne

    if (first === 'end') {
      if (top() === 'case') st.pop()           // fin du corps de case
      if (st.length === 0) return { ok: false, error: '« end » sans bloc ouvert' }
      st.pop()                                 // ferme le bloc/switch
      show = st.length + delim
    } else if (first === 'case' || first === 'default' ||
               (first === 'else' && inSwitch)) {
      if (top() === 'case') st.pop()           // fin du case précédent
      show = st.length + delim                 // au niveau du switch
      st.push('case')                          // ouvre le corps du nouveau case
    } else if (first === 'else' || first === 'elseif' || first === 'catch') {
      show = st.length - 1 + delim             // ligne dé-indentée, pile inchangée
    } else {
      // ligne commençant par un fermant de délimiteur → dé-indentée d'un cran
      if (/^[})]/.test(code)) show = st.length + delim - 1
      // ouvertures/fermetures nettes de BLOCS sur la ligne (mono-ligne = net 0)
      const sw = count(code, /\bswitch\b/g)
      let net = count(code, OPENERS) - count(code, /\bend\b/g)
      while (net > 0) { st.push('block'); net-- }
      while (net < 0) { if (top() === 'case') st.pop(); if (st.length) st.pop(); net++ }
      for (let k = 0; k < sw; k++) st.push('switch')
    }

    out.push(UNIT.repeat(Math.max(0, show)) + body)

    delim = Math.max(0, delim + delimBalance(code))   // maj délimiteurs pour la suite

    // ### ouvert sur cette ligne (nombre impair de ### hors chaîne) → bloc commentaire
    if (bareCodeHashes(body) % 2 === 1) inBlockComment = true
  }

  if (st.length !== 0) return { ok: false, error: 'bloc non fermé (« end » manquant)' }
  return { ok: true, code: out.join('\n') }
}

// Solde des délimiteurs sur une ligne de code nu. On ne compte QUE { } (maps) et
// ( ) (appels/groupes) : les crochets [ ] sont ambigus en Ollin (arrays ET
// ranges où « [a;b[ » utilise « [ » comme borne fermante), donc exclus.
function delimBalance(code) {
  let n = 0
  for (const c of code) {
    if (c === '{' || c === '(') n++
    else if (c === '}' || c === ')') n--
  }
  return n
}

// Compte les ### réellement en dehors d'une chaîne (pour l'état bloc-commentaire).
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
