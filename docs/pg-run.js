// Execution logic SHARED by the inline Run (the playground) and the standalone mode (run.html).
// One source of truth for preloading the project into the WASM runtime and for handling errors —
// top-level ones (a failing image.load) AS WELL AS graphics frame ones (update/draw) — so that
// the two modes behave identically and cannot drift apart.

export const MANIFEST = 'ollin.project.json'

// Persistence of the `data` module, in localStorage. Scopes: 0 is the project (its key being
// window.__ollinDataProject, set by the view before the run), 1 is shared ("data.shared"). The
// engine (C++) calls window.__ollinData.save(scope, blob) on EVERY write; we load both blobs
// again before each execute, through mod.dataLoad(...).
const DATA_PREFIX = 'ollin-data:'
function dataKey(scope) {
  if (scope === 1) return DATA_PREFIX + 'shared'
  return DATA_PREFIX + 'p:' + (window.__ollinDataProject || '_')
}
if (typeof window !== 'undefined' && !window.__ollinData) {
  window.__ollinData = {
    save(scope, blob) { try { localStorage.setItem(dataKey(scope), blob) } catch (_) {} },
  }
}
// Loads the persisted data into the runtime before a run (a no-op if dataLoad is missing).
export function loadDataInto(m) {
  if (!m || typeof m.dataLoad !== 'function') return
  let p = '', g = ''
  try { p = localStorage.getItem(dataKey(0)) || '' } catch (_) {}
  try { g = localStorage.getItem(dataKey(1)) || '' } catch (_) {}
  m.dataLoad(p, g)
}

// Pushes a project's files (.ol) and resources (images) into the runtime, before execution.
// `m` is the Ollin WASM module, `project` is { files, resources }.
export function loadProjectIntoRuntime(m, project) {
  if (!m) return
  try {
    // Always start from a CLEAN source table, sample mode (a null project) included:
    // otherwise, in the shared WASM instance, the sources of a previously run project would
    // stay importable, and the imports would be stale.
    if (m.resetSources) m.resetSources()
    if (!project) return
    for (const path in (project.files || {})) {
      if (path === MANIFEST) continue
      if (m.preloadSource) m.preloadSource(path, project.files[path])
    }
    const res = project.resources || {}
    for (const name in res) {
      const ext = (res[name].ext || '').toLowerCase()
      // 3D models (OBJ, GLTF, GLB) go to preloadModel; anything else is an image.
      if ((ext === 'obj' || ext === 'gltf' || ext === 'glb') && m.preloadModel) {
        m.preloadModel(name, res[name].b64, ext)
      } else if (m.preloadImage) {
        m.preloadImage(name, res[name].b64, ext)
      }
    }
  } catch (_) { /* best-effort preloading */ }
}

// Runs `code` and routes the result through hooks supplied by the caller:
//   hooks.onError(msg)    an error (top-level OR graphics frame), as an "error: …" string
//   hooks.onRunning()     the program has opened a canvas (the graphics loop has started)
//   hooks.onOutput(text)  the text output of a non-graphics program
//   hooks.filename        optional: the source file name shown in the errors
export function runProgram(m, code, canvasEl, hooks) {
  // An error inside a frame (update/draw): the WASM runtime (emscripten_frame) has already
  // stopped the loop and passes the message up to here.
  window.__ollinFrameError = (msg) => hooks.onError('error: ' + (msg || "erreur d'exécution"))
  loadDataInto(m)   // restores the persisted data (the `data` module) before the run
  let out
  try {
    out = m.execute(code, hooks.filename || '')
  } catch (e) {
    // A SYNCHRONOUS hard trap (an in-place restart on iOS) is caught here, which raises the
    // diagnostic overlay WITH the stack — the name of the faulting function — that the text
    // message alone would lose. The overlay only opens for a hard fault.
    try { window.__ollinCrash && window.__ollinCrash.captureError('execute (relance)', e) } catch (_) {}
    hooks.onError('error: ' + (e && e.message ? e.message : e))
    return
  }
  // A top-level error can arise AFTER the canvas is open (an image.load right after
  // graphics.canvas, say), so it is handled before the "canvas visible" branch; otherwise the
  // screen would stay mute.
  if (typeof out === 'string' && out.startsWith('error:')) {
    hooks.onError(out)
    return
  }
  if (canvasEl && canvasEl.style.display === 'block') {
    // A canvas has opened, so GLFW (the Emscripten glue) has installed its GLOBAL keydown
    // listener on window, which eats Backspace and Tab. It is never removed afterwards, the
    // runtime being shared. We flag it at PAGE level so that the editor's keyboard counter-
    // measure (in the playground) stays armed even when the run happened in the #/run view.
    window.__ollinGfxKbdArmed = true
    hooks.onRunning()
  } else {
    hooks.onOutput(out)
  }
}

// Bytes to base64, in chunks so as not to overflow the argument stack.
function bytesToB64(bytes) {
  let bin = ''
  const CHUNK = 0x8000
  for (let i = 0; i < bytes.length; i += CHUNK) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK))
  }
  return btoa(bin)
}

// SAMPLE mode: preloads the 3D models referenced by graphics.model("x.obj"), fetching them from
// samples/ (user projects go through their own resources instead). Best-effort: a model that
// cannot be found is simply ignored.
export async function preloadSampleModels(m, code, v) {
  if (!m || !m.preloadModel || typeof code !== 'string') return
  const seen = new Set()
  for (const file of findModels(code)) {
    if (seen.has(file)) continue
    seen.add(file)
    try {
      const r = await fetch('samples/' + file + '?v=' + v, { cache: 'no-cache' })
      if (!r.ok) continue
      const bytes = new Uint8Array(await r.arrayBuffer())
      m.preloadModel(file, bytesToB64(bytes), file.split('.').pop().toLowerCase())
    } catch (_) { /* best-effort */ }
  }
}

// Session cache of imported .ol sources (resolved path to text), which avoids downloading them
// again on every restart (a page reload means a fresh module, hence an empty cache).
const _importSrcCache = new Map()

// SAMPLE mode: preloads the IMPORTED .ol files (import "x.ol") from samples/ into the runtime's
// source registry, so that `import` resolves when a sample is run directly (user projects
// already preload all of their files). It follows chained imports breadth-first, RESOLVING each
// path as the parser does — relative to the importing file's directory — which keeps the
// registry keys consistent, sub-directories included. It returns the CONCATENATION of the
// imported sources, so that the caller can preload the models and assets they reference too.
// Best-effort.
export async function preloadSampleImports(m, code, v) {
  if (!m || !m.preloadSource || typeof code !== 'string') return ''
  const seen = new Set()
  const collected = []
  let queue = findImports(code).map((imp) => resolveImport('', imp))   // the entry file: an empty base_dir
  while (queue.length) {
    const key = queue.shift()
    if (seen.has(key)) continue
    seen.add(key)
    let src = _importSrcCache.get(key)
    if (src === undefined) {
      try {
        const r = await fetch('samples/' + key + '?v=' + v, { cache: 'no-cache' })
        if (!r.ok) continue
        src = await r.text()
        _importSrcCache.set(key, src)
      } catch (_) { continue }
    }
    m.preloadSource(key, src)          // the key is the resolved path, what source_get() looks for
    collected.push(src)
    const pdir = dirOf(key)
    for (const imp of findImports(src)) queue.push(resolveImport(pdir, imp))
  }
  return collected.join('\n')
}

// Import-resolution helpers, SHARED by the runtime preloading and the sample-project
// collection, so there is a single rule, identical to the parser's.
function findImports(src) {
  const re = /(?:^|\n)\s*import\s+["']([^"']+)["']/g
  const out = []
  let mm
  while ((mm = re.exec(src))) {
    let p = mm[1]
    if (!p.endsWith('.ol')) p += '.ol'
    out.push(p)
  }
  return out
}
const dirOf = (p) => (p.includes('/') ? p.slice(0, p.lastIndexOf('/') + 1) : '')
// Resolution identical to the parser's: base_dir plus the path (a naive concatenation), unless the path is absolute.
const resolveImport = (parentDir, imp) => (imp[0] === '/' ? imp : parentDir + imp)

// The resources referenced by Ollin code: file names carrying one of the given extensions. We
// collect EVERY string literal that looks like a file, without requiring it to be the direct
// argument of model() or image.load(): a name may live in a data table or a variable (see
// docs/samples/model_3d.ol). The preloading is best-effort — a string that is not a resource
// gives a 404, which is ignored, whereas a missed resource makes the program fail.
function findAssets(code, exts) {
  const re = new RegExp(`["']([^"'\\s]+\\.(?:${exts}))["']`, 'gi')
  const out = []
  let mm
  while ((mm = re.exec(code))) out.push(mm[1])
  return out
}

const findModels = (code) => findAssets(code, 'obj|glb|gltf')
// image.loadData (embedded base64) has no asset to collect, and so is not concerned.
const findImages = (code) => findAssets(code, 'png|jpg|jpeg|gif|webp|bmp')

// Builds a complete PROJECT from a sample of the repository: the entry file, all its transitive
// .ol imports (as files) and the 3D models it references (as base64 binary resources). It serves
// to open a sample as a real multi-file project and to fork it faithfully. It rejects if the
// entry file cannot be found; missing imports and assets are ignored (best-effort). It returns
// { files, resources, entry }.
export async function collectSampleProject(entryFile, v) {
  const files = {}
  const resources = {}
  const seen = new Set()
  let queue = [entryFile]
  while (queue.length) {
    const key = queue.shift()
    if (seen.has(key)) continue
    seen.add(key)
    let src
    try {
      const r = await fetch('samples/' + key + '?v=' + v, { cache: 'no-cache' })
      if (!r.ok) {
        if (key === entryFile) throw new Error('exemple introuvable : ' + key)
        continue
      }
      src = await r.text()
    } catch (e) {
      if (key === entryFile) throw e
      continue
    }
    files[key] = src
    const pdir = dirOf(key)
    for (const imp of findImports(src)) queue.push(resolveImport(pdir, imp))
  }
  // The binary assets referenced — 3D models (model("x.obj")) AND external images
  // (image.load("x.png")) — become base64 resources of the project.
  const allCode = Object.values(files).join('\n')
  const seenAsset = new Set()
  for (const name of [...findModels(allCode), ...findImages(allCode)]) {
    if (seenAsset.has(name)) continue
    seenAsset.add(name)
    try {
      const r = await fetch('samples/' + name + '?v=' + v, { cache: 'no-cache' })
      if (!r.ok) continue
      const bytes = new Uint8Array(await r.arrayBuffer())
      resources[name] = { b64: bytesToB64(bytes), ext: name.split('.').pop().toLowerCase() }
    } catch (_) { /* a missing asset is ignored */ }
  }
  return { files, resources, entry: entryFile }
}

// A "hard" reload, SHARED by every page: it empties the Cache API (the service worker) then
// reloads through a cache-busted URL, which also bypasses the page's own HTTP cache — a plain
// location.reload() may serve the old page again. It guarantees that the latest deployed code is
// what comes back.
export function hardReload() {
  // Keep the fragment (#/view/…): otherwise a hard reload loses the current route (a sample at
  // #/playground/sample/…, say) and falls back to the default view.
  const go = () => location.replace(location.pathname + '?t=' + Date.now() + location.hash)
  if ('caches' in window) {
    caches.keys().then(ks => Promise.all(ks.map(k => caches.delete(k)))).then(go).catch(go)
  } else {
    go()
  }
}

// Adds a unique cache-buster to a URL, forcing a fresh version.
export function freshUrl(url) {
  // The cache-buster goes BEFORE the fragment (#anchor), so the fragment is not lost.
  const h = url.indexOf('#')
  const base = h >= 0 ? url.slice(0, h) : url
  const frag = h >= 0 ? url.slice(h) : ''
  return base + (base.includes('?') ? '&' : '?') + 't=' + Date.now() + frag
}

// Samples read straight from the repository (the #/<view>/sample/<file> route). Single source of
// the route scheme and of the fetch, used by playground.js AND run.js.
export function sampleFromAnchor(anchor) {
  return (anchor || '').startsWith('sample/') ? anchor.slice('sample/'.length) : null
}

// Fetches a sample's code, fresh (cache-buster plus no-cache). It rejects unless the server
// answers 200, which avoids running or displaying the body of a 404 (an HTML page).
export async function fetchSample(file, v) {
  const r = await fetch('samples/' + file + '?v=' + v, { cache: 'no-cache' })
  if (!r.ok) throw new Error('exemple introuvable : ' + file)
  return r.text()
}
