// Tries keyboard.typed against the WASM engine in Chromium: the text the keys PRODUCE reaches the script, which a key
// name cannot say (a capital, a hyphen, an apostrophe, an accent), no control character comes with it, and nothing is
// delivered while the page blocks the keyboard (the playground's editor has the focus).
//
// By hand, like test-https-browser.js (no browser in tests/run.sh):  NODE_PATH=$(npm root -g) node tools/test-keyboard-browser.js
// The program is served from memory, so nothing is added to docs/samples.
const { chromium } = require('playwright')
const http = require('http')
const fs = require('fs')
const path = require('path')

const root = path.join(__dirname, '..', 'docs')
const mime = { '.js': 'text/javascript', '.wasm': 'application/wasm', '.json': 'application/json', '.html': 'text/html',
               '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.ol': 'text/plain' }
const PROBE = '/samples/_keyboard_probe.ol'
const program = `
global typedLog = ""
global keyLog = ""
func keyboard.typed(text)
    typedLog += "[" + text + "]"
end
func keyboard.keypressed(key)
    keyLog += key + ","
    if key == "f1" then
        assert(false, "TYPED=" + typedLog + " KEYS=" + keyLog)
    end
end
func draw()
    graphics.clear(colors.BLACK)
end
`

const server = http.createServer((req, res) => {
  const url = decodeURIComponent(req.url.split('?')[0])
  if (url === PROBE) {
    res.writeHead(200, { 'content-type': 'text/plain' })
    return res.end(program)
  }
  const file = path.join(root, url.endsWith('/') ? url + 'index.html' : url)
  fs.readFile(file, (err, data) => {
    if (err) {
      res.writeHead(404)
      return res.end()
    }
    res.writeHead(200, { 'content-type': mime[path.extname(file)] || 'application/octet-stream', 'cache-control': 'no-store' })
    res.end(data)
  })
})

server.listen(0, '127.0.0.1', async () => {
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox'] })
  let failed = false
  try {
    const page = await (await browser.newContext({ viewport: { width: 900, height: 600 } })).newPage()
    await page.goto(`http://127.0.0.1:${server.address().port}/index.html#/run${PROBE.replace('/samples/', '/sample/')}`)
    await page.waitForTimeout(5000)
    await page.evaluate(() => { window.__message = null; window.__ollinFrameError = (m) => { window.__message = m } })
    await page.mouse.click(450, 300)
    await page.waitForTimeout(200)

    const cdp = await page.context().newCDPSession(page)
    const press = async (key) => { await page.keyboard.press(key); await page.waitForTimeout(120) }
    // Playwright cannot press a character its US layout lacks: CDP sends it as text, as a layout would.
    const typeText = async (text) => {
      await cdp.send('Input.dispatchKeyEvent', { type: 'keyDown', key: text, text, unmodifiedText: text })
      await cdp.send('Input.dispatchKeyEvent', { type: 'keyUp', key: text })
      await page.waitForTimeout(120)
    }
    const setBlocked = async (blocked) => { await page.evaluate((b) => { window.__ollinKbdBlocked = b }, blocked); await page.waitForTimeout(150) }

    for (const key of ['a', 'Shift+A', '1', 'Minus', 'Quote', 'Space', 'Enter', 'Tab', 'Backspace']) await press(key)
    for (const text of ['é', 'ç', 'œ', '€']) await typeText(text)
    await setBlocked(true)
    await press('z')
    await press('y')
    await setBlocked(false)
    await press('q')
    await press('F1')
    await page.waitForTimeout(300)

    const message = await page.evaluate(() => window.__message)
    const expected = 'TYPED=[a][A][1][-][\'][ ][é][ç][œ][€][q] KEYS=a,shift,a,1,space,return,tab,backspace,q,f1,'
    const ok = typeof message === 'string' && message.endsWith(expected)
    console.log(ok ? 'OK   keyboard.typed' : `FAIL keyboard.typed\n  got      ${message}\n  expected ...${expected}`)
    failed = !ok
  } catch (e) {
    console.log('FAIL', e.message)
    failed = true
  }
  await browser.close()
  server.close()
  process.exit(failed ? 1 : 0)
})
