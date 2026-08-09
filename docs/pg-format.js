// Formateur Ollin « à la demande » — réindentation par blocs (heuristique ligne
// par ligne, pas d'AST). Ne change QUE l'indentation et les espaces superflus,
// jamais la sémantique. Conventions (cf. tests/syntax.ol) :
//   func / if…then / while…do / for…do / class / try / enum → +1 niveau, fermé par `end`
//   switch                                            → +1 (niveau des `case`)
//   case / else(dans switch) / default                → au niveau du switch, corps +1
//   case … do                                         → le `do` est un bloc ordinaire du
//     corps du case ; il partage le niveau du case et c'est SON `end` qui le ferme
//   else / elseif / catch                             → ligne dé-indentée, corps au niveau
// Une ligne qui ouvre À LA FOIS un bloc et un délimiteur — `f(x, func()` — ne vaut
// qu'UN niveau : le bloc « absorbe » les délimiteurs restés ouverts sur sa ligne
// d'ouverture, sans quoi son corps serait indenté deux fois.
// Chaînes "…" et commentaires (## ligne, ### bloc ###) : contenu jamais touché.
// En cas de blocs déséquilibrés, renvoie { ok:false } sans rien reformater.

const UNIT = '    '
// Tous les mots-clés ouvrant un bloc fermé par `end` (cf. docs/grammar.ebnf) ;
// `switch` et `do` sont traités à part (pile propre / opener seulement en tête de ligne).
const OPENERS = /\b(?:func|if|while|for|class|try|enum)\b/g
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
  // Pile de contextes de BLOC. Chaque entrée : { kind: 'block'|'switch'|'case',
  // absorb: délimiteurs ouverts sur la ligne d'ouverture du bloc, déjà comptés par elle }
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
    const inSwitch = top() === 'case' || top() === 'caseblock' || top() === 'switch'

    let show = level()             // niveau d'indentation d'affichage de la ligne

    if (first === 'end') {
      if (top() === 'caseblock') {
        // `case … do` : cet `end` ferme le bloc do du corps ; le case, lui, court
        // jusqu'au case suivant ou au `end` du switch.
        st[st.length - 1].kind = 'case'
        show = level() - 1
      } else {
        if (top() === 'case') popBlock()            // fin du corps de case
        if (st.length === 0) return { ok: false, error: '« end » sans bloc ouvert' }
        const closed = popBlock()                   // ferme le bloc/switch
        // `end` s'aligne sur la ligne qui a ouvert le bloc : ses délimiteurs absorbés
        // comptent encore, car ils ne seront refermés qu'ici (`end)`).
        show = level() - closed.absorb
      }
    } else if (first === 'case' || first === 'default' ||
               (first === 'else' && inSwitch)) {
      if (top() === 'case') popBlock()              // fin du case précédent
      show = level()                           // au niveau du switch
      // `case … do` : le bloc do du corps partage le niveau du case, et son `end` ne
      // ferme que lui (le case court jusqu'au case suivant ou au `end` du switch).
      pushBlock(/\bdo\s*$/.test(code) ? 'caseblock' : 'case')
    } else if (first === 'else' || first === 'elseif' || first === 'catch') {
      show = level() - 1                       // ligne dé-indentée, pile inchangée
    } else {
      // ligne commençant par un fermant de délimiteur → dé-indentée d'un cran
      if (/^[})\]]/.test(code)) show = level() - 1
      // ouvertures/fermetures nettes de BLOCS sur la ligne (mono-ligne = net 0)
      const sw = count(code, /\bswitch\b/g)
      // `do` standalone (doStmt) : opener seulement quand c'est le premier mot de la ligne
      // (dans `while x do` ou `for i=1,10 do`, `first` vaut `while`/`for`, pas `do`)
      const doBlock = first === 'do' ? 1 : 0
      let net = count(code, OPENERS) - count(code, /\bend\b/g)
      const opened = st.length
      while (net > 0) { pushBlock('block'); net-- }
      while (net < 0) { if (top() === 'case') popBlock(); if (st.length) popBlock(); net++ }
      for (let k = 0; k < sw; k++) pushBlock('switch')
      for (let k = 0; k < doBlock; k++) pushBlock('block')
      // Délimiteurs laissés ouverts par cette ligne : ils sont déjà représentés par le
      // niveau du bloc qu'elle ouvre → le bloc le plus interne les absorbe.
      const openDelims = delimBalance(code)
      if (st.length > opened && openDelims > 0) {
        st[st.length - 1].absorb = openDelims
        absorbed += openDelims
      }
    }

    out.push(UNIT.repeat(Math.max(0, show)) + body)

    delim = Math.max(0, delim + delimBalance(code))   // maj délimiteurs pour la suite

    // ### ouvert sur cette ligne (nombre impair de ### hors chaîne) → bloc commentaire
    if (bareCodeHashes(body) % 2 === 1) inBlockComment = true
  }

  if (st.length !== 0) return { ok: false, error: 'bloc non fermé (« end » manquant)' }
  return { ok: true, code: out.join('\n') }
}

// Solde des délimiteurs sur une ligne de code nu : { } (maps), ( ) (appels/groupes)
// et [ ] (arrays). Les crochets sont ambigus en Ollin — dans un range, « [a;b[ » ferme
// avec « [ » et « ]a;b] » ouvre avec « ] » —, mais un range contient TOUJOURS un « ; »
// entre ses bornes : sur une ligne qui en comporte un, on ne compte pas les crochets.
// Sans quoi un tableau écrit sur plusieurs lignes verrait son contenu dé-indenté.
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
