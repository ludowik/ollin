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
//   • hors-ligne    : un push auto qui échoue ne casse rien — l'état reste
//                     « sale » et sera repoussé plus tard (retryMs).
//
// `doPush(project) → Promise` : push réel (peut throw). `canPush(project) →
// bool` : garde-fou évalué à chaque déclenchement (projet lié, en ligne, pas de
// conflit, opt-in…). `onError(err, project)` : notification (auto uniquement) ;
// ne doit pas throw. Distinction clé : `schedule()` (auto) AVALE les erreurs et
// retente ; `flush()` (Push manuel) les PROPAGE pour que l'appelant gère le
// conflit (confirmation d'écrasement).

export function createRemoteSync({ doPush, canPush, onError, debounceMs = 3000, retryMs = 15000 } = {}) {
  let timer    = null    // debounce en cours
  let pending  = null    // dernier projet en attente de push
  let inFlight = null    // Promise « sûre » du push courant (ne rejette jamais)
  let requeue  = false   // une modif est arrivée pendant le push en vol

  const allowed = p => !!p && (!canPush || canPush(p))

  function arm(delay) {
    clearTimeout(timer)
    timer = setTimeout(() => { timer = null; run() }, delay)
  }

  // Démarre un push. Renvoie la Promise du travail réel (rejette en cas
  // d'échec) ; `inFlight` en garde une version neutralisée pour le single-flight
  // (les attentes concurrentes ne doivent jamais voir de rejet non géré).
  function begin(project) {
    requeue = false
    const work = Promise.resolve().then(() => doPush(project))
    inFlight = work.then(() => {}, () => {}).then(() => {
      inFlight = null
      if (requeue && allowed(pending)) arm(retryMs)
    })
    return work
  }

  // Planifie un push différé du projet (anti-rafale). Idempotent.
  function schedule(project) {
    pending = project
    if (allowed(project)) arm(debounceMs)
  }

  // Déclenchement AUTO : avale l'erreur (retry différé via requeue).
  function run() {
    if (inFlight) {
      requeue = true
      return
    }
    const project = pending
    if (!allowed(project)) return
    begin(project).catch(err => {
      requeue = true
      if (onError) {
        try { onError(err, project) } catch (_) {}
      }
    })
  }

  // Push immédiat (bouton « Push ») : annule le debounce, attend un push en vol,
  // puis pousse l'état courant. PROPAGE l'erreur (conflit géré par l'appelant).
  async function flush(project) {
    clearTimeout(timer)
    timer = null
    if (project) pending = project
    if (inFlight) await inFlight
    return begin(pending)
  }

  // Annule toute planification en attente (démontage, changement de projet).
  // N'interrompt pas un push déjà en vol.
  function cancel() {
    clearTimeout(timer)
    timer = null
    pending = null
    requeue = false
  }

  return {
    schedule,
    flush,
    cancel,
    get busy() {
      return !!inFlight || timer !== null
    },
  }
}
