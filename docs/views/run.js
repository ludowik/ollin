// RUN view (standalone full-screen execution) — init(ctx), called by app.js once the
// views/run.html fragment is mounted.
//   ctx = { root, getOllin, hardReload, navigate, v }
// It reloads the ACTIVE project from IndexedDB (written by the playground) and runs it through
// the SHARED logic (pg-run.js), with the same preloading and error handling as the playground's
// inline Run.

export async function init(ctx) {
  const { getOllin } = ctx
  let mod = null   // the WASM module, captured by stop(); nothing smuggled through a global

  // Shared modules, cache-busted with the app's version token: one session reuses the same URL,
  // so the module registry does not grow.
  const Store = await (await import('../pg-provider.js?v=' + ctx.v)).getProvider(ctx.v)
  const { loadProjectIntoRuntime, runProgram, sampleFromAnchor, fetchSample, preloadSampleModels, preloadSampleImports } = await import('../pg-run.js?v=' + ctx.v)
  const { pinToVisualViewport } = await import('../pg-viewport.js?v=' + ctx.v)

  // The full-screen bar sticks to the top of the visible area when the keyboard opens. PHONES
  // only, not tablets or iPads, which get the desktop interface: a coarse pointer AND a small
  // screen (a short side under 600px separates phones, at most ~430, from iPads, at least 744).
  const isPhone = !!(window.matchMedia && window.matchMedia('(pointer: coarse)').matches)
               && Math.min(window.screen.width, window.screen.height) < 600
  const unpinViewport = isPhone ? pinToVisualViewport() : () => {}

  const statusEl = document.getElementById('status')
  const outEl    = document.getElementById('out')
  const canvasEl = document.getElementById('canvas')   // the SHARED canvas, from the shell

  // Reparent the shared canvas into this view's graphics area.
  const pane = document.getElementById('output-pane')
  canvasEl.style.display = 'none'
  pane.appendChild(canvasEl)

  function showText(text) {
    outEl.style.display    = 'block'
    canvasEl.style.display = 'none'
    outEl.textContent = (text && String(text).length) ? String(text) : '(no output)'
    outEl.className   = (text && String(text).startsWith('error:')) ? 'err' : 'ok'
  }

  // (Re)starts the current program. Used both at startup and by "Reload".
  async function launch() {
    statusEl.textContent = ''
    // ONE name for the file being run: it is the base the imports resolve against, on the
    // preloading side and inside the engine, which derives its base directory from this very
    // string. Two formulas would let the two disagree.
    const entryName = project ? (project.entry || '') : (exampleFile || '')
    // The 3D models referenced are preloaded from samples/ (best-effort, and of no effect for a
    // project whose models are already among its resources).
    const imported = await preloadSampleImports(mod, code, ctx.v, entryName)
    await preloadSampleModels(mod, code + '\n' + imported, ctx.v)   // the imports' models too
    // The `data` module's project scope, consistent with the playground: the same key.
    window.__ollinDataProject = exampleFile ? ('sample:' + exampleFile) : (project && project.id ? project.id : '_')
    // FRESH render dimensions are handed to the engine (the `window` module reads
    // __ollinRenderW/H first). Without this, the value set by the playground PERSISTS on window,
    // and W/H stay frozen at the old size in full screen.
    const rr = pane.getBoundingClientRect()
    window.__ollinRenderW = Math.round(rr.width)
    window.__ollinRenderH = Math.round(rr.height)
    runProgram(mod, code, canvasEl, {
      filename:  entryName,
      onError:   (msg) => { statusEl.textContent = ''; showText(msg) },
      // A graphics program: keyboard focus goes to the canvas, for interactive programs.
      // preventScroll, otherwise mobile scrolls to bring the canvas into the viewport.
      onRunning: () => { statusEl.textContent = ''; try { canvasEl.focus({ preventScroll: true }) } catch (_) {} },
      onOutput:  (out) => showText(out),
    })
  }

  // Execution controls: Reload, Restart, Pause/Resume. TWO distinct restarts:
  //  • "Reload" reloads the PAGE, hence a new WASM instance, from a fresh module.
  //  • "Restart" runs again WITHIN THE SAME WASM instance, with no reload: faster, with no
  //    reload flash, and safe since the object pools' re-entrance was fixed (see
  //    MapPool::release).
  const reloadBtn   = document.getElementById('reload-btn')
  const relaunchBtn = document.getElementById('relaunch-btn')
  const pauseBtn    = document.getElementById('pause-btn')
  const ICON_PAUSE = '<svg width="13" height="13" viewBox="0 0 16 16" fill="currentColor"><rect x="3.5" y="2.5" width="3.2" height="11" rx="1"/><rect x="9.3" y="2.5" width="3.2" height="11" rx="1"/></svg>'
  const ICON_PLAY  = '<svg width="13" height="13" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5l9 5.5-9 5.5z"/></svg>'
  let paused = false
  function setPauseUI() {
    if (!pauseBtn) return
    pauseBtn.innerHTML = paused ? ICON_PLAY + '<span class="bar-label">Resume</span>'
                                : ICON_PAUSE + '<span class="bar-label">Pause</span>'
  }
  if (pauseBtn) {
    pauseBtn.addEventListener('click', () => {
      if (!mod) return
      if (paused) {
        // The break BEFORE resuming: the frame that follows must not be charged with the time
        // spent paused, otherwise every animation jumps forward by the length of the pause.
        try { mod.clockBreak() } catch (_) {}
        try { mod.resumeMainLoop() } catch (_) {}
        paused = false
      } else {
        try { mod.pauseMainLoop() } catch (_) {}
        paused = true
      }
      setPauseUI()
    })
  }
  // Screenshot, stored as a PNG resource of the project. The capture is produced by the ENGINE at
  // the end of a frame, the only moment when the framebuffer holds the composed screen: without
  // preserveDrawingBuffer, canvas.toDataURL would give an empty image. Hence the round trip —
  // request_capture files the request, then we wait for a frame to deliver the PNG.
  const shotBtn = document.getElementById('shot-btn')

  function stamp() {
    const d = new Date()
    const p = (n) => String(n).padStart(2, '0')
    return `${d.getFullYear()}${p(d.getMonth() + 1)}${p(d.getDate())}-${p(d.getHours())}${p(d.getMinutes())}${p(d.getSeconds())}`
  }

  // Waits for the PNG, for at most `tries` frames: a missed capture must not leave the button
  // stuck (a program with no draw(), a runtime error…).
  function waitCapture(tries = 40) {
    return new Promise((resolve) => {
      const poll = () => {
        let b64 = ''
        try { b64 = mod.takeCapture() } catch (_) {}
        if (b64) return resolve(b64)
        if (--tries <= 0) return resolve('')
        requestAnimationFrame(poll)
      }
      requestAnimationFrame(poll)
    })
  }

  // One capture at a time: two clicks close together would tread on each other, the request
  // being a single piece of state on the engine's side, and the first to arrive taking the PNG
  // away — the second would wait in vain and then report a failure.
  let capturing = false

  async function capture() {
    if (!mod || !mod.requestCapture || capturing) return
    if (!project) {
      // A sample read from the repository has no resources to store the image in.
      statusEl.textContent = 'capture: create a project from this example'
      return
    }
    capturing = true
    try {
      await takeShot()
    } finally {
      capturing = false
    }
  }

  async function takeShot() {
    // While paused no frame goes by, so the loop is resumed for the length of the capture.
    const wasPaused = paused
    if (wasPaused) {
      try { mod.clockBreak() } catch (_) {}
      try { mod.resumeMainLoop() } catch (_) {}
    }
    statusEl.textContent = 'capture…'
    mod.requestCapture()
    const b64 = await waitCapture()
    if (wasPaused) {
      try { mod.pauseMainLoop() } catch (_) {}
    }
    if (!b64) {
      statusEl.textContent = 'no screenshot available (nothing was rendered)'
      return
    }
    project.resources = project.resources || {}
    // A FREE name: the timestamp is to the second, so two captures close together would share a
    // key and the second would overwrite the project's first image.
    let name = 'capture-' + stamp() + '.png'
    for (let n = 2; project.resources[name] !== undefined; n++)
      name = 'capture-' + stamp() + '-' + n + '.png'
    project.resources[name] = { b64, ext: 'png' }
    await Store.saveProject(project)
    // Immediately usable by the program (image.load(name)), like an image added from the
    // editor.
    try { if (mod.preloadImage) mod.preloadImage(name, b64, 'png') } catch (_) {}
    statusEl.textContent = name
  }

  if (shotBtn) {
    shotBtn.addEventListener('click', () => { capture() })
  }
  if (reloadBtn) {
    reloadBtn.addEventListener('click', () => {
      location.reload()   // a brand-new WASM module (the safe path, and it keeps the #/run/… hash)
    })
  }
  if (relaunchBtn) {
    relaunchBtn.addEventListener('click', () => {
      // An IN-PLACE restart: it runs again in the SAME WASM instance, with no page reload.
      if (paused) {
        try { mod && mod.resumeMainLoop() } catch (_) {}
        paused = false
        setPauseUI()
      }
      launch()
    })
  }

  const stop = () => {
    try { mod && mod.pauseMainLoop && mod.pauseMainLoop() } catch (_) {}
    window.__ollinFrameError = undefined
    window.__ollinRenderW = undefined   // a size hint private to this view: it must not leak
    window.__ollinRenderH = undefined
    unpinViewport()
  }

  // Two sources: either a SAMPLE read straight from the repository (the #/run/sample/<file>
  // route, fetched fresh, so a refresh takes the repository's version again), or the ACTIVE
  // PROJECT from IndexedDB.
  const exampleFile = sampleFromAnchor(ctx.anchor)
  // The "Editor" link preserves the current sample; otherwise it would go back to project mode.
  if (exampleFile) {
    const back = document.querySelector('#bar a')
    if (back) back.setAttribute('href', '#/playground/sample/' + exampleFile)
  }
  let project = null
  let code = null
  if (exampleFile) {
    try {
      code = await fetchSample(exampleFile, ctx.v)   // it rejects on a 404, so an HTML page is never run
    } catch (e) {
      statusEl.textContent = ''
      showText('error: ' + (e && e.message ? e.message : 'example not found: ' + exampleFile))
      return stop
    }
  } else {
    try {
      await Store.init()
      const id = Store.getActiveId()
      if (id) project = await Store.getProject(id)
    } catch (_) {}
    code = (project && project.files) ? (project.files[project.entry] ?? '') : null
    if (project === null || code === null) {
      statusEl.textContent = ''
      showText('error: no project. Open this mode from the editor, with the "Full screen" button.')
      return stop
    }
  }

  try {
    mod = await getOllin()
  } catch (err) {
    statusEl.textContent = ''
    showText('error: WASM — ' + (err?.message ?? err))
    return stop
  }

  loadProjectIntoRuntime(mod, project)
  launch()

  return stop
}
