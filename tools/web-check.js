// Vérification de la web app DANS un vrai navigateur, SANS playwright (absent de
// certains conteneurs) : chromium piloté par le protocole DevTools, via le WebSocket
// natif de node ≥ 22. Aucune dépendance npm.
//
//   node tools/web-check.js '#/playground' probe.js [attente_ms]
//
// `probe.js` contient UNE expression JavaScript (souvent une fonction async immédiate)
// évaluée dans la page une fois chargée ; sa valeur est imprimée en JSON. Les messages de
// console et les exceptions de la page sont imprimés ensuite.
//
// Exemple de sonde — cliquer un bouton puis lire un état :
//   (async () => {
//     document.getElementById('shot-btn').click()
//     await new Promise(r => setTimeout(r, 3000))
//     return document.getElementById('status').textContent
//   })()
const http = require('http'), fs = require('fs'), path = require('path')
const { spawn } = require('child_process')

const ROOT = path.join(__dirname, '..', 'docs')
const CHROME = '/opt/pw-browsers/chromium-1194/chrome-linux/chrome'
const MIME = { '.html': 'text/html', '.js': 'text/javascript', '.json': 'application/json',
  '.wasm': 'application/wasm', '.css': 'text/css', '.png': 'image/png', '.ol': 'text/plain',
  '.obj': 'text/plain', '.glb': 'application/octet-stream', '.ebnf': 'text/plain' }

const hash = process.argv[2] || '#/playground'
const probeFile = process.argv[3]
const settle = Number(process.argv[4] || 7000)   // temps de chargement SPA + WASM
const sleep = ms => new Promise(r => setTimeout(r, ms))

// Serveur DANS ce process : un python3 -m http.server en arrière-plan fait échouer la
// commande shell (bind réseau sous sandbox), cf. CLAUDE.md.
const srv = http.createServer((q, r) => {
  let f = path.join(ROOT, q.url.split('?')[0].split('#')[0])
  try {
    if (fs.statSync(f).isDirectory()) f = path.join(f, 'index.html')
    const b = fs.readFileSync(f)
    r.writeHead(200, { 'Content-Type': MIME[path.extname(f)] || 'application/octet-stream' })
    r.end(b)
  } catch (_) { r.writeHead(404); r.end('not found') }
})

async function findPage(port) {
  for (let i = 0; i < 80; i++) {
    try {
      const list = await (await fetch(`http://127.0.0.1:${port}/json/list`)).json()
      const page = list.find(t => t.type === 'page' && t.webSocketDebuggerUrl)
      if (page) return page
    } catch (_) {}
    await sleep(250)
  }
  return null
}

function connect(url) {
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(url)
    let id = 0
    const pending = new Map()
    const logs = []
    ws.onmessage = (ev) => {
      const m = JSON.parse(ev.data)
      if (m.id && pending.has(m.id)) { pending.get(m.id)(m); pending.delete(m.id) }
      if (m.method === 'Runtime.consoleAPICalled')
        logs.push((m.params.args || []).map(a => a.value ?? a.description ?? '').join(' '))
      if (m.method === 'Runtime.exceptionThrown')
        logs.push('EXCEPTION ' + (m.params.exceptionDetails?.exception?.description || ''))
    }
    ws.onerror = reject
    ws.onopen = () => resolve({
      logs,
      send: (method, params = {}) => new Promise(res => {
        const mid = ++id
        pending.set(mid, res)
        ws.send(JSON.stringify({ id: mid, method, params }))
      }),
      close: () => ws.close(),
    })
  })
}

async function main() {
  await new Promise(r => srv.listen(0, '127.0.0.1', r))
  const port = srv.address().port
  const dbg = 9333
  const chrome = spawn(CHROME, [
    '--headless=new', `--remote-debugging-port=${dbg}`, '--no-sandbox',
    // GL logiciel : pas de GPU dans le conteneur, mais WebGL2 doit fonctionner.
    '--use-gl=angle', '--use-angle=swiftshader', '--window-size=900,700',
    `--user-data-dir=${fs.mkdtempSync('/tmp/ollin-chrome-')}`,
    `http://127.0.0.1:${port}/index.html${hash}`,
  ], { stdio: 'ignore' })

  const page = await findPage(dbg)
  if (!page) {
    console.log('chromium injoignable')
    chrome.kill(); srv.close()
    process.exitCode = 1
    return
  }
  const cdp = await connect(page.webSocketDebuggerUrl)
  await cdp.send('Runtime.enable')
  await sleep(settle)

  if (probeFile) {
    const expr = fs.readFileSync(probeFile, 'utf8')
    const r = await cdp.send('Runtime.evaluate', { expression: expr, awaitPromise: true, returnByValue: true })
    const det = r.result?.exceptionDetails
    console.log(det ? 'ERREUR ' + (det.exception?.description || det.text)
                    : JSON.stringify(r.result?.result?.value))
  }
  if (cdp.logs.length)
    console.log('console :', JSON.stringify(cdp.logs.slice(0, 12)))

  cdp.close(); chrome.kill(); srv.close()
}

main().catch(e => { console.log('ERREUR', e && e.message); process.exitCode = 1 })
