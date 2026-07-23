// Vue RUN (exécution autonome plein écran) — init(ctx) appelée par app.js après
// montage du fragment views/run.html.
//   ctx = { root, getOllin, hardReload, navigate, v }
// Recharge le projet ACTIF depuis IndexedDB (écrit par le playground) et
// l'exécute via la logique PARTAGÉE (pg-run.js) — mêmes préchargement et gestion
// d'erreurs que le Run inline du playground.

export async function init(ctx) {
  const { getOllin } = ctx
  let mod = null   // module WASM (capturé par stop() ; pas de global smuggling)

  // Modules partagés (cache-bustés avec le jeton de version de la SPA : une même
  // session réutilise la même URL → pas de croissance du registre de modules).
  const Store = await import('../pg-store.js?v=' + ctx.v)
  const { loadProjectIntoRuntime, runProgram, sampleFromAnchor, fetchSample, preloadSampleModels, preloadSampleImports } = await import('../pg-run.js?v=' + ctx.v)
  const { pinToVisualViewport } = await import('../pg-viewport.js?v=' + ctx.v)

  // Barre du plein ecran collee au haut du visible quand le clavier s'ouvre.
  const unpinViewport = pinToVisualViewport()

  const statusEl = document.getElementById('status')
  const outEl    = document.getElementById('out')
  const canvasEl = document.getElementById('canvas')   // canvas PARTAGÉ (shell)

  // Reparenter le canvas partagé dans la zone graphique de cette vue.
  const pane = document.getElementById('output-pane')
  canvasEl.style.display = 'none'
  pane.appendChild(canvasEl)

  function showText(text) {
    outEl.style.display    = 'block'
    canvasEl.style.display = 'none'
    outEl.textContent = (text && String(text).length) ? String(text) : '(aucune sortie)'
    outEl.className   = (text && String(text).startsWith('error:')) ? 'err' : 'ok'
  }

  // (Re)lance le programme courant. Réutilisé au démarrage ET par « Recharger ».
  async function launch() {
    statusEl.textContent = ''
    // Modèles 3D référencés → préchargés depuis samples/ (best-effort ; sans effet
    // pour un projet dont les modèles sont déjà dans ses ressources).
    const imported = await preloadSampleImports(mod, code, ctx.v)
    await preloadSampleModels(mod, code + '\n' + imported, ctx.v)   // modèles des imports aussi
    // Portée « projet » du module `data` : cohérente avec le playground (même clé).
    window.__ollinDataProject = exampleFile ? ('sample:' + exampleFile) : (project && project.id ? project.id : '_')
    runProgram(mod, code, canvasEl, {
      filename:  project ? (project.entry || '') : (exampleFile || ''),
      onError:   (msg) => { statusEl.textContent = ''; showText(msg) },
      // Programme graphique : focus clavier au canvas (programmes interactifs).
      // preventScroll : sinon mobile défile pour amener le canvas dans le viewport.
      onRunning: () => { statusEl.textContent = ''; try { canvasEl.focus({ preventScroll: true }) } catch (_) {} },
      onOutput:  (out) => showText(out),
    })
  }

  // ── Contrôles d'exécution : Recharger + Relancer + Pause/Reprendre ──────────
  // DEUX relances distinctes :
  //  • « Recharger » recharge la PAGE → nouvelle instance WASM (module frais).
  //  • « Relancer » ré-exécute DANS LA MÊME instance WASM (sans reload) : plus
  //    rapide (pas de flash de rechargement), et sûr depuis la correction de la
  //    ré-entrance des pools d'objets (voir MapPool::release).
  const reloadBtn   = document.getElementById('reload-btn')
  const relaunchBtn = document.getElementById('relaunch-btn')
  const pauseBtn    = document.getElementById('pause-btn')
  const ICON_PAUSE = '<svg width="13" height="13" viewBox="0 0 16 16" fill="currentColor"><rect x="3.5" y="2.5" width="3.2" height="11" rx="1"/><rect x="9.3" y="2.5" width="3.2" height="11" rx="1"/></svg>'
  const ICON_PLAY  = '<svg width="13" height="13" viewBox="0 0 16 16" fill="currentColor"><path d="M4 2.5l9 5.5-9 5.5z"/></svg>'
  let paused = false
  function setPauseUI() {
    if (!pauseBtn) return
    pauseBtn.innerHTML = paused ? ICON_PLAY + '<span class="bar-label">Reprendre</span>'
                                : ICON_PAUSE + '<span class="bar-label">Pause</span>'
  }
  if (pauseBtn) {
    pauseBtn.addEventListener('click', () => {
      if (!mod) return
      if (paused) {
        try { mod.resumeMainLoop() } catch (_) {}
        paused = false
      } else {
        try { mod.pauseMainLoop() } catch (_) {}
        paused = true
      }
      setPauseUI()
    })
  }
  if (reloadBtn) {
    reloadBtn.addEventListener('click', () => {
      location.reload()   // module WASM neuf (chemin sûr, conserve le hash #/run/…)
    })
  }
  if (relaunchBtn) {
    relaunchBtn.addEventListener('click', () => {
      // relance IN-PLACE : ré-exécute dans la MÊME instance WASM (pas de reload page)
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
    unpinViewport()
  }

  // Deux sources : soit un EXEMPLE lu direct depuis le dépôt (route
  // #/run/sample/<fichier>, rechargé frais → un refresh reprend la version du
  // dépôt), soit le PROJET ACTIF depuis IndexedDB.
  const exampleFile = sampleFromAnchor(ctx.anchor)
  // Le lien « Éditeur » préserve l'exemple courant (sinon retour en mode projet).
  if (exampleFile) {
    const back = document.querySelector('#bar a')
    if (back) back.setAttribute('href', '#/playground/sample/' + exampleFile)
  }
  let project = null
  let code = null
  if (exampleFile) {
    try {
      code = await fetchSample(exampleFile, ctx.v)   // rejette sur 404 (pas d'exécution d'une page HTML)
    } catch (e) {
      statusEl.textContent = ''
      showText('error: ' + (e && e.message ? e.message : 'exemple introuvable : ' + exampleFile))
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
      showText("error: aucun projet. Ouvre ce mode depuis l'éditeur (bouton « Plein écran »).")
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
