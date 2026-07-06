// Routeur de la web app monopage (SPA) Ollin.
//
// Une seule page (index.html = shell) héberge plusieurs VUES montées à la
// demande dans #view. Chaque vue = un fragment HTML (views/<nom>.html) + un
// module d'init (views/<nom>.js exportant init(ctx) → cleanup()).
//
// Routage par hash :
//   #/<vue>[/<ancre>]  → change de vue (ex. #/tutoriel, #/tutoriel/for)
//   #<ancre> (sans /)  → ancre interne de la vue courante (défilement natif)
//   (vide)             → vue par défaut (tutoriel)
// Le préfixe « #/ » distingue une route d'une simple ancre : les liens de
// section du tutoriel (href="#intro") restent de simples ancres et ne
// déclenchent pas de changement de vue.
//
// Le runtime WASM est chargé UNE SEULE FOIS (getOllin) et partagé par toutes
// les vues, de même que le <canvas> (déplacé dans la vue active, puis rendu au
// shell au démontage).
// Modules partagés importés avec cache-buster (politique anti-cache du projet).
const { hardReload, freshUrl } = await import('./pg-run.js?v=' + Date.now())

// ── Runtime WASM partagé (une instance pour toute la SPA) ───────────────────
let ollinPromise = null
function getOllin() {
  if (ollinPromise) return ollinPromise
  ollinPromise = new Promise((resolve, reject) => {
    const s = document.createElement('script')
    const bust = Date.now()
    s.src = 'wasm/ollin.js?' + bust
    s.onload = () => {
      const dir = s.src.replace(/\?.*$/, '').replace(/[^/]*$/, '')
      OllinModule({
        locateFile: f => dir + f + '?' + bust,
        canvas: document.getElementById('canvas'),
        print: () => {},
        printErr: () => {},
      }).then(resolve).catch(reject)
    }
    s.onerror = () => reject(new Error('WASM introuvable'))
    document.head.appendChild(s)
  })
  return ollinPromise
}

// ── Table des vues ──────────────────────────────────────────────────────────
// Vues internes (fragment monté) : { html, js }.
// Vues encore autonomes (migration incrémentale) : { external } → navigation
// pleine page cache-vidée, en attendant leur intégration comme fragment.
const ROUTES = {
  tutoriel:   { html: 'views/tutoriel.html',   js: './views/tutoriel.js' },
  playground: { html: 'views/playground.html', js: './views/playground.js' },
  run:        { html: 'views/run.html',        js: './views/run.js' },
}
const DEFAULT_VIEW = 'tutoriel'

const viewEl     = document.getElementById('view')
const canvasHome = document.getElementById('canvas-home')

let currentView    = null
let currentCleanup = null

function parseHash() {
  const h = location.hash
  if (h.startsWith('#/')) {
    const parts = h.slice(2).split('/')
    return { view: parts[0] || DEFAULT_VIEW, anchor: parts[1] || '' }
  }
  // Ancre nue (#intro) ou vide → vue courante/défaut, défilement sur l'ancre.
  return { view: currentView || DEFAULT_VIEW, anchor: h.startsWith('#') ? h.slice(1) : '' }
}

function stowCanvas() {
  const canvas = document.getElementById('canvas')
  if (canvas && canvas.parentNode !== canvasHome) {
    canvas.style.display = 'none'
    canvasHome.appendChild(canvas)
  }
}

async function mount(view, anchor) {
  const route = ROUTES[view] || ROUTES[DEFAULT_VIEW]

  // Vue encore autonome → navigation pleine page (cache-vidée).
  if (route.external) {
    location.assign(freshUrl(route.external))
    return
  }

  // Démonte la vue précédente proprement.
  if (currentCleanup) {
    try { currentCleanup() } catch (e) { console.error('cleanup:', e) }
    currentCleanup = null
  }
  stowCanvas()

  // Charge le fragment (cache-busté : une mise à jour est prise dès le prochain
  // rendu, cohérent avec la politique anti-cache du reste du projet).
  const bust = Date.now()
  try {
    const res  = await fetch(route.html + '?v=' + bust)
    viewEl.innerHTML = await res.text()

    const mod = await import(route.js + '?v=' + bust)
    const ctx = { root: viewEl, getOllin, hardReload, navigate }
    currentCleanup = (await mod.init(ctx)) || null
    currentView = view

    if (anchor) scrollToAnchor(anchor)
    else window.scrollTo(0, 0)
  } catch (e) {
    console.error('Échec de montage de la vue « ' + view + ' » :', e)
    viewEl.innerHTML = '<div style="padding:40px;text-align:center;font-family:system-ui,sans-serif;color:#c9d1e0">' +
      '<p style="color:#f87171;font-weight:600;margin-bottom:12px">Échec du chargement de la vue.</p>' +
      '<button onclick="location.reload()" style="background:#7c83ff;color:#fff;border:none;border-radius:7px;padding:9px 20px;font-size:14px;cursor:pointer">Recharger</button></div>'
    currentView = null
  }
}

function scrollToAnchor(id) {
  const el = document.getElementById(id)
  if (el) el.scrollIntoView({ behavior: 'smooth' })
}

// Navigation programmatique (utilisable par les vues via ctx.navigate).
function navigate(view, anchor) {
  location.hash = '#/' + view + (anchor ? '/' + anchor : '')
}

async function route() {
  const { view, anchor } = parseHash()
  // Même vue déjà montée + simple ancre → défilement sans re-montage.
  if (view === currentView && ROUTES[view] && !ROUTES[view].external) {
    if (anchor) scrollToAnchor(anchor)
    return
  }
  await mount(view, anchor)
}

addEventListener('hashchange', route)
route()
