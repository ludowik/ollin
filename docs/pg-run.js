// Logique d'exécution PARTAGÉE entre le Run inline (playground.html) et le mode
// autonome (run.html). But : une seule source de vérité pour le préchargement
// du projet dans le runtime WASM et pour la gestion des erreurs — top-level
// (ex. image.load qui échoue) ET frame graphique (update/draw) — afin que les
// deux modes se comportent à l'identique et ne divergent plus.

export const MANIFEST = 'ollin.project.json'

// Pousse fichiers (.ol) + ressources (images) d'un projet dans le runtime,
// avant exécution. `m` = module WASM Ollin, `project` = { files, resources }.
export function loadProjectIntoRuntime(m, project) {
  if (!m || !project) return
  try {
    if (m.resetSources) m.resetSources()
    for (const path in (project.files || {})) {
      if (path === MANIFEST) continue
      if (m.preloadSource) m.preloadSource(path, project.files[path])
    }
    const res = project.resources || {}
    for (const name in res) {
      if (m.preloadImage) m.preloadImage(name, res[name].b64, res[name].ext)
    }
  } catch (_) { /* préchargement best-effort */ }
}

// Exécute `code` et route le résultat via des hooks fournis par l'appelant :
//   hooks.onError(msg)   erreur (top-level OU frame graphique), chaîne « error: … »
//   hooks.onRunning()    le programme a ouvert un canvas (boucle graphique lancée)
//   hooks.onOutput(text) sortie texte d'un programme non graphique
export function runProgram(m, code, canvasEl, hooks) {
  // Erreur dans une frame (update/draw) : le runtime WASM (emscripten_frame) a
  // déjà arrêté la boucle et nous remonte le message ici.
  window.__ollinFrameError = (msg) => hooks.onError('error: ' + (msg || "erreur d'exécution"))
  let out
  try {
    out = m.execute(code)
  } catch (e) {
    hooks.onError('error: ' + (e && e.message ? e.message : e))
    return
  }
  // Une erreur du haut-niveau peut survenir APRÈS l'ouverture du canvas (ex.
  // image.load juste après graphics.canvas) : la traiter avant la branche
  // « canvas visible », sinon l'écran resterait muet.
  if (typeof out === 'string' && out.startsWith('error:')) {
    hooks.onError(out)
    return
  }
  if (canvasEl && canvasEl.style.display === 'block') {
    hooks.onRunning()
  } else {
    hooks.onOutput(out)
  }
}

// Rechargement « dur », PARTAGÉ par toutes les pages : vide le Cache API (Service
// Worker) puis recharge via une URL cache-bustée, ce qui contourne aussi le cache
// HTTP de la page elle-même (un simple location.reload() peut resservir l'ancienne
// page). Garantit qu'on récupère bien le dernier code déployé.
export function hardReload() {
  // Conserver le fragment (#/vue/…) : sinon un rechargement dur perd la route
  // courante (ex. un exemple #/playground/sample/…) et retombe sur la vue défaut.
  const go = () => location.replace(location.pathname + '?t=' + Date.now() + location.hash)
  if ('caches' in window) {
    caches.keys().then(ks => Promise.all(ks.map(k => caches.delete(k)))).then(go).catch(go)
  } else {
    go()
  }
}

// Ajoute un cache-buster unique à une URL → force une version fraîche.
export function freshUrl(url) {
  // Insère le cache-buster AVANT le fragment (#ancre) pour ne pas le perdre.
  const h = url.indexOf('#')
  const base = h >= 0 ? url.slice(0, h) : url
  const frag = h >= 0 ? url.slice(h) : ''
  return base + (base.includes('?') ? '&' : '?') + 't=' + Date.now() + frag
}

// Ouvre une page (nouvel onglet/fenêtre) en forçant une version fraîche.
export function openFresh(url, target) {
  return window.open(freshUrl(url), target)
}

// Fait que TOUTE navigation via un lien interne (*.html) dans le MÊME onglet
// force une version fraîche — comme le bouton Recharger et le mode autonome.
// On n'intercepte QUE la navigation _self : les liens _blank/_top et les clics
// avec modificateur (Ctrl/Cmd/Maj/clic-milieu) sont laissés au navigateur (pas
// de réécriture du href → pas d'accumulation de ?t=).
export function bindFreshLinks() {
  document.addEventListener('click', (e) => {
    if (e.defaultPrevented || e.button !== 0 || e.ctrlKey || e.metaKey || e.shiftKey || e.altKey) return
    const a = e.target.closest && e.target.closest('a[href]')
    if (!a) return
    const target = a.getAttribute('target')
    if (target && target !== '_self') return                            // _blank/_top : navigateur
    const href = a.getAttribute('href')
    if (!href || /^(https?:|\/\/|#|mailto:|tel:)/.test(href)) return    // externe / ancre pure
    if (!/\.html($|[?#])/.test(href)) return                            // pages HTML seulement
    e.preventDefault()
    location.assign(freshUrl(href))   // freshUrl préserve le #fragment
  })
}
