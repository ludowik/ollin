// The THUMBNAIL of a project: the picture its tile shows on the home screen, kept in the project's own
// record (`project.thumbnail`, a small JPEG as a data URL) and never sent to GitHub. It is taken from a
// capture of the running program, which only the ENGINE can produce — at the end of a frame, the one
// moment the framebuffer holds the composed screen (see the Capture button of the full-screen view).
//
// Three rules, in this order: a project that has a thumbnail keeps it; one that has none gets one taken
// by itself a few seconds into a run (scheduleAutoThumbnail); and a capture the user asks for replaces
// whatever the tile showed (the full-screen view's Capture button).

const SIZE = 256
// Delays (ms) of the automatic attempts: the first a few seconds after the start, the second only when the
// first got no picture from the engine at all (a technical failure — never a judgement on what the picture shows).
const AUTO_DELAYS = [3000, 5000]
const NOTICE_MS = 5000

// A short message at the foot of the screen. The toolbar's status line is hidden on a phone, and the outcome of
// an attempt (taken, or why not) must be readable wherever the program runs.
export function showNotice(text, ok = true) {
  const old = document.getElementById('thumb-notice')
  if (old) old.remove()
  const el = document.createElement('div')
  el.id = 'thumb-notice'
  el.textContent = text
  el.style.cssText = 'position:fixed;left:50%;bottom:16px;transform:translateX(-50%);z-index:10000;' +
    'max-width:calc(100vw - 32px);padding:8px 14px;border-radius:8px;font:13px system-ui,sans-serif;' +
    'background:var(--surface2,#222);border:1px solid var(--border-strong,#888);pointer-events:none;' +
    'color:' + (ok ? 'var(--text,#eee)' : 'var(--red,#f66)')
  document.body.appendChild(el)
  setTimeout(() => { if (el.isConnected) el.remove() }, NOTICE_MS)
}

// Waits for the engine to deliver the capture, for at most `tries` frames: a program with no draw() or
// one that failed must not wait for ever. '' when nothing came.
export function waitCapture(mod, tries = 40) {
  return new Promise((resolve) => {
    const poll = () => {
      let b64 = ''
      try { b64 = mod.takeCapture() } catch (_) {}
      if (b64) return resolve(b64)
      if (--tries <= 0) return resolve('')
      requestAnimationFrame(poll)
    }
    requestAnimationFrame(poll)
  })
}

// The square `side` of `source` at (sx, sy), reduced to SIZE by halves. A single drawImage from far above
// SIZE averages only the 2 x 2 pixels around each sample, so a one-pixel line can fall between samples and
// vanish — which a vortex of thin strokes would. Halving, each step averages what it merges.
function shrunkSquare(source, sx, sy, side) {
  let from = source
  let fx = sx
  let fy = sy
  let size = side
  while (size >= SIZE * 2) {
    const half = Math.floor(size / 2)
    const step = document.createElement('canvas')
    step.width = half
    step.height = half
    const sg = step.getContext('2d')
    sg.drawImage(from, fx, fy, size, size, 0, 0, half, half)
    from = step
    fx = 0
    fy = 0
    size = half
  }
  const out = document.createElement('canvas')
  out.width = SIZE
  out.height = SIZE
  const og = out.getContext('2d')
  og.fillStyle = '#000'
  og.fillRect(0, 0, SIZE, SIZE)
  og.drawImage(from, fx, fy, size, size, 0, 0, SIZE, SIZE)
  return out
}

// A PNG (base64) cropped to its centre square and scaled to SIZE, as a JPEG data URL.
export async function thumbnailFromPng(b64) {
  const img = new Image()
  img.src = 'data:image/png;base64,' + b64
  await img.decode()
  const side = Math.min(img.width, img.height)
  const canvas = shrunkSquare(img, (img.width - side) / 2, (img.height - side) / 2, side)
  return canvas.toDataURL('image/jpeg', 0.85)
}

// Asks the engine for a capture and turns it into a thumbnail: {url}, or {url: null, reason} when nothing came.
export async function captureThumbnail(mod) {
  if (!mod || !mod.requestCapture) return { url: null, reason: 'the engine cannot capture' }
  mod.requestCapture()
  const b64 = await waitCapture(mod)
  if (!b64) return { url: null, reason: 'no picture came from the engine' }
  return { url: await thumbnailFromPng(b64) }
}

// Takes the thumbnail by itself a few seconds into a run, when the project has none, whatever the picture shows.
// An attempt gives up quietly if the run is over (`isCurrent` false) or the project has meanwhile got a
// thumbnail; one that got no picture is tried once more. `save(url)` stores the result. `report(text, ok)` is told
// what became of the attempt, so that a failure can be read rather than guessed at. Returns what cancels it.
export function scheduleAutoThumbnail({ mod, isCurrent, hasThumbnail, save, report = () => {} }) {
  let cancelled = false
  let timer = 0
  const attempt = async (i) => {
    if (cancelled || !isCurrent() || hasThumbnail()) return
    report('taking the thumbnail…', true)
    let made
    try {
      made = await captureThumbnail(mod)
    } catch (e) {
      made = { url: null, reason: 'capture failed: ' + (e && e.message ? e.message : e) }
    }
    if (cancelled || !isCurrent() || hasThumbnail()) return
    if (made.url) {
      try {
        await save(made.url)
        report('thumbnail saved', true)
      } catch (e) {
        report('thumbnail not saved: ' + (e && e.message ? e.message : e), false)
      }
      return
    }
    if (i + 1 < AUTO_DELAYS.length) {
      timer = setTimeout(() => attempt(i + 1), AUTO_DELAYS[i + 1] - AUTO_DELAYS[i])
      return
    }
    report('no thumbnail: ' + made.reason, false)
  }
  timer = setTimeout(() => attempt(0), AUTO_DELAYS[0])
  return () => {
    cancelled = true
    clearTimeout(timer)
  }
}
