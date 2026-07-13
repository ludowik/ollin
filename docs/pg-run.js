// Logique d'exécution PARTAGÉE entre le Run inline (playground.html) et le mode
// autonome (run.html). But : une seule source de vérité pour le préchargement
// du projet dans le runtime WASM et pour la gestion des erreurs — top-level
// (ex. image.load qui échoue) ET frame graphique (update/draw) — afin que les
// deux modes se comportent à l'identique et ne divergent plus.

export const MANIFEST = 'ollin.project.json'

// Pousse fichiers (.ol) + ressources (images) d'un projet dans le runtime,
// avant exécution. `m` = module WASM Ollin, `project` = { files, resources }.
export function loadProjectIntoRuntime(m, project) {
  if (!m) return
  try {
    // Toujours repartir d'une table de sources PROPRE — y compris en mode exemple
    // (project null) : sinon, dans l'instance WASM partagée, les sources d'un
    // projet précédemment exécuté resteraient importables (imports périmés).
    if (m.resetSources) m.resetSources()
    if (!project) return
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
// DIAGNOSTIC (temporaire) : capte les PARAMÈTRES de l'appel texImage2D qui échoue
// (format/type/taille) pour identifier précisément quelle texture pose problème
// sur iOS. Patch posé une seule fois sur le prototype WebGL2.
function installTexDiag() {
  if (typeof WebGL2RenderingContext === 'undefined') return
  const proto = WebGL2RenderingContext.prototype
  if (proto.__ollinTexPatched) return
  proto.__ollinTexPatched = true
  const orig = proto.texImage2D
  proto.texImage2D = function (...a) {
    try {
      return orig.apply(this, a)
    } catch (e) {
      // a = target, level, internalformat, width, height, border, format, type, srcData
      const hex = n => '0x' + ((n | 0) >>> 0).toString(16)
      window.__ollinTexFail = 'texImage2D ifmt=' + hex(a[2]) + ' fmt=' + hex(a[6]) +
        ' type=' + hex(a[7]) + ' ' + a[3] + 'x' + a[4] +
        ' srcData=' + (a[8] === null ? 'null' : (a[8] === undefined ? 'undefined' : typeof a[8]))
      throw e
    }
  }
}

// État du contexte WebGL + paramètres de la dernière texture fautive.
function glDiag(canvasEl) {
  let s = ''
  try {
    const gl = canvasEl && (canvasEl.getContext('webgl2') || canvasEl.getContext('webgl'))
    s = gl ? (gl.isContextLost() ? ' [gl: CONTEXTE PERDU]' : ' [gl: contexte OK]') : ' [gl: aucun contexte]'
  } catch (e) {
    s = ' [gl: ' + (e && e.message ? e.message : e) + ']'
  }
  if (window.__ollinTexFail) s += ' [' + window.__ollinTexFail + ']'
  return s
}

export function runProgram(m, code, canvasEl, hooks) {
  installTexDiag()   // capte les paramètres d'un texImage2D fautif (diagnostic)
  // Écouteur de perte de contexte (diagnostic) : surface l'événement s'il survient.
  if (canvasEl && !canvasEl.__lostHook) {
    canvasEl.__lostHook = true
    canvasEl.addEventListener('webglcontextlost', () => {
      try { hooks.onError('error: contexte WebGL PERDU (canvas déplacé/ressources iOS)') } catch (_) {}
    })
  }
  // Erreur dans une frame (update/draw) : le runtime WASM (emscripten_frame) a
  // déjà arrêté la boucle et nous remonte le message ici.
  window.__ollinFrameError = (msg) => hooks.onError('error: ' + (msg || "erreur d'exécution") + glDiag(canvasEl))
  let out
  try {
    out = m.execute(code)
  } catch (e) {
    hooks.onError('error: ' + (e && e.message ? e.message : e) + glDiag(canvasEl))
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

// ── Exemples lus direct depuis le dépôt (route #/<vue>/sample/<fichier>) ─────
// Source unique du schéma de route + du fetch (utilisé par playground.js ET run.js).
export function sampleFromAnchor(anchor) {
  return (anchor || '').startsWith('sample/') ? anchor.slice('sample/'.length) : null
}

// Récupère le code d'un exemple (frais : cache-buster + no-cache). Rejette si le
// serveur ne renvoie pas 200 → évite d'exécuter/afficher un corps 404 (HTML).
export async function fetchSample(file, v) {
  const r = await fetch('samples/' + file + '?v=' + v, { cache: 'no-cache' })
  if (!r.ok) throw new Error('exemple introuvable : ' + file)
  return r.text()
}
