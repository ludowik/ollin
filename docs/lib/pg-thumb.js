// The THUMBNAIL of a project: the picture its tile shows on the home screen, kept in the project's own
// record (`project.thumbnail`, a small JPEG as a data URL) and never sent to GitHub. It is taken from a
// capture of the running program, which only the ENGINE can produce — at the end of a frame, the one
// moment the framebuffer holds the composed screen (see the Capture button of the full-screen view).
//
// Three rules, in this order: a project that has a thumbnail keeps it; one that has none gets one taken
// by itself a few seconds into a run (scheduleAutoThumbnail); and a capture the user asks for replaces
// whatever the tile showed (the full-screen view's Capture button).

const SIZE = 256
// A picture is BLANK when almost nothing in it differs from its commonest brightness: fewer than BLANK_PIXELS
// pixels (of 65 536) are more than BLANK_STEP levels away from it. Counting pixels rather than taking the
// spread of the brightness matters for sparse art — a few faint thin lines on black — whose spread is tiny
// though the picture is not empty. The step is low because an EMPTY frame is exactly uniform, so it has no
// pixel at all off its background, while faint thin lines, once reduced, sit only a few levels above it
// (measured: with a step of 6 such a drawing counted zero pixels and was rejected as blank).
const BLANK_STEP = 1
const BLANK_PIXELS = 40
const AUTO_DELAYS = [3000, 4000, 5000]   // ms: after the start, then after each attempt that found nothing usable

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

// A PNG (base64) cropped to its centre square and scaled to SIZE: {url, differing}, where `url` is a data URL
// and `differing` the number of pixels that stand out from the background. `url` is null when the picture is
// blank — unless `allowFlat`, for a capture the user asked for, which is theirs whatever it shows.
export async function thumbnailFromPng(b64, { allowFlat = false } = {}) {
  const img = new Image()
  img.src = 'data:image/png;base64,' + b64
  await img.decode()
  const side = Math.min(img.width, img.height)
  const canvas = shrunkSquare(img, (img.width - side) / 2, (img.height - side) / 2, side)
  const g = canvas.getContext('2d')
  const px = g.getImageData(0, 0, SIZE, SIZE).data
  const levels = new Uint8Array(SIZE * SIZE)
  const histogram = new Uint32Array(256)
  for (let i = 0, k = 0; i < px.length; i += 4, k++) {
    const y = Math.round(0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2])
    levels[k] = y
    histogram[y]++
  }
  let background = 0
  for (let y = 1; y < 256; y++) {
    if (histogram[y] > histogram[background]) background = y
  }
  let differing = 0
  for (let k = 0; k < levels.length; k++) {
    if (Math.abs(levels[k] - background) > BLANK_STEP) differing++
  }
  if (!allowFlat && differing < BLANK_PIXELS) return { url: null, differing }
  return { url: canvas.toDataURL('image/jpeg', 0.85), differing }
}

// Asks the engine for a capture and turns it into a thumbnail: {url, differing}, with url null and a `reason`
// when nothing usable came.
export async function captureThumbnail(mod, options) {
  if (!mod || !mod.requestCapture) return { url: null, reason: 'the engine cannot capture' }
  mod.requestCapture()
  const b64 = await waitCapture(mod)
  if (!b64) return { url: null, reason: 'no picture came from the engine' }
  const made = await thumbnailFromPng(b64, options)
  if (!made.url) return { url: null, reason: 'blank picture (' + made.differing + ' px stand out)' }
  return made
}

// Takes the thumbnail by itself a few seconds into a run, when the project has none. Each attempt gives up
// quietly if the run is over (`isCurrent` false) or the project has meanwhile got a thumbnail, and a blank
// frame — a program still loading — is tried again a little later. `save(url)` stores the result. `report(text, ok)`
// is told what became of each attempt, so that a failure can be read rather than guessed at. Returns what
// cancels it.
export function scheduleAutoThumbnail({ mod, isCurrent, hasThumbnail, save, report = () => {} }) {
  let cancelled = false
  let timer = 0
  const attempt = async (i) => {
    if (cancelled || !isCurrent() || hasThumbnail()) return
    let made = { url: null, reason: 'unknown' }
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
      timer = setTimeout(() => attempt(i + 1), AUTO_DELAYS[i + 1])
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
