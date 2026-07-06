// Routeur de la web app monopage (SPA) Ollin.
//
// Une seule page (index.html = shell) héberge plusieurs VUES montées à la
// demande dans #view. Chaque vue = un fragment HTML (views/<nom>.html) + un
// module d'init (views/<nom>.js exportant init(ctx) → cleanup()).
//
// Routage par hash :
//   #/<vue>[/<ancre>]  → change de vue (ex. #/tutoriel, #/tutoriel/for)
//   #<ancre> (sans /)  → ancre interne de la vue courante (défilement natif)
//   (vide)             → dernière vue visitée, sinon vue par défaut (tutoriel)
// Le préfixe « #/ » distingue une route d'une simple ancre : les liens de
// section du tutoriel (href="#intro") restent de simples ancres et ne
// déclenchent pas de changement de vue.
//
// Le runtime WASM est chargé UNE SEULE FOIS (getOllin) et partagé par toutes
// les vues, de même que le <canvas> (déplacé dans la vue active, puis rendu au
// shell au démontage).

// Jeton de version UNIQUE pour ce chargement de page : sert de cache-buster à
// TOUS les imports/fetch (routeur + vues + modules partagés via ctx.v). Un même
// chargement réutilise donc la même URL de module (pas de copie neuve à chaque
// navigation → pas de croissance non bornée du registre de modules), tandis
// qu'un rechargement (ou hardReload) repart avec un jeton frais → dernière
// version déployée. (Avant : Date.now() à chaque import → fuite par navigation.)
const V = Date.now()
const { hardReload } = await import('./pg-run.js?v=' + V)

// ── Runtime WASM partagé (une instance pour toute la SPA) ───────────────────
let ollinPromise = null
function getOllin() {
  if (ollinPromise) return ollinPromise
  ollinPromise = new Promise((resolve, reject) => {
    const s = document.createElement('script')
    s.src = 'wasm/ollin.js?' + V
    s.onload = () => {
      const dir = s.src.replace(/\?.*$/, '').replace(/[^/]*$/, '')
      OllinModule({
        locateFile: f => dir + f + '?' + V,
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
// anchorIsSection: l'ancre est un id de section à faire défiler (pas de
// re-montage). Sinon l'ancre est un paramètre de vue (ex. sample/<fichier>) →
// re-montage quand il change.
const ROUTES = {
  tutoriel:   { html: 'views/tutoriel.html',   js: './views/tutoriel.js', anchorIsSection: true },
  playground: { html: 'views/playground.html', js: './views/playground.js' },
  run:        { html: 'views/run.html',        js: './views/run.js' },
}
const DEFAULT_VIEW = 'tutoriel'
const LAST_VIEW_KEY = 'ollin-last-view'   // réouverture de la dernière vue
// Vues éligibles à la réouverture automatique : PAS `run`, qui exige un projet
// actif et retomberait sinon sur l'écran « aucun projet » à l'ouverture du site.
const RESTORABLE = new Set(['tutoriel', 'playground'])

// Viewport par vue. Le playground et le mode run bloquent le zoom (maximum-scale)
// pour éviter le zoom automatique d'iOS quand l'éditeur (police < 16px) prend le
// focus — comportement de l'ancienne page autonome, perdu au passage en SPA (un
// seul viewport partagé). Le tutoriel reste zoomable (lecture confortable).
const VIEWPORT = {
  tutoriel:   'width=device-width, initial-scale=1.0',
  playground: 'width=device-width, initial-scale=1.0, maximum-scale=1.0',
  run:        'width=device-width, initial-scale=1.0, maximum-scale=1.0, viewport-fit=cover',
}
function applyViewport(view) {
  const meta = document.querySelector('meta[name="viewport"]')
  if (meta) meta.setAttribute('content', VIEWPORT[view] || VIEWPORT[DEFAULT_VIEW])
}

const viewEl     = document.getElementById('view')
const canvasHome = document.getElementById('canvas-home')

let currentView    = null
let currentCleanup = null
let currentAnchor  = ''    // sous-chemin de la vue courante (ancre tutoriel, ou ex/<fichier>)
let navSeq         = 0     // garde de ré-entrance : identifie la navigation courante

function parseHash() {
  const h = location.hash
  if (h.startsWith('#/')) {
    const parts = h.slice(2).split('/')
    // anchor = tout ce qui suit la vue : ancre de section (tutoriel) OU sous-route
    // paramétrée de la vue (ex. « ex/game_of_life.ol » pour le playground/run).
    return { view: parts[0] || DEFAULT_VIEW, anchor: parts.slice(1).join('/') }
  }
  // Ancre nue (#intro) ou vide → vue courante/défaut, défilement sur l'ancre.
  return { view: currentView || DEFAULT_VIEW, anchor: h.startsWith('#') ? h.slice(1) : '' }
}

// Range le <canvas> partagé dans le shell (masqué) et REMET SES STYLES À PLAT :
// une vue peut poser des styles inline (le tutoriel : margin/borderRadius/…) ;
// sans reset ils fuiraient sur la vue suivante (canvas décentré, etc.).
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
  const seq = ++navSeq                 // toute navigation ultérieure invalide celle-ci
  const stale = () => seq !== navSeq

  await teardownCurrent()
  applyViewport(view)   // AVANT le montage → en place quand l'éditeur prend le focus

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
      // Une navigation plus récente a pris la main pendant l'init → nettoyer
      // immédiatement cette vue périmée (sinon ses écouteurs globaux fuient).
      if (cleanup) {
        try { cleanup() } catch (_) {}
      }
      return
    }
    currentCleanup = cleanup
    currentView = view
    currentAnchor = anchor
    if (RESTORABLE.has(view)) {
      try { localStorage.setItem(LAST_VIEW_KEY, view) } catch (_) {}
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
    console.error('Échec de montage de la vue « ' + view + ' » :', e)
    viewEl.innerHTML = '<div style="padding:40px;text-align:center;font-family:system-ui,sans-serif;color:#c9d1e0">' +
      '<p style="color:#f87171;font-weight:600;margin-bottom:12px">Échec du chargement de la vue.</p>' +
      '<button onclick="location.reload()" style="background:#7c83ff;color:#fff;border:none;border-radius:7px;padding:9px 20px;font-size:14px;cursor:pointer">Recharger</button></div>'
    currentView = null
  }
}

function scrollToAnchor(id) {
  const el = document.getElementById(id)
  if (el) {
    el.scrollIntoView({ behavior: 'smooth' })
  }
}

// Navigation programmatique (utilisable par les vues via ctx.navigate).
function navigate(view, anchor) {
  location.hash = '#/' + view + (anchor ? '/' + anchor : '')
}

async function route() {
  const { view, anchor } = parseHash()
  if (view === currentView && ROUTES[view]) {
    // Ancre = section (tutoriel) → défilement sans re-montage.
    if (ROUTES[view].anchorIsSection) {
      if (anchor) {
        scrollToAnchor(anchor)
      }
      return
    }
    // Ancre = paramètre de vue (ex. sample/<fichier>) : même valeur → déjà monté ;
    // changée (autre exemple) → re-monter.
    if (anchor === currentAnchor) {
      return
    }
  }
  await mount(view, anchor)
}

addEventListener('hashchange', route)

// Démarrage : sans hash explicite, rouvrir la DERNIÈRE vue visitée (mémorisée
// à chaque montage, hors `run`). Défaut = tutoriel. Une URL profonde (#/… ou
// #ancre) a toujours priorité sur la dernière vue.
function boot() {
  if (!location.hash) {
    const last = localStorage.getItem(LAST_VIEW_KEY)
    if (last && RESTORABLE.has(last) && last !== DEFAULT_VIEW) {
      location.hash = '#/' + last   // déclenche hashchange → route()
      return
    }
  }
  route()
}
boot()
