// Capture de crash À L'ÉCRAN (diagnostic device, notamment iOS/WebKit plein écran
// où la console n'est pas accessible). But : quand le runtime WASM part en faute
// dure — « memory access out of bounds », « table index is out of bounds »,
// RuntimeError, abort emscripten — afficher le message EXACT + la stack + le
// contexte (dernières lignes stderr, userAgent, mémoire) dans un overlay
// sélectionnable/copiable, au lieu de le perdre (print/printErr étaient muets).
//
// Une faute dure survenant dans la boucle rAF n'est PAS rattrapable par le
// try/catch C++ (emscripten_frame) : elle remonte au niveau JS en erreur non
// capturée / rejet non géré. On écoute donc window 'error' + 'unhandledrejection'
// + l'abort emscripten (wireModule), et on garde un tampon glissant de stderr.

const STDERR_RING = []          // dernières lignes printErr (contexte)
const RING_MAX = 60
let overlayEl = null
let shown = false

// Une faute dure a une signature reconnaissable ; le reste (avertissements du
// pilote GL, etc.) ne doit PAS déclencher l'overlay.
const FATAL_RE = /POISON|AddressSanitizer|heap-buffer-overflow|heap-use-after-free|stack-buffer-overflow|SUMMARY:|memory access out of bounds|table index is out of bounds|out of bounds|RuntimeError|\babort(ed)?\b|Assertion failed|null function or function signature mismatch|unreachable/i

function ensureOverlay() {
  if (overlayEl) return overlayEl
  const el = document.createElement('div')
  el.id = 'crash-overlay'
  el.style.cssText = [
    'position:fixed', 'inset:0', 'z-index:2147483647',
    'background:rgba(10,12,20,0.97)', 'color:#e6e9f0',
    'font:12px/1.5 ui-monospace,SFMono-Regular,Menlo,monospace',
    'padding:16px', 'overflow:auto', '-webkit-overflow-scrolling:touch',
    'white-space:pre-wrap', 'word-break:break-word', 'user-select:text',
    '-webkit-user-select:text', 'display:none',
  ].join(';')
  document.body.appendChild(el)
  overlayEl = el
  return el
}

function memInfo() {
  try {
    const m = performance && performance.memory
    if (m) return `jsHeap=${(m.usedJSHeapSize / 1048576) | 0}/${(m.jsHeapSizeLimit / 1048576) | 0} Mo`
  } catch (_) {}
  return 'jsHeap=?'
}

// Affiche l'overlay avec le message + la stack + le contexte. Idempotent : le
// PREMIER crash gagne (les suivants sont souvent des cascades).
function show(title, message, stack) {
  if (shown) return
  shown = true
  const el = ensureOverlay()
  const build = (document.querySelector('[data-build-date]') || {}).textContent || '?'
  const parts = [
    '⚠︎ CRASH — copie ce texte et envoie-le',
    '─'.repeat(36),
    'quand   : ' + title,
    'message : ' + (message || '(vide)'),
    '',
    'stack   :',
    (stack || '(pas de stack)'),
    '',
    'contexte:',
    '  build   ' + build,
    '  UA      ' + navigator.userAgent,
    '  écran   ' + innerWidth + '×' + innerHeight + ' dpr=' + (window.devicePixelRatio || 1),
    '  ' + memInfo(),
    '  standalone=' + (window.navigator.standalone === true),
    '',
    'stderr (dernières lignes) :',
    ...(STDERR_RING.length ? STDERR_RING.map(l => '  ' + l) : ['  (aucune)']),
  ]
  el.textContent = parts.join('\n')

  const bar = document.createElement('div')
  bar.style.cssText = 'position:sticky;bottom:0;display:flex;gap:8px;padding-top:12px;background:rgba(10,12,20,0.97)'
  const mk = (label, fn) => {
    const b = document.createElement('button')
    b.textContent = label
    b.style.cssText = 'flex:1;padding:10px;font:600 13px system-ui,sans-serif;background:#7c83ff;color:#fff;border:none;border-radius:7px'
    b.addEventListener('click', fn)
    return b
  }
  bar.appendChild(mk('Copier', () => {
    const t = el.textContent
    try { navigator.clipboard.writeText(t) } catch (_) {}
    // Repli sans clipboard API (WebKit hors HTTPS/gesture) : sélectionner tout.
    try {
      const r = document.createRange()
      r.selectNodeContents(el)
      const sel = getSelection()
      sel.removeAllRanges()
      sel.addRange(r)
    } catch (_) {}
  }))
  bar.appendChild(mk('Recharger', () => location.reload()))
  el.appendChild(bar)
  el.style.display = 'block'
}

// Ouvre l'overlay pour une exception JS/WASM SI elle est une faute dure (garde
// la stack, indispensable : elle nomme la fonction qui a fauté — getWasmTableEntry,
// index de fonction…). Une erreur de script Ollin ordinaire (« undeclared
// variable »…) n'est PAS fatale → reste dans la zone de sortie, pas d'overlay.
// Renvoie true si l'overlay a été ouvert. Appelé notamment par runProgram, car un
// trap SYNCHRONE pendant m.execute() (relance in-place) est rattrapé par son
// try/catch et n'atteindrait donc jamais le handler window 'error'.
export function captureError(title, err) {
  const msg = (err && err.message) || String(err)
  const stack = (err && err.stack) || ''
  if (FATAL_RE.test(msg) || FATAL_RE.test(stack)) {
    show(title, msg, stack)
    return true
  }
  return false
}

// Enregistre une ligne stderr dans le tampon glissant ; déclenche l'overlay si
// la ligne est une faute dure (l'abort emscripten passe souvent par printErr).
export function noteStderr(line) {
  if (line == null) return
  const s = String(line)
  STDERR_RING.push(s)
  if (STDERR_RING.length > RING_MAX) STDERR_RING.shift()
  if (FATAL_RE.test(s)) show('stderr fatal', s, '')
}

// Branche un objet de config emscripten AVANT instanciation : capte printErr
// (tampon + détection fatale) et l'abort dur. Retourne l'objet (chaînable).
export function wireModule(cfg) {
  const prevErr = cfg.printErr
  cfg.printErr = (line) => {
    noteStderr(line)
    if (prevErr) try { prevErr(line) } catch (_) {}
  }
  const prevAbort = cfg.onAbort
  cfg.onAbort = (reason) => {
    const r = (reason && reason.stack) ? reason.stack : String(reason)
    show('emscripten abort', String(reason), (reason && reason.stack) || '')
    if (prevAbort) try { prevAbort(reason) } catch (_) {}
  }
  return cfg
}

// Installe les capteurs globaux (une seule fois). À appeler tôt, avant de charger
// le WASM, pour attraper aussi les fautes d'instanciation.
let installed = false
export function installCrashOverlay() {
  if (installed) return
  installed = true
  // Exposé global : pg-run.js est chargé sous une URL cache-bustée (?v) distincte
  // → instance de module séparée. On partage donc l'état de l'overlay (latch
  // « premier crash gagne », tampon stderr) via window plutôt que par import.
  window.__ollinCrash = { captureError, noteStderr }
  window.addEventListener('error', (e) => {
    const err = e.error
    const msg = (err && err.message) || e.message || 'error'
    if (!FATAL_RE.test(msg) && !(err && err.stack && FATAL_RE.test(err.stack))) {
      // Erreur JS ordinaire (bug de vue, etc.) : on la garde en contexte mais on
      // n'ouvre l'overlay que pour les fautes dures du runtime.
      noteStderr('window.error: ' + msg)
      return
    }
    show('window.error', msg, (err && err.stack) || (e.filename + ':' + e.lineno))
  })
  window.addEventListener('unhandledrejection', (e) => {
    const r = e.reason
    const msg = (r && r.message) || String(r)
    const stack = (r && r.stack) || ''
    if (FATAL_RE.test(msg) || FATAL_RE.test(stack)) {
      show('unhandledrejection', msg, stack)
    } else {
      noteStderr('rejection: ' + msg)
    }
  })
}
