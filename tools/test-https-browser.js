#!/usr/bin/env node
// Tries the browser engine of the `https` module (src/modules/https_engine_web.cpp) against a REAL HTTPS server, in
// Chromium: what no headless test can do, `fetch` being the browser's. Run by hand, never by tests/run.sh, which has
// neither a browser nor the built WASM:
//
//   NODE_PATH=$(npm root -g) node tools/test-https-browser.js
//
// It needs docs/wasm built (tools/build-wasm.sh) and openssl. A server with a self-signed certificate is started on
// a free port, Chromium is told to accept that certificate, and a program of the language asks it for: a text with
// accents, a refusal without CORS headers, a 404, a redirection, an answer that never comes (timeout), a custom header
// (which makes the browser send a preflight request), a 3 MB body, a request cancelled before it is answered, and a
// request made from a callback. The answers are checked here, and the exit status says whether they were right.
//
// The Open-Meteo service the weather sample asks is NOT reached: there is no network in the usual container, so what
// the sample does with a real answer is only tried on answers written to look like the service's.
const http = require('http')
const https = require('https')
const fs = require('fs')
const os = require('os')
const path = require('path')
const { execFileSync } = require('child_process')
const { chromium } = require('playwright')

const ROOT = path.resolve(__dirname, '..', 'docs')
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.json': 'application/json',
               '.wasm': 'application/wasm', '.svg': 'image/svg+xml', '.png': 'image/png', '.ol': 'text/plain',
               '.webmanifest': 'application/json' }

function certificate() {
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'ollin-https-'))
  execFileSync('openssl', ['req', '-x509', '-newkey', 'rsa:2048', '-nodes', '-keyout', path.join(dir, 'k.pem'),
    '-out', path.join(dir, 'c.pem'), '-days', '2', '-subj', '/CN=localhost',
    '-addext', 'subjectAltName=DNS:localhost,IP:127.0.0.1'], { stdio: 'ignore' })
  return { key: fs.readFileSync(path.join(dir, 'k.pem')), cert: fs.readFileSync(path.join(dir, 'c.pem')) }
}

const site = http.createServer((req, res) => {
  let p = decodeURIComponent(req.url.split('?')[0])
  if (p.endsWith('/')) p += 'index.html'
  fs.readFile(path.join(ROOT, p), (err, data) => {
    if (err) { res.writeHead(404); res.end(); return }
    res.writeHead(200, { 'Content-Type': MIME[path.extname(p)] || 'application/octet-stream' })
    res.end(data)
  })
})

const api = https.createServer(certificate(), (req, res) => {
  const cors = { 'access-control-allow-origin': '*', 'access-control-allow-headers': '*' }
  if (req.method === 'OPTIONS') { res.writeHead(204, cors); res.end(); return }
  const u = req.url.split('?')[0]
  if (u === '/hello') { res.writeHead(200, { ...cors, 'content-type': 'text/plain; charset=utf-8' }); res.end('Héllo wörld ✓') }
  else if (u === '/nocors') { res.writeHead(200, { 'content-type': 'text/plain' }); res.end('secret') }
  else if (u === '/missing') { res.writeHead(404, { ...cors, 'content-type': 'text/plain' }); res.end('nothing here') }
  else if (u === '/redirect') { res.writeHead(302, { ...cors, location: '/hello' }); res.end() }
  else if (u === '/slow') { /* never answers */ }
  else if (u === '/echo') { res.writeHead(200, { ...cors, 'content-type': 'application/json' }); res.end(JSON.stringify({ x: req.headers['x-test'] || null })) }
  else if (u === '/huge') { res.writeHead(200, { ...cors, 'content-type': 'text/plain' }); res.end('x'.repeat(17 * 1024 * 1024)) }
  else if (u === '/big') { res.writeHead(200, { ...cors, 'content-type': 'text/plain' }); res.end('x'.repeat(3 * 1024 * 1024)) }
  else { res.writeHead(500, cors); res.end('?') }
})

const program = (API) => `global results = {}
global frames = 0
func note(name, res)
    results[name] = {ok: res.ok, status: res.status, error: res.error, len: len(res.body), head: string.substr(res.body, 1, 20), url: res.url}
end
func draw()
    frames += 1
    if frames == 90 then
        assert(false, json.stringify(results))
    end
end
func setup()
    graphics.canvas(W, H)
    https.get("${API}/hello", func(r) note("hello", r) end)
    https.get("${API}/nocors", func(r) note("nocors", r) end)
    https.get("${API}/missing", func(r) note("missing", r) end)
    https.get("${API}/redirect", func(r) note("redirect", r) end)
    https.get("${API}/slow", {timeout: 0.5}, func(r) note("slow", r) end)
    https.get("${API}/echo", {headers: {"X-Test": "abc"}}, func(r) note("echo", r) end)
    https.get("${API}/big", func(r) note("big", r) end)
    https.get("${API}/huge", func(r) note("huge", r) end)
    var c = https.get("${API}/hello", func(r) note("cancelled", r) end)
    c.cancel()
    https.get("${API}/hello", func(r)
        note("chain1", r)
        https.get("${API}/missing", func(r2) note("chain2", r2) end)
    end)
end
`

function check(results, API) {
  const failures = []
  const expect = (name, cond, shown) => { if (!cond) failures.push(name + ': ' + JSON.stringify(shown)) }
  const r = results
  expect('hello', r.hello && r.hello.ok && r.hello.status === 200 && r.hello.head === 'Héllo wörld ✓' && r.hello.len === 13, r.hello)
  expect('nocors', r.nocors && !r.nocors.ok && r.nocors.status === 0 && r.nocors.error && r.nocors.len === 0, r.nocors)
  expect('missing', r.missing && !r.missing.ok && r.missing.status === 404 && r.missing.head === 'nothing here' && !r.missing.error, r.missing)
  expect('redirect', r.redirect && r.redirect.ok && r.redirect.url === API + '/hello', r.redirect)
  expect('slow', r.slow && !r.slow.ok && r.slow.error === 'timeout' && r.slow.status === 0, r.slow)
  expect('echo', r.echo && r.echo.ok && r.echo.head === '{"x":"abc"}', r.echo)
  expect('big', r.big && r.big.ok && r.big.len === 3 * 1024 * 1024, r.big)
  expect('huge', r.huge && !r.huge.ok && r.huge.status === 0 && r.huge.error === 'response too large' && r.huge.len === 0, r.huge)
  expect('cancelled', r.cancelled === undefined, r.cancelled)
  expect('chain', r.chain1 && r.chain1.ok && r.chain2 && r.chain2.status === 404, [r.chain1, r.chain2])
  return failures
}

;(async () => {
  await new Promise((ok) => site.listen(0, '127.0.0.1', ok))
  await new Promise((ok) => api.listen(0, '127.0.0.1', ok))
  const base = 'http://127.0.0.1:' + site.address().port
  const API = 'https://127.0.0.1:' + api.address().port
  const browser = await chromium.launch({ args: ['--use-gl=angle', '--use-angle=swiftshader', '--no-sandbox', '--ignore-certificate-errors'] })
  const ctx = await browser.newContext({ viewport: { width: 420, height: 600 } })
  const page = await ctx.newPage()
  // The program is served in place of a sample, so nothing is written into the repository.
  await page.route('**/samples/zz_https_test.ol*', (route) => route.fulfill({ status: 200, contentType: 'text/plain', body: program(API) }))
  await page.addInitScript(() => {
    window.__errs = []
    Object.defineProperty(window, '__ollinFrameError', { set() {}, get() { return (m) => window.__errs.push(m) } })
  })
  await page.goto(base + '/index.html#/run/sample/zz_https_test.ol')
  let failures
  try {
    await page.waitForFunction(() => window.__errs.length > 0, null, { timeout: 40000 })
    const text = await page.evaluate(() => window.__errs[0])
    failures = check(JSON.parse(text.slice(text.indexOf('{'))), API)
  } catch (e) {
    failures = ['the program never reported: ' + e.message]
  }
  await browser.close()
  site.close()
  api.close()
  if (failures.length) {
    console.error('FAILED\n  ' + failures.join('\n  '))
    process.exit(1)
  }
  console.log('https engine ok: 10 checks against a local HTTPS server')
})()
