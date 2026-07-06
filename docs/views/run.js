// Vue RUN (exécution autonome plein écran) — init(ctx) appelée par app.js après
// montage du fragment views/run.html.
//   ctx = { root, getOllin, hardReload, navigate, v }
// Recharge le projet ACTIF depuis IndexedDB (écrit par le playground) et
// l'exécute via la logique PARTAGÉE (pg-run.js) — mêmes préchargement et gestion
// d'erreurs que le Run inline du playground.

export async function init(ctx) {
  const { getOllin, hardReload } = ctx
  let mod = null   // module WASM (capturé par stop() ; pas de global smuggling)

  // Modules partagés (cache-bustés avec le jeton de version de la SPA : une même
  // session réutilise la même URL → pas de croissance du registre de modules).
  const Store = await import('../pg-store.js?v=' + ctx.v)
  const { loadProjectIntoRuntime, runProgram } = await import('../pg-run.js?v=' + ctx.v)

  const statusEl = document.getElementById('status')
  const outEl    = document.getElementById('out')
  const canvasEl = document.getElementById('canvas')   // canvas PARTAGÉ (shell)

  // Reparenter le canvas partagé dans la zone graphique de cette vue.
  const pane = document.getElementById('output-pane')
  canvasEl.style.display = 'none'
  pane.appendChild(canvasEl)

  document.getElementById('reload-btn').addEventListener('click', hardReload)

  function showText(text) {
    outEl.style.display    = 'block'
    canvasEl.style.display = 'none'
    outEl.textContent = (text && String(text).length) ? String(text) : '(aucune sortie)'
    outEl.className   = (text && String(text).startsWith('error:')) ? 'err' : 'ok'
  }

  const stop = () => {
    try { mod && mod.pauseMainLoop && mod.pauseMainLoop() } catch (_) {}
    window.__ollinFrameError = undefined
  }

  // Deux sources : soit un EXEMPLE lu direct depuis le dépôt (route
  // #/run/sample/<fichier>, rechargé frais → un refresh reprend la version du
  // dépôt), soit le PROJET ACTIF depuis IndexedDB.
  const exampleFile = (ctx.anchor || '').startsWith('sample/') ? ctx.anchor.slice(7) : null
  // Le lien « Éditeur » préserve l'exemple courant (sinon retour en mode projet).
  if (exampleFile) {
    const back = document.querySelector('#bar a')
    if (back) back.setAttribute('href', '#/playground/sample/' + exampleFile)
  }
  let project = null
  let code = null
  if (exampleFile) {
    try {
      code = await fetch('samples/' + exampleFile + '?v=' + ctx.v, { cache: 'no-cache' }).then(r => r.text())
    } catch (_) {}
    if (code === null) {
      statusEl.textContent = ''
      showText("error: exemple introuvable : " + exampleFile)
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
      showText("error: aucun projet. Ouvre ce mode depuis l'éditeur (bouton « Autonome »).")
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
  statusEl.textContent = ''
  runProgram(mod, code, canvasEl, {
    onError:   (msg) => { statusEl.textContent = ''; showText(msg) },
    // Programme graphique : donner le focus clavier au canvas (programmes
    // interactifs lisant keyboard.*), comme l'ancien run.html (canvas tabindex).
    onRunning: () => { statusEl.textContent = 'En cours…'; try { canvasEl.focus() } catch (_) {} },
    onOutput:  (out) => showText(out),
  })

  return stop
}
