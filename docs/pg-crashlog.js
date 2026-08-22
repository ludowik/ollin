// ON-SCREEN crash capture, for diagnosing a device — chiefly iOS/WebKit in full screen, where
// the console cannot be reached. When the WASM runtime takes a hard fault — "memory access out
// of bounds", "table index is out of bounds", a RuntimeError, an emscripten abort — the EXACT
// message, the stack and the context (the last stderr lines, the userAgent, the memory) are
// shown in a selectable, copyable overlay instead of being lost (print and printErr were mute).
//
// A hard fault occurring in the rAF loop is NOT catchable by the C++ try/catch
// (emscripten_frame): it surfaces at the JS level as an uncaught error or an unhandled
// rejection. So we listen to window 'error' and 'unhandledrejection' plus the emscripten abort
// (wire_module), and keep a sliding stderr buffer.

const STDERR_RING = []          // the last printErr lines, as context
const RING_MAX = 60
let overlayEl = null
let shown = false

// A hard fault has a recognisable signature; everything else (GL driver warnings and so on)
// must NOT raise the overlay.
const FATAL_RE = /memory access out of bounds|table index is out of bounds|out of bounds|RuntimeError|\babort(ed)?\b|Assertion failed|null function or function signature mismatch|unreachable/i

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

// Shows the overlay with the message, the stack and the context. Idempotent: the FIRST crash
// wins, the following ones often being knock-on effects.
function show(title, message, stack) {
  if (shown) return
  shown = true
  const el = ensureOverlay()
  const build = (document.querySelector('[data-build-date]') || {}).textContent || '?'
  const parts = [
    '⚠︎ CRASH - copy this text and send it',
    '─'.repeat(36),
    'when    : ' + title,
    'message : ' + (message || '(empty)'),
    '',
    'stack   :',
    (stack || '(no stack)'),
    '',
    'context :',
    '  build   ' + build,
    '  UA      ' + navigator.userAgent,
    '  screen  ' + innerWidth + '×' + innerHeight + ' dpr=' + (window.devicePixelRatio || 1),
    '  ' + memInfo(),
    '  standalone=' + (window.navigator.standalone === true),
    '',
    'stderr (last lines):',
    ...(STDERR_RING.length ? STDERR_RING.map(l => '  ' + l) : ['  (none)']),
  ]
  el.textContent = parts.join('\n')

  const bar = document.createElement('div')
  bar.style.cssText = 'position:sticky;bottom:0;display:flex;gap:8px;padding-top:12px;background:rgba(10,12,20,0.97)'
  const mk = (label, fn) => {
    const b = document.createElement('button')
    b.textContent = label
    b.style.cssText = 'flex:1;padding:10px;font:600 13px system-ui,sans-serif;background:#9ba1ff;color:#fff;border:none;border-radius:7px'
    b.addEventListener('click', fn)
    return b
  }
  bar.appendChild(mk('Copier', () => {
    const t = el.textContent
    try { navigator.clipboard.writeText(t) } catch (_) {}
    // Fallback without the clipboard API (WebKit outside HTTPS or a gesture): select all.
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

// Opens the overlay for a JS or WASM exception IF it is a hard fault. The stack is kept, and is
// essential: it names the function that faulted (getWasmTableEntry, a function index…). An
// ordinary Ollin script error ("undeclared variable"…) is NOT fatal and stays in the output
// area, with no overlay. Returns true if the overlay was opened. It is called in particular by
// run_program, because a SYNCHRONOUS trap during m.execute() (an in-place restart) is caught by
// its own try/catch and would therefore never reach the window 'error' handler.
export function captureError(title, err) {
  const msg = (err && err.message) || String(err)
  const stack = (err && err.stack) || ''
  if (FATAL_RE.test(msg) || FATAL_RE.test(stack)) {
    show(title, msg, stack)
    return true
  }
  return false
}

// Records a stderr line in the sliding buffer, and raises the overlay if the line is a hard
// fault (the emscripten abort often goes through printErr).
export function noteStderr(line) {
  if (line == null) return
  const s = String(line)
  STDERR_RING.push(s)
  if (STDERR_RING.length > RING_MAX) STDERR_RING.shift()
  if (FATAL_RE.test(s)) show('stderr fatal', s, '')
}

// Wires an emscripten config object BEFORE instantiation: it captures printErr (buffer plus
// fatal detection) and the hard abort. Returns the object, so calls chain.
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

// Installs the global sensors, once. To be called early, before loading the WASM, so that
// instantiation faults are caught too.
let installed = false
export function installCrashOverlay() {
  if (installed) return
  installed = true
  // Exposed globally: pg-run.js is loaded under a distinct cache-busted URL (?v), hence as a
  // separate module instance. The overlay's state (the "first crash wins" latch, the stderr
  // buffer) is therefore shared through window rather than by import.
  window.__ollinCrash = { captureError, noteStderr }
  window.addEventListener('error', (e) => {
    const err = e.error
    const msg = (err && err.message) || e.message || 'error'
    if (!FATAL_RE.test(msg) && !(err && err.stack && FATAL_RE.test(err.stack))) {
      // An ordinary JS error (a view bug, say): we keep it as context but only open the
      // overlay for the runtime's hard faults.
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
