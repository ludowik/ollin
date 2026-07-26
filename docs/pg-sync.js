// ── Ollin Playground — coordinateur de sauvegarde distante ──────────────────
//
// Découple la sauvegarde LOCALE (instantanée, faite par l'appelant) de la
// sauvegarde DISTANTE (push GitHub, coûteuse et faillible). L'appelant fournit
// la mécanique réelle (`doPush`, `canPush`) ; ce module n'orchestre QUE le
// « quand » : anti-rafale (debounce), coalescing, single-flight, tolérance
// hors-ligne. Aucune connaissance de GitHub ni du modèle de projet ici.
//
// Garanties :
//   • debounce      : N frappes en < debounceMs = 1 seul push (le dernier état).
//   • single-flight : jamais deux pushs en parallèle.
//   • coalescing    : une modif arrivée pendant un push en vol re-planifie UN
//                     push après coup (pas d'empilement).
//   • hors-ligne    : un push qui échoue ne casse rien — l'état reste « sale »
//                     et sera repoussé plus tard (retryMs).
//
// `doPush(project) → Promise` : push réel (peut throw → l'état est re-planifié).
// `canPush(project) → bool` : garde-fou évalué à chaque déclenchement (projet
// éligible, en ligne, dirty…). `onError(err, project)` : notification ; ne doit
// pas throw.

export function createRemoteSync({ doPush, canPush, onError, debounceMs = 3000, retryMs = 15000 } = {}) {
  let timer    = null    // debounce en cours
  let pending  = null    // dernier projet en attente de push
  let inFlight = false    // un push est en cours
  let requeue  = false   // une modif est arrivée pendant le push en vol

  const allowed = p => !!p && (!canPush || canPush(p))

  function arm(delay) {
    clearTimeout(timer)
    timer = setTimeout(() => { timer = null; run() }, delay)
  }

  // Planifie un push différé du projet (anti-rafale). Idempotent.
  function schedule(project) {
    pending = project
    if (allowed(project)) arm(debounceMs)
  }

  // Déclenche le push. Single-flight : si un push est en vol, on marque `requeue`
  // (un nouveau push suivra à la fin). Avale l'erreur (retry différé via requeue).
  async function run() {
    if (inFlight) {
      requeue = true
      return
    }
    const project = pending
    if (!allowed(project)) return
    inFlight = true
    requeue = false
    try {
      await doPush(project)
    } catch (err) {
      requeue = true   // hors-ligne / échec : garder l'état sale, retenter plus tard
      if (onError) {
        try { onError(err, project) } catch (_) {}
      }
    } finally {
      inFlight = false
      if (requeue && allowed(pending)) arm(retryMs)
    }
  }

  // Annule toute planification en attente (démontage, changement de projet).
  // N'interrompt pas un push déjà en vol.
  function cancel() {
    clearTimeout(timer)
    timer = null
    pending = null
    requeue = false
  }

  return { schedule, cancel }
}
