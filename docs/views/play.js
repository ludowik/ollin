// PLAY view (the kiosk) — init(ctx), called by app.js once views/play.html is mounted.
//   ctx = { root, getOllin, hardReload, navigate, v, anchor }
// It runs ONE example of the repository (#/play/sample/<file>) filling the window, with no toolbar and
// nothing to go elsewhere with: app.js refuses every other route while this view is up, and the Back
// button is neutralised here. A launch screen (the gate) comes first: the Fullscreen API, the audio and
// the iOS sensors all answer to a gesture only, so the program starts on the tap that closes the gate.
// Leaving the full screen brings the gate back, with the program paused.
//
// The address is also made INSTALLABLE as an app of its own: the page swaps the site's manifest for one
// built for this example (name, icon, start address), so that the shortcut it leads to opens this
// kiosk and not the site. Where the browser offers an installation prompt (Chrome, Edge, Android), the
// gate shows an Install button; elsewhere the hint explains the manual way.
//
// What no page can do: stop Escape from leaving the full screen (Chrome on a desktop lets us keep it
// held, which is asked for), switch the system's own app switcher off, or close the tab. And an iPhone
// has no Fullscreen API at all: there, the gate only advises installing the app on the home screen.

export async function init(ctx) {
  const { getOllin } = ctx
  const { sampleFromAnchor, fetchSample, loadProjectIntoRuntime, launchProgram, preloadProgramAssets, resumeLoop,
          isStandaloneApp, watchRenderArea, unlockOrientation } = await import('../lib/pg-run.js?v=' + ctx.v)
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
  const standalone = isStandaloneApp()
  const root = document.documentElement
  const canFullscreen = !!(root.requestFullscreen || root.webkitRequestFullscreen)

  $('gate-title').textContent = file ? file.replace(/^.*\//, '').replace(/\.ol$/, '') : ''
  // Not installed and no Fullscreen API (an iPhone): the home screen is the only way to lose Safari's bars.
  $('gate-hint').hidden = standalone || canFullscreen

  // ── Installation as an app of its own ─────────────────────────────────────────────────────────
  // The site's manifest names the site and starts at its home screen. Swapped here for one that names THIS
  // example and starts at THIS address. A blob URL is enough for Chrome; Safari (iOS) reads the manifest,
  // the title and the touch icon at the moment of "Add to Home Screen", so they are set before any tap.
  const manifestLink = document.querySelector('link[rel="manifest"]')
  const touchIconLink = document.querySelector('link[rel="apple-touch-icon"]')
  const appTitleMeta = document.querySelector('meta[name="apple-mobile-web-app-title"]')
  let manifestUrl = null

  function applyIdentity(name, icon) {
    const base = new URL('.', location.href).href
    const icons = icon
      ? [{ src: icon.src, sizes: icon.size + 'x' + icon.size, type: 'image/png', purpose: 'any' }]
      : [{ src: base + 'icons/icon-192.png', sizes: '192x192', type: 'image/png' },
         { src: base + 'icons/icon-512.png', sizes: '512x512', type: 'image/png' }]
    const manifest = {
      // The id carries the example: the fragment of a start address is dropped from the identity, so
      // without it two examples installed from the same site would be one and the same app.
      id: base + '?app=' + encodeURIComponent(file),
      name,
      short_name: name,
      start_url: location.href,
      scope: base,
      display: 'fullscreen',
      display_override: ['fullscreen', 'standalone'],
      orientation: 'any',
      background_color: '#0f1117',
      theme_color: '#0f1117',
      icons,
    }
    const next = URL.createObjectURL(new Blob([JSON.stringify(manifest)], { type: 'application/manifest+json' }))
    if (manifestLink) manifestLink.setAttribute('href', next)
    if (manifestUrl) URL.revokeObjectURL(manifestUrl)
    manifestUrl = next
    if (touchIconLink && icon) touchIconLink.setAttribute('href', icon.src)
    if (appTitleMeta) appTitleMeta.setAttribute('content', name)
    document.title = name
    // A prompt captured against the PREVIOUS manifest would install the wrong app: it is dropped, and the
    // browser offers a new one for this manifest (or none, and then no button is shown).
    window.__installPrompt = null
    syncInstall()
  }

  // The prompt event is kept by app.js (it can arrive before this view exists); a tap on the button is
  // the gesture that lets it be shown.
  const installBtn = $('install-btn')
  function syncInstall() {
    installBtn.hidden = standalone || !window.__installPrompt
  }
  listen(window, 'ollin-install-state', syncInstall)
  installBtn.addEventListener('click', async (e) => {
    e.stopPropagation()      // the gate itself starts the program: this is not that
    const prompt = window.__installPrompt
    if (!prompt) return
    window.__installPrompt = null      // an event offers its prompt once
    syncInstall()
    try {
      prompt.prompt()
      await prompt.userChoice
    } catch (_) {}
  })

  function loadIcon(file) {
    return new Promise((resolve) => {
      const img = new Image()
      img.onload = () => resolve({ src: img.src, size: img.naturalWidth })
      img.onerror = () => resolve(null)
      img.src = new URL('samples/' + file, location.href).href
    })
  }

  // The catalogue gives the example its name and icon; the manifest is built once both are known (the icon's
  // real size is read from the image, not assumed). An example the catalogue does not list keeps its file name.
  if (file) {
    const fallbackName = $('gate-title').textContent
    Samples.fetchCatalog().then(async (entries) => {
      const entry = entries.find((e) => e.file === file)
      const name = entry ? entry.name : fallbackName
      const icon = entry && entry.icon ? await loadIcon(entry.icon) : null
      $('gate-title').textContent = name
      if (icon) {
        const img = $('gate-icon')
        img.src = icon.src
        img.hidden = false
      }
      applyIdentity(name, icon)
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
    return cleanup
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
      assets,
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
    resumeLoop(mod)
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
  let assets = null
  try {
    // Independent, so together: the sample is small, the engine is the long download.
    ;[code, mod] = await Promise.all([
      fetchSample(file, ctx.v),     // it rejects on a 404, so an HTML page is never run
      getOllin(),
    ])
  } catch (e) {
    fail('error: ' + (e && e.message ? e.message : e))
    return cleanup
  }
  try { mod.setStatsVisible(false) } catch (_) {}     // a clean screen: no memory and frame-rate readout
  loadProjectIntoRuntime(mod, null)
  // The models and imports download behind the launch screen: they need no gesture, and a tap should find
  // them ready instead of a blank canvas. Best-effort, as everywhere else.
  assets = preloadProgramAssets(mod, code, ctx.v, file).catch(() => {})
  showGate('', 'Touch to play')
  return cleanup

  // The router never leaves this view (route.lock): the page is the way out. This is the contract's cleanup,
  // not a path that runs, which is why the manifest swap is not undone here.
  function cleanup() {
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
