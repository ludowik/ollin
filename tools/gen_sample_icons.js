#!/usr/bin/env node
// Generates the examples' icons for the home screen: each graphical example of docs/samples/index.json is
// run in the full-screen view, in a square area, and its canvas is cropped and scaled to a 256 px PNG in
// docs/samples/icons/. Run by hand, never by the build — like the model converters — and again when an
// example changes: nothing notices that a picture has gone stale, only that it exists
// (tests/check_samples.sh).
//
//   NODE_PATH=$(npm root -g) node tools/gen_sample_icons.js [file.ol ...]
//
// With no argument every entry is done; with some, only those. An example that draws nothing (a text
// program), fails, or renders a flat picture gets NO icon, and its catalogue entry loses the `icon` field:
// the home screen then draws a generated tile for it. The catalogue is edited as text, one line at a time,
// so its alignment and its blank lines between groups stay as they are.
const http = require('http')
const fs = require('fs')
const path = require('path')
const { chromium } = require('playwright')

const ROOT = path.resolve(__dirname, '..', 'docs')
const CATALOGUE = path.join(ROOT, 'samples', 'index.json')
const ICONS = path.join(ROOT, 'samples', 'icons')
const SIZE = 256
const AREA = 640                       // the square the example draws in, in CSS pixels
const BAR = 48                         // the full-screen view's own bar, above that area
const SETTLE = 4500                    // ms an example runs before its picture is taken
const SETTLE_LONG = {                  // the heavier ones bake a world or load a model first
  'voxel_world/voxel_world.ol': 12000,
  'model_3d/model_3d.ol': 12000,
  'rally/rally.ol': 9000,
  'transforms_3d/transforms_3d.ol': 7000,
  'primitives_3d/primitives_3d.ol': 7000,
}
// Examples whose picture is no use as an icon, though they draw: the generated tile reads better.
const NO_ICON = {
  'camera.ol': 'needs a camera; its picture is a waiting message',
  'data_demo.ol': 'only small text on a flat background',
}
const FLAT = 3                         // a picture whose brightness varies less than this is blank

// Examples whose icon is not the plain square picture of a fresh run. `viewport` is the area the example
// draws in (CSS px), `seed` the `data` entries stored before it starts (project scope, encoded as the
// engine writes them: 's' + text), and `crop` the square kept, in CSS px of that area. The crop is
// measured against the example's own layout, so it must be redone when that layout changes.
//   Blockudoku: at W = H the game picks its side-by-side layout, with the score and the buttons in a
//   column; this wider-than-tall area gives the column layout instead, and the crop keeps the grid and the
//   three pieces on offer, without the header. The saved game fills the grid with a few placed pieces.
const SPECS = {
  'blockudoku/blockudoku.ol': {
    viewport: { width: 600, height: 640 },
    seed: {
      'blockudoku.game': 's1240|1|' +
        '000000500' + '220000550' + '280033000' + '880130000' + '000110070' +
        '600000777' + '660040000' + '600044200' + '000000220' + '|###/.#.,##/##,###/#../#..',
      'blockudoku.best': 'i2480',
    },
    crop: { x: 61, y: 122, side: 475 },
  },
}

const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
               '.wasm': 'application/wasm', '.svg': 'image/svg+xml', '.png': 'image/png', '.ol': 'text/plain',
               '.glb': 'model/gltf-binary', '.obj': 'text/plain', '.webmanifest': 'application/json' }

function serve() {
  return http.createServer((req, res) => {
    let p = decodeURIComponent(req.url.split('?')[0])
    if (p.endsWith('/')) p += 'index.html'
    fs.readFile(path.join(ROOT, p), (err, data) => {
      if (err) {
        res.writeHead(404)
        res.end()
        return
      }
      res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream' })
      res.end(data)
    })
  })
}

// Centre-crops a picture to a square and scales it, in a page of its own so the example's page is not
// disturbed. Returns the PNG as a data URL and how much the picture's brightness varies.
async function toIcon(tool, pngBase64, crop, cssWidth) {
  return tool.evaluate(async ([b64, size, crop, cssWidth]) => {
    const img = new Image()
    img.src = 'data:image/png;base64,' + b64
    await img.decode()
    const k = crop ? img.width / cssWidth : 1
    const side = crop ? crop.side * k : Math.min(img.width, img.height)
    const sx = crop ? crop.x * k : (img.width - side) / 2
    const sy = crop ? crop.y * k : (img.height - side) / 2
    const c = document.createElement('canvas')
    c.width = size
    c.height = size
    const g = c.getContext('2d')
    g.drawImage(img, sx, sy, side, side, 0, 0, size, size)
    const px = g.getImageData(0, 0, size, size).data
    let sum = 0
    let sum2 = 0
    const n = size * size
    for (let i = 0; i < px.length; i += 4) {
      const y = 0.299 * px[i] + 0.587 * px[i + 1] + 0.114 * px[i + 2]
      sum += y
      sum2 += y * y
    }
    const mean = sum / n
    return { url: c.toDataURL('image/png'), spread: Math.sqrt(Math.max(sum2 / n - mean * mean, 0)) }
  }, [pngBase64, SIZE, crop || null, cssWidth || 0])
}

async function capture(browser, base, tool, file) {
  const spec = SPECS[file]
  const area = spec ? spec.viewport : { width: AREA, height: AREA }
  const ctx = await browser.newContext({ viewport: { width: area.width, height: area.height + BAR }, deviceScaleFactor: spec ? 2 : 1 })
  const page = await ctx.newPage()
  try {
    if (spec) {
      await page.addInitScript(([key, seed]) => {
        const stored = {}
        for (const k in seed) stored[k] = seed[k]
        try { localStorage.setItem(key, JSON.stringify(stored)) } catch (_) {}
      }, ['ollin-data:p:sample:' + file, spec.seed])
    }
    await page.addInitScript(() => {
      window.__errs = []
      Object.defineProperty(window, '__ollinFrameError', { set() {}, get() { return (m) => window.__errs.push(m) } })
    })
    await page.goto(base + '/index.html#/run/sample/' + file)
    // The engine's memory and frame-rate readout is hidden through the host's own switch, so the picture
    // is the example's alone and nothing has to be cropped away.
    await page.waitForFunction(() => window.__ollinModule, null, { timeout: 20000 })
    await page.evaluate(() => window.__ollinModule.setStatsVisible(false))
    try {
      await page.waitForFunction(() => {
        const c = document.getElementById('canvas')
        return c && c.style.display !== 'none' && c.getBoundingClientRect().width > 0
      }, null, { timeout: 20000 })
    } catch (_) {
      return { skip: 'draws nothing (no canvas)' }
    }
    await page.waitForTimeout(SETTLE_LONG[file] || SETTLE)
    const errs = await page.evaluate(() => window.__errs)
    if (errs.length) return { skip: 'error: ' + errs[0] }
    const png = (await page.locator('#canvas').screenshot()).toString('base64')
    const icon = await toIcon(tool, png, spec && spec.crop, spec && spec.viewport.width)
    if (icon.spread < FLAT) return { skip: 'flat picture (spread ' + icon.spread.toFixed(1) + ')' }
    return { url: icon.url }
  } finally {
    await ctx.close()
  }
}

// Sets or removes ` "icon": "..."` on the catalogue line of `file`, leaving everything else of the line.
function setIconField(text, file, icon) {
  return text.split('\n').map((line) => {
    if (!line.includes('"file": "' + file + '"')) return line
    const bare = line.replace(/,\s*"icon":\s*"[^"]*"/, '')
    if (!icon) return bare
    return bare.replace(/\s*\}(,?)\s*$/, ', "icon": "' + icon + '" }$1')
  }).join('\n')
}

async function main() {
  const wanted = process.argv.slice(2)
  const entries = JSON.parse(fs.readFileSync(CATALOGUE, 'utf8')).filter((e) => !wanted.length || wanted.includes(e.file))
  if (!entries.length) {
    console.error('no catalogue entry matches')
    process.exit(2)
  }
  fs.mkdirSync(ICONS, { recursive: true })
  const server = serve()
  await new Promise((ok) => server.listen(0, '127.0.0.1', ok))
  const base = 'http://127.0.0.1:' + server.address().port
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox'] })
  const toolCtx = await browser.newContext()
  const tool = await toolCtx.newPage()
  let text = fs.readFileSync(CATALOGUE, 'utf8')
  let written = 0
  let skipped = 0
  for (const e of entries) {
    const name = path.basename(e.file, '.ol')
    process.stdout.write(e.file.padEnd(36))
    const r = NO_ICON[e.file] ? { skip: NO_ICON[e.file] } : await capture(browser, base, tool, e.file)
    if (r.skip) {
      console.log('no icon — ' + r.skip)
      skipped++
      fs.rmSync(path.join(ICONS, name + '.png'), { force: true })
      text = setIconField(text, e.file, null)
      continue
    }
    fs.writeFileSync(path.join(ICONS, name + '.png'), Buffer.from(r.url.split(',')[1], 'base64'))
    text = setIconField(text, e.file, 'icons/' + name + '.png')
    console.log('icons/' + name + '.png')
    written++
  }
  fs.writeFileSync(CATALOGUE, text)
  await browser.close()
  server.close()
  console.log('\n' + written + ' icons written, ' + skipped + ' without one')
}

main().catch((e) => {
  console.error(e)
  process.exit(1)
})
