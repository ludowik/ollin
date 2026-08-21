// Ollin playground — remote-save coordinator.
//
// It decouples the LOCAL save (instant, done by the caller) from the REMOTE one (a GitHub push,
// costly and fallible). The caller supplies the actual machinery (`doPush`, `canPush`); this
// module orchestrates ONLY the "when": debounce, coalescing, single-flight, offline tolerance.
// It knows nothing of GitHub nor of the project model.
//
// Guarantees:
//   • debounce      — N keystrokes within debounceMs give one push, of the last state.
//   • single-flight — never two pushes at once.
//   • coalescing    — an edit arriving during a push in flight schedules ONE push afterwards,
//                     with no stacking.
//   • offline       — a failing push breaks nothing: the state stays dirty and is pushed later
//                     (retryMs).
//
// `doPush(project) → Promise` is the real push (it may throw, and the state is rescheduled).
// `canPush(project) → bool` is a guard evaluated at every trigger (eligible project, online,
// dirty…). `onError(err, project)` notifies, and must not throw.

export function createRemoteSync({ doPush, canPush, onError, debounceMs = 3000, retryMs = 15000 } = {}) {
  let timer    = null    // debounce en cours
  let pending  = null    // dernier projet en attente de push
  let inFlight = false    // un push est en cours
  let requeue  = false   // an edit arrived while the push was in flight

  const allowed = p => !!p && (!canPush || canPush(p))

  function arm(delay) {
    clearTimeout(timer)
    timer = setTimeout(() => { timer = null; run() }, delay)
  }

  // Schedules a deferred push of the project (debounced). Idempotent.
  function schedule(project) {
    pending = project
    if (allowed(project)) arm(debounceMs)
  }

  // Fires the push. Single-flight: if one is in flight we mark `requeue`, so another follows at
  // the end. The error is swallowed, the retry being deferred through requeue.
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
      requeue = true   // offline or failed: keep the state dirty and retry later
      if (onError) {
        try { onError(err, project) } catch (_) {}
      }
    } finally {
      inFlight = false
      if (requeue && allowed(pending)) arm(retryMs)
    }
  }

  // Cancels any pending schedule (unmount, project change). It does not interrupt a push
  // already in flight.
  function cancel() {
    clearTimeout(timer)
    timer = null
    pending = null
    requeue = false
  }

  return { schedule, cancel }
}
