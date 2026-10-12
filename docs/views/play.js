// PLAY view (the kiosk) — init(ctx), called by app.js once views/play.html is mounted.
//   ctx = { root, getOllin, hardReload, navigate, v, anchor }
// It runs ONE example of the repository (#/play/sample/<file>) filling the window, with no toolbar and
// nothing to go elsewhere with: app.js refuses every other route while this view is up, and the Back
// button is neutralised here. A launch screen (the gate) comes first: the Fullscreen API, the audio and
// the iOS sensors all answer to a gesture only, so the program starts on the tap that closes the gate.
// Leaving the full screen brings the gate back, with the program paused.
//
// What no page can do: stop Escape from leaving the full screen (Chrome on a desktop lets us keep it
// held, which is asked for), switch the system's own app switcher off, or close the tab. And an iPhone
// has no Fullscreen API at all: there, the gate only advises installing the app on the home screen.

export async function init(ctx) {
  const { getOllin } = ctx
  const { sampleFromAnchor, fetchSample, loadProjectIntoRuntime, launchProgram, watchRenderArea, unlockOrientation } =
    await import('../lib/pg-run.js?v=' + ctx.v)
  const Samples = await import('../lib/pg-samples.js?v=' + ctx.v)

  const $ = (id) => document.getElementById(id)
  const gate = $('gate')
  const goBtn = $('go-btn')
  const failEl = $('fail')
  const outEl = $('out')
  const canvasEl = $('canvas')          // the SHARED canvas, from the shell
  const pane = $('output-pane')

  // Reparent the shared canvas into this view's graphics area.
  canvasEl.style.display = 'none'
  pane.appendChild(canvasEl)
  const unwatchArea = watchRenderArea(pane)

  const file = sampleFromAnchor(ctx.anchor)
  let mod = null
  let code = null
  let started = false      // the program has been launched
  let running = false      // and is not paused
  let wasFullscreen = false
  let wakeLock = null

  const listeners = []
  function listen(target, type, fn, opts) {
    target.addEventListener(type, fn, opts)
    listeners.push(() => target.removeEventListener(type, fn, opts))
  }

  // ── What the browser would otherwise do with a gesture ────────────────────────────────────────
  listen(document, 'contextmenu', (e) => e.preventDefault())
  listen(document, 'gesturestart', (e) => e.preventDefault())     // Safari's pinch zoom

  // Back is neutralised: one entry is pushed, and pushed again every time it is popped, so that the
  // entry before this page can never be reached by Back.
  history.pushState(null, '', location.href)
  listen(window, 'popstate', () => history.pushState(null, '', location.href))

  // ── The gate ──────────────────────────────────────────────────────────────────────────────────
  const standalone = (() => {
    try {
      return window.navigator.standalone === true ||
             (window.matchMedia && window.matchMedia('(display-mode: standalone), (display-mode: fullscreen)').matches)
    } catch (_) { return false }
  })()
  const root = document.documentElement
  const canFullscreen = !!(root.requestFullscreen || root.webkitRequestFullscreen)

  $('gate-title').textContent = file ? file.replace(/^.*\//, '').replace(/\.ol$/, '') : ''
  // Not installed and no Fullscreen API (an iPhone): the home screen is the only way to lose Safari's bars.
  $('gate-hint').hidden = standalone || canFullscreen

  if (file) {
    Samples.fetchCatalog().then((entries) => {
      const entry = entries.find((e) => e.file === file)
      if (!entry) return
      $('gate-title').textContent = entry.name
      if (entry.icon) {
        const img = $('gate-icon')
        img.addEventListener('load', () => { img.hidden = false }, { once: true })
        img.src = 'samples/' + entry.icon
      }
    })
  }

  function showGate(note, label) {
    $('gate-note').textContent = note
    goBtn.textContent = label
    goBtn.disabled = false
    gate.hidden = false
  }

  // A message instead of the program: an error (with Retry, which loads the same address again and
  // leads nowhere else) or the text a non-graphics program printed.
  function showText(text, isError) {
    gate.hidden = true
    running = false
    try { mod && mod.pauseMainLoop && mod.pauseMainLoop() } catch (_) {}
    canvasEl.style.display = 'none'
    outEl.textContent = (text && String(text).length) ? String(text) : '(no output)'
    failEl.className = isError ? 'err' : 'ok'
    failEl.hidden = false
  }
  const fail = (msg) => showText(msg, true)

  $('retry-btn').addEventListener('click', () => location.reload())

  if (!file) {
    fail('error: no example named in the address (#/play/sample/<file>)')
    return () => { unwatchArea(); listeners.forEach((off) => off()) }
  }

  // ── Full screen, the screen kept awake, Escape kept held ─────────────────────────────────────
  function requestFullscreen() {
    if (standalone || !canFullscreen) return
    try {
      const ask = root.requestFullscreen || root.webkitRequestFullscreen
      const p = ask.call(root, { navigationUI: 'hide' })
      if (p && p.catch) p.catch(() => {})
    } catch (_) {}
  }

  async function holdScreen() {
    try { wakeLock = await navigator.wakeLock.request('screen') } catch (_) {}
  }
  function releaseScreen() {
    try { wakeLock && wakeLock.release() } catch (_) {}
    wakeLock = null
  }
  // A page that goes to the background loses its wake lock: it is asked for again on return.
  listen(document, 'visibilitychange', () => {
    if (!document.hidden && running && (!wakeLock || wakeLock.released)) holdScreen()
  })

  function onFullscreenChange() {
    const inFullscreen = !!(document.fullscreenElement || document.webkitFullscreenElement)
    if (inFullscreen) {
      wasFullscreen = true
      try { navigator.keyboard && navigator.keyboard.lock && navigator.keyboard.lock(['Escape']).catch(() => {}) } catch (_) {}
      return
    }
    // Full screen was left, by Escape or by a system gesture: the program waits behind the gate.
    if (wasFullscreen && running) {
      wasFullscreen = false
      running = false
      try { mod.pauseMainLoop() } catch (_) {}
      releaseScreen()
      showGate('Paused', 'Touch to resume')
    }
  }
  listen(document, 'fullscreenchange', onFullscreenChange)
  listen(document, 'webkitfullscreenchange', onFullscreenChange)

  // ── Starting and resuming ─────────────────────────────────────────────────────────────────────
  function focusCanvas() {
    try { canvasEl.focus({ preventScroll: true }) } catch (_) {}
  }

  async function start() {
    running = true
    holdScreen()
    await launchProgram(mod, {
      code,
      entryName: file,
      dataScope: 'sample:' + file,
      v: ctx.v,
      pane,
      canvasEl,
      hooks: {
        onError: (msg) => fail(msg),
        onRunning: focusCanvas,
        onOutput: (text) => showText(text, false),
      },
    })
  }

  function resume() {
    // The break BEFORE resuming: the frame that follows must not be charged with the time spent
    // behind the gate, otherwise every animation jumps forward by the length of the pause.
    try { mod.clockBreak() } catch (_) {}
    try { mod.resumeMainLoop() } catch (_) {}
    running = true
    holdScreen()
    focusCanvas()
  }

  gate.addEventListener('click', () => {
    if (goBtn.disabled) return
    // The Fullscreen API answers to a gesture, so it is asked first, before anything is awaited.
    requestFullscreen()
    gate.hidden = true
    if (started) {
      resume()
    } else {
      started = true
      start()
    }
  })

  // The example and the engine load while the gate is up; the button wakes when both are there.
  try {
    code = await fetchSample(file, ctx.v)     // it rejects on a 404, so an HTML page is never run
    mod = await getOllin()
  } catch (e) {
    fail('error: ' + (e && e.message ? e.message : e))
    return () => { unwatchArea(); listeners.forEach((off) => off()) }
  }
  try { mod.setStatsVisible(false) } catch (_) {}     // a clean screen: no memory and frame-rate readout
  loadProjectIntoRuntime(mod, null)
  showGate('', 'Touch to play')

  return () => {
    unwatchArea()
    listeners.forEach((off) => off())
    releaseScreen()
    unlockOrientation()
    try { navigator.keyboard && navigator.keyboard.unlock && navigator.keyboard.unlock() } catch (_) {}
    try { mod && mod.pauseMainLoop && mod.pauseMainLoop() } catch (_) {}
    try { if (document.fullscreenElement) document.exitFullscreen() } catch (_) {}
    window.__ollinFrameError = undefined
    window.__ollinRenderW = undefined   // a size hint private to this view: it must not leak
    window.__ollinRenderH = undefined
  }
}
