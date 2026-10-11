// The THUMBNAIL of a project: the picture its tile shows on the home screen, kept in the project's own
// record (`project.thumbnail`, a small JPEG as a data URL) and never sent to GitHub. It is taken from a
// capture of the running program, which only the ENGINE can produce — at the end of a frame, the one
// moment the framebuffer holds the composed screen (see the Capture button of the full-screen view).
//
// Three rules, in this order: a project that has a thumbnail keeps it; one that has none gets one taken
// by itself a few seconds into a run (scheduleAutoThumbnail); and a capture the user asks for replaces
// whatever the tile showed (the full-screen view's Capture button).

const SIZE = 256
const FLAT = 3            // a picture whose brightness varies less than this is blank: not worth keeping
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

// A PNG (base64) cropped to its centre square and scaled to SIZE: a data URL, or null when the picture is
// flat — unless `allowFlat`, for a capture the user asked for, which is theirs whatever it shows.
export async function thumbnailFromPng(b64, { allowFlat = false } = {}) {
  const img = new Image()
  img.src = 'data:image/png;base64,' + b64
  await img.decode()
  const side = Math.min(img.width, img.height)
  const canvas = document.createElement('canvas')
  canvas.width = SIZE
  canvas.height = SIZE
  const g = canvas.getContext('2d')
  g.fillStyle = '#000'
  g.fillRect(0, 0, SIZE, SIZE)
  g.drawImage(img, (img.width - side) / 2, (img.height - side) / 2, side, side, 0, 0, SIZE, SIZE)
  if (!allowFlat) {
    const px = g.getImageData(0, 0, SIZE, SIZE).data
    let sum = 0
    let sum2 = 0
    for (let i = 0; i < px.length; i += 4) {
      const y = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]
      sum += y
      sum2 += y * y
    }
    const n = SIZE * SIZE
    const mean = sum / n
    if (Math.sqrt(Math.max(sum2 / n - mean * mean, 0)) < FLAT) return null
  }
  return canvas.toDataURL('image/jpeg', 0.85)
}

// Asks the engine for a capture and turns it into a thumbnail; null when nothing usable came.
export async function captureThumbnail(mod, options) {
  if (!mod || !mod.requestCapture) return null
  mod.requestCapture()
  const b64 = await waitCapture(mod)
  return b64 ? thumbnailFromPng(b64, options) : null
}

// Takes the thumbnail by itself a few seconds into a run, when the project has none. Each attempt gives up
// quietly if the run is over (`isCurrent` false) or the project has meanwhile got a thumbnail, and a blank
// frame — a program still loading — is tried again a little later. `save(url)` stores the result.
// Returns what cancels it.
export function scheduleAutoThumbnail({ mod, isCurrent, hasThumbnail, save }) {
  let cancelled = false
  let timer = 0
  const attempt = async (i) => {
    if (cancelled || !isCurrent() || hasThumbnail()) return
    let url = null
    try { url = await captureThumbnail(mod) } catch (_) {}
    if (cancelled || !isCurrent() || hasThumbnail()) return
    if (url) {
      await save(url)
      return
    }
    if (i + 1 < AUTO_DELAYS.length) timer = setTimeout(() => attempt(i + 1), AUTO_DELAYS[i + 1])
  }
  timer = setTimeout(() => attempt(0), AUTO_DELAYS[0])
  return () => {
    cancelled = true
    clearTimeout(timer)
  }
}
