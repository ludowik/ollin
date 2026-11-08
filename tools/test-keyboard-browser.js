// Tries keyboard.typed, keyboard.show and keyboard.hide against the WASM engine in Chromium.
//  - On a computer: the text the keys PRODUCE reaches the script, which a key name cannot say (a capital, a hyphen, an
//    apostrophe, an accent), no control character comes with it, and nothing is delivered while the page blocks the
//    keyboard (the playground's editor has the focus).
//  - On a touch screen (emulated): the first tap gives the focus to the page's invisible text element WITHOUT asking for a
//    keyboard, the script's show() then lets the keyboard come (inputmode "text"), the text of the element reaches
//    typed() once and not twice, the iPhone's curly apostrophe arrives straight, backspace and return stay key names,
//    the tap still reaches mouse.pressed, and hide() gives the focus back.
// What no emulation can say is whether a real phone raises its keyboard: that was measured on an iPhone with a probe page
// (since removed), and the findings are in pg-text-input.js.
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
const PROBE_TOUCH = '/samples/_keyboard_probe_touch.ol'
const programTouch = `
global typedLog = ""
global keyLog = ""
global taps = 0
func keyboard.typed(text)
    typedLog += "[" + text + "]"
end
func keyboard.keypressed(key)
    keyLog += key + ","
    if key == "f2" then
        keyboard.hide()
    elseif key == "f1" then
        assert(false, "TYPED=" + typedLog + " KEYS=" + keyLog + " TAPS=" + taps)
    end
end
func mouse.pressed(x, y)
    taps += 1
    keyboard.show()
end
func draw()
    graphics.clear(colors.BLACK)
end
`
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
  if (url === PROBE || url === PROBE_TOUCH) {
    res.writeHead(200, { 'content-type': 'text/plain' })
    return res.end(url === PROBE ? program : programTouch)
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

    // ── a touch screen ─────────────────────────────────────────────────────────────────────────────────
    const phone = await (await browser.newContext({ viewport: { width: 390, height: 700 }, hasTouch: true, isMobile: true })).newPage()
    // Which event each focus() of the invisible element happens in (window.event is empty outside an event handler). An
    // iPhone raises its keyboard only for a focus() taken inside the gesture of a tap, and Chromium does not care: this is
    // the only way for the test to see a focus taken a frame later, from show(), which a phone refused.
    await phone.addInitScript(() => {
      window.__focusLog = []
      const focus = HTMLElement.prototype.focus
      HTMLElement.prototype.focus = function (...args) {
        if (this.isContentEditable) window.__focusLog.push(window.event ? window.event.type : 'outside any event')
        return focus.apply(this, args)
      }
    })
    await phone.goto(`http://127.0.0.1:${server.address().port}/index.html#/run${PROBE_TOUCH.replace('/samples/', '/sample/')}`)
    await phone.waitForTimeout(5000)
    await phone.evaluate(() => { window.__message = null; window.__ollinFrameError = (m) => { window.__message = m } })
    const sinkState = () => phone.evaluate(() => {
      const el = document.activeElement
      return { sink: !!(el && el.isContentEditable), mode: el && el.getAttribute ? el.getAttribute('inputmode') : null,
               wanted: !!(window.__ollinTextInput && window.__ollinTextInput.wanted) }
    })
    const before = await sinkState()
    const box = await phone.evaluate(() => { const r = document.getElementById('canvas').getBoundingClientRect(); return { x: r.x + r.width / 2, y: r.y + r.height / 2 } })
    const session = await phone.context().newCDPSession(phone)
    // Held for a while: the engine polls its input once per frame, and a tap that opens and closes inside one frame is
    // never seen (page.touchscreen.tap does exactly that).
    await session.send('Input.dispatchTouchEvent', { type: 'touchStart', touchPoints: [{ x: box.x, y: box.y, id: 0 }] })
    await phone.waitForTimeout(150)
    await session.send('Input.dispatchTouchEvent', { type: 'touchEnd', touchPoints: [] })
    await phone.waitForTimeout(400)
    const afterTap = await sinkState()
    const focusLog = await phone.evaluate(() => window.__focusLog)
    const insert = async (text) => { await session.send('Input.insertText', { text }); await phone.waitForTimeout(120) }
    const key = async (name, code, vk) => {
      await session.send('Input.dispatchKeyEvent', { type: 'rawKeyDown', key: name, code, windowsVirtualKeyCode: vk })
      await session.send('Input.dispatchKeyEvent', { type: 'keyUp', key: name, code, windowsVirtualKeyCode: vk })
      await phone.waitForTimeout(120)
    }
    await insert('é')
    await insert('\u2018')            // the iPhone's smart apostrophe
    await insert('ab')                 // two characters in one event
    // A real key with a character: raylib hears it too (GLFW), and the sink gets the same character. Once, not twice.
    await session.send('Input.dispatchKeyEvent', { type: 'keyDown', key: 'x', code: 'KeyX', text: 'x', unmodifiedText: 'x', windowsVirtualKeyCode: 88 })
    await session.send('Input.dispatchKeyEvent', { type: 'keyUp', key: 'x', code: 'KeyX', windowsVirtualKeyCode: 88 })
    await phone.waitForTimeout(150)
    await key('Backspace', 'Backspace', 8)
    await key('Enter', 'Enter', 13)
    const typedWhileUp = await sinkState()
    await key('F2', 'F2', 113)         // the script calls keyboard.hide()
    await phone.waitForTimeout(300)
    const afterHide = await sinkState()
    await key('F1', 'F1', 112)
    await phone.waitForTimeout(300)
    const touchMessage = await phone.evaluate(() => window.__message)

    const checks = [
      ['the program asks for text (typed declared)', before.wanted === true],
      ['no sink has the focus before any tap', before.sink === false],
      ['the first tap armed the sink, and the script\'s show() let the keyboard come', afterTap.sink === true && afterTap.mode === 'text'],
      ['the first tap took the focus inside its touchend, never from show() a frame later (' + focusLog.join(', ') + ')',
       focusLog.length >= 1 && focusLog.every((type) => type === 'touchend')],
      ['the tap still reached mouse.pressed', typeof touchMessage === 'string' && /TAPS=[1-9]/.test(touchMessage)],
      ['the text arrived once, the curly apostrophe straight', typeof touchMessage === 'string' && touchMessage.includes("TYPED=[é]['][ab][x] ") && !touchMessage.includes('[é][é]')],
      ['backspace and return stayed key names', typeof touchMessage === 'string' && /KEYS=x,backspace,return,/.test(touchMessage)],
      ['the sink kept the focus while typing', typedWhileUp.sink === true],
      ['hide() gave the focus back', afterHide.sink === false],
    ]
    for (const [name, ok2] of checks) {
      console.log((ok2 ? 'OK   ' : 'FAIL ') + name)
      if (!ok2) failed = true
    }
    if (failed) console.log('  touch message: ' + touchMessage)
  } catch (e) {
    console.log('FAIL', e.message)
    failed = true
  }
  await browser.close()
  server.close()
  process.exit(failed ? 1 : 0)
})
