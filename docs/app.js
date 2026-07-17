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

// Capture de crash à l'écran (diagnostic device — iOS plein écran sans console).
// Installé AVANT tout chargement WASM pour attraper aussi les fautes dures.
const { installCrashOverlay, wireModule } = await import('./pg-crashlog.js?v=' + V)
installCrashOverlay()

// ── Runtime WASM partagé (une instance pour toute la SPA) ───────────────────
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
// Dernière ROUTE complète visitée (vue + sous-chemin : ancre tutoriel, sample…),
// mémorisée pour la rouvrir au prochain lancement. On stocke la route entière
// (pas juste la vue) → on retrouve l'exemple/l'ancre exacts. `run` est EXCLU
// (transitoire, exige un projet actif) : on conserve la dernière route
// tutoriel/playground pour ne pas rouvrir sur « aucun projet ».
const LAST_HASH_KEY = 'ollin-last-route'

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

// L'app est-elle lancée en mode « installé » (ajout à l'écran d'accueil iOS, ou
// display-mode standalone) ? Dans ce cas l'OS relance TOUJOURS l'URL figée au
// moment de l'installation (souvent #/playground), et NON la dernière position —
// il faut donc restaurer explicitement la dernière route mémorisée.
function isStandaloneApp() {
  try {
    return window.navigator.standalone === true ||
           (window.matchMedia && window.matchMedia('(display-mode: standalone)').matches)
  } catch (_) {
    return false
  }
}

// Démarrage : rouvrir la DERNIÈRE route visitée (mémorisée à chaque montage, hors
// `run`). On la restaure quand :
//   • l'onglet est rouvert « nu » (aucune route explicite), OU
//   • l'app est installée (URL de lancement figée, pas la dernière position).
// Sinon — onglet navigateur avec une route explicite (lien profond, marque-page)
// — cette route a priorité. Défaut (aucune route mémorisée) = tutoriel.
function boot() {
  let last = null
  try {
    last = localStorage.getItem(LAST_HASH_KEY)
  } catch (_) {}
  // Ne JAMAIS écraser une navigation EXPLICITE vers #/run : le bouton « Plein
  // écran » ouvre index.html#/run dans un nouveau contexte ; en mode installé, la
  // restauration ci-dessous le remplacerait par la dernière route (qui n'inclut
  // jamais `run`) → le plein écran ne se lancerait plus.
  const explicitRun = location.hash.startsWith('#/run')
  if (!explicitRun && last && (isStandaloneApp() || !location.hash) && location.hash !== last) {
    location.hash = last   // déclenche hashchange → route()
    return
  }
  route()
}
boot()

// ── État du déploiement GitHub Pages (une vérif, non bloquante) ──────────────
// V = Date.now() → un chargement récupère TOUJOURS le dernier déploiement RÉUSSI.
// Il suffit donc de regarder le STATUT du dernier déploiement github-pages :
//   in_progress/queued/pending → une nouvelle version arrive (proposer de recharger)
//   failure/error              → le dernier déploiement a échoué (on voit la version d'avant)
//   success (ou API injoignable / rate-limit) → silencieux (on est à jour).
// Repo public, CORS ouvert sur api.github.com. Best-effort :
//  - token GitHub (auteur, via pg-github) utilisé s'il est présent → 5000 req/h au lieu de 60 ;
//  - résultat TERMINAL mis en cache 2 min (sessionStorage) → évite de re-taper l'API à
//    chaque rechargement (utile derrière un NAT partagé). L'état transitoire (déploiement
//    en cours) n'est PAS mis en cache → « Recharger » revoit toujours l'état frais.
const DEPLOY_REPO = 'ludowik/ollin'
const DEPLOY_CACHE_KEY = 'ollin-deploy-state'
const DEPLOY_TTL = 120000
const TRANSIENT = ['in_progress', 'queued', 'pending']

async function checkPagesDeploy() {
  let state = null
  try {
    const cached = JSON.parse(sessionStorage.getItem(DEPLOY_CACHE_KEY) || 'null')
    if (cached && (Date.now() - cached.t) < DEPLOY_TTL) {
      state = cached.state
    } else {
      const token = localStorage.getItem('ollin-gh-token')   // auteur → limite 5000/h
      const headers = { Accept: 'application/vnd.github+json' }
      if (token) headers.Authorization = 'Bearer ' + token
      const api = (p) => fetch('https://api.github.com/repos/' + DEPLOY_REPO + p, { headers, cache: 'no-store' })
        .then(r => (r.ok ? r.json() : Promise.reject(r.status)))
      const deps = await api('/deployments?environment=github-pages&per_page=1')
      if (Array.isArray(deps) && deps.length) {
        const st = await api('/deployments/' + deps[0].id + '/statuses?per_page=1')
        state = Array.isArray(st) && st[0] ? st[0].state : null
      }
      // ne cacher que les états stables → l'état « en cours » reste toujours revérifié
      if (state && !TRANSIENT.includes(state)) {
        try { sessionStorage.setItem(DEPLOY_CACHE_KEY, JSON.stringify({ t: Date.now(), state })) } catch (_) {}
      }
    }
  } catch (_) { return /* hors ligne / rate-limit / privé : silencieux */ }
  if (TRANSIENT.includes(state)) {
    showDeployBanner('⏳ Une nouvelle version se déploie — recharge dans un instant.', true)
  } else if (state === 'failure' || state === 'error') {
    showDeployBanner('⚠ Le dernier déploiement a échoué — tu vois la version précédente.', false)
  }
}

// Bandeau ancré EN BAS (ne recouvre pas la barre d'outils du haut) ; dismissible.
function showDeployBanner(msg, offerReload) {
  if (document.getElementById('deploy-banner')) return
  const bar = document.createElement('div')
  bar.id = 'deploy-banner'
  bar.style.cssText = 'position:fixed;bottom:0;left:0;right:0;z-index:9999;background:#242742;' +
    'color:#c9d1e0;border-top:1px solid #2e3150;font:13px system-ui,-apple-system,sans-serif;' +
    'padding:8px 14px;display:flex;align-items:center;gap:12px;box-shadow:0 -2px 10px rgba(0,0,0,.45)'
  const txt = document.createElement('span'); txt.textContent = msg; txt.style.flex = '1'
  bar.appendChild(txt)
  if (offerReload) {
    const rb = document.createElement('button')
    rb.textContent = 'Recharger'
    rb.style.cssText = 'background:#7c83ff;color:#fff;border:none;border-radius:5px;padding:5px 12px;font-size:13px;cursor:pointer'
    rb.addEventListener('click', () => hardReload())
    bar.appendChild(rb)
  }
  const close = document.createElement('button')
  close.textContent = '✕'; close.title = 'Fermer'
  close.style.cssText = 'background:none;border:none;color:#7c85a2;font-size:16px;cursor:pointer;line-height:1'
  close.addEventListener('click', () => bar.remove())
  bar.appendChild(close)
  document.body.appendChild(bar)
}
checkPagesDeploy()
