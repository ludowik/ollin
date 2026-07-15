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
      const ext = (res[name].ext || '').toLowerCase()
      // Modèles 3D (OBJ/GLTF/GLB) → preloadModel ; sinon image.
      if ((ext === 'obj' || ext === 'gltf' || ext === 'glb') && m.preloadModel) {
        m.preloadModel(name, res[name].b64, ext)
      } else if (m.preloadImage) {
        m.preloadImage(name, res[name].b64, ext)
      }
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
    // Trap dur SYNCHRONE (relance in-place iOS) : rattrapé ici → surface l'overlay
    // de diagnostic AVEC la stack (nom de la fonction fautive), que le message
    // texte seul perdrait. N'ouvre l'overlay que pour une faute dure.
    try { window.__ollinCrash && window.__ollinCrash.captureError('execute (relance)', e) } catch (_) {}
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

// Octets → base64 (par blocs pour ne pas dépasser la pile d'arguments).
function bytesToB64(bytes) {
  let bin = ''
  const CHUNK = 0x8000
  for (let i = 0; i < bytes.length; i += CHUNK) {
    bin += String.fromCharCode.apply(null, bytes.subarray(i, i + CHUNK))
  }
  return btoa(bin)
}

// Mode EXEMPLE : précharge les modèles 3D référencés par graphics.model("x.obj")
// en les récupérant depuis samples/ (les projets utilisateur, eux, passent par
// leurs ressources). Best-effort : un modèle introuvable est simplement ignoré.
export async function preloadSampleModels(m, code, v) {
  if (!m || !m.preloadModel || typeof code !== 'string') return
  const re = /model\s*\(\s*["']([^"']+\.(?:obj|glb|gltf))["']\s*\)/gi
  const seen = new Set()
  let match
  while ((match = re.exec(code))) {
    const file = match[1]
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

// Cache de sources .ol importées (chemin résolu → texte) pour la session : évite
// de re-télécharger à chaque relance (page reload = module frais = cache vidé).
const _importSrcCache = new Map()

// Mode EXEMPLE : précharge les fichiers .ol IMPORTÉS (import "x.ol") depuis samples/
// dans le registre de sources du runtime, pour que `import` se résolve quand on lance
// un exemple direct (les projets utilisateur préchargent déjà tous leurs fichiers).
// Suit les imports en chaîne (BFS) en RÉSOLVANT chaque chemin comme le parseur
// (relatif au dossier du fichier importateur) → clé de registre cohérente, y compris
// en sous-dossier. Renvoie la CONCATÉNATION des sources importées (pour que
// l'appelant y précharge aussi les modèles/assets référencés). Best-effort.
export async function preloadSampleImports(m, code, v) {
  if (!m || !m.preloadSource || typeof code !== 'string') return ''
  const findImports = (src) => {
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
  // Résolution identique au parseur : base_dir + chemin (concat naïve), sauf chemin absolu.
  const resolve = (parentDir, imp) => (imp[0] === '/' ? imp : parentDir + imp)
  const seen = new Set()
  const collected = []
  let queue = findImports(code).map((imp) => resolve('', imp))   // entrée : base_dir vide
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
    m.preloadSource(key, src)          // clé = chemin résolu (= ce que source_get() cherche)
    collected.push(src)
    const pdir = dirOf(key)
    for (const imp of findImports(src)) queue.push(resolve(pdir, imp))
  }
  return collected.join('\n')
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
