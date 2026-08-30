// Router of the Ollin single-page web app.
//
// One page (index.html, the shell) hosts several VIEWS, mounted on demand in #view. Each view is
// an HTML fragment (views/<name>.html) plus an init module (views/<name>.js, exporting
// init(ctx) → cleanup()).
//
// Hash routing:
//   #/<view>[/<anchor>]  changes view (#/tutoriel, #/tutoriel/for)
//   #<anchor> (with no /) is an internal anchor of the current view (native scrolling)
//   (empty)              is the last visited view, otherwise the default one (the tutorial)
// The "#/" prefix is what tells a route from a plain anchor: the tutorial's section links
// (href="#intro") stay plain anchors and do not trigger a change of view.
//
// The WASM runtime is loaded ONCE (getOllin) and shared by every view, as is the <canvas>, which
// is moved into the active view and given back to the shell on unmount.

// A UNIQUE version token for this page load, used as a cache-buster for ALL imports and fetches
// (the router, the views, and the shared modules through ctx.v). One load therefore reuses the
// same module URL — no fresh copy per navigation, hence no unbounded growth of the module
// registry — while a reload (or a hardReload) starts again with a fresh token, hence the latest
// deployed version. Before that, a Date.now() on every import leaked one copy per navigation.
const V = Date.now()

// The common stylesheet of the menu bars. Injected HERE rather than declared in index.html:
// index.html may be served from the browser's cache, and a version predating the file would not
// reference it — whereas the views are always loaded fresh and no longer carry bar styles of
// their own. The bars would then have no style at all (observed). app.js, on the other hand, is
// imported with a version token, hence always fresh, and the stylesheet follows.
document.head.insertAdjacentHTML('beforeend', '<link rel="stylesheet" href="app-bar.css?v=' + V + '">')

// Installed as an app on macOS, the window keeps a native TITLE BAR above the page, and our own
// bar ended up underneath it: its buttons were painted but the clicks went to the window. CSS
// cannot tell one system from another, so the height is set here, and only there — an iPhone
// keeps its notch inset alone, a browser tab keeps nothing.
// The window's frame is not measurable from the page (innerHeight is the content area, and
// outerHeight is not exposed to a web app), so this is the macOS title-bar height, not a
// measurement: it is the ONE number to adjust if the bar sits too low or too high.
const MAC_TITLEBAR_H = '28px'
if (matchMedia('(display-mode: standalone)').matches && /Mac/i.test(navigator.platform || ''))
  document.documentElement.style.setProperty('--titlebar-h', MAC_TITLEBAR_H)

const { hardReload } = await import('./pg-run.js?v=' + V)

// On-screen crash capture, for diagnosing a device (iOS in full screen, with no console).
// Installed BEFORE any WASM load, so that hard faults are caught too.
const { installCrashOverlay, wireModule } = await import('./pg-crashlog.js?v=' + V)
installCrashOverlay()

// The shared WASM runtime: one instance for the whole app.
let ollinPromise = null
function getOllin() {
  if (ollinPromise) return ollinPromise
  ollinPromise = new Promise((resolve, reject) => {
    const s = document.createElement('script')
    s.src = 'wasm/ollin.js?' + V
    s.onload = () => {
      const dir = s.src.replace(/\?.*$/, '').replace(/[^/]*$/, '')
      OllinModule(wireModule({
        locateFile: f => dir + f + '?' + V,
        canvas: document.getElementById('canvas'),
        print: () => {},
        printErr: () => {},
      })).then(resolve).catch(reject)
    }
    s.onerror = () => reject(new Error('WASM not found'))
    document.head.appendChild(s)
  })
  return ollinPromise
}

// Table of views. anchorIsSection means the anchor is a section id to scroll to, with no
// remount. Otherwise the anchor is a view parameter (sample/<file>, say), and the view is
// remounted when it changes.
const ROUTES = {
  tutoriel:   { html: 'views/tutoriel.html',   js: './views/tutoriel.js', anchorIsSection: true },
  playground: { html: 'views/playground.html', js: './views/playground.js' },
  run:        { html: 'views/run.html',        js: './views/run.js' },
  perf:       { html: 'views/perf.html',       js: './views/perf.js' },
}
const DEFAULT_VIEW = 'tutoriel'
// The last complete ROUTE visited (the view plus its sub-path: a tutorial anchor, a sample…),
// remembered so as to reopen it on the next launch. The whole route is stored, not just the
// view, so the exact sample or anchor comes back. `run` is EXCLUDED, being transient and
// requiring an active project: we keep the last tutorial or playground route, so as not to
// reopen on "no project".
const LAST_HASH_KEY = 'ollin-last-route'

// A viewport per view. The playground and the run mode lock the zoom (maximum-scale) to avoid
// iOS's automatic zoom when the editor — whose font is under 16px — takes focus. That was the
// behaviour of the former standalone page, lost when moving to a single page with one shared
// viewport. The tutorial stays zoomable, for comfortable reading.
const VIEWPORT = {
  tutoriel:   'width=device-width, initial-scale=1.0',
  playground: 'width=device-width, initial-scale=1.0, maximum-scale=1.0',
  run:        'width=device-width, initial-scale=1.0, maximum-scale=1.0, viewport-fit=cover',
  perf:       'width=device-width, initial-scale=1.0',
}
function applyViewport(view) {
  const meta = document.querySelector('meta[name="viewport"]')
  if (meta) meta.setAttribute('content', VIEWPORT[view] || VIEWPORT[DEFAULT_VIEW])
}

const viewEl     = document.getElementById('view')
const canvasHome = document.getElementById('canvas-home')

let currentView    = null
let currentCleanup = null
let currentAnchor  = ''    // the current view's sub-path (a tutorial anchor, or ex/<file>)
let navSeq         = 0     // re-entrance guard: identifies the current navigation

function parseHash() {
  const h = location.hash
  if (h.startsWith('#/')) {
    const parts = h.slice(2).split('/')
    // anchor is everything after the view: a section anchor (the tutorial) OR a parameterised
    // sub-route of the view ("ex/game_of_life.ol", for the playground or the run mode).
    return { view: parts[0] || DEFAULT_VIEW, anchor: parts.slice(1).join('/') }
  }
  // A bare anchor (#intro), or none: the current or default view, scrolled to the anchor.
  return { view: currentView || DEFAULT_VIEW, anchor: h.startsWith('#') ? h.slice(1) : '' }
}

// Puts the shared <canvas> back in the shell (hidden) and FLATTENS ITS STYLES: a view may set
// inline styles (the tutorial sets margin, borderRadius…), and without the reset they would leak
// into the next view, leaving the canvas off-centre.
function stowCanvas() {
  const canvas = document.getElementById('canvas')
  if (canvas && canvas.parentNode !== canvasHome) {
    canvas.style.cssText = 'display:none'
    canvasHome.appendChild(canvas)
  }
}

async function teardownCurrent() {
  if (currentCleanup) {
    try { currentCleanup() } catch (e) { console.error('cleanup:', e) }
    currentCleanup = null
  }
  stowCanvas()
}

async function mount(view, anchor) {
  const route = ROUTES[view] || ROUTES[DEFAULT_VIEW]
  const seq = ++navSeq                 // any later navigation invalidates this one
  const stale = () => seq !== navSeq

  await teardownCurrent()
  applyViewport(view)   // BEFORE the mount, so it is in place when the editor takes focus

  try {
    const res  = await fetch(route.html + '?v=' + V)
    const html = await res.text()
    if (stale()) {
      return
    }
    viewEl.innerHTML = html

    const mod = await import(route.js + '?v=' + V)
    if (stale()) {
      return
    }
    const ctx = { root: viewEl, getOllin, hardReload, navigate, v: V, anchor }
    const cleanup = (await mod.init(ctx)) || null
    if (stale()) {
      // A more recent navigation took over during the init, so this stale view is cleaned up at
      // once; otherwise its global listeners leak.
      if (cleanup) {
        try { cleanup() } catch (_) {}
      }
      return
    }
    currentCleanup = cleanup
    currentView = view
    currentAnchor = anchor
    if (view !== 'run') {
      try {
        localStorage.setItem(LAST_HASH_KEY, '#/' + view + (anchor ? '/' + anchor : ''))
      } catch (_) {}
    }

    if (anchor) {
      scrollToAnchor(anchor)
    } else {
      window.scrollTo(0, 0)
    }
  } catch (e) {
    if (stale()) {
      return
    }
    console.error('Failed to mount the view "' + view + '":', e)
    viewEl.innerHTML = '<div style="padding:40px;text-align:center;font-family:system-ui,sans-serif;color:#dde4ef">' +
      '<p style="color:#f87171;font-weight:600;margin-bottom:12px">The view failed to load.</p>' +
      '<button onclick="location.reload()" style="background:#9ba1ff;color:#fff;border:none;border-radius:7px;padding:9px 20px;font-size:14px;cursor:pointer">Reload</button></div>'
    currentView = null
  }
}

function scrollToAnchor(id) {
  const el = document.getElementById(id)
  if (el) {
    el.scrollIntoView({ behavior: 'smooth' })
  }
}

// Programmatic navigation, available to the views through ctx.navigate.
function navigate(view, anchor) {
  location.hash = '#/' + view + (anchor ? '/' + anchor : '')
}

async function route() {
  const { view, anchor } = parseHash()
  if (view === currentView && ROUTES[view]) {
    // The anchor is a section (the tutorial): scroll, with no remount.
    if (ROUTES[view].anchorIsSection) {
      if (anchor) {
        scrollToAnchor(anchor)
      }
      return
    }
    // The anchor is a view parameter (sample/<file>): the same value is already mounted, a
    // changed one (another sample) means a remount.
    if (anchor === currentAnchor) {
      return
    }
  }
  await mount(view, anchor)
}

addEventListener('hashchange', route)

// Is the app running "installed" (added to the iOS home screen, or in standalone display mode)?
// In that case the OS ALWAYS relaunches the URL frozen at installation time (often #/playground)
// and NOT the last position, so the last remembered route has to be restored explicitly.
function isStandaloneApp() {
  try {
    return window.navigator.standalone === true ||
           (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
  } catch (_) {
    return false
  }
}

// Startup: reopen the LAST route visited (remembered on every mount, `run` excepted). It is
// restored when the tab is reopened "bare", with no explicit route, OR when the app is installed
// (a frozen launch URL rather than the last position). Otherwise — a browser tab with an
// explicit route, a deep link, a bookmark — that route wins. With no remembered route the
// default is the tutorial.
function boot() {
  let last = null
  try {
    last = localStorage.getItem(LAST_HASH_KEY)
  } catch (_) {}
  // NEVER override an EXPLICIT navigation to #/run: the "Full screen" button opens
  // index.html#/run in a new context, and in installed mode the restoration below would replace
  // it with the last route (which never includes `run`), so full screen would no longer start.
  const explicitRun = location.hash.startsWith('#/run')
  if (!explicitRun && last && (isStandaloneApp() || !location.hash) && location.hash !== last) {
    location.hash = last   // triggers hashchange, hence route()
    return
  }
  route()
}
boot()

// State of the GitHub Pages deployment: one check, non-blocking. Since V = Date.now(), a load
// ALWAYS fetches the last SUCCESSFUL deployment, so it is enough to look at the STATUS of the
// last github-pages deployment:
//   in_progress, queued, pending  a new version is on its way (offer to reload)
//   failure, error                the last deployment failed (we are seeing the previous version)
//   success (or an unreachable, rate-limited API)  stay silent, we are up to date.
// The repository is public and api.github.com allows CORS. Best-effort:
//  - the GitHub token (the author's, through pg-github) is used when present, which raises the
//    limit from 60 to 5000 requests an hour;
//  - a TERMINAL result is cached for two minutes (sessionStorage), which avoids hitting the API
//    on every reload (useful behind a shared NAT). The transient state, a deployment under way,
//    is NOT cached, so "Reload" always sees fresh state.
const DEPLOY_REPO = 'ludowik/ollin'
const DEPLOY_CACHE_KEY = 'ollin-deploy-state'
const DEPLOY_DISMISS_KEY = 'ollin-deploy-dismissed'
const DEPLOY_TTL = 120000
const TRANSIENT = ['in_progress', 'queued', 'pending']

async function checkPagesDeploy() {
  // Pointless in the full-screen run mode, where a program is running: no banner over it, and
  // no API calls from that view.
  if (location.hash.startsWith('#/run')) return
  let state = null
  try {
    const cached = JSON.parse(sessionStorage.getItem(DEPLOY_CACHE_KEY) || 'null')
    if (cached && (Date.now() - cached.t) < DEPLOY_TTL) {
      state = cached.state
    } else {
      const token = localStorage.getItem('ollin-gh-token')   // authenticated, hence a 5000/h limit
      const headers = { Accept: 'application/vnd.github+json' }
      if (token) headers.Authorization = 'Bearer ' + token
      const api = (p) => fetch('https://api.github.com/repos/' + DEPLOY_REPO + p, { headers, cache: 'no-store' })
        .then(r => (r.ok ? r.json() : Promise.reject(r.status)))
      const deps = await api('/deployments?environment=github-pages&per_page=1')
      if (Array.isArray(deps) && deps.length) {
        const st = await api('/deployments/' + deps[0].id + '/statuses?per_page=1')
        state = Array.isArray(st) && st[0] ? st[0].state : null
      }
      // Only stable states are cached, so an "under way" state is always checked again.
      if (state && !TRANSIENT.includes(state)) {
        try { sessionStorage.setItem(DEPLOY_CACHE_KEY, JSON.stringify({ t: Date.now(), state })) } catch (_) {}
      }
    }
  } catch (_) { return /* offline, rate-limited or private: stay silent */ }
  // No nagging: once the user has dismissed the banner for THIS state, we say no more for the
  // session (a change of state shows it again).
  let dismissed = null
  try { dismissed = sessionStorage.getItem(DEPLOY_DISMISS_KEY) } catch (_) {}
  if (dismissed === state) return
  if (TRANSIENT.includes(state)) {
    showDeployBanner('⏳ A new version is deploying - reload in a moment.', true, state)
  } else if (state === 'failure' || state === 'error') {
    showDeployBanner('⚠ The last deployment failed - you are seeing the previous version.', false, state)
  }
}

// A banner anchored at the BOTTOM, so it does not cover the toolbar; styled in index.html.
function showDeployBanner(msg, offerReload, state) {
  if (document.getElementById('deploy-banner')) return
  const bar = document.createElement('div')
  bar.id = 'deploy-banner'
  const txt = document.createElement('span'); txt.className = 'msg'; txt.textContent = msg
  bar.appendChild(txt)
  if (offerReload) {
    const rb = document.createElement('button')
    rb.className = 'reload'; rb.textContent = 'Reload'
    rb.addEventListener('click', () => hardReload())
    bar.appendChild(rb)
  }
  const close = document.createElement('button')
  close.className = 'close'; close.textContent = '✕'; close.title = 'Close'
  close.addEventListener('click', () => {
    bar.remove()
    try { sessionStorage.setItem(DEPLOY_DISMISS_KEY, state) } catch (_) {}
  })
  bar.appendChild(close)
  document.body.appendChild(bar)
}
checkPagesDeploy()
